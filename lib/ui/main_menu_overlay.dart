import 'package:flutter/material.dart';
import '../snake_game.dart';

class MainMenuOverlay extends StatelessWidget {
  final SnakeGame game;
  const MainMenuOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SNAKE',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arcade Survival',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Démarre une nouvelle partie
                  game.resetGame();
                  game.overlays.remove('MainMenu');
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Jouer'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  // Placeholder paramètres
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Paramètres à venir')),
                  );
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: const Text('Paramètres'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Afficher/masquer le menu sans fermer l’app
                game.overlays.remove('MainMenu');
              },
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }
}
