// lib/snake_game.dart
import 'dart:math';
import 'dart:async' as async;
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

    // Collision with snake head (use pixel head from gameRef)
    if (gameRef._pixelPositions.isNotEmpty) {
      final headPixel = gameRef._pixelPositions.first + Vector2(gameRef.gridSize / 2, gameRef.gridSize / 2);
      final dist = (enemy.position - headPixel).length;
      if (dist < enemy.size + (gameRef.gridSize / 2)) {
        // Collision occured
        if (gameRef.hasShield) {
          // player destroys enemy
          gameRef.enemiesKilled++;
          gameRef.experience += 5;
          gameRef.score += 50;
          gameRef.checkLevelUp();
          removeFromParent();
        } else {
          // kill player (game over)
          gameRef.endGame();
        }
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
  // grid
  final int gridSize = 24; // pixels per cell (visual)
  late int gridWidth;
  late int gridHeight;

  // grid-based snake (positions in grid cells)
  List<Vector2> snake = [];
  Vector2 direction = Vector2(1, 0);
  Vector2 nextDirection = Vector2(1, 0);

  // pixel positions for smooth rendering (one per segment)
  final List<Vector2> _pixelPositions = [];

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
  late async.Timer gameTimer;
  late async.Timer enemySpawnTimer;
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

  List<PowerUp> availablePowerUps = [];

  // interpolation smoothing (how fast pixels move to target)
  double pixelLerpSpeed = 12.0; // higher -> faster visual interpolation

  @override
  Future<void> onLoad() async {
    super.onLoad();
    gridWidth = (size.x / gridSize).floor();
    gridHeight = (size.y / gridSize).floor();
    initializePowerUps();
    initializeGame();
    startGameLoop();
    startEnemySpawning();
  }

  void initializePowerUps() {
    availablePowerUps = [
      PowerUp(PowerUpType.speed, "Vitesse", "Augmente la vitesse de 20%", Colors.yellow),
      PowerUp(PowerUpType.shield, "Bouclier", "Protection contre les ennemis (10s)", Colors.blue),
      PowerUp(PowerUpType.multiFood, "Multi-Nourriture", "Double les points de nourriture (15s)", Colors.orange),
    ];
  }

  void initializeGame() {
    snake = [
      Vector2((gridWidth / 2).toDouble(), (gridHeight / 2).toDouble()),
      Vector2((gridWidth / 2 - 1).toDouble(), (gridHeight / 2).toDouble()),
      Vector2((gridWidth / 2 - 2).toDouble(), (gridHeight / 2).toDouble()),
    ];
    // create pixel positions aligned to grid
    _pixelPositions.clear();
    for (var seg in snake) {
      _pixelPositions.add(Vector2(seg.x * gridSize, seg.y * gridSize));
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

    food = null;
    generateFood();
  }

  void startGameLoop() {
    // cancel if existing
    try { gameTimer.cancel(); } catch (_) {}
    final intervalMs = (baseMoveInterval / speedMultiplier * 1000).round();
    gameTimer = async.Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (gameStarted && !gameOver && !showPowerUpSelection) {
        _stepSnake(); // logical move (grid)
      }
    });
  }

  void startEnemySpawning() {
    try { enemySpawnTimer.cancel(); } catch (_) {}
    enemySpawnTimer = async.Timer.periodic(Duration(milliseconds: (enemySpawnRate * 1000).round()), (_) {
      if (gameStarted && !gameOver && !showPowerUpSelection) {
        _spawnEnemy();
      }
    });
  }

  void _spawnEnemy() {
    // spawn at random side, convert to pixel coords
    int side = random.nextInt(4);
    Vector2 pos;
    Vector2 dir;
    switch (side) {
      case 0:
        pos = Vector2(random.nextDouble() * size.x, -30);
        dir = Vector2(0, 1);
        break;
      case 1:
        pos = Vector2(size.x + 30, random.nextDouble() * size.y);
        dir = Vector2(-1, 0);
        break;
      case 2:
        pos = Vector2(random.nextDouble() * size.x, size.y + 30);
        dir = Vector2(0, -1);
        break;
      default:
        pos = Vector2(-30, random.nextDouble() * size.y);
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
  void _stepSnake() {
    if (!gameStarted || gameOver || showPowerUpSelection) return;

    direction = nextDirection;

    final newHead = Vector2(snake.first.x + direction.x, snake.first.y + direction.y);

    // collisions walls
    if (newHead.x < 0 || newHead.x >= gridWidth || newHead.y < 0 || newHead.y >= gridHeight) {
      if (!hasShield) {
        endGame();
        return;
      }
    }

    // collision self
    for (var s in snake) {
      if (s.x == newHead.x && s.y == newHead.y) {
        if (!hasShield) {
          endGame();
          return;
        }
      }
    }

    snake.insert(0, newHead);

    // ensure pixel positions list length matches
    _pixelPositions.insert(0, Vector2(newHead.x * gridSize, newHead.y * gridSize));

    // food?
    if (food != null && newHead.x == food!.x && newHead.y == food!.y) {
      int points = hasMultiFood ? 20 : 10;
      score += points;
      experience += 2;
      foodEaten++;
      generateFood();
      checkLevelUp();

      // speed up gradually
      if (baseMoveInterval > 0.08) {
        baseMoveInterval *= 0.98;
        startGameLoop();
      }
    } else {
      // remove tail logically and pixel target
      snake.removeLast();
      _pixelPositions.removeLast();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!gameStarted || gameOver || showPowerUpSelection) return;

    // Smoothly interpolate pixel positions to their target (grid * gridSize)
    for (int i = 0; i < snake.length; i++) {
      final target = Vector2(snake[i].x * gridSize, snake[i].y * gridSize);
      final current = _pixelPositions[i];
      // simple lerp toward target:
      final lerpT = (1 - (1 / (1 + pixelLerpSpeed * dt))).clamp(0.0, 1.0);
      current.x = current.x + (target.x - current.x) * lerpT;
      current.y = current.y + (target.y - current.y) * lerpT;
      // update stored
      _pixelPositions[i] = current;
    }

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

  void checkLevelUp() {
    if (experience >= experienceToNextLevel) {
      level++;
      experience = 0;
      experienceToNextLevel = (experienceToNextLevel * 1.5).round();

      // increase difficulty
      if (enemySpawnRate > 1.0) {
        enemySpawnRate *= 0.9;
        startEnemySpawning();
      }

      // show power-up overlay (UI side reads this)
      showPowerUpSelection = true;
    }
  }

  void selectPowerUp(PowerUpType type) {
    switch (type) {
      case PowerUpType.speed:
        speedMultiplier += 0.2;
        startGameLoop();
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

  void generateFood() {
    Vector2 newFood;
    do {
      newFood = Vector2(
        random.nextInt(gridWidth).toDouble(),
        random.nextInt(gridHeight).toDouble(),
      );
    } while (snake.any((segment) => segment.x == newFood.x && segment.y == newFood.y));
    food = newFood;
  }

  // called from Flutter GestureDetector in main.dart
  void handlePanUpdate(DragUpdateDetails details) {
    if (!gameStarted || gameOver || showPowerUpSelection) return;
    final delta = details.delta;
    if (delta.dx.abs() > delta.dy.abs()) {
      // horizontal swipe
      final newDir = delta.dx > 0 ? Vector2(1, 0) : Vector2(-1, 0);
      if (!(direction.x == -newDir.x && direction.y == -newDir.y)) {
        nextDirection = newDir;
      }
    } else {
      final newDir = delta.dy > 0 ? Vector2(0, 1) : Vector2(0, -1);
      if (!(direction.x == -newDir.x && direction.y == -newDir.y)) {
        nextDirection = newDir;
      }
    }
  }

  // optional tap handler (e.g., pause / resume)
  void handleTapDown(TapDownDetails details) {
    // currently unused; can implement pause/resume or boost
  }

  void changeDirection(String newDirection) {
    if (gameOver || showPowerUpSelection) return;
    Vector2 newDir;
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
    if (direction.x != -newDir.x || direction.y != -newDir.y) {
      nextDirection = newDir;
    }
  }

  void endGame() {
    gameOver = true;
    gameStarted = false;
  }

  void resetGame() {
    try { gameTimer.cancel(); } catch (_) {}
    try { enemySpawnTimer.cancel(); } catch (_) {}
    baseMoveInterval = 0.25;
    enemySpawnRate = 3.0;
    initializeGame();
    startGameLoop();
    startEnemySpawning();
  }

  @override
  void render(Canvas canvas) {
    // DRAW BACKGROUND & GRID FIRST
    // background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), Paint()..color = Colors.black);

    // grid lines (subtle)
    final gridPaint = Paint()..color = Colors.grey.withOpacity(0.08);
    for (int i = 0; i <= gridWidth; i++) {
      final x = i * gridSize.toDouble();
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), gridPaint);
    }
    for (int j = 0; j <= gridHeight; j++) {
      final y = j * gridSize.toDouble();
      canvas.drawLine(Offset(0, y), Offset(size.x, y), gridPaint);
    }

    // draw snake (visual/pixel positions) BEFORE components so components (enemies) appear ON TOP
    final headPaint = Paint()..color = hasShield ? Colors.lightBlue : Colors.lightGreen;
    final bodyPaint = Paint()..color = hasShield ? Colors.cyan : Colors.green;
    for (int i = 0; i < _pixelPositions.length; i++) {
      final p = _pixelPositions[i];
      final paint = i == 0 ? headPaint : bodyPaint;
      canvas.drawRect(
        Rect.fromLTWH(p.x + 1, p.y + 1, gridSize.toDouble() - 2, gridSize.toDouble() - 2),
        paint,
      );
    }

    // draw food also BEFORE components (if you prefer food above enemies you'd make food a component with higher priority)
    if (food != null) {
      final center = Offset(food!.x * gridSize + gridSize / 2, food!.y * gridSize + gridSize / 2);
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
    try { gameTimer.cancel(); } catch (_) {}
    try { enemySpawnTimer.cancel(); } catch (_) {}
    super.onRemove();
  }
}
