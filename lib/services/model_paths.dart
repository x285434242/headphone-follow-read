/// 模型文件路径约定。
///
/// 模型体积较大（ASR ~230MB、TTS ~100MB+、声纹 ~30MB、降噪 ~5MB），
/// 不打包进 APK，首次启动时下载到应用数据目录 models/ 下。
/// 各模型下载地址见项目根 README 的「模型清单」表，App 内「模型管理」页
/// 提供手动放置/校验入口。这里只负责拼出 sherpa-onnx 需要的路径。
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelPaths {
  static Future<String> get baseDir async {
    final dir = await getApplicationSupportDirectory();
    final models = p.join(dir.path, 'models');
    await Directory(models).create(recursive: true);
    return models;
  }

  static Future<String> asrModel() async => p.join(await baseDir, 'asr', 'model.onnx');
  static Future<String> asrTokens() async => p.join(await baseDir, 'asr', 'tokens.txt');

  static Future<String> ttsModel() async => p.join(await baseDir, 'tts', 'model.onnx');
  static Future<String> ttsTokens() async => p.join(await baseDir, 'tts', 'tokens.txt');
  static Future<String> ttsLexicon() async => p.join(await baseDir, 'tts', 'lexicon.txt');
  static Future<String> ttsVocoder() async => p.join(await baseDir, 'tts', 'vocoder.onnx');

  static Future<String> speakerModel() async =>
      p.join(await baseDir, 'speaker', 'embedding.onnx');
  static Future<String> denoiseModel() async =>
      p.join(await baseDir, 'denoise', 'gtcrn_simple.onnx');
  static Future<String> voxLockEnroll() async =>
      p.join(await baseDir, 'denoise', 'enroll.onnx');
  static Future<String> voxLockChunk() async =>
      p.join(await baseDir, 'denoise', 'chunk_int8.onnx');

  /// 检查某模型是否已就绪（非空文件）。
  static Future<bool> exists(String path) async {
    final f = File(path);
    return await f.exists() && await f.length() > 1024;
  }

  /// 返回缺失的模型文件列表，供 UI 提示。
  static Future<List<String>> missing() async {
    final candidates = <String>[
      await asrModel(), await asrTokens(),
      await ttsModel(), await ttsTokens(), await ttsLexicon(),
      await speakerModel(),
    ];
    final out = <String>[];
    for (final c in candidates) {
      if (!await exists(c)) out.add(p.basename(c));
    }
    return out;
  }
}
