// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
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
      home: const MenuScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: _MenuAnimatedBackground()),
          // Contenu du menu au-dessus du fond
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Snake Game', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(220, 56)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GameScreen()),
                      );
                    },
                    child: const Text('Jouer'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuAnimatedBackground extends StatefulWidget {
  const _MenuAnimatedBackground();

  @override
  State<_MenuAnimatedBackground> createState() => _MenuAnimatedBackgroundState();
}

class _MenuAnimatedBackgroundState extends State<_MenuAnimatedBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Size _size = Size.zero;
  late List<_Star> _stars;
  late List<_Cloud> _clouds;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 24))..addListener(() => setState(() {}))..repeat();
    _stars = [];
    _clouds = [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    if (size != _size && size.width > 0 && size.height > 0) {
      _size = size;
      _generateDecor(size);
    }
  }

  void _generateDecor(Size s) {
    // étoiles
    final rng = Random(42);
    final int starCount = (80 + s.width / 10).clamp(80, 160).toInt();
    _stars = List.generate(starCount, (i) {
      return _Star(
        Offset(rng.nextDouble() * s.width, rng.nextDouble() * (s.height * 0.6)),
        0.4 + rng.nextDouble() * 0.6,
        0.5 + rng.nextDouble() * 1.2,
        0.5 + rng.nextDouble() * 1.5,
      );
    });
    // nuages (jour)
  const int seedClouds = 99;
  final rng2 = Random(seedClouds);
  const int cloudCount = 6;
    _clouds = List.generate(cloudCount, (i) {
      return _Cloud(
        Offset(rng2.nextDouble() * s.width, (s.height * 0.18) + rng2.nextDouble() * (s.height * 0.22)),
        0.8 + rng2.nextDouble() * 0.8,
        8 + rng2.nextDouble() * 16,
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_size == Size.zero) return const SizedBox.shrink();
    final t = _ctrl.value; // 0..1
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MenuBackgroundPainter(
          time: t,
          stars: _stars,
          clouds: _clouds,
        ),
      ),
    );
  }
}

class _MenuBackgroundPainter extends CustomPainter {
  final double time; // 0..1
  final List<_Star> stars;
  final List<_Cloud> clouds;
  _MenuBackgroundPainter({required this.time, required this.stars, required this.clouds});

  @override
  void paint(Canvas canvas, Size size) {
    // Cycle jour/nuit: 0..0.5 jour, 0.5..1.0 nuit
  final bool isNight = time >= 0.5;
  final double phase = isNight ? (time - 0.5) * 2.0 : time * 2.0; // 0..1
  final double dayAlpha = isNight ? (1.0 - phase) : 1.0;

    // Ciel: gradient selon jour/nuit
    final Rect sky = Offset.zero & size;
    final Paint skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isNight
            ? [const Color(0xFF0B1022), const Color(0xFF111A35), const Color(0xFF1E2748)]
            : [const Color(0xFF64B5F6), const Color(0xFF90CAF9), const Color(0xFFE3F2FD)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(sky);
    canvas.drawRect(sky, skyPaint);

    // Soleil/Lune (simple trajectoire en arc)
    final double cx = size.width * 0.5;
    final double cy = size.height * 0.15;
    final double rx = size.width * 0.45;
    final double ry = size.height * 0.22;

    // angle jour 0..pi, nuit pi..2pi
    final double angle = isNight ? (pi + phase * pi) : (phase * pi);
    final Offset sunPos = Offset(cx - rx * cos(angle), cy + ry * sin(angle));
    final Offset moonPos = Offset(cx - rx * cos(angle + pi), cy + ry * sin(angle + pi));

    // Soleil
    if (!isNight || dayAlpha > 0.05) {
      final Paint sun = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF59D).withValues(alpha: 0.9 * dayAlpha),
            const Color(0xFFFFEE58).withValues(alpha: 0.7 * dayAlpha),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: sunPos, radius: 70));
      canvas.drawCircle(sunPos, 70, sun);
      canvas.drawCircle(sunPos, 26, Paint()..color = const Color(0xFFFFF176).withValues(alpha: 0.95 * dayAlpha));
    }

    // Lune
    if (isNight) {
      final Paint moon = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFCFD8DC).withValues(alpha: 0.9),
            const Color(0xFFB0BEC5).withValues(alpha: 0.6),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: moonPos, radius: 60));
      canvas.drawCircle(moonPos, 60, moon);
      // cratères simples
      final Paint crater = Paint()..color = const Color(0xFF90A4AE).withValues(alpha: 0.5);
      for (int i = 0; i < 8; i++) {
        final double a = i / 8.0 * pi * 2;
        final Offset p = moonPos + Offset(cos(a), sin(a)) * 24;
        canvas.drawCircle(p, 5 + 3 * sin(a * 2), crater);
      }
    }

    // Étoiles (nuit uniquement)
    if (isNight) {
      for (final s in stars) {
        final double tw = 0.6 + 0.4 * (0.5 + 0.5 * sin((time * 6.283) * s.twinkle + s.twinkle));
        final double a = (0.15 + 0.85 * tw) * s.baseAlpha;
        final Paint p = Paint()..color = Colors.white.withValues(alpha: a * 0.9);
        canvas.drawCircle(s.pos, s.radius, p);
      }
    }

    // Nuages (jour uniquement)
    if (!isNight) {
      for (final c in clouds) {
        final double x = (c.pos.dx + (time * c.speed * 40)) % (size.width + 160) - 80;
        final double y = c.pos.dy;
        _drawCloud(canvas, Offset(x, y), c.scale);
      }
    }

    // Bande sol/ligne d'horizon douce
    final double horizon = size.height * 0.72;
    final Rect ground = Rect.fromLTRB(0, horizon, size.width, size.height);
    final Paint groundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3E2723), Color(0xFF2B1B16)],
      ).createShader(ground);
    canvas.drawRect(ground, groundPaint);
    canvas.drawRect(Rect.fromLTRB(0, horizon - 2, size.width, horizon), Paint()..color = Colors.black.withValues(alpha: 0.2));
  }

  void _drawCloud(Canvas canvas, Offset pos, double scale) {
    final Paint p = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85);
    void bub(Offset o, double r) => canvas.drawCircle(pos + o * scale, r * scale, p);
    bub(const Offset(0, 0), 24);
    bub(const Offset(20, 0), 20);
    bub(const Offset(-18, 4), 18);
    bub(const Offset(8, -8), 16);
    bub(const Offset(-6, -6), 14);
  }

  @override
  bool shouldRepaint(covariant _MenuBackgroundPainter old) {
    return old.time != time || old.stars != stars || old.clouds != clouds;
  }
}

class _Star {
  final Offset pos;
  final double baseAlpha;
  final double twinkle; // vitesse twinkle
  final double radius;
  _Star(this.pos, this.baseAlpha, this.twinkle, this.radius);
}

class _Cloud {
  final Offset pos;
  final double scale;
  final double speed;
  _Cloud(this.pos, this.scale, this.speed);
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
    if (mounted) setState(() {});
  }

  // Pause removed

  @override
  void dispose() {
    _uiTick?.cancel();
    super.dispose();
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
                      // Bandeau debug compact
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilterChip(
                            selected: game.demoMode,
                            label: const Text('Démo'),
                            onSelected: (_) {
                              setState(() => game.demoMode = !game.demoMode);
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              game.wave = max(0, game.wave - (game.wave % 5)); // aligne sur cycle
                              game.waveBreakTimer = 0; // démarre prochaine vague
                            },
                            child: const Text('Vague++'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              if (!game.bossActive) {
                                game.wave = (game.wave ~/ 5) * 5 + 5; // saute au palier boss
                                game.waveBreakTimer = 0;
                              }
                            },
                            child: const Text('Boss'),
                          ),
                          const SizedBox(width: 8),
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
  final double _bgRadius = 56;
  final double _knobRadius = 22;

  double get _maxR => _bgRadius - _knobRadius;

  void _start(Offset pos) {
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
  _FloatingJoystickPainter({
    required this.active,
    required this.center,
    required this.knob,
    required this.bgRadius,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final bg = Paint()..color = const Color(0x66000000);
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final knobPaint = Paint()..color = const Color(0xFFEEEEEE).withValues(alpha: 0.9);

    canvas.drawCircle(center, bgRadius, bg);
    canvas.drawCircle(center, bgRadius, ring);
    canvas.drawCircle(center + knob, knobRadius, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _FloatingJoystickPainter old) {
    return old.active != active || old.center != center || old.knob != knob;
  }
}
