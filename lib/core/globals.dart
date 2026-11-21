/// 全局单例，独立文件避免 main.dart 与各页面的循环依赖。
import 'package:flutter/material.dart';
import '../services/speech_engine.dart';
import '../services/audio_service.dart';

final speechEngine = SpeechEngine();
final audioService = AudioService();

void initEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  SpeechEngine.ensureBindings();
}
