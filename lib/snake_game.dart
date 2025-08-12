// lib/snake_game.dart
import 'dart:math';
import 'dart:async' as async;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

enum PowerUpType { speed, shield, multiFood }

class PowerUp {
  final PowerUpType type;
  final String name;
  final String description;
  final Color color;

  PowerUp(this.type, this.name, this.description, this.color);
}

/// Simple data-only Enemy (logic moved into EnemyComponent)
class Enemy {
  Vector2 position;
  Vector2 direction;
  double speed;
  Color color;
  double size;
  int health;

  Enemy({
    required this.position,
    required this.direction,
    this.speed = 100.0, // pixels / second
    this.color = Colors.purple,
    this.size = 12.0,
    this.health = 1,
  });
}

/// Enemy as a Flame Component so it renders and updates itself
class EnemyComponent extends PositionComponent {
  final Enemy enemy;
  final SnakeGame gameRef;

  EnemyComponent({required this.enemy, required this.gameRef}) {
    // set component position and anchor — rendering will be done relative to Offset.zero
    position = enemy.position.clone();
    anchor = Anchor.center;
    size = Vector2.all(enemy.size * 2);
    // default priority: we may override when adding; keep a reasonable default
    priority = 10;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Move enemy (pixels)
    enemy.position += enemy.direction.normalized() * enemy.speed * dt;
    // update component position so Flame translates the canvas automatically
    position = enemy.position.clone();

    // Out of bounds -> remove
    if (enemy.position.x < -enemy.size - 50 ||
        enemy.position.x > gameRef.size.x + enemy.size + 50 ||
        enemy.position.y < -enemy.size - 50 ||
        enemy.position.y > gameRef.size.y + enemy.size + 50) {
      removeFromParent();
    }

    // Collision with snake head (head eats enemies now)
    final head = gameRef.headCenter;
    if (head != null) {
      final dist = (enemy.position - head).length;
      if (dist < enemy.size + gameRef.snakeHeadRadius) {
        gameRef.enemiesKilled++;
        gameRef.experience += 5;
        gameRef.score += 50;
        gameRef.checkLevelUp();
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // draw centered at component origin (Offset.zero) because PositionComponent already set the transform
    final paint = Paint()..color = enemy.color;
    canvas.drawCircle(Offset.zero, enemy.size, paint);

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset.zero, enemy.size, border);
  }
}


class SnakeGame extends FlameGame {
  SnakeGame({this.playerSpeed = 140.0});
  // grid
  final int gridSize = 24; // pixels per cell (visual)
  late final int gridWidth;
  late final int gridHeight;
  // playfield (texture zone) with vertical margins
  // Marges de la zone de jeu: on garde le haut, on réduit par le bas
  final double topMargin = 48.0;
  final double bottomExtra = 120.0; // augmente davantage uniquement le bas
  double get bottomMargin => topMargin + bottomExtra;
  late Vector2 playOrigin; // top-left pixel of playfield
  late Vector2 playSize;   // width/height of playfield in pixels

  // grid-based snake (positions in grid cells)
  final List<Vector2> snake = [];
  Vector2 direction = Vector2(1, 0);
  Vector2 nextDirection = Vector2(1, 0);

  // pixel positions for smooth rendering (one per segment)

  // food in grid coords
  Vector2? food;

  // progression
  int score = 0;
  int level = 1;
  int enemiesKilled = 0;
  int foodEaten = 0;
  int experience = 0;
  int experienceToNextLevel = 10;

  // states
  bool gameOver = false;
  bool gameStarted = false;
  bool showPowerUpSelection = false;

  // timers
  async.Timer? _gameTimer;
  async.Timer? _enemySpawnTimer;
  double baseMoveInterval = 0.25; // seconds between logical moves

  // enemies
  double enemySpawnRate = 3.0; // seconds
  final Random random = Random();

  // powerups
  bool hasShield = false;
  double shieldDuration = 0.0;
  bool hasMultiFood = false;
  double multiFoodDuration = 0.0;
  double speedMultiplier = 1.0;

  final List<PowerUp> availablePowerUps = [];

  // interpolation smoothing (how fast pixels move to target)
  final double pixelLerpSpeed = 12.0; // higher -> faster visual interpolation

  // grass background
  ui.Image? _grassTile;
  Paint? _grassPaint;
  final int _grassTileSize = 64; // px
  // Joystick (four-direction control) provided by Flutter overlay
  Vector2? _joystickDelta; // normalized [-1,1]
  final double _joystickDeadZone = 0.2;
  int _pendingGrowth = 0;

  // Continuous movement (pixels per second) like enemies
  double playerSpeed; // configurable via ctor
  Vector2 _headPixel = Vector2.zero();
  // Keep track of last grid cell we processed for collisions/food
  Vector2 _headGrid = Vector2.zero();
  // Smooth body via sampled trail
  final List<Vector2> _trail = [];
  final List<Vector2> _segmentCenters = [];
  int _segmentCount = 0;
  double get _segmentSpacing => gridSize.toDouble() * 0.92;
  final double _minTrailSample = 1.0; // px between samples (finer for smoother follow)
  // Permet au corps d'avancer même quand la tête s'arrête (rattrapage le long de la trace)
  double _catchup = 0.0;

  /// Helper: true si le jeu est actif (pas game over, pas en pause, pas en sélection de power-up)
  bool get isGameActive => gameStarted && !gameOver && !showPowerUpSelection;

  /// Annule et nettoie les timers pour éviter les doublons ou fuites mémoire
  void _cancelTimers() {
    _gameTimer?.cancel();
    _enemySpawnTimer?.cancel();
  }


  @override
  Future<void> onLoad() async {
    super.onLoad();
  // Define playfield occupying full width, smaller height (top/bottom margins)
  playOrigin = Vector2(0, topMargin);
  playSize = Vector2(size.x, (size.y - topMargin - bottomMargin).clamp(0, size.y));
  gridWidth = (playSize.x / gridSize).floor();
  gridHeight = (playSize.y / gridSize).floor();
    await _generateGrassTile();
    _initializePowerUps();
    _initializeGame();
    _startGameLoop();
    _startEnemySpawning();
  }

  // Called from Flutter overlay to feed joystick input
  void setJoystickDelta(double dx, double dy) {
    if (dx == 0 && dy == 0) {
      _joystickDelta = null;
    } else {
      _joystickDelta = Vector2(dx, dy);
    }
  }

  Future<void> _generateGrassTile() async {
    // Create a simple procedural grass tile once
    final double s = _grassTileSize.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));

    // Base green
    final base = Paint()..color = const Color(0xFF1B5E20); // dark green
    canvas.drawRect(Rect.fromLTWH(0, 0, s, s), base);

    final rng = Random(42);
    // Add lighter patches
    for (int i = 0; i < 120; i++) {
      final cx = rng.nextDouble() * s;
      final cy = rng.nextDouble() * s;
      final r = 0.5 + rng.nextDouble() * 1.5;
      final paint = Paint()
        ..color = Color.lerp(const Color(0xFF43A047), const Color(0xFF2E7D32), rng.nextDouble())!
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }

    // Draw some thin blades
    final bladePaint = Paint()
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.8)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 70; i++) {
      final x = rng.nextDouble() * s;
      final y = rng.nextDouble() * s;
      final len = 2.0 + rng.nextDouble() * 4.0;
      final angle = (rng.nextDouble() - 0.5) * 0.8; // slight tilt
      final dx = len * cos(angle);
      final dy = -len * sin(angle);
      canvas.drawLine(Offset(x, y), Offset(x + dx, y + dy), bladePaint);
    }

    final picture = recorder.endRecording();
    _grassTile = await picture.toImage(_grassTileSize, _grassTileSize);
    // Build shader paint for tiling
    final Float64List identity = Float64List.fromList(<double>[
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    _grassPaint = Paint()
      ..shader = ui.ImageShader(_grassTile!, TileMode.repeated, TileMode.repeated, identity);
  }


  void _initializePowerUps() {
    availablePowerUps.clear();
    availablePowerUps.addAll([
      PowerUp(PowerUpType.speed, "Vitesse", "Augmente la vitesse de 20%", Colors.yellow),
      PowerUp(PowerUpType.shield, "Bouclier", "Protection contre les ennemis (10s)", Colors.blue),
      PowerUp(PowerUpType.multiFood, "Multi-Nourriture", "Double les points de nourriture (15s)", Colors.orange),
    ]);
  }


  void _initializeGame() {
    snake.clear();
    snake.addAll([
      Vector2((gridWidth / 2).toDouble(), (gridHeight / 2).toDouble()),
      Vector2((gridWidth / 2 - 1).toDouble(), (gridHeight / 2).toDouble()),
      Vector2((gridWidth / 2 - 2).toDouble(), (gridHeight / 2).toDouble()),
    ]);
    // initialize smooth body model
    _segmentCount = snake.length;
    _segmentCenters.clear();
    final initialHeadCenter = Vector2(
      playOrigin.x + snake.first.x * gridSize + gridSize / 2,
      playOrigin.y + snake.first.y * gridSize + gridSize / 2,
    );
    // Determine initial direction (fallback to right if zero)
    Vector2 dir0 = direction.clone();
    if (dir0.length2 == 0) dir0 = Vector2(1, 0);
    dir0.normalize();
    for (int i = 0; i < _segmentCount; i++) {
      _segmentCenters.add(initialHeadCenter - dir0 * (_segmentSpacing * i));
    }
    // Seed the trail backward so body doesn't collapse when not yet moved
    _trail
      ..clear()
      ..add(initialHeadCenter.clone());
    final double seedLen = (_segmentCount - 1) * _segmentSpacing + 64;
    double acc = 0;
    while (acc < seedLen) {
      final last = _trail.last;
      final next = last - dir0 * _minTrailSample;
      _trail.add(next);
      acc += _minTrailSample;
    }

  direction = Vector2(1, 0);
    nextDirection = Vector2(1, 0);
    score = 0;
    level = 1;
    enemiesKilled = 0;
    foodEaten = 0;
    experience = 0;
    experienceToNextLevel = 10;
    gameOver = false;
    gameStarted = true;
    showPowerUpSelection = false;

    hasShield = false;
    hasMultiFood = false;
    speedMultiplier = 1.0;

  // Seed pixel head based on current grid head
  _headPixel = Vector2(playOrigin.x + snake.first.x * gridSize, playOrigin.y + snake.first.y * gridSize);
  _headGrid = snake.first.clone();
  food = null;
    generateFood();
  }


  void _startGameLoop() {
    // Still used to progressively speed up legacy timing (not moving by cell anymore)
    _gameTimer?.cancel();
    _gameTimer = async.Timer.periodic(const Duration(seconds: 10), (_) {});
  }

  void _startEnemySpawning() {
    _enemySpawnTimer?.cancel();
    _enemySpawnTimer = async.Timer.periodic(Duration(milliseconds: (enemySpawnRate * 1000).round()), (_) {
      if (isGameActive) {
        _spawnEnemy();
      }
    });
  }

  /// Fait apparaître un ennemi sur un bord aléatoire
  void _spawnEnemy() {
    // Spawn at the extremities (edges) of the texture playfield
    int side = random.nextInt(4); // 0: top, 1: right, 2: bottom, 3: left
    Vector2 pos;
    Vector2 dir;
    final Rect r = playRect;
    switch (side) {
      case 0: // top
        pos = Vector2(r.left + random.nextDouble() * r.width, r.top - 30);
        dir = Vector2(0, 1);
        break;
      case 1: // right
        pos = Vector2(r.right + 30, r.top + random.nextDouble() * r.height);
        dir = Vector2(-1, 0);
        break;
      case 2: // bottom
        pos = Vector2(r.left + random.nextDouble() * r.width, r.bottom + 30);
        dir = Vector2(0, -1);
        break;
      default: // left
        pos = Vector2(r.left - 30, r.top + random.nextDouble() * r.height);
        dir = Vector2(1, 0);
    }

    final enemy = Enemy(
      position: pos,
      direction: dir,
      speed: 60.0 + level * 10.0, // px/s
      color: level > 5 ? Colors.red : Colors.purple,
      size: 10.0 + level.toDouble(),
      health: level > 3 ? 2 : 1,
    );

    final comp = EnemyComponent(enemy: enemy, gameRef: this);
    // ensure enemies draw above the snake (priority high)
    comp.priority = 10;
    add(comp);
  }

  // logical grid step
  /// Mouvement continu et corps fluide via trail
  void _stepSnakeContinuous(double dt) {
    if (!gameStarted || gameOver || showPowerUpSelection) return;
    // Apply joystick decision first
    direction = nextDirection;

    // Move the head pixel position continuously
    final vel = direction.normalized() * playerSpeed * dt;
    _headPixel += vel;

    // Head center for precise collisions/bounds
    final headCenter = _headPixel + Vector2(gridSize / 2, gridSize / 2);
    final Rect r = playRect;
    final double rr = snakeHeadRadius;
    // Bounds: game over as soon as the head circle touches the edge (independent of shield)
    if (headCenter.x - rr < r.left || headCenter.x + rr > r.right || headCenter.y - rr < r.top || headCenter.y + rr > r.bottom) {
      endGame();
      return;
    }

    // Pixel-based food collision (eat on touch)
    if (food != null) {
      final foodCenter = Offset(
        playOrigin.x + food!.x * gridSize + gridSize / 2,
        playOrigin.y + food!.y * gridSize + gridSize / 2,
      );
      final d = (Offset(headCenter.x, headCenter.y) - foodCenter).distance;
      if (d <= snakeHeadRadius + (gridSize / 2 - 2)) {
        _pendingGrowth += hasMultiFood ? 2 : 1;
        int points = hasMultiFood ? 20 : 10;
        score += points;
        experience += 2;
        foodEaten++;
        generateFood();
        checkLevelUp();
      }
    }
  // Convert to grid cell for growth pacing only
  final gx = ((_headPixel.x - playOrigin.x) / gridSize).floorToDouble();
  final gy = ((_headPixel.y - playOrigin.y) / gridSize).floorToDouble();
  final newGrid = Vector2(gx, gy);

    // Update sampled trail with head center
    final headC = _headPixel + Vector2(gridSize / 2, gridSize / 2);
    // Distance parcourue par la tête ce frame (pour piloter le rattrapage)
    double moveDist = 0.0;
    if (_trail.isNotEmpty) {
      moveDist = (headC - _trail.first).length;
    }
    if (_trail.isEmpty || (_trail.first - headC).length >= _minTrailSample) {
      _trail.insert(0, headC.clone());
    } else {
      _trail[0] = headC.clone();
    }
    // Trim trail to needed length
    double needed = (_segmentCount - 1) * _segmentSpacing - _catchup;
    if (needed < 0) needed = 0;
    needed += 64; // marge de sécurité
    double acc = 0;
    for (int i = 0; i < _trail.length - 1; i++) {
      acc += (_trail[i] - _trail[i + 1]).length;
      if (acc > needed) {
        _trail.removeRange(i + 1, _trail.length);
        break;
      }
    }
    // Met à jour le rattrapage: si la tête bouge, on réduit le retard; sinon le corps avance
    if (moveDist > 0) {
      _catchup -= moveDist;
      if (_catchup < 0) _catchup = 0;
    } else {
      final maxCatch = (_segmentCount - 1) * _segmentSpacing;
      _catchup += playerSpeed * dt;
      if (_catchup > maxCatch) _catchup = maxCatch;
    }
    // Apply pending growth when entering a new cell (pace growth)
    if (newGrid.x != _headGrid.x || newGrid.y != _headGrid.y) {
      if (_pendingGrowth > 0) {
        _segmentCount += _pendingGrowth;
        _pendingGrowth = 0;
      }
      _headGrid = newGrid;
    }
    // Ensure centers list size
    if (_segmentCenters.length != _segmentCount) {
      if (_segmentCenters.isEmpty) {
        _segmentCenters.addAll(List.generate(_segmentCount, (i) => headC.clone()));
      } else if (_segmentCenters.length < _segmentCount) {
        final last = _segmentCenters.last;
        _segmentCenters.addAll(List.generate(_segmentCount - _segmentCenters.length, (i) => last.clone()));
      } else {
        _segmentCenters.removeRange(_segmentCount, _segmentCenters.length);
      }
      // Clamp le rattrapage au nouveau maximum
      final maxCatch = (_segmentCount - 1) * _segmentSpacing;
      if (_catchup > maxCatch) _catchup = maxCatch;
    }
    // Sample segment centers along the trail
    for (int idx = 0; idx < _segmentCount; idx++) {
      double targetDist = idx * _segmentSpacing - _catchup;
      if (targetDist < 0) targetDist = 0;
      _segmentCenters[idx] = _sampleTrail(targetDist);
    }
  }

  /// Met à jour l'état du jeu à chaque frame (interpolation, timers, etc.)
  @override
  void update(double dt) {
    super.update(dt);
    if (!gameStarted || gameOver || showPowerUpSelection) return;

    // Joystick input (from Flutter) -> analog direction (normalized)
    final joy = _joystickDelta;
    if (joy != null && joy.length > _joystickDeadZone) {
      nextDirection = joy.normalized();
    }

  // Continuous movement
  _stepSnakeContinuous(dt);

    // Update power-up timers
    if (hasShield) {
      shieldDuration -= dt;
      if (shieldDuration <= 0) {
        hasShield = false;
      }
    }
    if (hasMultiFood) {
      multiFoodDuration -= dt;
      if (multiFoodDuration <= 0) {
        hasMultiFood = false;
      }
    }
  }

  /// Vérifie si le joueur passe au niveau supérieur
  void checkLevelUp() {
    if (experience >= experienceToNextLevel) {
      experience = 0;
      experienceToNextLevel = (experienceToNextLevel * 1.5).round();

      // increase difficulty
      if (enemySpawnRate > 1.0) {
        enemySpawnRate *= 0.9;
  _startEnemySpawning();
      }

      // show power-up overlay (UI side reads this)
      showPowerUpSelection = true;
    }
  }

  /// Applique le power-up sélectionné
  void selectPowerUp(PowerUpType type) {
    switch (type) {
      case PowerUpType.speed:
        speedMultiplier += 0.2;
  _startGameLoop();
        break;
      case PowerUpType.shield:
        hasShield = true;
        shieldDuration = 10.0;
        break;
      case PowerUpType.multiFood:
        hasMultiFood = true;
        multiFoodDuration = 15.0;
        break;
    }
    showPowerUpSelection = false;
  }

  /// Génère une nouvelle position de nourriture qui ne chevauche pas le serpent
  void generateFood() {
    // Place food avoiding current segment centers if possible
    for (int attempts = 0; attempts < 200; attempts++) {
      final candidate = Vector2(
        random.nextInt(gridWidth).toDouble(),
        random.nextInt(gridHeight).toDouble(),
      );
      final c = Offset(
        playOrigin.x + candidate.x * gridSize + gridSize / 2,
        playOrigin.y + candidate.y * gridSize + gridSize / 2,
      );
      bool ok = true;
      for (final s in _segmentCenters) {
        if ((Offset(s.x, s.y) - c).distance < gridSize * 0.8) {
          ok = false;
          break;
        }
      }
      if (ok) { food = candidate; return; }
    }
    // Fallback
    food = Vector2(
      random.nextInt(gridWidth).toDouble(),
      random.nextInt(gridHeight).toDouble(),
    );
  }

  // Swipe retiré: le contrôle se fait via joystick

  // optional tap handler (e.g., pause / resume)
  /// Gère le tap utilisateur (peut servir à pause/reprendre ou boost)
  void handleTapDown(TapDownDetails details) {
    // currently unused; can implement pause/resume or boost
  }

  /// Change la direction du serpent via une chaîne ('up', 'down', ...)
  void changeDirection(String newDirection) {
  if (gameOver || showPowerUpSelection) return;
    Vector2? newDir;
    switch (newDirection) {
      case 'up':
        newDir = Vector2(0, -1);
        break;
      case 'down':
        newDir = Vector2(0, 1);
        break;
      case 'left':
        newDir = Vector2(-1, 0);
        break;
      case 'right':
        newDir = Vector2(1, 0);
        break;
      default:
        return;
    }
  if (direction.x == -newDir.x && direction.y == -newDir.y) return;
    nextDirection = newDir;
  }

  /// Termine la partie
  void endGame() {
    gameOver = true;
    gameStarted = false;
  }


  /// Réinitialise la partie
  void resetGame() {
    _cancelTimers();
    baseMoveInterval = 0.25;
    enemySpawnRate = 3.0;
    _initializeGame();
    _startGameLoop();
    _startEnemySpawning();
  }

  /// Dessine le jeu (grille, serpent, nourriture, ennemis, UI overlay)
  @override
  void render(Canvas canvas) {
    // Dark outside area
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), Paint()..color = const Color(0xFF0D2813));
    // Draw grass texture only inside playfield
    if (_grassPaint != null) {
      canvas.drawRect(playRect, _grassPaint!);
    } else {
      canvas.drawRect(playRect, Paint()..color = const Color(0xFF1B5E20));
    }

    // grid lines (more discreet) inside the playfield only
  final gridPaint = Paint()..color = Colors.black.withValues(alpha: 0.04);
    canvas.save();
    canvas.clipRect(playRect);
    for (int i = 0; i <= gridWidth; i++) {
      final x = playOrigin.x + i * gridSize.toDouble();
      canvas.drawLine(Offset(x, playOrigin.y), Offset(x, playOrigin.y + playSize.y), gridPaint);
    }
    for (int j = 0; j <= gridHeight; j++) {
      final y = playOrigin.y + j * gridSize.toDouble();
      canvas.drawLine(Offset(playOrigin.x, y), Offset(playOrigin.x + playSize.x, y), gridPaint);
    }
    canvas.restore();

    // draw snake (rounded segments) BEFORE components
    final headPaint = Paint()..color = hasShield ? Colors.lightBlue : Colors.lightGreen;
    final bodyPaint = Paint()..color = hasShield ? Colors.cyan : Colors.green;
    final double r = snakeHeadRadius;
    for (int i = _segmentCenters.length - 1; i >= 0; i--) {
      final c = _segmentCenters[i];
      final paint = i == 0 ? headPaint : bodyPaint;
      canvas.drawCircle(Offset(c.x, c.y), r, paint);
    }
    // simple eyes on the head for character
    if (_segmentCenters.isNotEmpty) {
      final center = Offset(_segmentCenters.first.x, _segmentCenters.first.y);
      final dir = direction.normalized();
      final eyeOffset = Offset(dir.x * 4, dir.y * 4);
      final eyeSep = Offset(-dir.y * 5, dir.x * 5);
      final eyePaint = Paint()..color = Colors.white;
      final pupilPaint = Paint()..color = Colors.black;
      final e1 = center + eyeOffset + eyeSep;
      final e2 = center + eyeOffset - eyeSep;
      canvas.drawCircle(e1, 3, eyePaint);
      canvas.drawCircle(e2, 3, eyePaint);
      canvas.drawCircle(e1, 1.5, pupilPaint);
      canvas.drawCircle(e2, 1.5, pupilPaint);
    }

    // draw food also BEFORE components (if you prefer food above enemies you'd make food a component with higher priority)
    if (food != null) {
      final center = Offset(playOrigin.x + food!.x * gridSize + gridSize / 2, playOrigin.y + food!.y * gridSize + gridSize / 2);
      final r = gridSize / 2 - 2;
      final paint = Paint()..color = hasMultiFood ? Colors.orange : Colors.red;
      canvas.drawCircle(center, r, paint);
    }

    // NOW render components (EnemyComponent etc.) on top of the snake/food
    super.render(canvas);

    // UI overlay basic: score (small)
    final tp = TextPainter(
      text: TextSpan(text: 'Score: $score  Level: $level', style: const TextStyle(color: Colors.white, fontSize: 14)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, const Offset(10, 6));
  }

  @override
  void onRemove() {
    _cancelTimers();
  // Cleanup generated image
  _grassTile?.dispose();
    super.onRemove();
  }

  // Convenience getter: rectangle of the texture/playfield
  Rect get playRect => Rect.fromLTWH(playOrigin.x, playOrigin.y, playSize.x, playSize.y);

  double get snakeHeadRadius => gridSize * 0.45;

  // Current head center (pixels)
  Vector2? get headCenter => _segmentCenters.isNotEmpty ? _segmentCenters.first : null;

  // Sample a point at a given distance along the trail from the head
  Vector2 _sampleTrail(double distFromHead) {
    if (_trail.isEmpty) return Vector2(_headPixel.x + gridSize / 2, _headPixel.y + gridSize / 2);
    double d = 0;
    for (int i = 0; i < _trail.length - 1; i++) {
      final a = _trail[i];
      final b = _trail[i + 1];
      final segLen = (a - b).length;
      if (d + segLen >= distFromHead) {
        final t = (distFromHead - d) / segLen;
        return Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
      }
      d += segLen;
    }
    return _trail.last.clone();
  }
}
