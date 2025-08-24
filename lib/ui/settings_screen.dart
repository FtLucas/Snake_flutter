import 'package:flutter/material.dart';
import '../state/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Audio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _tile(
            title: 'Musique',
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: s.musicVolume,
                onChanged: (v) => setState(() => s.setMusic(v)),
              ),
            ),
          ),
          _tile(
            title: 'Effets',
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: s.sfxVolume,
                onChanged: (v) => setState(() => s.setSfx(v)),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Vibrations'),
            value: s.vibrations,
            onChanged: (v) => setState(() => s.setVibrations(v)),
          ),
          const SizedBox(height: 12),
          const Text('Gameplay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Joystick gaucher'),
            value: s.leftHandedJoystick,
            onChanged: (v) => setState(() => s.setLeftHanded(v)),
          ),
          _tile(
            title: 'Taille joystick',
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
            title: 'Opacité joystick',
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
            title: 'Marge joystick',
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
            decoration: const InputDecoration(labelText: 'Qualité graphique'),
            value: s.graphics,
            items: const [
              DropdownMenuItem(value: GraphicsQuality.low, child: Text('Basse')),
              DropdownMenuItem(value: GraphicsQuality.medium, child: Text('Moyenne')),
              DropdownMenuItem(value: GraphicsQuality.high, child: Text('Haute')),
            ],
            onChanged: (v) => setState(() => s.setGraphics(v ?? GraphicsQuality.medium)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Daltonien'),
            value: s.colorBlindMode,
            onChanged: (v) => setState(() => s.setColorBlind(v)),
          ),
          const SizedBox(height: 12),
          const Text('Langue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Langue de l’interface'),
            value: s.language,
            items: const [
              DropdownMenuItem(value: 'fr', child: Text('Français')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => setState(() => s.setLanguage(v ?? 'fr')),
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
