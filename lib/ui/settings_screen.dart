import 'package:flutter/material.dart';
import '../state/settings.dart';
import '../state/translations.dart';
import '../state/player_profile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    // Écouter les changements de settings pour rafraîchir l'UI
    s.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    s.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('audio'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _tile(
            title: tr('music'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: s.musicVolume,
                onChanged: (v) => setState(() => s.setMusic(v)),
              ),
            ),
          ),
          _tile(
            title: tr('effects'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: s.sfxVolume,
                onChanged: (v) => setState(() => s.setSfx(v)),
              ),
            ),
          ),
          SwitchListTile(
            title: Text(tr('vibrations')),
            value: s.vibrations,
            onChanged: (v) => setState(() => s.setVibrations(v)),
          ),
          const SizedBox(height: 12),
          Text(tr('gameplay'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _tile(
            title: tr('joystick_size'),
            trailing: SizedBox(
              width: 220,
              child: Slider(
                value: s.joystickSize,
                min: 0.6,
                max: 1.6,
                onChanged: (v) => setState(() => s.setJoystickSize(v)),
              ),
            ),
          ),
          _tile(
            title: tr('joystick_opacity'),
            trailing: SizedBox(
              width: 220,
              child: Slider(
                value: s.joystickOpacity,
                min: 0.2,
                max: 1.0,
                onChanged: (v) => setState(() => s.setJoystickOpacity(v)),
              ),
            ),
          ),
          _tile(
            title: tr('joystick_margin'),
            trailing: SizedBox(
              width: 220,
              child: Slider(
                value: s.joystickMargin,
                min: 0,
                max: 48,
                onChanged: (v) => setState(() => s.setJoystickMargin(v)),
              ),
            ),
          ),
          DropdownButtonFormField<GraphicsQuality>(
            decoration: InputDecoration(labelText: tr('graphics_quality')),
            value: s.graphics,
            items: [
              DropdownMenuItem(value: GraphicsQuality.low, child: Text(tr('low'))),
              DropdownMenuItem(value: GraphicsQuality.medium, child: Text(tr('medium'))),
              DropdownMenuItem(value: GraphicsQuality.high, child: Text(tr('high'))),
            ],
            onChanged: (v) => setState(() => s.setGraphics(v ?? GraphicsQuality.medium)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(tr('colorblind_mode')),
            value: s.colorBlindMode,
            onChanged: (v) => setState(() => s.setColorBlind(v)),
          ),
          const SizedBox(height: 12),
          Text(tr('language'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: tr('interface_language')),
            value: s.language,
            items: const [
              DropdownMenuItem(value: 'fr', child: Text('Français')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => setState(() => s.setLanguage(v ?? 'fr')),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton.icon(
              onPressed: _showResetDialog,
              icon: const Icon(Icons.restore, color: Colors.red),
              label: Text(tr('reset_game')),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.red,
                minimumSize: const Size(200, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('reset_game_title')),
        content: Text(tr('reset_game_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              await PlayerProfile.instance.resetProfile();
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('reset_game_success'))),
                );
                setState(() {});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('reset_game_confirm')),
          ),
        ],
      ),
    );
  }

  Widget _tile({required String title, required Widget trailing}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: trailing,
    );
  }
}
