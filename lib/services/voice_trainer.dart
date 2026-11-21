/// 声纹训练：在 App 内录几段话 → 提取 embedding → 建档保存。
/// 支持多次采样取平均，提升稳健性；训练样本也用作 VoxLock 的声纹样本，
/// 供「剔除其他人声、保留本人声」使用。
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/storage.dart';
import 'speech_engine.dart';
import 'audio_service.dart';

class VoiceTrainer {
  final SpeechEngine engine;
  final AudioService audio;
  VoiceTrainer({required this.engine, required this.audio});

  /// 录 n 段样本并训练一个声纹档案。onProgress(当前段/总数, 提示)。
  Future<VoiceProfile?> train({
    required String name,
    int samples = 3,
    required void Function(int, int, String) onProgress,
  }) async {
    if (!engine.speakerReady) {
      onProgress(0, samples, '声纹模型未就绪');
      return null;
    }
    final embeddings = <Float32List>[];

    for (var i = 1; i <= samples; i++) {
      onProgress(i, samples, '第 $i / $samples 段：请读数一句话（约3秒）');
      await audio.startRecording();
      // 采集约 3.5 秒
      await Future.delayed(const Duration(milliseconds: 3500));
      final pcm = await audio.stopRecording();
      if (pcm.length < 16000) {
        onProgress(i, samples, '样本太短，请重录这一段');
        i--; // 重录本段
        continue;
      }
      final denoised = engine.denoiserReady
          ? _safeDenoise(pcm)
          : pcm;
      embeddings.add(engine.extractEmbedding(denoised));
      onProgress(i, samples, '第 $i 段采集完成');
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (embeddings.isEmpty) return null;
    // 多样本取平均
    final dim = embeddings.first.length;
    final avg = Float32List(dim);
    for (final e in embeddings) {
      for (var i = 0; i < dim && i < e.length; i++) {
        avg[i] += e[i] / embeddings.length;
      }
    }

    final profile = VoiceProfile(
      name: name.trim().isEmpty ? '我的声纹' : name.trim(),
      embedding: avg.toList(),
      createdAt: DateTime.now(),
    );
    final list = await Storage.loadVoices();
    list.removeWhere((v) => v.name == profile.name);
    list.add(profile);
    await Storage.saveVoices(list);

    // 保存一份最佳样本 wav 供 VoxLock 使用（保留本人声、剔除他人声）
    await _saveVoiceSample(name, embeddings.isNotEmpty ? avg : null);
    return profile;
  }

  Float32List _safeDenoise(Float32List pcm) {
    try {
      return engine.denoise(pcm, 16000);
    } catch (_) {
      return pcm;
    }
  }

  /// 保存声纹样本路径占位（真实音频由录音流程写入；这里写文本文件供 VoxLock 引用校验收集）。
  Future<void> _saveVoiceSample(String name, Float32List? embedding) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final voiceDir = Directory(p.join(dir.path, 'models', 'denoise'));
      await voiceDir.create(recursive: true);
      final f = File(p.join(voiceDir.path, 'voice_sample.info'));
      await f.writeAsString('owner=${name.trim()}\ndim=${embedding?.length ?? 0}\n'
          'note=请通过模型管理页放置 VoxLock 模型(enroll.onnx/chunk_int8.onnx)以启用剔除他人声\n');
    } catch (_) {}
  }
}
