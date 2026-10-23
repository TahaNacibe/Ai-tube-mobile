import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_constants.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiTubeApp());
}

class AiTubeApp extends StatefulWidget {
  const AiTubeApp({super.key});

  @override
  State<AiTubeApp> createState() => _AiTubeAppState();
}

class _AiTubeAppState extends State<AiTubeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Map<String, dynamic> _preferences = {
    'assistantName': 'Assistant',
    'apiBaseUrl': 'http://10.0.2.2:8000',
    'webSearchEnabled': true,
    'imageSearchEnabled': true,
    'darkModeEnabled': false,
    'profileName': '',
    'profilePersona': '',
    'profileContext': '',
    'profileAvatar': '',
  };
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final store = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(store.getString(preferencesKey) ?? '{}');
      if (saved is Map<String, dynamic>) _preferences.addAll(saved);
    } on FormatException {
      await store.remove(preferencesKey);
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _savePreferences(Map<String, dynamic> next) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(preferencesKey, jsonEncode(next));
    if (mounted) setState(() => _preferences = next);
  }

  Future<void> _openSettings() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final updated = await navigator.push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          preferences: Map<String, dynamic>.from(_preferences),
          onSave: _savePreferences,
        ),
      ),
    );
    if (updated != null) await _savePreferences(updated);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _preferences['darkModeEnabled'] == true;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'AI Tube',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(false),
      darkTheme: buildAppTheme(true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ChatScreen(
              preferences: _preferences,
              onOpenSettings: _openSettings,
            ),
    );
  }
}
