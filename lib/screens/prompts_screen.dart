import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../core/models.dart';
import '../core/storage.dart';
import '../core/text_utils.dart' as text;

class PromptsScreen extends StatefulWidget {
  const PromptsScreen({super.key});

  @override
  State<PromptsScreen> createState() => _PromptsScreenState();
}

class _PromptsScreenState extends State<PromptsScreen> {
  List<PromptItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await Storage.loadPrompts();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _save() => Storage.savePrompts(_items);

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);

    List<String> lines;
    if (file.name.toLowerCase().endsWith('.json')) {
      try {
        final raw = jsonDecode(content);
        if (raw is! List) throw const FormatException('JSON 需为数组');
        lines = raw.map((e) => e is Map ? (e['text'] ?? '').toString() : e.toString()).toList();
      } catch (e) {
        _snack('JSON 解析失败：$e');
        return;
      }
    } else {
      lines = text.splitIntoSentences(content);
    }
    lines = lines.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (lines.isEmpty) {
      _snack('文件里没有有效句子');
      return;
    }
    final newItems = <PromptItem>[];
    for (var i = 0; i < lines.length; i++) {
      newItems.add(PromptItem(
          id: DateTime.now().microsecondsSinceEpoch.toString() + '_$i',
          text: lines[i],
          order: i));
    }
    setState(() => _items = newItems);
    await _save();
    _snack('已载入 ${lines.length} 句');
  }

  Future<void> _addOne() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加提示词'),
        content: TextField(controller: controller, autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      setState(() => _items.add(PromptItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            text: controller.text.trim(),
            order: _items.length,
          )));
      await _save();
    }
  }

  Future<void> _delete(int index) async {
    setState(() => _items.removeAt(index));
    await _save();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('提示词（${_items.length} 句）'),
        actions: [
          IconButton(onPressed: _pickFile, tooltip: '导入TXT/JSON', icon: const Icon(Icons.file_upload)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addOne,
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text('还没有提示词。点右上角导入 TXT（自动按标点分句）或 JSON，或点 + 手动添加。',
                  textAlign: TextAlign.center))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (ctx, i) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(_items[i].text),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _delete(i),
                  ),
                ),
              ),
            ),
    );
  }
}
