/// sherpa-onnx 引擎封装：离线 ASR（SenseVoice）、离线 TTS（Matcha/VITS）、
/// 声纹嵌入（3D-Speaker）、语音降噪（GTCRN / VoxLock）。
///
/// 所有 API 签名均按 sherpa-onnx Flutter 插件 2.0.2 官方源码核对。
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'model_paths.dart';

class SpeechEngine {
  static bool _bound = false;

  sherpa.OfflineRecognizer? _asr;
  sherpa.OfflineTts? _tts;
  sherpa.SpeakerEmbeddingExtractor? _speaker;
  sherpa.OfflineSpeechDenoiser? _denoiser;

  /// 必须在任何 sherpa-onnx 调用前执行一次（每个 isolate 都要，App 单 isolate 即可）。
  static void ensureBindings() {
    if (_bound) return;
    sherpa.initBindings();
    _bound = true;
  }

  int get ttsSampleRate => _tts?.sampleRate ?? 22050;
  bool get asrReady => _asr != null;
  bool get ttsReady => _tts != null;
  bool get speakerReady => _speaker != null;
  bool get denoiserReady => _denoiser != null;
  int get speakerDim => _speaker?.dim ?? 0;

  /// 初始化 ASR：SenseVoice（中文/方言/情感识别强），失败可回退 Paraformer。
  Future<void> initAsr({String language = 'zh'}) async {
    ensureBindings();
    final model = await ModelPaths.asrModel();
    final tokens = await ModelPaths.asrTokens();

    final modelCfg = sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: model,
        language: language,
        useInverseTextNormalization: true,
      ),
      tokens: tokens,
      numThreads: 2,
      provider: 'cpu',
    );
    final cfg = sherpa.OfflineRecognizerConfig(model: modelCfg);
    _asr = sherpa.OfflineRecognizer(cfg);
  }

  /// 初始化 TTS：Matcha（中文自然、端侧轻量），需 acoustic model + vocoder + tokens + lexicon。
  Future<void> initTts() async {
    ensureBindings();
    final model = await ModelPaths.ttsModel();
    final vocoder = await ModelPaths.ttsVocoder();
    final tokens = await ModelPaths.ttsTokens();
    final lexicon = await ModelPaths.ttsLexicon();

    final modelCfg = sherpa.OfflineTtsModelConfig(
      matcha: sherpa.OfflineTtsMatchaModelConfig(
        acousticModel: model,
        vocoder: vocoder,
        tokens: tokens,
        lexicon: lexicon,
      ),
      numThreads: 2,
      provider: 'cpu',
    );
    _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelCfg));
  }

  /// 初始化声纹嵌入提取器（3D-Speaker ERes2Net，中文说话人）。
  Future<void> initSpeaker() async {
    ensureBindings();
    final model = await ModelPaths.speakerModel();
    _speaker = sherpa.SpeakerEmbeddingExtractor(
      config: sherpa.SpeakerEmbeddingExtractorConfig(
        model: model,
        numThreads: 2,
        provider: 'cpu',
      ),
    );
  }

  /// 初始化降噪：GTCRN（去背景噪声）。若提供声纹样本路径，可用 VoxLock 保留本人声、
  /// 剔除其他人声（voxLockVoiceSample 非空时启用 VoxLock 而非 GTCRN）。
  Future<void> initDenoise({String voxLockVoiceSample = ''}) async {
    ensureBindings();
    final gtcrn = await ModelPaths.denoiseModel();
    final useVoxLock = voxLockVoiceSample.isNotEmpty;
    final modelCfg = sherpa.OfflineSpeechDenoiserModelConfig(
      gtcrn: sherpa.OfflineSpeechDenoiserGtcrnModelConfig(
        model: useVoxLock ? '' : gtcrn,
      ),
      voxlock: sherpa.OfflineSpeechDenoiserVoxLockModelConfig(
        enrollModel: useVoxLock ? await ModelPaths.voxLockEnroll() : '',
        chunkModel: useVoxLock ? await ModelPaths.voxLockChunk() : '',
        voiceSample: voxLockVoiceSample,
      ),
      numThreads: 2,
      provider: 'cpu',
    );
    _denoiser = sherpa.OfflineSpeechDenoiser(
        sherpa.OfflineSpeechDenoiserConfig(model: modelCfg));
  }

  /// ASR：整段 PCM → 文字。samples 为 float32 单声道（16k）。
  String recognize(Float32List samples, {int sampleRate = 16000}) {
    if (_asr == null) throw StateError('ASR 未初始化');
    final stream = _asr!.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      _asr!.decode(stream);
      return _asr!.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  /// TTS：文字 → PCM（含语速、情绪标签）。mood/speed 来自语气语调分析。
  sherpa.GeneratedAudio synthesize(
    String text, {
    double speed = 1.0,
    int sid = 0,
  }) {
    if (_tts == null) throw StateError('TTS 未初始化');
    final config = sherpa.OfflineTtsGenerationConfig(
      sid: sid,
      speed: speed,
      silenceScale: 0.2,
    );
    return _tts!.generateWithConfig(text: text, config: config);
  }

  /// 声纹：PCM → embedding 向量。
  Float32List extractEmbedding(Float32List samples, {int sampleRate = 16000}) {
    if (_speaker == null) throw StateError('声纹模型未初始化');
    final stream = _speaker!.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      // 整段音频一次送入后即可提取；训练时建议 3 秒以上样本更稳定
      return _speaker!.compute(stream);
    } finally {
      stream.free();
    }
  }

  /// 降噪：PCM → 干净 PCM（官方方法名是 run）。
  Float32List denoise(Float32List samples, int sampleRate) {
    if (_denoiser == null) throw StateError('降噪模型未初始化');
    final out = _denoiser!.run(samples: samples, sampleRate: sampleRate);
    return Float32List.fromList(out.samples);
  }

  void dispose() {
    _asr?.free();
    _tts?.free();
    _speaker?.free();
    _denoiser?.free();
    _asr = null;
    _tts = null;
    _speaker = null;
    _denoiser = null;
  }
}
