// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'snake_game.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snake Game',
      theme: ThemeData(
        primarySwatch: Colors.green,
        brightness: Brightness.dark,
      ),
      home: GameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late SnakeGame game;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    game = SnakeGame();

    // Timer pour rafraîchir l'UI Flutter (score/level). 100ms est suffisant.
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top UI: score / level / enemies / food (Reset supprimé)
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Score & Level (lecture directe depuis game)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Score: ${game.score}', style: const TextStyle(color: Colors.white, fontSize: 18)),
                      Text('Level: ${game.level}', style: const TextStyle(color: Colors.yellow)),
                    ],
                  ),

                  // Right: enemies / food (anciennement à droite)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Enemies: ${game.enemiesKilled}', style: const TextStyle(color: Colors.red)),
                      Text('Food: ${game.foodEaten}', style: const TextStyle(color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),

            // Game area with gesture detection (swipe handled here)
            Expanded(
              child: Stack(
                children: [
                  GestureDetector(
                    onPanUpdate: (details) {
                      game.handlePanUpdate(details);
                    },
                    onTapDown: (details) {
                      game.handleTapDown(details);
                    },
                    child: GameWidget(game: game),
                  ),

                  // overlay for power-up selection
                  if (game.showPowerUpSelection)
                    Container(
                      color: Colors.black.withOpacity(0.8),
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('NIVEAU SUPÉRIEUR!', style: TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              const Text('Choisissez une amélioration:', style: TextStyle(color: Colors.white, fontSize: 18)),
                              const SizedBox(height: 20),
                              ...game.availablePowerUps.map((powerUp) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        game.selectPowerUp(powerUp.type);
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: powerUp.color,
                                      minimumSize: const Size(300, 64),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(powerUp.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                        const SizedBox(height: 6),
                                        Text(powerUp.description, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Game over display (avec Reset)
                  if (game.gameOver)
                    Container(
                      color: Colors.black.withOpacity(0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('GAME OVER', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Text('Score: ${game.score}', style: const TextStyle(color: Colors.white)),
                            Text('Level: ${game.level}', style: const TextStyle(color: Colors.white)),
                            Text('Enemies killed: ${game.enemiesKilled}', style: const TextStyle(color: Colors.white)),
                            Text('Food eaten: ${game.foodEaten}', style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  game.resetGame();
                                });
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(160, 50)),
                              child: Text('Reset'),
                            )
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom area: only power-up indicators, tactile arrow buttons removed
            Container(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  // Power-up indicator chips (kept)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (game.hasShield)
                        Chip(label: Text('🛡️ ${game.shieldDuration.toStringAsFixed(1)}s'), backgroundColor: Colors.cyan.withOpacity(0.2)),
                      if (game.hasMultiFood)
                        Chip(label: Text('🍎x2 ${game.multiFoodDuration.toStringAsFixed(1)}s'), backgroundColor: Colors.orange.withOpacity(0.2)),
                      if (game.speedMultiplier > 1.0)
                        Chip(label: Text('⚡ x${game.speedMultiplier.toStringAsFixed(1)}'), backgroundColor: Colors.yellow.withOpacity(0.2)),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // (Directional buttons removed — use swipe now)
                  const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
