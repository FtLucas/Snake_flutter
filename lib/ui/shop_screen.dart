import 'package:flutter/material.dart';
import '../state/player_profile.dart';
import '../state/settings.dart';
import '../state/translations.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
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
      appBar: AppBar(title: Text(tr('shop'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _coinsBar(),
            const SizedBox(height: 12),
            _item(tr('coin_pack_100'), 100, () {
              profile.addCoins(100);
              setState(() {});
            }),
            const SizedBox(height: 12),
            _item(tr('coin_pack_500'), 500, () {
              profile.addCoins(500);
              setState(() {});
            }),
            const SizedBox(height: 20),
            Text(tr('cosmetics'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _cosmetic(tr('skin_neon_snake'), 'skin_neon'),
            _cosmetic(tr('trail_sparks'), 'trail_sparks'),
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
          child: Text(tr('buy')),
        ),
      ),
    );
  }

  Widget _cosmetic(String name, String id) {
    final owned = profile.isOwned(id);
    final equipped = (id == profile.equippedSnakeSkin) || (id == profile.equippedTrail);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.brush),
        title: Text(name),
        subtitle: owned
            ? (equipped ? Text(tr('equipped')) : null)
            : Text(tr('locked')),
        trailing: owned
            ? (equipped
                ? null
                : TextButton(
                    onPressed: () {
                      if (id.startsWith('skin_')) {
                        profile.equippedSnakeSkin = id;
                      } else {
                        profile.equippedTrail = id;
                      }
                      setState(() {});
                    },
                    child: Text(tr('equip')),
                  ))
            : ElevatedButton(
                onPressed: () {
                  if (profile.spend(50)) {
                    profile.ownedCosmetics.add(id);
                    setState(() {});
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('not_enough_coins'))),
                    );
                  }
                },
                child: Text(tr('buy')),
              ),
      ),
    );
  }
}
