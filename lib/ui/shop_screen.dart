import 'package:flutter/material.dart';
import '../state/player_profile.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final profile = PlayerProfile.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boutique')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _coinsBar(),
            const SizedBox(height: 12),
            _item('Pack de pièces (100)', 100, () {
              profile.addCoins(100);
              setState(() {});
            }),
            const SizedBox(height: 12),
            _item('Pack de pièces (500)', 500, () {
              profile.addCoins(500);
              setState(() {});
            }),
            const SizedBox(height: 20),
            const Text('Cosmétiques', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _cosmetic('Skin Serpent Vert Néon'),
            _cosmetic('Trail Étincelles'),
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

  Widget _item(String title, int price, VoidCallback onBuy) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: ElevatedButton(
          onPressed: onBuy,
          child: const Text('Acheter'),
        ),
      ),
    );
  }

  Widget _cosmetic(String name) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.brush),
        title: Text(name),
        subtitle: const Text('Bientôt disponible'),
        trailing: OutlinedButton(onPressed: null, child: const Text('Locked')),
      ),
    );
  }
}
