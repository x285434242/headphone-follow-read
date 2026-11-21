/// 数据模型：提示词、声纹档案、训练配置

class PromptItem {
  final String id;
  final String text;
  final int order;
  final String note;

  const PromptItem({
    required this.id,
    required this.text,
    this.order = 0,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'order': order,
        'note': note,
      };

  factory PromptItem.fromJson(Map<String, dynamic> j) => PromptItem(
        id: j['id']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        order: (j['order'] as num?)?.toInt() ?? 0,
        note: j['note']?.toString() ?? '',
      );

  PromptItem copyWith({String? text, int? order, String? note}) => PromptItem(
        id: id,
        text: text ?? this.text,
        order: order ?? this.order,
        note: note ?? this.note,
      );
}

class VoiceProfile {
  final String name;
  final List<double> embedding;
  final DateTime createdAt;

  const VoiceProfile({
    required this.name,
    required this.embedding,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'embedding': embedding,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VoiceProfile.fromJson(Map<String, dynamic> j) => VoiceProfile(
        name: j['name']?.toString() ?? '',
        embedding: (j['embedding'] as List? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// 跟读训练配置（对应电脑端 config.py 的字段）
class TrainConfig {
  double textSimilarityThreshold; // 通过线
  double silenceThreshold;        // 静音能量阈值
  double silenceDurationSec;      // 静音多久算一句结束
  double maxListenSec;            // 最长监听
  bool recordDuringPlayback;      // 边播边录
  bool denoiseEnabled;            // 降噪开关
  bool speakerVerifyEnabled;      // 声纹验证开关
  double speakerThreshold;        // 声纹通过线
  String ttsVoice;                // TTS 音色/模型标识
  double ttsSpeed;                // 语速

  TrainConfig({
    this.textSimilarityThreshold = 0.75,
    this.silenceThreshold = 0.02,
    this.silenceDurationSec = 0.8,
    this.maxListenSec = 10.0,
    this.recordDuringPlayback = true,
    this.denoiseEnabled = true,
    this.speakerVerifyEnabled = false,
    this.speakerThreshold = 0.6,
    this.ttsVoice = 'matcha_zh',
    this.ttsSpeed = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'textSimilarityThreshold': textSimilarityThreshold,
        'silenceThreshold': silenceThreshold,
        'silenceDurationSec': silenceDurationSec,
        'maxListenSec': maxListenSec,
        'recordDuringPlayback': recordDuringPlayback,
        'denoiseEnabled': denoiseEnabled,
        'speakerVerifyEnabled': speakerVerifyEnabled,
        'speakerThreshold': speakerThreshold,
        'ttsVoice': ttsVoice,
        'ttsSpeed': ttsSpeed,
      };

  factory TrainConfig.fromJson(Map<String, dynamic> j) => TrainConfig(
        textSimilarityThreshold:
            (j['textSimilarityThreshold'] as num?)?.toDouble() ?? 0.75,
        silenceThreshold: (j['silenceThreshold'] as num?)?.toDouble() ?? 0.02,
        silenceDurationSec:
            (j['silenceDurationSec'] as num?)?.toDouble() ?? 0.8,
        maxListenSec: (j['maxListenSec'] as num?)?.toDouble() ?? 10.0,
        recordDuringPlayback: j['recordDuringPlayback'] as bool? ?? true,
        denoiseEnabled: j['denoiseEnabled'] as bool? ?? true,
        speakerVerifyEnabled: j['speakerVerifyEnabled'] as bool? ?? false,
        speakerThreshold: (j['speakerThreshold'] as num?)?.toDouble() ?? 0.6,
        ttsVoice: j['ttsVoice']?.toString() ?? 'matcha_zh',
        ttsSpeed: (j['ttsSpeed'] as num?)?.toDouble() ?? 1.0,
      );
}

/// 训练状态（UI 用）
enum TrainState { idle, preparing, playing, listening, recognizing, done, error }

class TrainEvent {
  final TrainState state;
  final int index;
  final int total;
  final int passed;
  final String message;
  final String recognized;
  final double score;
  final double level;

  const TrainEvent({
    required this.state,
    this.index = 0,
    this.total = 0,
    this.passed = 0,
    this.message = '',
    this.recognized = '',
    this.score = 0.0,
    this.level = 0.0,
  });
}
