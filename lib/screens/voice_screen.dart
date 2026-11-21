import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/storage.dart';
import '../core/globals.dart' show speechEngine, audioService;
import '../services/voice_trainer.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  List<VoiceProfile> _voices = [];
  bool _training = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await Storage.loadVoices();
    if (mounted) setState(() => _voices = v);
  }

  Future<void> _train() async {
    final granted = await audioService.ensurePermission();
    if (!granted) {
      _snack('需要麦克风权限');
      return;
    }
    if (!speechEngine.speakerReady) {
      try {
        await speechEngine.initSpeaker();
      } catch (e) {
        _snack('声纹模型未就绪：$e');
        return;
      }
    }
    if (speechEngine.denoiserReady == false) {
      try { await speechEngine.initDenoise(); } catch (_) {}
    }

    final nameCtrl = TextEditingController(text: '我的声纹');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练声纹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('将录 3 段、每段约 3 秒，读任意句子即可。'),
            const SizedBox(height: 8),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '档案名称')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _training = true);
    final trainer = VoiceTrainer(engine: speechEngine, audio: audioService);
    final profile = await trainer.train(
      name: nameCtrl.text,
      onProgress: (cur, total, msg) {
        if (mounted) setState(() => _progress = '[$cur/$total] $msg');
      },
    );
    if (mounted) setState(() => _training = false);
    if (profile != null) {
      await _load();
      _snack('声纹「${profile.name}」训练完成');
    } else {
      _snack('训练失败，请检查模型与麦克风');
    }
  }

  Future<void> _delete(VoiceProfile v) async {
    final list = await Storage.loadVoices();
    list.removeWhere((x) => x.name == v.name);
    await Storage.saveVoices(list);
    await _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('声纹训练')),
      floatingActionButton: FloatingActionButton(
        onPressed: _training ? null : _train,
        child: const Icon(Icons.fingerprint),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '录几段自己的声音建立声纹档案，训练时会自动提取特征并降噪。'
              '建档后可开启「声纹验证」，跟读时剔除其他人的声音。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_training) ...[
              LinearProgressIndicator(value: null),
              const SizedBox(height: 8),
              Text(_progress),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _voices.isEmpty
                  ? const Center(child: Text('还没有声纹档案，点右下角按钮训练'))
                  : ListView.builder(
                      itemCount: _voices.length,
                      itemBuilder: (ctx, i) {
                        final v = _voices[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.record_voice_over),
                            title: Text(v.name),
                            subtitle: Text(
                                '${v.embedding.length} 维 · ${v.createdAt.toString().substring(0, 16)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _delete(v),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
