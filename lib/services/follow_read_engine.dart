/// 跟读训练引擎（移植电脑端流程）：
///   逐句 → TTS 合成 → [边播边录] → 端点检测 → 降噪 → 声纹验证 → ASR → 相似度 → 通过/重来
/// 通过回调 Stream<TrainEvent> 把进度回传 UI。
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../core/models.dart';
import '../core/text_utils.dart' as text;
import 'speech_engine.dart';
import 'audio_service.dart';

class FollowReadEngine {
  final SpeechEngine engine;
  final AudioService audio;
  final TrainConfig config;
  final void Function(TrainEvent) onEvent;

  bool _stopped = false;
  bool _lastPassed = false;
  double _currentLevel = 0.0; // 由录音电平回调实时更新

  FollowReadEngine({
    required this.engine,
    required this.audio,
    required this.config,
    required this.onEvent,
  });

  void stop() => _stopped = true;

  void _emit(TrainEvent e) => onEvent(e);

  /// 跑一轮训练。voices 为已建档声纹（用于剔除其他人声）。
  Future<void> run(List<String> sentences,
      {List<VoiceProfile> voices = const []}) async {
    _stopped = false;
    final total = sentences.length;
    var passed = 0;
    _emit(const TrainEvent(state: TrainState.preparing, message: '准备引擎…'));

    if (!engine.asrReady || !engine.ttsReady) {
      _emit(const TrainEvent(
          state: TrainState.error,
          message: '模型未就绪，请先在「模型管理」页放置模型文件'));
      return;
    }

    for (var i = 0; i < total; i++) {
      if (_stopped) break;
      final sentence = sentences[i];

      // 1) TTS 合成（多音字标注 + 语气语调）
      final speakText = config.ttsVoice == 'matcha_zh'
          ? text.annotatePolyphones(sentence)
          : sentence;
      final prosody = text.analyzeProsody(sentence, baseSpeed: config.ttsSpeed);
      sherpa.GeneratedAudio generated;
      try {
        generated = engine.synthesize(speakText, speed: prosody.speed);
      } catch (e) {
        _emit(TrainEvent(
            state: TrainState.error, message: 'TTS 合成失败：$e'));
        continue;
      }
      final genSamples = Float32List.fromList(generated.samples);
      final genDuration = generated.sampleRate > 0
          ? genSamples.length / generated.sampleRate
          : 0.0;
      final wav = AudioService.float32ToWavBytes(genSamples, generated.sampleRate);

      // 2) 播放 + 录音（未通过在本句重试）
      var attempt = 0;
      while (!_stopped) {
        attempt++;
        _emit(TrainEvent(
          state: TrainState.playing,
          index: i,
          total: total,
          passed: passed,
          message: config.recordDuringPlayback
              ? '朗读中，请直接跟读（同步收音）'
              : '请听完提示后跟读',
        ));

        Future<void>? playFuture;
        try {
          if (config.recordDuringPlayback) {
            // 先开麦，再播放；播放期间用户跟读声同步入库
            await audio.startRecording(
                onLevel: (lv) => _currentLevel = lv);
            playFuture = audio.playWavBytes(wav);
            await _waitForSpeechEnd(genDuration);
          } else {
            // 串行：播完再录
            await audio.playWavBytes(wav);
            await Future.delayed(const Duration(milliseconds: 200));
            await audio.startRecording(
                onLevel: (lv) => _currentLevel = lv);
            await _waitForSpeechEnd(0);
          }
          final pcm = await audio.stopRecording();
          if (playFuture != null) await playFuture;

          await _handleRecognition(
            sentence, pcm, i, total, passed, voices,
            onPassed: () => passed++,
          );
        } catch (e) {
          try {
            await audio.stopRecording();
          } catch (_) {}
          _emit(TrainEvent(
              state: TrainState.error,
              index: i,
              total: total,
              passed: passed,
              message: '播放/录音失败：$e'));
          break;
        }

        if (_lastPassed) break;
        _emit(TrainEvent(
            state: TrainState.playing,
            index: i,
            total: total,
            passed: passed,
            message: '未达标，重新提示本句…'));
      }
      await Future.delayed(
          Duration(milliseconds: (prosody.pauseAfter * 1000).round()));
    }

    _emit(TrainEvent(
      state: TrainState.done,
      total: total,
      passed: passed,
      message: '完成！通过 $passed / $total 句',
    ));
  }

  /// 端点检测：等用户开口，开口后连续静音 silenceDurationSec 结束；
  /// 若始终没人说话，最多等到「朗读时长 + maxListenSec」后结束。
  Future<void> _waitForSpeechEnd(double playbackDuration) async {
    final sw = Stopwatch()..start();
    var started = false;
    var silentMs = 0;
    const tickMs = 50;
    final hardLimitMs =
        ((playbackDuration + config.maxListenSec) * 1000).round();

    while (sw.elapsedMilliseconds < hardLimitMs) {
      if (_stopped) return;
      await Future.delayed(const Duration(milliseconds: tickMs));
      _emit(TrainEvent(state: TrainState.listening, level: _currentLevel));
      final voiced = _currentLevel >= config.silenceThreshold;
      if (voiced) {
        started = true;
        silentMs = 0;
      } else if (started) {
        silentMs += tickMs;
        if (silentMs >= config.silenceDurationSec * 1000) break;
      }
    }
  }

  /// 识别 + 降噪 + 声纹验证 + 相似度比对。
  Future<void> _handleRecognition(
    String sentence,
    Float32List pcm,
    int index,
    int total,
    int passed,
    List<VoiceProfile> voices, {
    required void Function() onPassed,
  }) async {
    _emit(TrainEvent(
        state: TrainState.recognizing,
        index: index,
        total: total,
        passed: passed,
        message: '正在识别…'));

    if (pcm.length < 1600) {
      _lastPassed = false;
      _emit(TrainEvent(
          state: TrainState.listening,
          index: index,
          total: total,
          message: '未检测到有效语音，请再读一遍'));
      return;
    }

    var signal = pcm;
    if (config.denoiseEnabled && engine.denoiserReady) {
      try {
        signal = engine.denoise(signal, 16000);
      } catch (_) {}
    }

    // 声纹验证：剔除其他人声
    if (config.speakerVerifyEnabled &&
        voices.isNotEmpty &&
        engine.speakerReady) {
      try {
        final emb = engine.extractEmbedding(signal);
        final isMine = voices.any((v) =>
            _cosine(emb, Float32List.fromList(v.embedding)) >=
            config.speakerThreshold);
        if (!isMine) {
          _lastPassed = false;
          _emit(TrainEvent(
              state: TrainState.listening,
              index: index,
              total: total,
              message: '检测到非本人声音，请本人跟读'));
          return;
        }
      } catch (_) {}
    }

    final recognized = engine.recognize(signal);
    final cleaned = text.collapseRepeats(recognized);
    final score = text.similarity(sentence, cleaned);
    _lastPassed = score >= config.textSimilarityThreshold;
    _emit(TrainEvent(
      state: TrainState.listening,
      index: index,
      total: total,
      passed: passed,
      recognized: recognized,
      score: score,
      message: _lastPassed ? '通过' : '相似度不足，重来',
    ));
    if (_lastPassed) onPassed();
  }

  static double _cosine(Float32List a, Float32List b) {
    final n = a.length < b.length ? a.length : b.length;
    if (n == 0) return 0;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }
}
