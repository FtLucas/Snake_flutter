// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'snake_game.dart';

void main() {
  runApp(const MyApp());
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
      home: const GameScreen(),
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
  bool _paused = false;
  String? _directionErrorMsg;

  @override
  void initState() {
    super.initState();
    game = SnakeGame(
      onDirectionError: _showDirectionError,
    );
      if (mounted) setState(() {});
  }

  void _showDirectionError(String msg) {
    setState(() {
      _directionErrorMsg = msg;
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _directionErrorMsg = null;
        });
      }
    });
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      game.gameStarted = !_paused;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Game and UI in a column
            Column(
              children: [
                Container(
                  height: 70,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Score: ${game.score}', style: const TextStyle(color: Colors.white, fontSize: 18)),
                          Text('Level: ${game.level}', style: const TextStyle(color: Colors.yellow)),
                        ],
                      ),
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
                Expanded(
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      game.handlePanUpdate(details);
                    },
                    onTapDown: (details) {
                      game.handleTapDown(details);
                    },
                    child: GameWidget(game: game),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
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
                    ],
                  ),
                ),
              ],
            ),
            // Overlays always on top
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
            // Game Over overlay
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
                            _paused = false;
                          });
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(160, 50)),
                        child: const Text('Reset'),
                      )
                    ],
                  ),
                ),
              ),
            // Pause button always visible
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 32),
                tooltip: _paused ? 'Reprendre' : 'Pause',
                onPressed: _togglePause,
                splashRadius: 28,
              ),
            ),
            // Error message always visible
            if (_directionErrorMsg != null)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_directionErrorMsg!, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
