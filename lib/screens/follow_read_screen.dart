import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/storage.dart';
import '../core/text_utils.dart' as text;
import '../services/follow_read_engine.dart';
import '../services/model_paths.dart' as ModelPaths;
import '../core/globals.dart' show speechEngine, audioService;

class FollowReadScreen extends StatefulWidget {
  const FollowReadScreen({super.key});

  @override
  State<FollowReadScreen> createState() => _FollowReadScreenState();
}

class _FollowReadScreenState extends State<FollowReadScreen> {
  TrainConfig _config = TrainConfig();
  List<PromptItem> _prompts = [];
  List<String> get _sentences =>
      _prompts.where((p) => p.text.trim().isNotEmpty).map((p) => p.text).toList();

  TrainEvent _state = const TrainEvent(state: TrainState.idle, message: '就绪');
  FollowReadEngine? _engine;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Storage.loadConfig();
    final p = await Storage.loadPrompts();
    if (mounted) setState(() {
      _config = c;
      _prompts = p;
    });
  }

  Future<void> _start() async {
    if (_sentences.isEmpty) {
      _snack('请先到「提示词」页上传或添加句子');
      return;
    }
    if (!speechEngine.asrReady || !speechEngine.ttsReady) {
      final missing = await _initModels();
      if (!mounted) return;
      if (missing != null) {
        _snack(missing);
        return;
      }
    }

    final granted = await audioService.ensurePermission();
    if (!granted) {
      _snack('需要麦克风权限才能跟读');
      return;
    }

    final voices = await Storage.loadVoices();
    setState(() => _running = true);
    _engine = FollowReadEngine(
      engine: speechEngine,
      audio: audioService,
      config: _config,
      onEvent: (e) {
        if (mounted) setState(() => _state = e);
      },
    );
    await _engine!.run(_sentences, voices: voices);
    if (mounted) setState(() => _running = false);
  }

  /// 尝试从已放置的模型文件初始化引擎；返回错误信息或 null（成功）。
  Future<String?> _initModels() async {
    try {
      final ready = await _hasModels();
      if (!ready) {
        return '模型未就绪：请到「模型」页按清单放置模型文件';
      }
      await speechEngine.initAsr();
      await speechEngine.initTts();
      if (_config.denoiseEnabled) {
        try { await speechEngine.initDenoise(); } catch (_) {}
      }
      if (_config.speakerVerifyEnabled) {
        try { await speechEngine.initSpeaker(); } catch (_) {}
      }
      return null;
    } catch (e) {
      return '模型加载失败：$e';
    }
  }

  Future<bool> _hasModels() async {
    // 复用 model_paths 的缺失检查
    return await _checkAllModels();
  }

  Future<bool> _checkAllModels() async {
    final m = await ModelPaths.missing();
    return m.isEmpty;
  }

  void _stop() {
    _engine?.stop();
    setState(() => _state = const TrainEvent(state: TrainState.idle, message: '正在停止…'));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final idx = _state.index;
    final total = _state.total;
    final current = (idx >= 0 && idx < _sentences.length) ? _sentences[idx] : '—';

    return Scaffold(
      appBar: AppBar(title: const Text('跟读训练')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _running ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始训练'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _running ? _stop : null,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: total > 0 ? (idx + 1) / total : 0,
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text('进度 ${total > 0 ? idx + 1 : 0} / $total　通过 ${_state.passed}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  current,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('状态：${_state.message}',
                style: TextStyle(
                  color: _state.state == TrainState.error ? Colors.red : Colors.indigo,
                  fontSize: 16,
                )),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _state.level.clamp(0.0, 1.0).toDouble()),
            const Text('音量（读的时候应跳动）',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('识别到的文字：', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(_state.recognized.isEmpty ? '—' : _state.recognized,
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(_state.score > 0
                        ? '相似度 ${(_state.score * 100).toStringAsFixed(0)}%（通过线 ${(_config.textSimilarityThreshold * 100).toStringAsFixed(0)}%）'
                        : '相似度：—',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Text(
              '提示：默认边播边录，听到朗读就直接跟着读，不必等播完。'
              '模型与声纹请先到对应页面配置。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
