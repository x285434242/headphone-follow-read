/// 本地存储：提示词、声纹档案、训练配置（SharedPreferences + JSON）
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class Storage {
  static const _kPrompts = 'prompts_json';
  static const _kVoices = 'voices_json';
  static const _kConfig = 'config_json';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get prefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ---------- 提示词 ----------
  static Future<List<PromptItem>> loadPrompts() async {
    final raw = (await prefs).getString(_kPrompts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PromptItem.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePrompts(List<PromptItem> items) async {
    await (await prefs).setString(
        _kPrompts, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  // ---------- 声纹 ----------
  static Future<List<VoiceProfile>> loadVoices() async {
    final raw = (await prefs).getString(_kVoices);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => VoiceProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveVoices(List<VoiceProfile> items) async {
    await (await prefs).setString(
        _kVoices, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  // ---------- 配置 ----------
  static Future<TrainConfig> loadConfig() async {
    final raw = (await prefs).getString(_kConfig);
    if (raw == null || raw.isEmpty) return TrainConfig();
    try {
      return TrainConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return TrainConfig();
    }
  }

  static Future<void> saveConfig(TrainConfig c) async {
    await (await prefs).setString(_kConfig, jsonEncode(c.toJson()));
  }
}
