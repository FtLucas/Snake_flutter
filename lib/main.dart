// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'snake_game.dart';
import 'ui/home_menu_screen.dart';
import 'ui/shop_screen.dart';
import 'ui/skill_tree_screen.dart';
import 'ui/settings_screen.dart';
import 'state/settings.dart';
import 'state/player_profile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
  // Load persisted settings/profile early
  AppSettings.instance.load();
  PlayerProfile.instance.load();
    return MaterialApp(
      title: 'Snake Game',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeMenuScreen(),
        '/game': (context) => const GameScreen(),
        '/shop': (context) => const ShopScreen(),
        '/skills': (context) => const SkillTreeScreen(),
  '/settings': (context) => const SettingsScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late SnakeGame game;
  Timer? _uiTick;

  @override
  void initState() {
    super.initState();
    game = SnakeGame();
    // Tick l'UI fréquemment pour refléter les changements de l'état du jeu (gameOver, score, etc.)
    _uiTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  // Le menu principal est dans une route séparée ('/').
  }

  // Pause removed

  @override
  void dispose() {
    _uiTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // désactive le retour en arrière in-game
      child: Scaffold(
      backgroundColor: Colors.black,
  body: Stack(
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
                // Zone de jeu avec joystick par-dessus uniquement cette zone
                Expanded(
                  child: Stack(
                    children: [
                      GameWidget(game: game),
                      Positioned.fill(
                        child: _FloatingJoystick(
                          onChanged: (dx, dy) => game.setJoystickDelta(dx, dy),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      // Bandeau debug compact (Wrap pour éviter les overflows sur petits écrans)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            selected: game.demoMode,
                            label: const Text('Démo'),
                            onSelected: (_) {
                              setState(() => game.demoMode = !game.demoMode);
                            },
                          ),
                          ElevatedButton(
                            onPressed: () {
                              game.wave = max(0, game.wave - (game.wave % 5)); // aligne sur cycle
                              game.waveBreakTimer = 0; // démarre prochaine vague
                            },
                            child: const Text('Vague++'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (!game.bossActive) {
                                game.wave = (game.wave ~/ 5) * 5 + 5; // saute au palier boss
                                game.waveBreakTimer = 0;
                              }
                            },
                            child: const Text('Boss'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                game.isNight = !game.isNight;
                                game.nightOpacity = game.isNight ? 1.0 : 0.0;
                              });
                            },
                            child: const Text('Jour/Nuit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (game.hasShield)
                            Chip(label: Text('🛡️ ${game.shieldDuration.toStringAsFixed(1)}s'), backgroundColor: Colors.cyan.withValues(alpha: 0.2)),
                          if (game.hasMultiFood)
                            Chip(label: Text('🍎x2 ${game.multiFoodDuration.toStringAsFixed(1)}s'), backgroundColor: Colors.orange.withValues(alpha: 0.2)),
                          if (game.speedMultiplier > 1.0)
                            Chip(label: Text('⚡ x${game.speedMultiplier.toStringAsFixed(1)}'), backgroundColor: Colors.yellow.withValues(alpha: 0.2)),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
            // Joystick déplacé au-dessus de la zone de jeu uniquement (voir plus haut)
            // Overlays always on top
            if (game.showPowerUpSelection)
              Container(
                color: Colors.black.withValues(alpha: 0.8),
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
                color: Colors.black.withValues(alpha: 0.7),
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
                        child: const Text('Reset'),
                      )
                    ],
                  ),
                ),
              ),
            // Pause button removed
            // Message d'erreur de demi-tour retiré
          ],
        ),
      ),
    );
  }
}

// Joystick flottant: spawn sous le doigt, suit le doigt s'il s'éloigne
class _FloatingJoystick extends StatefulWidget {
  final void Function(double dx, double dy) onChanged;
  const _FloatingJoystick({required this.onChanged});

  @override
  State<_FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<_FloatingJoystick> {
  bool _active = false;
  Offset _center = Offset.zero;
  Offset _knob = Offset.zero;
  double get _bgRadius => 56 * AppSettings.instance.joystickSize;
  double get _knobRadius => 22 * AppSettings.instance.joystickSize;

  double get _maxR => _bgRadius - _knobRadius;

  void _start(Offset pos) {
    final left = AppSettings.instance.leftHandedJoystick;
    final margin = AppSettings.instance.joystickMargin;
    final startArea = Rect.fromLTWH(
      left ? 0 : (MediaQuery.of(context).size.width * 0.5),
      0,
      MediaQuery.of(context).size.width * 0.5,
      MediaQuery.of(context).size.height,
    ).deflate(margin);
    if (!startArea.contains(pos)) return;
    setState(() {
      _active = true;
      _center = pos;
      _knob = Offset.zero;
    });
    widget.onChanged(0, 0);
  }

  void _update(Offset pos) {
    if (!_active) return;
    final rel = pos - _center;
    if (rel.distance <= _maxR) {
      setState(() => _knob = rel);
    } else {
      final dir = rel / rel.distance;
      // le centre suit le doigt, en gardant le knob au rayon max
      final newKnob = dir * _maxR;
      final newCenter = pos - newKnob;
      setState(() {
        _center = newCenter;
        _knob = newKnob;
      });
    }
    final dx = (_knob.dx / _maxR).clamp(-1.0, 1.0);
    final dy = (_knob.dy / _maxR).clamp(-1.0, 1.0);
    widget.onChanged(dx, dy);
  }

  void _end() {
    if (!_active) return;
    setState(() {
      _active = false;
      _knob = Offset.zero;
    });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
  final opacity = AppSettings.instance.joystickOpacity;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (d) {
        final box = context.findRenderObject() as RenderBox;
        _start(box.globalToLocal(d.globalPosition));
      },
      onPanUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        _update(box.globalToLocal(d.globalPosition));
      },
      onPanEnd: (_) => _end(),
      onPanCancel: () => _end(),
      child: CustomPaint(
        painter: _FloatingJoystickPainter(
          active: _active,
          center: _center,
          knob: _knob,
          bgRadius: _bgRadius,
          knobRadius: _knobRadius,
          opacity: opacity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FloatingJoystickPainter extends CustomPainter {
  final bool active;
  final Offset center;
  final Offset knob;
  final double bgRadius;
  final double knobRadius;
  final double opacity;
  _FloatingJoystickPainter({
    required this.active,
    required this.center,
    required this.knob,
    required this.bgRadius,
    required this.knobRadius,
    this.opacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final bg = Paint()..color = const Color(0x66000000).withValues(alpha: opacity);
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.3 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final knobPaint = Paint()..color = const Color(0xFFEEEEEE).withValues(alpha: 0.9 * opacity);

    canvas.drawCircle(center, bgRadius, bg);
    canvas.drawCircle(center, bgRadius, ring);
    canvas.drawCircle(center + knob, knobRadius, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _FloatingJoystickPainter old) {
    return old.active != active || old.center != center || old.knob != knob;
  }
}
