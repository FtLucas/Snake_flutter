// lib/snake_game.dart
import 'dart:math';
import 'dart:async' as async;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

enum PowerUpType { speed, shield, multiFood }

enum EnemyClass { antTank, antDps, antRanged, antHealer, antPoison, antBoss }

class PowerUp {
  final PowerUpType type;
  final String name;
  final String description;
  final Color color;

  PowerUp(this.type, this.name, this.description, this.color);
}

class _Cloud {
  Offset pos; // sky-space position
  double speed; // px/s
  double scale; // 0.7..1.4
  _Cloud(this.pos, this.speed, this.scale);
}

class _Star {
  Offset pos;
  double twinkle; // 0..1 phase
  _Star(this.pos, this.twinkle);
}

class _Rock {
  Offset pos;
  double r;
  double ex; // ellipse x-scale
  Color color;
  _Rock(this.pos, this.r, this.ex, this.color);
}

class _Chamber {
  Offset c;
  double rx;
  double ry;
  _Chamber(this.c, this.rx, this.ry);
}

/// Simple data-only Enemy (logic moved into EnemyComponent)
class Enemy {
  Vector2 position;
  Vector2 direction;
  double speed;
  Color color;
  double size;
  int health;
  int maxHealth;
  EnemyClass kind;
  double cooldown; // generic per-type timer (fire/heal)
  int contactDamage;

  Enemy({
    required this.position,
    required this.direction,
    this.speed = 100.0, // pixels / second
    this.color = Colors.purple,
    this.size = 12.0,
  this.health = 1,
  this.maxHealth = 1,
  this.kind = EnemyClass.antDps,
  this.cooldown = 0,
  this.contactDamage = 1,
  });
}

/// Enemy as a Flame Component so it renders and updates itself
class EnemyComponent extends PositionComponent {
  // Tuning constants for ranges
  static const double rangedDesired = 180.0; // px preferred distance to player
  static const double rangedFireRange = 320.0; // px max firing range
  static const double healerPreferred = 220.0; // px preferred distance
  final Enemy enemy;
  final SnakeGame gameRef;
  // short-lived VFX timer for healer aura
  double _healFx = 0.0;
  double _bodyHitCooldown = 0.0; // avoid damage spam when touching snake body
  // Attack target selection along snake body (proportion 0..1 mapped to segment index >= 1)
  double _bodyTargetT = 0.6; // 0 = head, 1 = tail (we will clamp to >= 1 segment)
  double _retargetTimer = 0.0;
  double _bodySideSign = 1.0; // left/right offset sign
  double _bodyOffsetPx = 6.0; // small lateral offset so attackers don't stack perfectly
  // Prevent ranged ants from shooting while fleeing; add a short lockout after fleeing ends
  double _postFleeShootLock = 0.0;

  EnemyComponent({required this.enemy, required this.gameRef}) {
    // set component position and anchor — rendering will be done relative to Offset.zero
    position = enemy.position.clone();
    anchor = Anchor.center;
    size = Vector2.all(enemy.size * 2);
    // default priority: we may override when adding; keep a reasonable default
    priority = 10;
    // Initialize per-enemy body target so attackers pick different places on the body
    final rnd = gameRef.random;
    _bodyTargetT = 0.15 + rnd.nextDouble() * 0.8; // avoid exactly the head, allow near tail
    _retargetTimer = 2.0 + rnd.nextDouble() * 2.5;
    _bodySideSign = rnd.nextBool() ? 1.0 : -1.0;
    _bodyOffsetPx = 4.0 + rnd.nextDouble() * 8.0;
  }

  // Composite hit test between snake head (circle) and this ant modeled as three circles
  // positioned like in render (abdomen, thorax, head) and oriented by current direction.
  bool _headHitsAnt(Vector2 headCenter, double headRadius) {
    final r = enemy.size;
    // local offsets used in render
  final Offset abdomen = Offset(-r * 0.9, 0);
  const Offset thorax = Offset.zero;
  final Offset antHead = Offset(r * 0.95, 0);
  const List<double> radiiMul = [0.85, 0.7, 0.5];
  final List<double> radii = [for (final m in radiiMul) r * m];
  final List<Offset> locals = [abdomen, thorax, antHead];
    // orientation: treat direction as (cos,sin) on unit circle; default to +X
    final dir = enemy.direction.length2 > 0 ? enemy.direction.normalized() : Vector2(1, 0);
    final double cosA = dir.x;
    final double sinA = dir.y;
    for (int i = 0; i < locals.length; i++) {
      final o = locals[i];
      // rotate and translate to world (enemy.position is component center)
      final wx = enemy.position.x + o.dx * cosA - o.dy * sinA;
      final wy = enemy.position.y + o.dx * sinA + o.dy * cosA;
      final d = (Vector2(wx, wy) - headCenter).length;
      if (d < radii[i] + headRadius) return true;
    }
    return false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!gameRef.isGameActive) return;

    // Snapshot body centers to avoid concurrent length changes while iterating
    final List<Vector2> segsSnap = List<Vector2>.of(gameRef._segmentCenters);

    // Movement/abilities by class
    final head = gameRef.headCenter;
    Vector2 delta = Vector2.zero();
    bool fleeing = false; // whether this unit is currently moving away from the player
    if (head != null) {
      final toHead = (head - enemy.position);
      final dist = toHead.length;
      switch (enemy.kind) {
        case EnemyClass.antRanged:
          const double desired = rangedDesired;
          if (dist > desired + 20) {
            enemy.direction = toHead.normalized();
            delta += enemy.direction * enemy.speed * dt;
          } else if (dist < desired - 40) {
            enemy.direction = (-toHead).normalized();
            delta += enemy.direction * (enemy.speed * 0.8) * dt;
            fleeing = true;
          }
          enemy.cooldown -= dt;
          // Block shots while fleeing and briefly after (feel fairer)
          if (_postFleeShootLock > 0) _postFleeShootLock -= dt;
          if (!fleeing && _postFleeShootLock <= 0 && enemy.cooldown <= 0 && dist <= rangedFireRange) {
            enemy.cooldown = 1.6;
            final dir = toHead.normalized();
            gameRef.spawnProjectile(enemy.position.clone(), dir * 220, 1);
          }
          break;
        case EnemyClass.antHealer:
          // Backline behavior: keep distance from player, drift toward allies
          const desired = healerPreferred;
          Vector2 move = Vector2.zero();
          if (dist < desired) {
            // too close: move away from player
            move += (-toHead).normalized() * (enemy.speed * 0.7);
            fleeing = true;
          } else {
            // far enough: drift toward nearest ally to heal
            EnemyComponent? nearest;
            double best = double.infinity;
            for (final c in gameRef.children.query<EnemyComponent>()) {
              if (identical(c, this)) continue;
              final d = (c.enemy.position - enemy.position).length;
              if (d < best) { best = d; nearest = c; }
            }
            if (nearest != null) {
              final toAlly = (nearest.enemy.position - enemy.position);
              move += toAlly.normalized() * (enemy.speed * 0.4);
            }
          }
          if (move.length2 > 0) {
            final dirM = move.normalized();
            enemy.direction = dirM;
            delta += dirM * (move.length * dt);
          }
          enemy.cooldown -= dt;
          if (enemy.cooldown <= 0) {
            enemy.cooldown = 2.5;
            gameRef.healNearbyEnemies(this, radius: 140, heal: 1);
            _healFx = 0.6; // trigger heal aura effect
          }
          break;
        default:
          // Attackers aim for the snake BODY, not the head.
          // Retarget occasionally so they spread along the body.
          _retargetTimer -= dt;
          if (_retargetTimer <= 0) {
            final rnd = gameRef.random;
            _bodyTargetT = 0.12 + rnd.nextDouble() * 0.82;
            _retargetTimer = 2.0 + rnd.nextDouble() * 2.5;
            _bodySideSign = rnd.nextBool() ? 1.0 : -1.0;
            _bodyOffsetPx = 4.0 + rnd.nextDouble() * 8.0;
          }
          // Choose a segment index >= 1 from current body snapshot
          if (segsSnap.length >= 2) {
            int idx = 1 + (_bodyTargetT * (segsSnap.length - 1)).floor();
            if (idx < 1) idx = 1;
            if (idx >= segsSnap.length) idx = segsSnap.length - 1;
            Vector2 target = segsSnap[idx];
            // small lateral offset to avoid stacking
            Vector2 tangent;
            if (idx >= 2) {
              tangent = (segsSnap[idx - 1] - segsSnap[idx]).normalized();
            } else if (segsSnap.length >= 3) {
              tangent = (segsSnap[idx] - segsSnap[idx + 1]).normalized();
            } else {
              tangent = (head - target).normalized();
            }
            final normal = Vector2(-tangent.y, tangent.x);
            target += normal * (_bodyOffsetPx * _bodySideSign);
            final toTarget = (target - enemy.position);
            if (toTarget.length2 > 0) {
              enemy.direction = toTarget.normalized();
              delta += enemy.direction * enemy.speed * dt;
            }
          } else {
            // Fallback to head if body is not long enough
            enemy.direction = toHead.normalized();
            delta += enemy.direction * enemy.speed * dt;
          }
      }
    } else {
      final dir = enemy.direction.length2 > 0 ? enemy.direction.normalized() : Vector2(1, 0);
      delta += dir * enemy.speed * dt;
    }

    // Anti-corner nudge: if too close to walls, steer slightly toward center to avoid sticking
    final ir = gameRef.playRect.deflate(enemy.size + 1);
    final center = Vector2(ir.center.dx, ir.center.dy);
    final posPred = enemy.position + delta;
    final leftD = (posPred.x - ir.left);
    final rightD = (ir.right - posPred.x);
    final topD = (posPred.y - ir.top);
    final bottomD = (ir.bottom - posPred.y);
    final minD = min(min(leftD, rightD), min(topD, bottomD));
    const double stickMargin = 14.0;
    if (minD < stickMargin) {
      final toCenter = (center - posPred);
      if (toCenter.length2 > 0) {
        final nudge = toCenter.normalized() * (enemy.speed * 0.6 * dt) * ((stickMargin - minD) / stickMargin);
        delta += nudge;
      }
    }
    // Extra inward bias if fleeing and too close to boundary
    if (fleeing) {
      const double fleeMargin = 36.0;
      if (minD < fleeMargin) {
        final toCenter = (center - posPred);
        if (toCenter.length2 > 0) {
          final nudge = toCenter.normalized() * (enemy.speed * 1.2 * dt) * ((fleeMargin - minD) / fleeMargin);
          delta += nudge;
        }
      }
    }

    // Apply delta and clamp all ants inside the playfield
    enemy.position += delta;
    enemy.position.x = enemy.position.x.clamp(ir.left, ir.right).toDouble();
    enemy.position.y = enemy.position.y.clamp(ir.top, ir.bottom).toDouble();
    // update component position so Flame translates the canvas automatically
    position = enemy.position.clone();

    // VFX timers decay
    if (_healFx > 0) {
      _healFx -= dt;
      if (_healFx < 0) _healFx = 0;
    }
    if (_bodyHitCooldown > 0) {
      _bodyHitCooldown -= dt;
      if (_bodyHitCooldown < 0) _bodyHitCooldown = 0;
    }
    // If we were fleeing on this frame, keep a tiny post-flee lock so ranged won't insta-shoot
    if (fleeing) {
      // Small value; if they keep fleeing, it will just be refreshed next tick
      _postFleeShootLock = max(_postFleeShootLock, 0.25);
    }

    // Collisions with snake
    final headCenter = head; // alias after potential null check above
    if (headCenter != null) {
      // Head contact: decrement PV, kill only when <= 0
      final bool headHit = _headHitsAnt(headCenter, gameRef.snakeHeadRadius);
      if (headHit) {
        if (enemy.kind == EnemyClass.antPoison) {
          gameRef.applyPoison(4.0);
        }
        enemy.health -= 1;
        if (enemy.health <= 0) {
          gameRef._pendingGrowth += 1; // eating grants a segment
          gameRef.enemiesKilled++;
          gameRef.experience += 5;
          gameRef.score += 50;
          gameRef.checkLevelUp();
          final wasBoss = enemy.kind == EnemyClass.antBoss;
          removeFromParent();
          if (wasBoss) {
            gameRef.onBossDefeated();
          }
          return;
        } else {
          // small pushback
          final push = (enemy.position - headCenter).normalized() * 8;
          enemy.position += push;
          position = enemy.position.clone();
        }
      }
      // Body contact: does NOT kill ants; damages snake instead (with brief cooldown)
      if (segsSnap.isNotEmpty) {
        for (int i = 1; i < segsSnap.length; i++) {
          final d = (enemy.position - segsSnap[i]).length;
          if (d < enemy.size + gameRef.snakeHeadRadius * 0.9) {
            if (_bodyHitCooldown <= 0) {
              if (enemy.kind == EnemyClass.antPoison) {
                gameRef.applyPoison(4.0);
              }
              gameRef.damageSnake(enemy.contactDamage);
              _bodyHitCooldown = 0.4;
            }
            // push enemy away a bit from the segment
            final push = (enemy.position - segsSnap[i]).normalized() * 10;
            enemy.position += push;
            position = enemy.position.clone();
            break;
          }
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Ant "3D-like" with shadow and spherical shading
    final r = enemy.size;

    // Shadow (unrotated, under the ant)
    final Rect shadowOval = Rect.fromCenter(
      center: const Offset(0, 0) + Offset(0, r * 0.45),
      width: r * 1.8,
      height: r * 0.6,
    );
  canvas.drawOval(shadowOval, Paint()..color = Colors.black.withValues(alpha: 0.22 * gameRef.lightIntensity));

    // Rotate canvas toward current direction (origin is component center)
    final dir = enemy.direction.length2 > 0 ? enemy.direction.normalized() : Vector2(1, 0);
    final ang = atan2(dir.y, dir.x);
    canvas.save();
    canvas.rotate(ang);

    // Spherical body pieces with radial gradients
    Color mixColor(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    Paint spherePaint(Color base, Offset center, double rad) {
  final lighter = mixColor(base, Colors.white, 0.35 * gameRef.lightIntensity);
  final darker = mixColor(base, Colors.black, 0.25 * gameRef.lightIntensity);
      final lightOffset = Offset(-gameRef.lightDir.dx * rad * 0.6, -gameRef.lightDir.dy * rad * 0.6);
      return Paint()..shader = ui.Gradient.radial(center + lightOffset, rad, [lighter, base, darker], [0.0, 0.55, 1.0]);
    }

    final base = enemy.color;
    if (enemy.kind == EnemyClass.antBoss) {
      // Boss: thicker shadow, slight outline, and pulsing aura
      final auraT = (DateTime.now().millisecondsSinceEpoch % 1200) / 1200.0; // 0..1
      final auraR = r * (1.2 + 0.15 * sin(auraT * pi * 2));
      final aura = Paint()
        ..color = const Color(0xFFBA68C8).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(const Offset(0, 0), auraR, aura);
    }
  final abdomen = Offset(-r * 0.9, 0);
  const thorax = Offset(0, 0);
    final head = Offset(r * 0.95, 0);
  canvas.drawCircle(abdomen, r * 0.85, spherePaint(base, abdomen, r * 0.85));
  canvas.drawCircle(thorax, r * 0.7, spherePaint(base, thorax, r * 0.7));
  canvas.drawCircle(head, r * 0.5, spherePaint(base, head, r * 0.5));

    // legs (3 pairs)
    final stroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = -1; i <= 1; i++) {
      final y = i * r * 0.55;
      canvas.drawLine(Offset(-r * 0.2, y), Offset(-r * 0.95, y - r * 0.55), stroke);
      canvas.drawLine(Offset(-r * 0.2, y), Offset(-r * 0.95, y + r * 0.55), stroke);
    }

    // eyes on head
    final eyePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = Colors.black;
    final eyeOffset = Offset(r * 0.15, 0);
    final eyeSep = Offset(0, r * 0.22);
    final e1 = head + eyeOffset + eyeSep;
    final e2 = head + eyeOffset - eyeSep;
    canvas.drawCircle(e1, r * 0.12, eyePaint);
    canvas.drawCircle(e2, r * 0.12, eyePaint);
    canvas.drawCircle(e1, r * 0.06, pupilPaint);
    canvas.drawCircle(e2, r * 0.06, pupilPaint);

    // antennae from head
    final antStroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final antLen = r * 0.9;
    canvas.drawLine(head, head + Offset(antLen * 0.9, -antLen * 0.5), antStroke);
    canvas.drawLine(head, head + Offset(antLen * 0.9, antLen * 0.5), antStroke);

    // healer aura effect when healing (unchanged)
    if (enemy.kind == EnemyClass.antHealer && _healFx > 0) {
      final t = (0.6 - _healFx) / 0.6; // 0..1
      final auraColor = Colors.lightGreenAccent.withValues(alpha: (0.6 - t * 0.6));
      final aura = Paint()
        ..color = auraColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final rr = r * (1.0 + t * 1.2);
      canvas.drawCircle(thorax, rr, aura);
      // small sparkles
      final spark = Paint()..color = Colors.lightGreenAccent.withValues(alpha: (0.7 - t * 0.7));
      for (int i = 0; i < 8; i++) {
        final a = i * pi / 4 + t * pi * 2;
        final p = Offset(thorax.dx + cos(a) * (rr + 2), thorax.dy + sin(a) * (rr + 2));
        canvas.drawCircle(p, r * 0.12, spark);
      }
    }

    canvas.restore();

    // Health bar (drawn unrotated above the ant)
    if (enemy.maxHealth > 0) {
      final double pct = enemy.health.clamp(0, enemy.maxHealth) / enemy.maxHealth;
      final double bw = enemy.size * 1.8;
      const double bh = 3.0;
      final double y = -enemy.size - 10.0;
      final Rect bg = Rect.fromCenter(center: Offset(0, y), width: bw, height: bh);
      final Paint bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
  canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(2)), bgPaint);
      // bar color by health
      Color fc;
      if (pct > 0.5) {
        fc = const Color(0xFF66BB6A);
      } else if (pct > 0.25) {
        fc = const Color(0xFFFFEE58);
      } else {
        fc = const Color(0xFFE53935);
      }
      final double fw = bw * pct;
      final Rect fg = Rect.fromLTWH(bg.left, bg.top, fw, bh);
      final Paint fgPaint = Paint()..color = fc;
  canvas.drawRRect(RRect.fromRectAndRadius(fg, const Radius.circular(2)), fgPaint);
      // optional thin border
      final Paint border = Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
  canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(2)), border);
    }
  }
}

class ProjectileComponent extends PositionComponent {
  final SnakeGame gameRef;
  Vector2 velocity; // px/s
  double radius;
  int damage;
  ProjectileComponent({required this.gameRef, required Vector2 position, required this.velocity, this.radius = 4, this.damage = 1}) {
    this.position = position.clone();
    anchor = Anchor.center;
    size = Vector2.all(radius * 2);
    priority = 11;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!gameRef.isGameActive) return;
    position += velocity * dt;
    if (!Rect.fromLTWH(0, 0, gameRef.size.x, gameRef.size.y).inflate(20).contains(Offset(position.x, position.y))) {
      removeFromParent();
      return;
    }
    for (final c in gameRef._segmentCenters) {
      final d = (c - position).length;
      if (d < radius + gameRef.snakeHeadRadius * 0.9) {
        gameRef.damageSnake(damage);
        removeFromParent();
        return;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final p = Paint()..color = Colors.black87;
    canvas.drawCircle(Offset.zero, radius, p);
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

  // Wave system
  int wave = 0;
  bool waveActive = false;
  int waveRemaining = 0;
  double waveBreakTimer = 0.0;
  // Délai fixe entre les vagues (et avant la première)
  double waveBreakFixed = 4.0; // ajustable: 3.0–6.0 selon préférence
  double spawnIntervalInWave = 0.8;
  double spawnTimerInWave = 0.0;
  double waveElapsed = 0.0; // seconds since current wave start
  double waveDurationTarget = 12.0; // seconds target for sun progress
  // Boss & cycle jour/nuit
  bool isNight = false;
  double nightOpacity = 0.0; // 0 = jour, 1 = nuit
  bool bossActive = false;
  EnemyComponent? currentBoss;

  // Demo/Debug
  bool demoMode = false; // auto-pilote pour valider sans jouer
  double demoTimeScale = 2.5; // accélération des timers en mode démo

  // powerups
  bool hasShield = false;
  double shieldDuration = 0.0;
  bool hasMultiFood = false;
  double multiFoodDuration = 0.0;
  double speedMultiplier = 1.0;

  final List<PowerUp> availablePowerUps = [];

  // interpolation smoothing (how fast pixels move to target)
  final double pixelLerpSpeed = 12.0; // higher -> faster visual interpolation
  // Direction de la lumière (dynamique, contrôlée par la position du soleil)
  Offset lightDir = const Offset(-0.6, -0.8);
  // Intensité de la lumière (0 nuit, 1 plein soleil)
  double lightIntensity = 1.0;
  // Soleil: position (dans le ciel noir), cible et intensité cible pour interpolation
  Offset _sunPos = const Offset(0, 0);
  Offset _sunTargetPos = const Offset(0, 0);
  double _sunIntensity = 1.0;
  double _sunTargetIntensity = 1.0;
  // Warm tint around sunrise/sunset (0 cool, 1 warm)
  double _warmFactor = 0.0;
  // Progression du soleil sur l'horizon (0=gauche,1=droite) cumulée sur les vagues
  double _sunProgress = 0.0;
  double _waveSunBaseProgress = 0.0;
  double _waveSunTargetProgress = 0.25;
  // Lune
  Offset _moonPos = const Offset(-100, -100);
  Offset _moonTargetPos = const Offset(-100, -100);
  double _moonIntensity = 0.0;
  double _moonTargetIntensity = 0.0;

  // grass background
  ui.Image? _grassTile;
  Paint? _grassPaint;
  final int _grassTileSize = 64; // px
  // extra detail layers for 3D-like grass
  ui.Image? _grassHiTile;
  ui.Image? _grassLoTile;
  Paint? _grassHiPaint;
  Paint? _grassLoPaint;
  // soil decor (rocks/pebbles) in bottom band
  final List<_Rock> _rocks = [];
  // additional soil texture: stable grain specks (light/dark)
  final List<Offset> _soilGrainsLight = [];
  final List<Offset> _soilGrainsDark = [];
  // anthill
  Offset _anthillMouth = Offset.zero;
  double _anthillWidth = 44.0;
  // debug: show only anthill (no soil/rocks) to validate its shape
  final bool _debugAnthillOnly = false; // re-enable soil/rocks
  // toggle anthill visibility and spawns
  final bool _showAnthill = false;
  final List<_Chamber> _anthillChambers = [];
  // Sky decor
  final List<_Cloud> _clouds = [];
  final List<_Star> _stars = [];
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
  // status
  double _poisonTimer = 0.0;
  double _poisonTick = 0.0;
  int get snakeHp => _segmentCount;
  List<Vector2> get bodyCenters => _segmentCenters;

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
    _generateSoilDecor();
  _computeAnthill();
    _initializePowerUps();
    _initializeGame();
    _startGameLoop();
  _startEnemySpawning(); // disabled in favor of waves (kept for compatibility)
  }

  void _generateSoilDecor() {
    _rocks.clear();
    _soilGrainsLight.clear();
    _soilGrainsDark.clear();
    final Rect soil = Rect.fromLTWH(0, playOrigin.y + playSize.y, size.x, size.y - (playOrigin.y + playSize.y));
    final int count = (size.x / 12).clamp(12, 80).toInt();
    for (int i = 0; i < count; i++) {
      final double x = random.nextDouble() * soil.width;
      final double y = random.nextDouble() * soil.height;
      final double r = 2.0 + random.nextDouble() * 6.0;
      final double ex = 0.8 + random.nextDouble() * 0.8;
      // Choose whitish/grey/black palette to avoid flicker and match request
      const List<Color> palette = [
        Color(0xFFECEFF1), // very light
        Color(0xFFCFD8DC),
        Color(0xFFB0BEC5),
        Color(0xFF90A4AE),
        Color(0xFF757575),
        Color(0xFF616161),
        Color(0xFF424242), // dark
      ];
      final Color base = palette[random.nextInt(palette.length)];
      _rocks.add(_Rock(Offset(soil.left + x, soil.top + y), r, ex, base));
    }

    // Grain specks: precompute light/dark tiny dots, avoid the top 4px under the grass edge
  const double marginTop = 4.0;
    final Rect soilGrainArea = Rect.fromLTWH(soil.left, soil.top + marginTop, soil.width, max(0.0, soil.height - marginTop));
    if (soilGrainArea.height > 0 && soilGrainArea.width > 0) {
      // Counts proportional to area, clamped to a reasonable range
      final int lightCount = (soilGrainArea.width * soilGrainArea.height / 1600).clamp(80, 420).toInt();
      final int darkCount = (soilGrainArea.width * soilGrainArea.height / 2000).clamp(60, 360).toInt();
      for (int i = 0; i < lightCount; i++) {
        final double x = random.nextDouble() * soilGrainArea.width;
        final double y = random.nextDouble() * soilGrainArea.height;
        _soilGrainsLight.add(Offset(soilGrainArea.left + x, soilGrainArea.top + y));
      }
      for (int i = 0; i < darkCount; i++) {
        final double x = random.nextDouble() * soilGrainArea.width;
        final double y = random.nextDouble() * soilGrainArea.height;
        _soilGrainsDark.add(Offset(soilGrainArea.left + x, soilGrainArea.top + y));
      }
    }
  }

  void _computeAnthill() {
  // Build a larger multi-chamber anthill inspired by the reference
  final Rect soil = Rect.fromLTWH(0, playRect.bottom, size.x, size.y - playRect.bottom);
  // Mouth centered slightly right
  _anthillMouth = Offset(soil.left + soil.width * 0.65, soil.top);
  _anthillWidth = max(52.0, soil.width * 0.12);
  _anthillChambers.clear();
  if (soil.height <= 0) return;
  // Place 6 chambers at different depths/positions
  double w = soil.width; double h = soil.height;
  Offset P(double px, double py) => Offset(soil.left + w * px, soil.top + h * py);
  double rx(double f) => max(26.0, h * f);
  double ry(double f) => max(18.0, h * f * 0.75);
  _anthillChambers.add(_Chamber(P(0.26, 0.20), rx(0.10), ry(0.095)));
  _anthillChambers.add(_Chamber(P(0.60, 0.26), rx(0.11), ry(0.095)));
  _anthillChambers.add(_Chamber(P(0.28, 0.48), rx(0.14), ry(0.11)));
  _anthillChambers.add(_Chamber(P(0.76, 0.54), rx(0.13), ry(0.10)));
  _anthillChambers.add(_Chamber(P(0.54, 0.74), rx(0.12), ry(0.095)));
  _anthillChambers.add(_Chamber(P(0.34, 0.80), rx(0.115), ry(0.09)));
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
        ..color = Color.lerp(const Color(0xFF43A047), const Color(0xFF2E7D32), rng.nextDouble())!;
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

    // Build highlight detail tile (white highlights on transparent)
    final recHi = ui.PictureRecorder();
    final canHi = Canvas(recHi, Rect.fromLTWH(0, 0, s, s));
    canHi.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..blendMode = BlendMode.clear);
    final Paint hi = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 80; i++) {
      final x = rng.nextDouble() * s;
      final y = rng.nextDouble() * s;
      final len = 2.2 + rng.nextDouble() * 3.0;
      final a = (rng.nextDouble() - 0.5) * 0.9;
      final p0 = Offset(x, y);
      final p1 = p0 + Offset(cos(a) * len, -sin(a) * len);
      hi.strokeWidth = 0.8 + rng.nextDouble() * 0.6;
      canHi.drawLine(p0, p1, hi);
    }
    final picHi = recHi.endRecording();
    _grassHiTile = await picHi.toImage(_grassTileSize, _grassTileSize);
    _grassHiPaint = Paint()
      ..shader = ui.ImageShader(_grassHiTile!, TileMode.repeated, TileMode.repeated, identity)
      ..blendMode = BlendMode.plus; // additive highlights

    // Build shadow detail tile (dark dots/ellipses on transparent)
    final recLo = ui.PictureRecorder();
    final canLo = Canvas(recLo, Rect.fromLTWH(0, 0, s, s));
    canLo.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..blendMode = BlendMode.clear);
    final Paint lo = Paint()
      ..color = Colors.black.withValues(alpha: 0.7);
    for (int i = 0; i < 70; i++) {
      final cx = rng.nextDouble() * s;
      final cy = rng.nextDouble() * s;
      final rw = 0.6 + rng.nextDouble() * 1.4;
      final rh = 0.4 + rng.nextDouble() * 1.0;
      canLo.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rw, height: rh), lo);
    }
    final picLo = recLo.endRecording();
    _grassLoTile = await picLo.toImage(_grassTileSize, _grassTileSize);
    _grassLoPaint = Paint()
      ..shader = ui.ImageShader(_grassLoTile!, TileMode.repeated, TileMode.repeated, identity)
      ..blendMode = BlendMode.multiply; // darken
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
  _poisonTimer = 0.0;
  _poisonTick = 0.0;
  // Reset night/boss state
  isNight = false;
  nightOpacity = 0.0;
  bossActive = false;
  currentBoss = null;

  // Init sun state
  // Sun starts at left when launching the game
  _sunPos = Offset(playOrigin.x + 40, topMargin * 0.7);
  _sunTargetPos = _sunPos;
  _sunIntensity = 1.0;
  _sunTargetIntensity = 1.0;
  // Moon starts hidden
  _moonPos = const Offset(-100, -100);
  _moonTargetPos = const Offset(-100, -100);
  _moonIntensity = 0.0;
  _moonTargetIntensity = 0.0;
  // Sun progress init
  _sunProgress = 0.0; // left
  _waveSunBaseProgress = 0.0;
  _waveSunTargetProgress = 0.25;

  // Seed pixel head based on current grid head
  _headPixel = Vector2(playOrigin.x + snake.first.x * gridSize, playOrigin.y + snake.first.y * gridSize);
  _headGrid = snake.first.clone();
  food = null;
    generateFood();
    // Seed clouds (day) and stars (night)
    _clouds
      ..clear()
      ..addAll(List.generate(6, (i) {
        final x = playOrigin.x + random.nextDouble() * playSize.x;
        final y = topMargin * (0.2 + random.nextDouble() * 0.6);
        final scale = 0.8 + random.nextDouble() * 0.6;
        final speed = 10 + random.nextDouble() * 20;
        return _Cloud(Offset(x, y), speed, scale);
      }));
    _stars
      ..clear()
      ..addAll(List.generate(40, (i) {
        final x = playOrigin.x + random.nextDouble() * playSize.x;
        final y = random.nextDouble() * (topMargin * 0.9);
        final tw = random.nextDouble();
        return _Star(Offset(x, y), tw);
      }));
  }


  void _startGameLoop() {
    // Still used to progressively speed up legacy timing (not moving by cell anymore)
    _gameTimer?.cancel();
    _gameTimer = async.Timer.periodic(const Duration(seconds: 10), (_) {});
  }

  void _startEnemySpawning() {
  // Wave system: start at Wave 0 (idle) and wait before launching Wave 1
  _enemySpawnTimer?.cancel();
  wave = 0;
  waveActive = false;
  waveRemaining = 0;
  spawnIntervalInWave = 0.8;
  spawnTimerInWave = 0.0;
  waveBreakTimer = waveBreakFixed; // fixed delay before first wave
  }

  /// Fait apparaître un ennemi sur un bord aléatoire
  void _spawnEnemy() {
  // Spawn at the extremities (edges) of the texture playfield
  // Spawn from edges only (anthill disabled for now)
  int side = random.nextInt(4);
    Vector2 pos;
    Vector2 dir;
    final Rect r = playRect;
    switch (side) {
      case 0: // top (spawn just inside)
        pos = Vector2(r.left + random.nextDouble() * r.width, r.top + 6);
        dir = Vector2(0, 1);
        break;
      case 1: // right
        pos = Vector2(r.right - 6, r.top + random.nextDouble() * r.height);
        dir = Vector2(-1, 0);
        break;
      case 2: // bottom
        pos = Vector2(r.left + random.nextDouble() * r.width, r.bottom - 6);
        dir = Vector2(0, -1);
        break;
      default: // left
        pos = Vector2(r.left + 6, r.top + random.nextDouble() * r.height);
        dir = Vector2(1, 0);
    }

    // Difficulty scaling by wave
    final int w = wave <= 0 ? 1 : wave;
    final double spdFactor = 1.0 + 0.05 * (w - 1); // +5% speed per wave
    final int extraTankHp = ((w - 1) ~/ 3); // +1 HP every 3 waves

    // Choose an ant class
    final roll = random.nextDouble();
    late Enemy enemy;
    if (roll < 0.2) {
      enemy = Enemy(
        position: pos,
        direction: dir,
        speed: 80 * spdFactor,
        size: 18,
        color: const Color(0xFF4E342E),
        health: 3 + extraTankHp,
        maxHealth: 3 + extraTankHp,
        kind: EnemyClass.antTank,
        contactDamage: 2,
      );
    } else if (roll < 0.55) {
      enemy = Enemy(
        position: pos,
        direction: dir,
        speed: 140 * spdFactor,
        size: 12,
        color: const Color(0xFF5D4037),
        health: 1,
        maxHealth: 1,
        kind: EnemyClass.antDps,
        contactDamage: 1,
      );
    } else if (roll < 0.75) {
      enemy = Enemy(
        position: pos,
        direction: dir,
        speed: 110 * spdFactor,
        size: 12,
        color: const Color(0xFF00E676), // vivid green for poison
        health: 1,
        maxHealth: 1,
        kind: EnemyClass.antPoison,
        contactDamage: 1,
      );
    } else if (roll < 0.9) {
      enemy = Enemy(
        position: pos,
        direction: dir,
        speed: 100 * spdFactor,
        size: 11,
        color: const Color(0xFF795548),
        health: 1,
        maxHealth: 1,
        kind: EnemyClass.antHealer,
        contactDamage: 1,
      );
    } else {
      enemy = Enemy(
        position: pos,
        direction: dir,
        speed: 70 * spdFactor, // ranged slower, scales a bit
        size: 12,
        color: const Color(0xFF212121),
        health: 1, // keep ranged at 1 HP
        maxHealth: 1,
        kind: EnemyClass.antRanged,
        contactDamage: 1,
      );
    }

    final comp = EnemyComponent(enemy: enemy, gameRef: this);
    comp.priority = 10;
    // Clamp initial spawn fully inside playRect based on size
    final ir2 = playRect.deflate(enemy.size + 1);
    enemy.position.x = enemy.position.x.clamp(ir2.left, ir2.right).toDouble();
    enemy.position.y = enemy.position.y.clamp(ir2.top, ir2.bottom).toDouble();
    add(comp);
  }

  // logical grid step
  /// Mouvement continu et corps fluide via trail
  void _stepSnakeContinuous(double dt) {
    if (!gameStarted || gameOver || showPowerUpSelection) return;
    // Apply joystick decision first
    direction = nextDirection;

    // Move the head pixel position continuously
  final double effectiveSpeed = playerSpeed * speedMultiplier;
  final vel = direction.normalized() * effectiveSpeed * dt;
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
  _catchup += effectiveSpeed * dt;
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

  // Accélération légère des timers en mode démo (n'affecte pas la physique de collision)
  final double tScale = demoMode ? demoTimeScale : 1.0;

    // Joystick input (from Flutter) -> analog direction (normalized)
    final joy = _joystickDelta;
    if (!demoMode) {
      if (joy != null && joy.length > _joystickDeadZone) {
        nextDirection = joy.normalized();
      }
    } else {
      // Auto-pilote simple: va vers la pomme, évite les bords
      final headCenter = _headPixel + Vector2(gridSize / 2, gridSize / 2);
      Vector2 target;
      if (food != null) {
        target = Vector2(
          playOrigin.x + food!.x * gridSize + gridSize / 2,
          playOrigin.y + food!.y * gridSize + gridSize / 2,
        );
      } else {
        target = Vector2(playOrigin.x + playSize.x / 2, playOrigin.y + playSize.y / 2);
      }
      Vector2 steer = (target - headCenter);
      // évite les bords: repoussement si proche
      const double margin = 30.0;
      if (headCenter.x < playRect.left + margin) steer += Vector2(60, 0);
      if (headCenter.x > playRect.right - margin) steer += Vector2(-60, 0);
      if (headCenter.y < playRect.top + margin) steer += Vector2(0, 60);
      if (headCenter.y > playRect.bottom - margin) steer += Vector2(0, -60);
      if (steer.length2 > 0) {
        nextDirection = steer.normalized();
      }
    }

  // Continuous movement
  _stepSnakeContinuous(dt);
    if (_poisonTimer > 0) {
      _poisonTimer -= dt;
      _poisonTick += dt;
      if (_poisonTick >= 2.5) {
        _poisonTick = 0;
        damageSnake(1);
      }
    }

    // Update power-up timers
    if (hasShield) {
      shieldDuration -= dt * tScale;
      if (shieldDuration <= 0) {
        hasShield = false;
      }
    }
    if (hasMultiFood) {
      multiFoodDuration -= dt * tScale;
      if (multiFoodDuration <= 0) {
        hasMultiFood = false;
      }
    }

  // Night fade in/out
    if (bossActive) {
      // fade to full night while boss is alive
      nightOpacity += (dt * tScale) / 1.0; // ~1s fade-in (accéléré en démo)
      if (nightOpacity > 1.0) nightOpacity = 1.0;
      isNight = true;
    } else if (isNight) {
      // fade back to day after boss
      nightOpacity -= (dt * tScale) / 1.2; // ~1.2s fade-out (accéléré en démo)
      if (nightOpacity <= 0) {
        nightOpacity = 0;
        isNight = false;
      }
    }

  // Wave system update (paused during boss)
    if (bossActive) {
      // no wave progression or spawns while boss is alive
    } else if (!waveActive) {
      waveBreakTimer -= dt * tScale;
      if (waveBreakTimer <= 0) {
        wave += 1;
        if (wave % 5 == 0) {
          // Boss wave: night + single boss spawn; hold until defeated
          bossActive = true;
          isNight = true;
          // Clear any existing apple at boss start
          food = null;
          // Place sun fully at the right edge before sunset
          final Rect sky = Rect.fromLTWH(playRect.left, 0, playRect.width, topMargin);
          _sunProgress = 1.0;
          final Offset rightEdge = Offset(sky.right - 40, sky.top + sky.height * 0.35);
          _sunPos = rightEdge;
          _sunTargetPos = rightEdge;
          _spawnBoss();
          // ensure normal wave spawns are idle
          waveActive = false;
          waveRemaining = 0;
          spawnTimerInWave = 0.0;
        } else {
          waveActive = true;
          waveRemaining = 3 + (wave * 2);
          spawnIntervalInWave = max(0.35, 0.8 - wave * 0.03);
          spawnTimerInWave = 0.0;
          // Estimate wave duration to drive sun progress (spawns + combat buffer)
          waveElapsed = 0.0;
          final double spawnPhase = waveRemaining * spawnIntervalInWave;
          waveDurationTarget = max(10.0, spawnPhase + 6.0);
          // Set sun progress target for this wave so it continues from where it stopped
          // Approach: divide a “day” into 4 regular waves (before boss). Each wave advances a quarter,
          // but we allow partial advancement if wave ends early. We preserve progress on breaks.
          final int posInCycle = ((wave - 1) % 5); // 0..3 regular, 4 is boss
          // If we’re on the last regular wave before boss (posInCycle==3), aim near the right edge.
          final double target = (posInCycle == 3) ? 0.98 : min(1.0, (posInCycle + 1) / 4.0);
          _waveSunBaseProgress = _sunProgress;
          _waveSunTargetProgress = max(_sunProgress, target);
        }
      }
    } else {
      // active regular wave: spawn enemies until done
  spawnTimerInWave -= dt * tScale;
      if (spawnTimerInWave <= 0 && waveRemaining > 0) {
        _spawnEnemy();
        waveRemaining--;
        spawnTimerInWave = spawnIntervalInWave;
      }
      // when wave enemies have all been spawned, start break (even if some survive)
      if (waveRemaining == 0) {
        waveActive = false;
        // Fixed delay before the next wave so it doesn't launch immediately
        waveBreakTimer = waveBreakFixed;
      }
      // Track elapsed time within the wave for sun progress
  waveElapsed += dt * tScale;
      // Advance sun progress towards the target proportionally to wave progress
      if (wave % 5 != 0) {
        final double t = (waveElapsed / waveDurationTarget).clamp(0.0, 1.0);
        _sunProgress = ui.lerpDouble(_waveSunBaseProgress, _waveSunTargetProgress, t)!;
      }
    }

  // Update sun/moon targets continuously so the sun moves during the wave
  _updateSunAndMoonTargets();
    // Smoothly lerp sun and moon
    _sunPos = Offset(
      ui.lerpDouble(_sunPos.dx, _sunTargetPos.dx, (dt * 1.5).clamp(0.0, 1.0))!,
      ui.lerpDouble(_sunPos.dy, _sunTargetPos.dy, (dt * 1.5).clamp(0.0, 1.0))!,
    );
    _sunIntensity = ui.lerpDouble(_sunIntensity, _sunTargetIntensity, (dt * 1.5).clamp(0.0, 1.0))!;
    _moonPos = Offset(
      ui.lerpDouble(_moonPos.dx, _moonTargetPos.dx, (dt * 1.5).clamp(0.0, 1.0))!,
      ui.lerpDouble(_moonPos.dy, _moonTargetPos.dy, (dt * 1.5).clamp(0.0, 1.0))!,
    );
    _moonIntensity = ui.lerpDouble(_moonIntensity, _moonTargetIntensity, (dt * 1.5).clamp(0.0, 1.0))!;
    // Derive light direction from sun position relative to playfield center
    final Offset center = playRect.center;
    final Offset vec = (center - _sunPos);
    if (vec.distanceSquared > 0) {
      lightDir = Offset(vec.dx / vec.distance, vec.dy / vec.distance);
    }
    // Reduce scene light with nightOpacity (sun sets)
    lightIntensity = (1.0 - nightOpacity) * _sunIntensity;
  // Warm factor: stronger near sunrise/sunset (sun near left/right)
  final Rect sky = Rect.fromLTWH(playRect.left, 0, playRect.width, topMargin);
  final double sNorm = ((_sunPos.dx - (sky.left + 40)) / ((sky.right - 40) - (sky.left + 40))).clamp(0.0, 1.0);
  _warmFactor = (1.0 - (sNorm - 0.5).abs() * 2.0).clamp(0.0, 1.0) * lightIntensity;

    // Animate clouds (day): drift to the right; wrap around
    for (final c in _clouds) {
      c.pos = c.pos.translate(c.speed * dt, 0);
      if (c.pos.dx > playOrigin.x + playSize.x + 60) {
        c.pos = Offset(playOrigin.x - 60, c.pos.dy);
      }
    }
    // Animate stars (night): small twinkle oscillation
    for (final s in _stars) {
      s.twinkle += dt * (0.5 + random.nextDouble());
      if (s.twinkle > 1000) s.twinkle -= 1000;
    }
  }

  void _updateSunAndMoonTargets() {
    // Define a sky rectangle above the playfield for the sun to travel
    final Rect sky = Rect.fromLTWH(playRect.left, 0, playRect.width, topMargin);
    if (bossActive) {
      // During boss/night: sun sets beyond horizon bottom-right and intensity goes to 0
      _sunTargetPos = Offset(sky.right + 60, sky.bottom + 40);
      _sunTargetIntensity = 0.0;
  // Moon at center and slightly to the right
  _moonTargetPos = Offset(sky.left + sky.width * 0.62, sky.top + sky.height * 0.50);
      _moonTargetIntensity = 1.0;
      return;
    }
    // Regular day (non-boss): position sun based on cumulative progress, hold during breaks.
    if (wave % 5 != 0 || wave == 0) {
      final double t = _sunProgress.clamp(0.0, 1.0);
      final double x = ui.lerpDouble(sky.left + 40, sky.right - 40, t)!;
      final double y = ui.lerpDouble(sky.top + sky.height * 0.7, sky.top + sky.height * 0.3, t)!;
      _sunTargetPos = Offset(x, y);
      _sunTargetIntensity = 0.7 + 0.3 * (1.0 - (t - 0.5).abs() * 2.0).clamp(0.0, 1.0);
      _moonTargetPos = const Offset(-100, -100);
      _moonTargetIntensity = 0.0;
      return;
    }
    if (wave == 0) {
      // Game start idle: sun sits at left
      _sunTargetPos = Offset(sky.left + 40, sky.top + sky.height * 0.7);
      _sunTargetIntensity = 0.85;
      _moonTargetPos = const Offset(-100, -100);
      _moonTargetIntensity = 0.0;
      return;
    }
    // Break and other non-active, non-boss states: keep targets as-is.
    return;
  }

  /// Vérifie si le joueur passe au niveau supérieur
  void checkLevelUp() {
    if (experience >= experienceToNextLevel) {
      experience = 0;
      experienceToNextLevel = (experienceToNextLevel * 1.5).round();
  level += 1;

      // increase difficulty
      if (enemySpawnRate > 1.0) {
        enemySpawnRate *= 0.9;
  // Keep current wave progression; do not restart waves on level-up
      }

  // Affiche le choix de compétence seulement tous les 5 niveaux
  showPowerUpSelection = (level % 5 == 0);
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

  // Helpers for enemies
  void spawnProjectile(Vector2 pos, Vector2 vel, int damage) {
    add(ProjectileComponent(gameRef: this, position: pos, velocity: vel, damage: damage));
  }

  void healNearbyEnemies(EnemyComponent healer, {double radius = 140, int heal = 1}) {
    for (final c in children.query<EnemyComponent>()) {
      if (identical(c, healer)) continue;
      final d = (c.enemy.position - healer.enemy.position).length;
      if (d <= radius) {
        c.enemy.health = (c.enemy.health + heal).clamp(0, c.enemy.maxHealth);
      }
    }
  }

  void damageSnake(int amount) {
    if (hasShield) return;
    _segmentCount -= amount;
    if (_segmentCount <= 0) {
      endGame();
      return;
    }
    if (_segmentCenters.length > _segmentCount) {
      _segmentCenters.removeRange(_segmentCount, _segmentCenters.length);
    }
    final maxCatch = (_segmentCount - 1).clamp(0, 9999) * _segmentSpacing;
    if (_catchup > maxCatch) _catchup = maxCatch;
  }

  void applyPoison(double seconds) {
    _poisonTimer = max<double>(_poisonTimer, seconds);
  }

  // Boss lifecycle
  void _spawnBoss() {
    // Spawn boss near a random edge, larger stats
    final Rect r = playRect;
    final int side = random.nextInt(4);
    late Vector2 pos;
    late Vector2 dir;
    switch (side) {
      case 0:
        pos = Vector2(r.left + random.nextDouble() * r.width, r.top + 10);
        dir = Vector2(0, 1);
        break;
      case 1:
        pos = Vector2(r.right - 10, r.top + random.nextDouble() * r.height);
        dir = Vector2(-1, 0);
        break;
      case 2:
        pos = Vector2(r.left + random.nextDouble() * r.width, r.bottom - 10);
        dir = Vector2(0, -1);
        break;
      default:
        pos = Vector2(r.left + 10, r.top + random.nextDouble() * r.height);
        dir = Vector2(1, 0);
    }
    // scale boss difficulty with wave
    final int w = max(1, wave);
    final int baseHp = 20 + (w ~/ 2) * 5; // grows with waves
    final double spd = 90.0 + min(60.0, w * 2.0);
    final Enemy boss = Enemy(
      position: pos,
      direction: dir,
      speed: spd,
      size: 26,
      color: const Color(0xFF9C27B0), // distinctive purple
      health: baseHp,
      maxHealth: baseHp,
      kind: EnemyClass.antBoss,
      contactDamage: 2,
    );
    final EnemyComponent comp = EnemyComponent(enemy: boss, gameRef: this);
    comp.priority = 12;
    // Clamp inside playRect
    final ir2 = playRect.deflate(boss.size + 1);
    boss.position.x = boss.position.x.clamp(ir2.left, ir2.right).toDouble();
    boss.position.y = boss.position.y.clamp(ir2.top, ir2.bottom).toDouble();
    add(comp);
    currentBoss = comp;
  }

  void onBossDefeated() {
    if (!bossActive) return;
    bossActive = false;
    currentBoss = null;
    // Begin day fade-out; schedule next regular wave after a fixed break
    waveActive = false;
    waveRemaining = 0;
    waveBreakTimer = waveBreakFixed;
    // isNight stays true until nightOpacity animates back to 0 in update()
  // Hide the moon now; sun will resume from its last progress on next waves
  _moonTargetPos = const Offset(-100, -100);
  _moonTargetIntensity = 0.0;
  _moonPos = _moonTargetPos;
  _moonIntensity = 0.0;
  // Reset sun to start-of-day (wave 0) so a new cycle begins after boss
  final Rect sky = Rect.fromLTWH(playRect.left, 0, playRect.width, topMargin);
  _sunProgress = 0.0; // left
  _waveSunBaseProgress = 0.0;
  _waveSunTargetProgress = 0.25;
  _sunPos = Offset(sky.left + 40, sky.top + sky.height * 0.7);
  _sunTargetPos = _sunPos;
  _sunIntensity = 0.85;
  _sunTargetIntensity = 0.85;
  }

  /// Génère une nouvelle position de nourriture qui ne chevauche pas le serpent
  void generateFood() {
  if (bossActive) { return; } // pause apples during boss
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
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), Paint()..color = const Color(0xFF000000));

    // Sky band: day or night gradient depending on lightIntensity/nightOpacity
    final Rect sky = Rect.fromLTWH(playOrigin.x, 0, playSize.x, topMargin);
    if ((lightIntensity > 0.2) && !isNight) {
      // Day sky: deep to light blue
      final Paint skyPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(sky.left, sky.bottom),
          Offset(sky.left, sky.top),
          const [
            Color(0xFF2196F3),
            Color(0xFFBBDEFB),
          ],
          [0.0, 1.0],
        );
      canvas.drawRect(sky, skyPaint);
    } else {
      // Night sky: black to deep navy
      final Paint skyPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(sky.left, sky.bottom),
          Offset(sky.left, sky.top),
          const [
            Color(0xFF000000),
            Color(0xFF061126),
          ],
          [0.0, 1.0],
        );
      canvas.drawRect(sky, skyPaint);
    }
    // Stars (night) and clouds (day+night) in the sky band
    canvas.save();
    canvas.clipRect(sky);
    // Stars: visible mostly at night
    if (isNight || lightIntensity < 0.2) {
      for (final s in _stars) {
        final double phase = (sin(s.twinkle * pi * 2) * 0.5 + 0.5);
        final double a = (0.35 + 0.65 * phase) * (0.4 + 0.6 * nightOpacity);
  final Paint starPaint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: a.clamp(0.0, 1.0));
        canvas.drawCircle(s.pos, 1.2 + 0.8 * phase, starPaint);
      }
    }
    // Clouds: soft white puffs, brighter by day, faint at night
    for (final c in _clouds) {
      final double sc = c.scale;
      final double baseAlpha = isNight ? 0.12 : (0.18 + 0.10 * (1.0 - (1.0 - lightIntensity).clamp(0.0, 1.0)));
      // add a touch of warmth near sunrise/sunset
      final double warmBoost = 0.08 * _warmFactor;
  final Paint cloud = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: (baseAlpha + warmBoost).clamp(0.06, 0.35));
      // three blobs + base oval
      canvas.drawCircle(c.pos + Offset(-12 * sc, 0), 12 * sc, cloud);
      canvas.drawCircle(c.pos + Offset(0, -6 * sc), 14 * sc, cloud);
      canvas.drawCircle(c.pos + Offset(14 * sc, 0), 10 * sc, cloud);
      final Rect base = Rect.fromCenter(center: c.pos + Offset(2 * sc, 6 * sc), width: 50 * sc, height: 16 * sc);
      canvas.drawRRect(RRect.fromRectAndRadius(base, Radius.circular(8 * sc)), cloud);
    }
    canvas.restore();
    // Soil band at bottom (earth + stones)
    final Rect soil = Rect.fromLTWH(0, playRect.bottom, size.x, size.y - playRect.bottom);
    if (soil.height > 2) {
  if (!_debugAnthillOnly) {
        // Base gradient soil
        final Color topSoil = isNight ? const Color(0xFF3E2A25) : const Color(0xFF4E342E);
        final Color botSoil = isNight ? const Color(0xFF2A1C18) : const Color(0xFF3E2723);
        final Paint soilPaint = Paint()
          ..shader = ui.Gradient.linear(
            soil.topLeft,
            soil.bottomLeft,
            [topSoil, botSoil],
            const [0.0, 1.0],
          );
        canvas.drawRect(soil, soilPaint);
        // Add subtle, slightly wavy strata lines for organic feel
        final Paint strata = Paint()
          ..color = (isNight ? const Color(0xFF4A352E) : const Color(0xFF5D4037)).withValues(alpha: isNight ? 0.10 : 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        for (double y = soil.top + 6; y < soil.bottom; y += 10) {
          final Path wave = Path();
          // horizontal wave with gentle amplitude and phase drift across the width
          double phase = ((y - soil.top) * 0.12);
          const double amp = 1.8; // px
          const double freq = 2 * pi / 120.0; // cycles per 120px
          const double step = 16.0;
          wave.moveTo(soil.left, y);
          for (double x = soil.left + step; x <= soil.right; x += step) {
            final double yp = y + sin((x * freq) + phase) * amp;
            wave.lineTo(x, yp);
          }
          canvas.drawPath(wave, strata);
        }
        // Soil grain: tiny light and dark specks precomputed, to enrich texture
        if (_soilGrainsLight.isNotEmpty || _soilGrainsDark.isNotEmpty) {
          final double a = isNight ? 0.10 : 0.18;
          final Paint grainLight = Paint()..color = const Color(0xFF8D6E63).withValues(alpha: a);
          final Paint grainDark = Paint()..color = const Color(0xFF3E2723).withValues(alpha: a * 0.9);
          for (final o in _soilGrainsLight) {
            if (!soil.contains(o)) continue;
            canvas.drawRect(Rect.fromCenter(center: o, width: 1.5, height: 1.5), grainLight);
          }
          for (final o in _soilGrainsDark) {
            if (!soil.contains(o)) continue;
            canvas.drawRect(Rect.fromCenter(center: o, width: 1.5, height: 1.5), grainDark);
          }
        }
        // Draw rocks with simple shading
        for (final r in _rocks) {
          final Offset p = r.pos;
          if (!soil.contains(p)) continue;
          final double rx = r.r * r.ex;
          final double ry = r.r;
          // base rock: use precomputed palette color (no flicker)
          final Paint rp = Paint()..color = r.color;
          canvas.drawOval(Rect.fromCenter(center: p, width: rx * 2, height: ry * 2), rp);
          // light side highlight based on sun direction
          final Offset n = Offset(-lightDir.dx, -lightDir.dy);
          final Offset hp = p + n * (min(rx, ry) * 0.25);
          final Paint hi = Paint()..color = Colors.white.withValues(alpha: isNight ? 0.10 : 0.16);
          canvas.drawOval(Rect.fromCenter(center: hp, width: rx * 0.9, height: ry * 0.9), hi);
          // bottom shadow
          final Paint sh = Paint()..color = Colors.black.withValues(alpha: isNight ? 0.32 : 0.25);
          canvas.drawOval(Rect.fromCenter(center: p + Offset(0, ry * 0.3), width: rx * 1.2, height: ry * 0.5), sh);
        }
        // Contact shadow under grass edge
        final Rect contact = Rect.fromLTWH(playRect.left, playRect.bottom - 1, playRect.width, min(18.0, soil.height));
        final Paint contactPaint = Paint()
          ..shader = ui.Gradient.linear(
            contact.topLeft,
            contact.bottomLeft,
            [Colors.black.withValues(alpha: 0.35), Colors.transparent],
            const [0.0, 1.0],
          );
        canvas.drawRect(contact, contactPaint);
      }
  // Anthill: mouth + main shaft + branch tunnels + chambers
  if (_showAnthill) {
  final double mouthW = _anthillWidth;
  final double shaftW = max(26.0, mouthW * 0.55);
  final double tunW = max(20.0, mouthW * 0.45);
      final Paint dig = Paint()
        ..color = const Color(0xFF120E0C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shaftW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final Paint digBranch = Paint()
        ..color = const Color(0xFF1A1412)
        ..style = PaintingStyle.stroke
        ..strokeWidth = tunW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      // Main shaft from mouth to deep center (gentle S-curve)
      final Path shaft = Path()
        ..moveTo(_anthillMouth.dx, soil.top + 2)
        ..cubicTo(
          _anthillMouth.dx - mouthW * 0.06, soil.top + soil.height * 0.22,
          _anthillMouth.dx + mouthW * 0.04, soil.top + soil.height * 0.52,
          _anthillMouth.dx - mouthW * 0.10, soil.top + soil.height * 0.84,
        );
      canvas.drawPath(shaft, dig);
      // Branch nodes along the shaft
      final List<Offset> nodes = [
        Offset(_anthillMouth.dx - mouthW * 0.02, soil.top + soil.height * 0.22),
        Offset(_anthillMouth.dx + mouthW * 0.00, soil.top + soil.height * 0.40),
        Offset(_anthillMouth.dx - mouthW * 0.06, soil.top + soil.height * 0.58),
        Offset(_anthillMouth.dx - mouthW * 0.10, soil.top + soil.height * 0.78),
      ];
      // Branches to chambers from nearest node
      for (final ch in _anthillChambers) {
        final Offset node = nodes.reduce((a, b) =>
          ((a - ch.c).distance <= (b - ch.c).distance) ? a : b);
        final Path p = Path()
          ..moveTo(node.dx, node.dy)
          ..cubicTo(
            (node.dx * 2 + ch.c.dx) / 3,
            (node.dy + ch.c.dy) / 2,
            (node.dx + ch.c.dx * 2) / 3,
            (node.dy * 0.6 + ch.c.dy * 0.4),
            ch.c.dx,
            ch.c.dy,
          );
        canvas.drawPath(p, digBranch);
      }
      // Chambers: light fill with border
      final Paint chamberFill = Paint()..color = const Color(0xFFD7C1A7);
      final Paint chamberRim = Paint()
        ..color = const Color(0xFF5D4037)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      for (final ch in _anthillChambers) {
        final Rect ell = Rect.fromCenter(center: ch.c, width: ch.rx * 2, height: ch.ry * 2);
        canvas.drawOval(ell, chamberFill);
        canvas.drawOval(ell, chamberRim);
      }
      // Mouth opening cap and rim
      final Paint rim = Paint()..color = const Color(0xFF6D4C41).withValues(alpha: 0.7);
      canvas.drawLine(Offset(_anthillMouth.dx - mouthW * 0.5, soil.top), Offset(_anthillMouth.dx + mouthW * 0.5, soil.top), rim);
      final Path mound = Path()
        ..moveTo(_anthillMouth.dx - mouthW * 0.95, soil.top)
        ..quadraticBezierTo(_anthillMouth.dx, soil.top - 16, _anthillMouth.dx + mouthW * 0.95, soil.top)
        ..close();
      final Paint moundPaint = Paint()..color = (isNight ? const Color(0xFF3E2A25) : const Color(0xFF4E342E)).withValues(alpha: 0.9);
      canvas.drawPath(mound, moundPaint);
  }
    }

    // Draw sun disc if above horizon (intensity > 0)
    if (_sunIntensity > 0.01) {
      final double sunR = 14 + 6 * lightIntensity;
      final Offset sp = _sunPos;
      // Halo glow
      final Paint halo = Paint()
        ..shader = ui.Gradient.radial(
          sp,
          sunR * 3.0,
            [
              const Color(0xFFFFF59D).withValues(alpha: 0.35 * lightIntensity),
              Colors.transparent,
            ],
          [0.0, 1.0],
        );
      canvas.drawCircle(sp, sunR * 3.0, halo);
      // Sun body
      final Paint sunPaint = Paint()
        ..shader = ui.Gradient.radial(
          sp,
          sunR,
          const [Color(0xFFFFF176), Color(0xFFFFEE58), Color(0xFFFFC107)],
          const [0.0, 0.6, 1.0],
        );
      canvas.drawCircle(sp, sunR, sunPaint);
    }
    // Draw moon during night
    if (_moonIntensity > 0.01) {
      final double moonR = 12 + 5 * (1.0 - lightIntensity); // a bit larger
      final Offset mp = _moonPos;
      // Moon halo
      final Paint halo = Paint()
        ..shader = ui.Gradient.radial(
          mp,
          moonR * 2.4,
          [
            const Color(0xFFB3E5FC).withValues(alpha: 0.28 * _moonIntensity),
            Colors.transparent,
          ],
          [0.0, 1.0],
        );
      canvas.drawCircle(mp, moonR * 2.4, halo);
      // Full moon base
      final Paint moonBase = Paint()..color = const Color(0xFFE0E6EA);
      // subtle radial shading on the moon disc
      final Paint moonShade = Paint()
        ..shader = ui.Gradient.radial(
          mp.translate(-moonR * 0.15, -moonR * 0.1),
          moonR * 1.1,
          [const Color(0xFFE9EEF1), const Color(0xFFD1D8DD)],
          [0.0, 1.0],
        );
      canvas.save();
      canvas.drawCircle(mp, moonR, moonBase);
      canvas.drawCircle(mp, moonR, moonShade);
      // Craters: one big + several small, with inner shadow rim
      void crater(Offset c, double r) {
        final Paint craterBase = Paint()..color = const Color(0xFFB9C2C9).withValues(alpha: 0.85);
        final Paint craterInner = Paint()
          ..shader = ui.Gradient.radial(
            c.translate(-r * 0.25, -r * 0.2),
            r,
            [const Color(0xFFAAB4BC), const Color(0xFF8F9AA4)],
            [0.0, 1.0],
          );
        // draw base and inner
        canvas.drawCircle(c, r, craterBase);
        canvas.drawCircle(c, r * 0.78, craterInner);
        // highlight rim on sun-facing side
        final Offset toSun = (Offset(_sunPos.dx, _sunPos.dy) - mp);
        final double ang = atan2(toSun.dy, toSun.dx);
        final Paint rim = Paint()..color = Colors.white.withValues(alpha: 0.18);
  const int steps = 14;
        for (int i = 0; i <= steps; i++) {
          final double t = i / steps;
          final double a0 = ang - pi * 0.2;
          final double a = a0 + t * (pi * 0.4);
          final Offset p0 = c + Offset(cos(a) * (r * 0.95), sin(a) * (r * 0.95));
          canvas.drawCircle(p0, max(0.6, r * 0.06), rim);
        }
      }
      // Big crater slightly lower-right of center
      crater(mp.translate(moonR * 0.18, moonR * 0.12), moonR * 0.38);
      // Small craters
      crater(mp.translate(-moonR * 0.22, -moonR * 0.10), moonR * 0.20);
      crater(mp.translate(-moonR * 0.05, moonR * 0.28), moonR * 0.16);
      crater(mp.translate(moonR * 0.32, -moonR * 0.20), moonR * 0.14);
      crater(mp.translate(moonR * -0.30, moonR * 0.04), moonR * 0.12);
      canvas.restore();
    }
    // Draw grass texture only inside playfield (base + lighting details)
    if (_grassPaint != null) {
      canvas.save();
      canvas.clipRect(playRect);
      // Base tile
      canvas.drawRect(playRect, _grassPaint!);
      // Lighting modulation based on lightDir: highlights in sun direction, shadows opposite
      if (_grassHiPaint != null && _grassLoPaint != null) {
        // Compute alpha from light intensity and warm factor to blend naturally
        final double hiA = (0.10 + 0.12 * lightIntensity + 0.10 * _warmFactor).clamp(0.0, 0.35);
        final double loA = (0.12 + 0.10 * (1.0 - lightIntensity)).clamp(0.0, 0.35);
        // Parallax offsets to give directional feel
        final Offset hiOffset = Offset(-lightDir.dx, -lightDir.dy) * 12.0;
        final Offset loOffset = Offset(lightDir.dx, lightDir.dy) * 10.0;

        // Draw highlights layer
        canvas.save();
        canvas.translate(hiOffset.dx, hiOffset.dy);
        canvas.drawRect(
          playRect.inflate(20),
          (_grassHiPaint!..colorFilter = ui.ColorFilter.mode(Colors.white.withValues(alpha: hiA), BlendMode.modulate)),
        );
        canvas.restore();
        // Draw shadows layer
        canvas.save();
        canvas.translate(loOffset.dx, loOffset.dy);
        canvas.drawRect(
          playRect.inflate(20),
          (_grassLoPaint!..colorFilter = ui.ColorFilter.mode(Colors.black.withValues(alpha: loA), BlendMode.modulate)),
        );
        canvas.restore();
      }
      canvas.restore();
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

    // Overlays "3D-like" sur le playfield: lumière directionnelle + vignette modulées par la lumière
    canvas.save();
    canvas.clipRect(playRect);
    // Bande lumineuse directionnelle
    final Offset start = playRect.center + lightDir * (playRect.shortestSide * 0.8);
    final Offset end = playRect.center - lightDir * (playRect.shortestSide * 0.8);
    // Warm tint color
    final Color warmHi = Color.lerp(Colors.white, const Color(0xFFFFE0B2), _warmFactor * 0.9)!;
    final Color warmLo = Color.lerp(Colors.black, const Color(0xFFFFCC80), _warmFactor * 0.6)!;
    final Paint lightPaint = Paint()
      ..shader = ui.Gradient.linear(
        start,
        end,
        [
          warmHi.withValues(alpha: 0.06 * lightIntensity),
          Colors.transparent,
          warmLo.withValues(alpha: 0.10 * lightIntensity),
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawRect(playRect, lightPaint);
    // Vignette douce
    final Paint vignette = Paint()
      ..shader = ui.Gradient.radial(
        playRect.center,
        playRect.shortestSide * 0.65,
        [
          Colors.transparent,
          warmLo.withValues(alpha: 0.12 * lightIntensity),
        ],
        [0.65, 1.0],
      );
    canvas.drawRect(playRect, vignette);
    // Sun-ray beam: a faint elongated gradient streak from sun direction
    if (lightIntensity > 0.15) {
      canvas.save();
      // Create a long narrow rect centered on playfield and rotate it along lightDir
      final double beamLen = playRect.longestSide * 1.2;
      final double beamWid = playRect.shortestSide * 0.16;
      final Rect beam = Rect.fromCenter(center: playRect.center, width: beamLen, height: beamWid);
      final double ang = atan2(-lightDir.dy, -lightDir.dx); // towards sun
      canvas.translate(playRect.center.dx, playRect.center.dy);
      canvas.rotate(ang);
      canvas.translate(-playRect.center.dx, -playRect.center.dy);
      final Paint beamPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(beam.left, beam.center.dy),
          Offset(beam.right, beam.center.dy),
          [
            Colors.transparent,
            warmHi.withValues(alpha: 0.08 * lightIntensity),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawRect(beam, beamPaint);
      canvas.restore();
    }
    canvas.restore();

    // Serpent en "3D-like": ombres portées + sphères ombrées
    final double r = snakeHeadRadius;
    // Ombre portée sous les segments
    for (int i = _segmentCenters.length - 1; i >= 0; i--) {
      final c = _segmentCenters[i];
      final Rect shadowOval = Rect.fromCenter(
        center: Offset(c.x, c.y + r * 0.45),
        width: r * 1.8,
        height: r * 0.6,
      );
  canvas.drawOval(shadowOval, Paint()..color = Colors.black.withValues(alpha: 0.22 * lightIntensity));
    }
    // Sphères avec dégradé radial
  Color mixColor2(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    for (int i = _segmentCenters.length - 1; i >= 0; i--) {
      final c = _segmentCenters[i];
      final base = hasShield
          ? (i == 0 ? Colors.lightBlue : Colors.cyan)
          : (i == 0 ? Colors.lightGreen : Colors.green);
  final lighter = mixColor2(base, Colors.white, 0.35);
  final darker = mixColor2(base, Colors.black, 0.25);
      final center = Offset(c.x, c.y);
      final lightOffset = Offset(-lightDir.dx * r * 0.6, -lightDir.dy * r * 0.6);
      final shader = ui.Gradient.radial(
        center + lightOffset,
        r,
        [
          Color.lerp(lighter, base, 1 - lightIntensity)!,
          base,
          Color.lerp(darker, base, 1 - lightIntensity)!,
        ],
        [0.0, 0.55, 1.0],
      );
      canvas.drawCircle(center, r, Paint()..shader = shader);
      // Contre-jour: fin liseré côté soleil
      if (lightIntensity > 0.05) {
        final Offset toSun = Offset(-lightDir.dx, -lightDir.dy);
        final double ang = atan2(toSun.dy, toSun.dx);
        final Paint rim = Paint()
          ..color = Color.lerp(Colors.white, const Color(0xFFFFE0B2), _warmFactor)!
              .withValues(alpha: 0.18 * lightIntensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawArc(Rect.fromCircle(center: center, radius: r), ang - 0.45, 0.9, false, rim);
      }
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
      final center = Offset(
        playOrigin.x + food!.x * gridSize + gridSize / 2,
        playOrigin.y + food!.y * gridSize + gridSize / 2,
      );
      final r = gridSize / 2 - 2;
      // Apple skin: red body with a slight highlight, stem and leaf
      final red = hasMultiFood ? const Color(0xFFFF7043) : const Color(0xFFE53935);
      final body = Paint()..color = red;
  final bodyShadow = Paint()..color = Colors.black.withValues(alpha: 0.08 * lightIntensity);
      canvas.drawCircle(center.translate(1.5, 2), r, bodyShadow);
      canvas.drawCircle(center, r, body);
      // highlight
  final highlight = Paint()..color = Colors.white.withValues(alpha: 0.25);
      canvas.drawCircle(center.translate(-r * 0.35, -r * 0.35), r * 0.35, highlight);
      // stem
      final stem = Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center.translate(0, -r * 0.9), center.translate(0, -r * 0.4), stem);
      // leaf
      final leafPaint = Paint()..color = const Color(0xFF66BB6A);
      final leafPath = Path()
        ..moveTo(center.dx + 0, center.dy - r * 0.65)
        ..quadraticBezierTo(center.dx + r * 0.7, center.dy - r * 1.0, center.dx + r * 0.9, center.dy - r * 0.3)
        ..quadraticBezierTo(center.dx + r * 0.4, center.dy - r * 0.2, center.dx + 0, center.dy - r * 0.65)
        ..close();
      canvas.drawPath(leafPath, leafPaint);
    }

    // NOW render components (EnemyComponent etc.) on top of the snake/food
    super.render(canvas);

  // Night overlay (after world and entities)
  if (isNight || nightOpacity > 0) {
      final double a = nightOpacity.clamp(0.0, 1.0);
      if (a > 0) {
  final Paint nightPaint = Paint()..color = const Color(0xFF000814).withValues(alpha: 0.58 * a);
        canvas.save();
        canvas.clipRect(playRect);
        canvas.drawRect(playRect, nightPaint);
        canvas.restore();
      }
    }

    // UI overlay basic: score (small)
    final tp = TextPainter(
  text: TextSpan(text: 'Score: $score  Level: $level  Wave: $wave${bossActive ? "  Boss" : ""}', style: const TextStyle(color: Colors.white, fontSize: 14)),
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
