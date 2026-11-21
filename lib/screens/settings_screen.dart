import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TrainConfig _c = TrainConfig();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Storage.loadConfig();
    if (mounted) setState(() => _c = c);
  }

  Future<void> _save() async {
    await Storage.saveConfig(_c);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')));
    }
  }

  Widget _slider(String label, double value, double min, double max, int digits,
      void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value.toStringAsFixed(digits),
                style: const TextStyle(color: Colors.indigo)),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.save))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('跟读流程', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('播放时同步收音（影子跟读）'),
            subtitle: const Text('开：听到就读；关：播完→再录音'),
            value: _c.recordDuringPlayback,
            onChanged: (v) => setState(() => _c.recordDuringPlayback = v),
          ),
          SwitchListTile(
            title: const Text('启用降噪（剔除背景杂音）'),
            value: _c.denoiseEnabled,
            onChanged: (v) => setState(() => _c.denoiseEnabled = v),
          ),
          SwitchListTile(
            title: const Text('启用声纹验证（剔除其他人声）'),
            subtitle: const Text('需先在「声纹」页建档，并放置 VoxLock 模型'),
            value: _c.speakerVerifyEnabled,
            onChanged: (v) => setState(() => _c.speakerVerifyEnabled = v),
          ),
          const Divider(height: 24),
          const Text('判定参数', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          _slider('文本相似度通过线', _c.textSimilarityThreshold, 0.5, 1.0, 2,
              (v) => setState(() => _c.textSimilarityThreshold = v)),
          _slider('声纹通过线', _c.speakerThreshold, 0.3, 0.9, 2,
              (v) => setState(() => _c.speakerThreshold = v)),
          _slider('静音能量阈值', _c.silenceThreshold, 0.005, 0.1, 3,
              (v) => setState(() => _c.silenceThreshold = v)),
          _slider('静音判定秒数', _c.silenceDurationSec, 0.3, 2.0, 1,
              (v) => setState(() => _c.silenceDurationSec = v)),
          _slider('最长监听秒数', _c.maxListenSec, 5, 30, 0,
              (v) => setState(() => _c.maxListenSec = v)),
          _slider('语速', _c.ttsSpeed, 0.6, 1.6, 2,
              (v) => setState(() => _c.ttsSpeed = v)),
          const Divider(height: 24),
          const Text('语音输出', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ListTile(
            title: const Text('TTS 音色/引擎'),
            subtitle: Text(_c.ttsVoice),
            trailing: DropdownButton<String>(
              value: _c.ttsVoice,
              items: const [
                DropdownMenuItem(value: 'matcha_zh', child: Text('Matcha 中文（多音字注音）')),
                DropdownMenuItem(value: 'vits_zh', child: Text('VITS 中文')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _c.ttsVoice = v);
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存设置'),
            ),
          ),
        ],
      ),
    );
  }
}
