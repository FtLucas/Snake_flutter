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
}
