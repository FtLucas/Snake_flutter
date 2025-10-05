import 'package:flutter/material.dart';
import '../state/player_profile.dart';
import '../state/settings.dart';
import '../state/translations.dart';

class SkillTreeScreen extends StatefulWidget {
  const SkillTreeScreen({super.key});

  @override
  State<SkillTreeScreen> createState() => _SkillTreeScreenState();
}

class _SkillTreeScreenState extends State<SkillTreeScreen> {
  final profile = PlayerProfile.instance;
  final settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('skill_tree'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _coinsBar(),
            const SizedBox(height: 12),
            _skillTile('speed', tr('speed_skill'), tr('speed_skill_desc'), Icons.speed),
            _skillTile('shield', tr('shield_skill'), tr('shield_skill_desc'), Icons.shield),
            _skillTile('food', tr('food_skill'), tr('food_skill_desc'), Icons.restaurant),
          ],
        ),
      ),
    );
  }

  Widget _coinsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on, color: Colors.amber),
          const SizedBox(width: 8),
          Text('${profile.coins}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _skillTile(String key, String title, String desc, IconData icon) {
    final lvl = profile.skillLevel(key);
    final cost = profile.upgradeCost(key, lvl);
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text('$title  (${tr('level_short')} $lvl)'),
        subtitle: Text(desc),
        trailing: ElevatedButton(
          onPressed: () {
            final ok = profile.upgradeSkill(key);
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('not_enough_coins'))),
              );
            }
            setState(() {});
          },
          child: Text('${tr('upgrade')} ($cost)'),
        ),
      ),
    );
  }
}
