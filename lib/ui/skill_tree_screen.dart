import 'package:flutter/material.dart';
import '../state/player_profile.dart';

class SkillTreeScreen extends StatefulWidget {
  const SkillTreeScreen({super.key});

  @override
  State<SkillTreeScreen> createState() => _SkillTreeScreenState();
}

class _SkillTreeScreenState extends State<SkillTreeScreen> {
  final profile = PlayerProfile.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arbre de compétences')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _coinsBar(),
            const SizedBox(height: 12),
            _skillTile('speed', 'Vitesse', 'Augmente la vitesse de base', Icons.speed),
            _skillTile('shield', 'Bouclier', 'Augmente la durée du bouclier de départ', Icons.shield),
            _skillTile('food', 'Glouton', 'Augmente les points gagnés en mangeant', Icons.restaurant),
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
        title: Text('$title  (Niv. $lvl)'),
        subtitle: Text(desc),
        trailing: ElevatedButton(
          onPressed: () {
            final ok = profile.upgradeSkill(key);
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pas assez de pièces')),
              );
            }
            setState(() {});
          },
          child: Text('Améliorer ($cost)'),
        ),
      ),
    );
  }
}
