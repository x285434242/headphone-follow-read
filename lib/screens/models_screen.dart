import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/model_paths.dart';

class ModelEntry {
  final String name;
  final String file;
  final String purpose;
  final String url;
  final Future<String> Function() path;
  final bool required;

  ModelEntry({
    required this.name,
    required this.file,
    required this.purpose,
    required this.url,
    required this.path,
    this.required = true,
  });
}

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final List<ModelEntry> _entries = [
    ModelEntry(
      name: 'ASR 识别模型 (SenseVoice)',
      file: 'asr/model.onnx + tokens.txt',
      purpose: '中文/方言精准识别，替换原 tiny 模型',
      url: 'https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models',
      path: ModelPaths.asrModel,
    ),
    ModelEntry(
      name: 'TTS 声学模型 (Matcha)',
      file: 'tts/model.onnx + vocoder.onnx + tokens.txt + lexicon.txt',
      purpose: '端侧中文语音合成（可语音克隆）',
      url: 'https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models',
      path: ModelPaths.ttsModel,
    ),
    ModelEntry(
      name: '声纹嵌入 (3D-Speaker)',
      file: 'speaker/embedding.onnx',
      purpose: '声纹注册/验证、剔除其他人声',
      url: 'https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-models',
      path: ModelPaths.speakerModel,
    ),
    ModelEntry(
      name: '降噪 (GTCRN)',
      file: 'denoise/gtcrn_simple.onnx',
      purpose: '剔除背景杂音',
      url: 'https://github.com/k2-fsa/sherpa-onnx/releases/tag/speech-enhancement-models',
      path: ModelPaths.denoiseModel,
      required: false,
    ),
    ModelEntry(
      name: '目标说话人提取 (VoxLock)',
      file: 'denoise/enroll.onnx + chunk_int8.onnx',
      purpose: '保留本人声、剔除其他人声（需先训练声纹）',
      url: 'https://github.com/k2-fsa/sherpa-onnx/releases',
      path: ModelPaths.voxLockEnroll,
      required: false,
    ),
  ];

  final Map<int, bool> _status = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final base = await ModelPaths.baseDir;
    final map = <int, bool>{};
    for (var i = 0; i < _entries.length; i++) {
      final path = await _entries[i].path();
      map[i] = await ModelPaths.exists(path);
    }
    if (mounted) setState(() => _status.addAll(map));
    // ignore: unused_local_variable
    final unused = base;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型管理'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '模型体积较大，不打包进 APK。首次使用请从 GitHub Releases 下载，'
                '解压后用文件管理器放到手机：\n'
                'Android/data/com.example.earphone_follow_read/files/models/ 对应子目录。'
                '也可点下方各模型的「下载」直达发布页。',
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(_entries.length, (i) {
            final e = _entries[i];
            final ok = _status[i] ?? false;
            return Card(
              child: ListTile(
                leading: Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: ok ? Colors.green : Colors.grey,
                ),
                title: Text(e.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.purpose, style: const TextStyle(fontSize: 12)),
                    Text(e.file,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    FutureBuilder<String>(
                      future: e.path(),
                      builder: (ctx, snap) => Text(
                        '路径：${snap.data ?? ''}',
                        style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
                trailing: TextButton(
                  onPressed: () => _openUrl(e.url),
                  child: const Text('下载'),
                ),
                isThreeLine: true,
              ),
            );
          }),
        ],
      ),
    );
  }
}
