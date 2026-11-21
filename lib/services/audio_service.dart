/// 录音与播放服务：
/// - 录音用 record 插件输出 16k 单声道 PCM16，边播边录时可持续采集；
/// - 播放 TTS 用 audioplayers 播放生成好的 WAV 字节；
/// - 提供字节↔Float32 转换与 WAV 编码（sherpa-onnx 需要 float32 PCM）。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<int>>? _recordSub;
  final List<int> _pcmChunks = <int>[];
  final Completer<void> _stopped = Completer<void>();
  bool _recording = false;

  bool get isRecording => _recording;

  Future<bool> ensurePermission() => _recorder.hasPermission();

  /// 开始采集。onLevel 回传实时音量（0~1），供 UI 音量条显示。
  Future<void> startRecording({void Function(double)? onLevel}) async {
    if (_recording) return;
    _pcmChunks.clear();
    _recording = true;

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );
    final stream = await _recorder.startStream(config);
    _recordSub = stream.listen(
      (chunk) {
        if (!_recording) return;
        _pcmChunks.addAll(chunk);
        if (onLevel != null && chunk.length >= 2) {
          // 取一小段样本估算 RMS
          var sum = 0;
          final step = chunk.length > 640 ? (chunk.length ~/ 320) : 2;
          var n = 0;
          for (var i = 0; i + 1 < chunk.length; i += step) {
            final v = chunk[i] | (chunk[i + 1] << 8);
            final s = v > 32767 ? v - 65536 : v;
            sum += s * s;
            n++;
          }
          final rms = n > 0 ? math.sqrt(sum / n) : 0.0;
          onLevel((rms / 32768).clamp(0.0, 1.0).toDouble());
        }
      },
      onDone: () {
        if (!_stopped.isCompleted) _stopped.complete();
      },
      onError: (_) {
        if (!_stopped.isCompleted) _stopped.complete();
      },
    );
  }

  /// 停止采集并返回 Float32 PCM（16k 单声道）。
  Future<Float32List> stopRecording() async {
    if (!_recording) return Float32List(0);
    _recording = false;
    await _recordSub?.cancel();
    _recordSub = null;
    await _recorder.stop();

    final bytes = Uint8List.fromList(_pcmChunks);
    _pcmChunks.clear();
    return pcm16ToFloat32(bytes);
  }

  /// 播放 WAV 字节（TTS 产物），返回完成 Future。带超时兜底避免卡死。
  Future<void> playWavBytes(Uint8List bytes) async {
    await _player.stop();
    final done = Completer<void>();
    late StreamSubscription sub;
    sub = _player.onPlayerComplete.listen((_) {
      sub.cancel();
      if (!done.isCompleted) done.complete();
    });
    await _player.play(BytesSource(bytes));
    // 按字节数估算时长 + 缓冲，作为超时上限
    final estMs = (bytes.length / (16000 * 2) * 1000).round() + 3000;
    await done.future.timeout(
      Duration(milliseconds: estMs < 3000 ? 3000 : estMs),
      onTimeout: () {
        sub.cancel();
      },
    );
  }

  Future<void> stopPlayback() => _player.stop();

  /// 写临时 WAV 文件（给 audioplayers 用 FileSource 时可选）。
  Future<File> writeTempWav(Uint8List bytes, {String name = 'tts.wav'}) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  // ---------- 音频格式转换 ----------
  static Float32List pcm16ToFloat32(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      final s = view.getInt16(i * 2, Endian.little);
      out[i] = s / 32768.0;
    }
    return out;
  }

  /// 把 float32 PCM 编码成 16bit WAV 字节（供 audioplayers 播放）。
  static Uint8List float32ToWavBytes(Float32List samples, int sampleRate) {
    final byteData = ByteData(44 + samples.length * 2);
    // RIFF header
    void writeStr(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        byteData.setUint8(off + i, s.codeUnitAt(i));
      }
    }
    writeStr(0, 'RIFF');
    byteData.setUint32(4, 36 + samples.length * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    byteData.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      var v = (samples[i] * 32767).round().clamp(-32768, 32767).toInt();
      if (v < 0) v += 65536;
      byteData.setUint16(44 + i * 2, v, Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  void dispose() {
    _recordSub?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
