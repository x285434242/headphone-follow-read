import 'package:flutter/material.dart';
import 'core/globals.dart';
import 'screens/follow_read_screen.dart';
import 'screens/prompts_screen.dart';
import 'screens/voice_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  initEngine();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '耳机跟读训练器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _pages = const [
    FollowReadScreen(),
    PromptsScreen(),
    VoiceScreen(),
    ModelsScreen(),
    SettingsScreen(),
  ];

  @override
  void dispose() {
    audioService.dispose();
    speechEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.record_voice_over), label: '跟读'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '提示词'),
          NavigationDestination(icon: Icon(Icons.fingerprint), label: '声纹'),
          NavigationDestination(icon: Icon(Icons.storage), label: '模型'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
