import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/audio_service.dart';
import 'theme.dart';
import 'screens/browse_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/player_screen.dart';
import 'widgets/mini_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AudioService(),
      child: const PigMobileApp(),
    ),
  );
}

class PigMobileApp extends StatelessWidget {
  const PigMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIG',
      theme: PigTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}

/// Main app shell with bottom nav + mini player.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentTab = 0;

  final _tabs = const [
    _TabInfo(icon: Icons.play_circle_outline, label: 'Player'),
    _TabInfo(icon: Icons.tune, label: 'Browse'),
    _TabInfo(icon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentTab == 0
          ? null
          : AppBar(
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  'assets/pigIconsnout.png',
                  errorBuilder: (_, e, s) =>
                      const Icon(Icons.music_note, color: PigTheme.hotPink),
                ),
              ),
              title: const Text(
                'PIG',
                style: TextStyle(
                  color: PigTheme.hotPink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: const [
                PlayerScreen(asTab: true),
                BrowseScreen(),
                SettingsScreen(),
              ],
            ),
          ),
          if (_currentTab != 0)
            MiniPlayer(onTap: () => setState(() => _currentTab = 0)),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: _tabs
            .map(
              (t) =>
                  BottomNavigationBarItem(icon: Icon(t.icon), label: t.label),
            )
            .toList(),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo({required this.icon, required this.label});
}
