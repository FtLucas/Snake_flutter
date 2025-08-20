import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

class GardenMenuGame extends FlameGame {
  final _rng = Random(1337);
  double _groundTop = 0; // y du haut de l’herbe
  double _t = 0.0; // 0..1 cycle jour/nuit
  double cycleSeconds = 30.0;
  double _soilH = 0; // hauteur de la bande de terre au bas

  late List<Offset> _flowers;
  late List<Color> _flowerColors;
  late Offset _treeBase; // pied de tronc (sur l’herbe)
  late double _treeHeight;
  late List<Offset> _apples;
  // Canopy data for effects spawning
  late Offset _canopyCenter;
  late double _canopyR;
  // Menu critters and sky
  final List<_MStar> _stars = [];
  final List<_MAnt> _ants = [];
  final List<_SoilItem> _soilItems = [];
  final List<_FallingApple> _falling = [];
  final List<_Firefly> _flies = [];
  final List<_Cloud> _clouds = [];
  final List<_Tuft> _tufts = [];
  // Horloge globale
  double _time = 0.0;

  // Fourmilière (entrée dessinée sur la lèvre herbe/terre)
  late Offset _hillPos;
  double _hillR = 18.0;

  // Serpent façon in-game: tête/direction/vitesse + trail et HP
  Offset _mHead = Offset.zero;
  Offset _mDir = const Offset(1, 0);
  double _mSpeed = 90.0; // px/s
  final List<Offset> _trail = <Offset>[]; // head-first order
  double _trailSpacing = 12.0; // distance entre points de trail
  // Segments réels du corps (suivent la tête)
  final List<Offset> _segments = <Offset>[]; // [0]=tête
  int _snakeHp = 0; // HP ~ longueur visible (segments)
  int _snakeMaxHp = 0;
  bool _snakeAlive = true;
  double _respawnT = 0.0;
  double _dmgCooldown = 0.0; // petite invulnérabilité pour ne pas fondre instantanément
  double _spawnTimer = 0.0; // Timer pour le spawn irrégulier des fourmis

  @override
  Future<void> onLoad() async {
    _rebuildDecor();
    // Ajouter plus de fourmis dès le lancement
    for (int i = 0; i < 20; i++) {
      final double angle = _rng.nextDouble() * pi * 2;
      final double distance = _hillR * (1.5 + _rng.nextDouble() * 5.0);
      final Offset spawnPosition = _hillPos + Offset(cos(angle) * distance, sin(angle) * distance);
      _ants.add(_MAnt(
        p: spawnPosition,
        dir: _rng.nextDouble() * 6.283,
        speed: 20 + _rng.nextDouble() * 34,
      ));
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _rebuildDecor();
  }

  void _rebuildDecor() {
  _groundTop = size.y * 0.60; // herbe: ~40% bas
  _soilH = (size.y * 0.12).clamp(28, 64); // bande de terre en bas (plus haute)

    final int n = (size.x / 28).clamp(10, 45).toInt();
    _flowers = List.generate(n, (i) {
      final x = (i + 0.5 + _rng.nextDouble() * 0.5) * (size.x / n);
  // Les fleurs ne poussent que dans l'herbe, pas dans la terre
  final maxGrassY = (size.y - _soilH - 22).clamp(_groundTop + 10, size.y - _soilH - 22);
  final y = _groundTop + 8 + _rng.nextDouble() * (maxGrassY - (_groundTop + 8));
      return Offset(x, y);
    });
    const palette = [
      Color(0xFFF06292), Color(0xFFFF8A65), Color(0xFFFFD54F),
      Color(0xFF81C784), Color(0xFF4FC3F7), Color(0xFFBA68C8),
    ];
  _flowerColors = List.generate(_flowers.length, (i) => palette[i % palette.length].withValues(alpha: 0.9));

    _treeBase = Offset(size.x * 0.18, _groundTop);
    _treeHeight = size.y * 0.42;

  // Canopée un peu moins volumineuse et cohérente avec le rendu
  final center = Offset(_treeBase.dx, _groundTop - _treeHeight * 0.66);
  final r = _treeHeight * 0.35; // réduit de 0.38 -> 0.35
  _canopyCenter = center;
  _canopyR = r;
  // Pommes réparties de façon uniforme et à l'intérieur de la canopée
  final int appleCount = (12 + (size.x / 200).clamp(0, 10)).toInt();
    const double golden = 2.399963229728653; // ~phi angle
    _apples = [
      for (int i = 0; i < appleCount; i++)
        () {
          final a = i * golden + _rng.nextDouble() * 0.2;
          // 75% en couronne proche du bord pour couvrir les feuilles externes
          final outer = _rng.nextDouble() < 0.75;
          final rr = outer
              ? r * (0.62 + 0.28 * _rng.nextDouble()) // 0.62..0.90 r (périphérie)
              : r * (0.28 + 0.30 * _rng.nextDouble()); // 0.28..0.58 r (intérieur)
          final p = center + Offset(cos(a) * rr, sin(a) * rr * 0.9);
          return p;
        }(),
    ];

    // Stars (twinkling at night) with stable positions
    _stars
      ..clear()
      ..addAll(List.generate((size.x * 0.3).clamp(40, 140).toInt(), (i) {
        return _MStar(
          pos: Offset(_rng.nextDouble() * size.x, _rng.nextDouble() * (_groundTop * 0.9)),
          phase: _rng.nextDouble() * 6.283,
          speed: 1.0 + _rng.nextDouble() * 2.0,
          radius: 0.8 + _rng.nextDouble() * 1.6,
        );
      }));

      // Fourmilière: positionnée sur la lèvre herbe/terre (avant le spawn des fourmis)
      _hillPos = Offset(size.x * 0.74, size.y - _soilH);
      _hillR = (size.x * 0.03).clamp(14.0, 24.0);

    // Ants: plus nombreuses près de la fourmilière, mais partout dans l'herbe
    _ants
      ..clear()
      ..addAll(List.generate((size.x / 60).clamp(10, 26).toInt(), (i) {
        final bool nearHill = i < ((size.x / 60).clamp(10, 26).toInt() * 0.45).round();
        Offset p;
        if (nearHill) {
          // autour de l'entrée (ellipse aplatie), puis clamp dans l'herbe
          final double a = _rng.nextDouble() * pi * 2;
          final double rr = (_hillR * 3.0) + _rng.nextDouble() * (_hillR * 5.0);
          p = _hillPos + Offset(cos(a) * rr, sin(a) * rr * 0.6);
          final double minY = _groundTop + 6;
          final double maxY = size.y - _soilH - 12;
          p = Offset(p.dx.clamp(6, size.x - 6), p.dy.clamp(minY, maxY));
        } else {
          p = Offset(
            _rng.nextDouble() * size.x,
            _groundTop + 10 + _rng.nextDouble() * ((size.y - _soilH) - _groundTop - 26),
          );
        }
        return _MAnt(
          p: p,
          dir: _rng.nextDouble() * 6.283,
          speed: 20 + _rng.nextDouble() * 34,
        );
      }));

  // Snake: initialized in-game style in this method below

    // Soil decor items (stones and fossils), stable via size-derived seed
    _soilItems.clear();
    final seed = (size.x.floor() * 73856093) ^ (size.y.floor() * 19349663);
    final rnd = Random(seed);
    final double soilTop = size.y - _soilH;
    final double soilBottom = size.y;
    final int stones = (size.x / 30).clamp(8, 44).toInt();
    for (int i = 0; i < stones; i++) {
      final x = rnd.nextDouble() * size.x;
      final r = 2.4 + rnd.nextDouble() * 5.6;
      final double margin = r + 1.0; // garder la pierre dans la terre
      final y = rnd.nextDouble() * (soilBottom - soilTop - margin * 2) + soilTop + margin;
      final g = (190 + rnd.nextInt(50)).clamp(170, 235);
  final col = Color.fromARGB(255, g, g, g).withValues(alpha: 0.95);
      _soilItems.add(_SoilItem.stone(Offset(x, y), r, col, ex: 0.7 + rnd.nextDouble() * 0.7));
    }
    // Un peu plus de fossiles, placés avec marges en fonction de leur taille
    final int fossils = (size.x / 200).clamp(2, 5).toInt();
    for (int i = 0; i < fossils; i++) {
      final x = rnd.nextDouble() * size.x;
      final kind = rnd.nextBool() ? SoilKind.fossilShell : SoilKind.fossilFish;
      final double s = 0.8 + rnd.nextDouble() * 1.4;
      final double margin = (kind == SoilKind.fossilShell ? 7.0 : 4.0) * s + 2.0; // marge visuelle
      final y = rnd.nextDouble() * (soilBottom - soilTop - margin * 2) + soilTop + margin;
      _soilItems.add(_SoilItem.fossil(Offset(x, y), kind, s, rnd.nextDouble() * pi * 2));
    }

    // Touffes d'herbe (dans la zone verte, au-dessus de la terre)
    _tufts
      ..clear()
      ..addAll(List.generate((size.x / 36).clamp(10, 36).toInt(), (i) {
        final x = _rng.nextDouble() * size.x;
        final double minY = _groundTop + 6;
        final double maxY = (size.y - _soilH - 18).clamp(minY + 4, size.y - _soilH - 18);
        final y = _rng.nextDouble() * (maxY - minY) + minY;
        final scale = 0.9 + _rng.nextDouble() * 1.8; // plus hautes
        return _Tuft(Offset(x, y), scale);
      }));

    // Effects: reset falling apples and fireflies
    _falling.clear();
    _flies
      ..clear()
      ..addAll(List.generate((size.x / 40).clamp(14, 36).toInt(), (i) {
        // spawn around canopy, some closer to ground near trunk
        final ang = _rng.nextDouble() * pi * 2;
        final rr = _canopyR * (0.3 + _rng.nextDouble() * 0.9);
        final base = _canopyCenter + Offset(cos(ang) * rr, sin(ang) * rr * 0.7);
  final f = _Firefly(
          p: base + Offset(_rng.nextDouble() * 30 - 15, _rng.nextDouble() * 20 - 10),
          phase: _rng.nextDouble() * pi * 2,
          speed: 0.6 + _rng.nextDouble() * 0.8,
        );
  // paramètres de déplacement erratique (2D wander)
  f.localSpeed = 1.0 + _rng.nextDouble() * 1.6; // phase interne pour scintillement
  f.maxSpd = 24.0 + _rng.nextDouble() * 36.0;   // vitesse max px/s
  f.jitter = 30.0 + _rng.nextDouble() * 45.0;   // accélération aléatoire px/s^2
  f.damping = 1.2 + _rng.nextDouble() * 1.2;    // freinage
  f.v = Offset(_rng.nextDouble() * 10 - 5, _rng.nextDouble() * 10 - 5);
  // cible initiale (feuille proche)
  f.target = _sampleLeafPoint();
  f.targetT = 0.0;
  f.targetDur = 2.0 + _rng.nextDouble() * 2.0;
        return f;
      }));

    // Nuages doux (jour), positions stables mais dépendantes de la taille
  _clouds
      ..clear()
      ..addAll(List.generate((size.x / 260).clamp(2, 5).toInt(), (i) {
        final x = _rng.nextDouble() * size.x;
        final y = _rng.nextDouble() * (_groundTop * 0.7) + 10; // bien dans le ciel
        final r = 26.0 + _rng.nextDouble() * 22.0; // taille de base
        final speed = 6.0 + _rng.nextDouble() * 8.0;
        return _Cloud(pos: Offset(x, y), r: r, speed: speed);
      }));

    // Serpent façon in-game: spawn aléatoire dans l'herbe
    _trailSpacing = 12.0;
    _mSpeed = 90.0;
    _snakeMaxHp = (size.x / 20).clamp(12, 26).toInt();
    _snakeHp = _snakeMaxHp;
    _snakeAlive = true;
    _respawnT = 0.0;
    // position de départ dans la zone herbe
    final double minX = 10, maxX = size.x - 10;
    final double minY = _groundTop + 10, maxY = size.y - _soilH - 14;
    _mHead = Offset(
      _rng.nextDouble() * (maxX - minX) + minX,
      _rng.nextDouble() * (maxY - minY) + minY,
    );
    // direction aléatoire normalisée
    final double ang = _rng.nextDouble() * pi * 2;
    _mDir = Offset(cos(ang), sin(ang));
    // initialise les segments du corps
    _segments
      ..clear()
      ..addAll(List.generate(_snakeHp, (i) => _mHead - _mDir * (_trailSpacing * i)));
    _trail.clear(); // on n'utilise plus la trail éparse pour le rendu
  }

  // Réduction de la zone de vision du serpent
  bool _isAntInVision(Offset antPosition) {
    const double visionRadius = 100.0; // Réduction du rayon de vision
    return (antPosition - _mHead).distance <= visionRadius;
  }

  // Spawn irrégulier des fourmis depuis la fourmilière
  void _spawnAntsIrregularly(double deltaTime) {
    _spawnTimer -= deltaTime;
    if (_spawnTimer <= 0.0) {
      _spawnTimer = 1.0 + _rng.nextDouble() * 2.0; // Intervalle réduit entre 1 et 3 secondes
      final double angle = _rng.nextDouble() * pi * 2;
      final double distance = _hillR * (1.5 + _rng.nextDouble() * 2.0);
      final Offset spawnPosition = _hillPos + Offset(cos(angle) * distance, sin(angle) * distance);
      _ants.add(_MAnt(
        p: spawnPosition,
        dir: _rng.nextDouble() * 6.283,
        speed: 20 + _rng.nextDouble() * 34,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Mise à jour de la vitesse du serpent
    if (_snakeAlive) {
        // Removed _reduceSnakeSpeed(dt) as it is undefined
    }

    _spawnAntsIrregularly(dt); // Gestion du spawn irrégulier des fourmis

    // Filtrer les fourmis visibles
    _ants.removeWhere((ant) => !_isAntInVision(ant.p));

  _t = (_t + dt / cycleSeconds) % 1.0;
    _time += dt;
    // ants wander/chase
    for (final a in _ants) {
      // comportement: poursuite du serpent si à portée, sinon errance
  const double chaseR = 90.0;
      final Offset toHead = _mHead - a.p;
      final double dh = toHead.distance;
      if (_snakeAlive && dh < chaseR) {
        final double base = atan2(toHead.dy, toHead.dx);
        a.dir = base + (_rng.nextDouble() - 0.5) * 0.2; // léger bruit
      } else {
        a.dir += (_rng.nextDouble() - 0.5) * 0.7 * dt; // jitter
      }
      final double spd = _snakeAlive && dh < chaseR ? (a.speed * 1.15) : a.speed;
      final v = Offset(cos(a.dir), sin(a.dir)) * spd * dt;
      a.p += v;
      if (a.p.dx < 6) { a.p = Offset(6, a.p.dy); a.dir = pi - a.dir; }
      if (a.p.dx > size.x - 6) { a.p = Offset(size.x - 6, a.p.dy); a.dir = pi - a.dir; }
      if (a.p.dy < _groundTop + 6) { a.p = Offset(a.p.dx, _groundTop + 6); a.dir = -a.dir; }
  if (a.p.dy > size.y - _soilH - 10) { a.p = Offset(a.p.dx, size.y - _soilH - 10); a.dir = -a.dir; }
    }
    // Serpent style in-game: déplacement, collisions, HP/respawn
    if (_dmgCooldown > 0) _dmgCooldown -= dt;
    if (_snakeAlive) {
      // steering: vise une fourmi proche sinon errance + évitement bords
      final double minX = 8, maxX = size.x - 8;
      final double minY = _groundTop + 8, maxY = size.y - _soilH - 12;
      Offset avoid = Offset.zero;
      if (_mHead.dx < minX + 18) avoid += const Offset(1, 0);
      if (_mHead.dx > maxX - 18) avoid += const Offset(-1, 0);
      if (_mHead.dy < minY + 18) avoid += const Offset(0, 1);
      if (_mHead.dy > maxY - 18) avoid += const Offset(0, -1);
      // cibler l'ant la plus proche dans un rayon
      const double seekR = 120.0;
      Offset dir = _mDir;
      double bestD = seekR;
      for (final a in _ants) {
        final double d = (a.p - _mHead).distance;
        if (d < bestD) {
          bestD = d;
          dir = (a.p - _mHead);
        }
      }
      if (bestD == seekR) {
        // pas de cible -> errance légère
        double ang = atan2(_mDir.dy, _mDir.dx);
        ang += (_rng.nextDouble() - 0.5) * 1.2 * dt; // zigzag
        dir = Offset(cos(ang), sin(ang));
      }
      if (avoid != Offset.zero) {
        final double d = avoid.distance;
        avoid = avoid / d;
        dir = (dir * 0.9 + avoid * 0.6);
        final double m = dir.distance;
        if (m > 0.0001) dir = dir / m;
      }
      _mDir = dir;
      _mHead += _mDir * _mSpeed * dt;
      // clamp safety
      _mHead = Offset(_mHead.dx.clamp(minX, maxX), _mHead.dy.clamp(minY, maxY));

      // segments du corps: chaque segment suit le précédent à distance fixe
      if (_segments.isEmpty || _segments.length != _snakeHp) {
        _segments
          ..clear()
          ..addAll(List.generate(max(0, _snakeHp), (i) => _mHead - _mDir * (_trailSpacing * i)));
      } else {
        _segments[0] = _mHead;
        for (int i = 1; i < _segments.length; i++) {
          final Offset prev = _segments[i - 1];
          final Offset cur = _segments[i];
          final Offset to = prev - cur;
          final double d = to.distance;
          if (d > 0.001) {
            final Offset dirS = to / d;
            _segments[i] = prev - dirS * _trailSpacing;
          }
        }
      }

      // interactions: manger les fourmis touchées (disparaissent)
      for (int i = _ants.length - 1; i >= 0; i--) {
        final a = _ants[i];
        if ((a.p - _mHead).distance < 10.0) {
          _ants.removeAt(i);
          _snakeHp = min(_snakeMaxHp, _snakeHp + 1); // gagne 1 PV en mangeant
        }
      }
      // fourmis qui "attaquent" si trop proches du corps (n'importe quel segment)
      bool attacked = false;
      if (_dmgCooldown <= 0) {
        for (final a in _ants) {
          // test sur quelques segments (ou tous si peu)
          final int step = _segments.length > 16 ? 2 : 1;
          for (int si = 0; si < _segments.length; si += step) {
            if ((a.p - _segments[si]).distance < 11.0) {
              attacked = true;
              break;
            }
          }
          if (attacked) break;
        }
      }
      if (attacked) {
        _snakeHp = max(0, _snakeHp - 1);
        _dmgCooldown = 0.6;
        if (_snakeHp == 0) {
          _snakeAlive = false;
          _respawnT = 3.0;
          _segments.clear();
        }
      }
    } else {
      _respawnT -= dt;
      if (_respawnT <= 0) {
        // respawn
        _snakeHp = _snakeMaxHp;
        _snakeAlive = true;
        final double minX = 10, maxX = size.x - 10;
        final double minY = _groundTop + 10, maxY = size.y - _soilH - 14;
        _mHead = Offset(
          _rng.nextDouble() * (maxX - minX) + minX,
          _rng.nextDouble() * (maxY - minY) + minY,
        );
        final double ang = _rng.nextDouble() * pi * 2;
        _mDir = Offset(cos(ang), sin(ang));
        _segments
          ..clear()
          ..addAll(List.generate(_snakeHp, (i) => _mHead - _mDir * (_trailSpacing * i)));
      }
    }

    // falling apples update + occasional spawn
    if (_falling.length < 6 && _rng.nextDouble() < 0.25 * dt) {
      // spawn near top of canopy
      final ang = _rng.nextDouble() * pi * 2;
      final rr = _canopyR * (0.2 + _rng.nextDouble() * 0.6);
      final start = _canopyCenter + Offset(cos(ang) * rr, sin(ang) * rr * 0.6);
      final vx = (_rng.nextDouble() * 40 - 20);
      _falling.add(_FallingApple(p: start, v: Offset(vx, -10), spin: _rng.nextDouble() * 6.283));
    }
    final double groundY = _groundTop - 3; // rest just on grass
    for (final fa in _falling) {
      if (fa.rest) continue;
      fa.v = fa.v + Offset(0, 220 * dt); // gravity
      fa.p = fa.p + fa.v * dt;
      fa.spin += dt * 2.0;
      if (fa.p.dy >= groundY) {
        fa.p = Offset(fa.p.dx, groundY);
        if (fa.v.dy > 60) {
          fa.v = Offset(fa.v.dx * 0.6, -fa.v.dy * 0.25); // small bounce
        } else {
          fa.v = Offset.zero;
          fa.rest = true;
        }
      }
    }

    // fireflies: déplacement erratique 2D autour de l'arbre (toutes directions)
    for (final f in _flies) {
      // phase pour bruit pseudo-aléatoire et scintillement
      f.phase += dt * f.localSpeed;

      // attraction douce vers une feuille (cible renouvelée périodiquement)
      f.targetT += dt;
      if (f.targetT >= f.targetDur || (f.p - f.target).distance < 10) {
        f.target = _sampleLeafPoint();
        f.targetT = 0.0;
        f.targetDur = 2.0 + _rng.nextDouble() * 2.0;
      }
      // bruit 2D: combinaisons sinusoïdales indépendantes pour X/Y
      final double t = _time;
      final double nx = (sin(f.seed * 1.3 + t * 1.7) + sin(f.seed * 2.1 + t * 2.3 + 1.2)) * 0.5;
      final double ny = (cos(f.seed * 1.5 + t * 1.1) + sin(f.seed * 2.7 + t * 2.0 + 0.7)) * 0.5;
      final Offset noiseA = Offset(nx, ny) * f.jitter; // px/s^2

      // force vers la cible
      Offset toT = f.target - f.p;
      final double d = toT.distance;
      if (d > 0.001) {
        toT = toT / d * 12.0;
      } else {
        toT = Offset.zero; // ~px/s^2
      }

      // freinage
      final Offset damp = f.v * -f.damping;

      // accélération finale
      final Offset acc = noiseA + toT + damp;
      f.v += acc * dt;
      // limiter la vitesse
      final double sp = f.v.distance;
      if (sp > f.maxSpd) {
        f.v = f.v / sp * f.maxSpd;
      }

      // tentative de nouvelle position
      Offset p = f.p + f.v * dt;

  // contrainte: rester proche de l'arbre (ellipse plus large et plus haute)
  final double rx = _canopyR * 2.6;
  final double ry = _canopyR * 2.1;
      Offset rel = p - _canopyCenter;
      double norm = (rel.dx * rel.dx) / (rx * rx) + (rel.dy * rel.dy) / (ry * ry);
      if (norm > 1.0) {
        final double k = 1 / sqrt(norm);
        // repositionner sur le bord et refléter une partie de la vitesse
        final Offset newPos = _canopyCenter + rel * k;
        final Offset nrm = rel == Offset.zero ? const Offset(0, -1) : rel / rel.distance; // normal
        final double vn = f.v.dx * nrm.dx + f.v.dy * nrm.dy;
        f.v = f.v - nrm * (vn * 1.4);
        p = newPos;
      }

      // éviter la terre
  final double minY = max(0, _groundTop - _canopyR * 1.4); // zone plus haute
      final double maxY = size.y - _soilH - 12;
      if (p.dy < minY) {
        p = Offset(p.dx, minY);
        f.v = Offset(f.v.dx, f.v.dy.abs() * 0.6);
      }
      if (p.dy > maxY) {
        p = Offset(p.dx, maxY);
        f.v = Offset(f.v.dx, -f.v.dy.abs() * 0.6);
      }
      if (p.dx < 4) {
        p = const Offset(4, 0);
        p = Offset(p.dx, f.p.dy);
        f.v = Offset(f.v.dx.abs() * 0.6, f.v.dy);
      }
      if (p.dx > size.x - 4) {
        p = Offset(size.x - 4, f.p.dy);
        f.v = Offset(-f.v.dx.abs() * 0.6, f.v.dy);
      }

      f.p = p;
    }

    // déplacement lent des nuages le jour (toujours mis à jour, rendu faible la nuit)
    for (final cl in _clouds) {
      cl.pos = cl.pos.translate(cl.speed * dt, 0);
      if (cl.pos.dx - cl.r * 2 > size.x) {
        cl.pos = Offset(-cl.r * 2, cl.pos.dy);
      }
    }
  }

  // échantillonner un point plausible sur le volume des feuilles (canopée)
  Offset _sampleLeafPoint() {
    final double a = _rng.nextDouble() * pi * 2;
    // biais radial pour privilégier la périphérie
    final double rr = _canopyR * sqrt(0.35 + 0.65 * _rng.nextDouble());
    final Offset p = _canopyCenter + Offset(cos(a) * rr, sin(a) * rr * 0.85);
    return p;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

  // full rect not used; drawing is split between sky and grass bands.

  // ratio jour/nuit: lissé (sinusoïdal)
  final double theta = _t * 2 * pi; // 0..2π
  final double dayAmt = 0.5 + 0.5 * sin(theta); // 0..1..0
  final double nightAmt = 1.0 - dayAmt;

    // ciel
    final Rect sky = Rect.fromLTWH(0, 0, size.x, _groundTop);
    final Paint skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        sky.bottomLeft, sky.topLeft,
        [
          Color.lerp(const Color(0xFF0D47A1), const Color(0xFF061126), nightAmt)!,
          Color.lerp(const Color(0xFF90CAF9), const Color(0xFF0B1530), nightAmt)!,
        ],
        const [0.0, 1.0],
      );
    canvas.drawRect(sky, skyPaint);

  // Twinkling stars crossfaded by nightAmt (no abrupt pop)
    for (final s in _stars) {
      final a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * s.speed + s.phase));
  final Paint p = Paint()..color = Colors.white.withValues(alpha: a * (nightAmt * nightAmt));
      canvas.drawCircle(s.pos, s.radius, p);
    }

    // soleil/lune en orbite elliptique
  const double sunR = 16.0;
    final Offset c = Offset(size.x * 0.5, _groundTop * 0.55);
    final double rx = size.x * 0.35;
    final double ry = _groundTop * 0.35;
    final Offset sunPos = c + Offset(cos(theta) * rx, -sin(theta) * ry);
  final Offset sp = sunPos;
  final Paint halo = Paint()
      ..shader = ui.Gradient.radial(sp, sunR * 3, [const Color(0xFFFFF59D).withValues(alpha: 0.35 * dayAmt), Colors.transparent], const [0, 1]);
    canvas.drawCircle(sp, sunR * 3, halo);
  final Paint body = Paint()
      ..shader = ui.Gradient.radial(sp, sunR, const [Color(0xFFFFF176), Color(0xFFFFC107)], const [0, 1])
  ..colorFilter = ui.ColorFilter.mode(Colors.white.withValues(alpha: dayAmt.clamp(0.0, 1.0)), BlendMode.modulate);
    canvas.drawCircle(sp, sunR, body);

    // lune en opposition de phase
  const double moonR = 13.0;
    final Offset mp = c + Offset(cos(theta + pi) * rx, -sin(theta + pi) * ry);
  final Paint mHalo = Paint()
      ..shader = ui.Gradient.radial(mp, moonR * 2.4, [const Color(0xFFB3E5FC).withValues(alpha: 0.28 * nightAmt), Colors.transparent], const [0, 1]);
    canvas.drawCircle(mp, moonR * 2.4, mHalo);
  canvas.drawCircle(mp, moonR, Paint()..color = const Color(0xFFE0E6EA).withValues(alpha: nightAmt));

    // Nuages (rendus principalement le jour, légère présence au crépuscule)
    if (dayAmt > 0) {
      for (final cl in _clouds) {
  final double a = (0.35 + 0.5 * dayAmt).clamp(0.0, 0.85);
  final Paint cp = Paint()..color = const Color(0xFFF5F7FA).withValues(alpha: a);
        // forme blobby (plusieurs cercles)
        canvas.drawCircle(cl.pos.translate(-cl.r * 0.6, 0), cl.r * 0.8, cp);
        canvas.drawCircle(cl.pos, cl.r, cp);
        canvas.drawCircle(cl.pos.translate(cl.r * 0.6, 0), cl.r * 0.75, cp);
        // ombre douce en bas
        final Rect shade = Rect.fromCenter(center: cl.pos.translate(0, cl.r * 0.25), width: cl.r * 2.0, height: cl.r * 0.7);
        final Paint sh = Paint()
          ..shader = ui.Gradient.radial(shade.center, shade.width * 0.5, [Colors.black.withValues(alpha: 0.08 * dayAmt), Colors.transparent], const [0, 1]);
        canvas.drawOval(shade, sh);
      }
    }

    // herbe (aucune autre bande en bas)
  final Rect grass = Rect.fromLTWH(0, _groundTop, size.x, size.y - _groundTop);
    final Paint grassPaint = Paint()
      ..shader = ui.Gradient.linear(
        grass.topLeft, grass.bottomLeft,
        [const Color(0xFF2E7D32), const Color(0xFF1B5E20)],
        const [0.0, 1.0],
      );
    canvas.drawRect(grass, grassPaint);
    // bande lumineuse directionnelle sur l'herbe (3D-like)
    final Offset ld = (sp - grass.center).scale(1, 1);
    final double len = ld.distance == 0 ? 1 : ld.distance;
    final Offset dir = Offset(ld.dx / len, ld.dy / len);
    final Offset g0 = grass.center - dir * (size.x * 0.6);
    final Offset g1 = grass.center + dir * (size.x * 0.6);
    final Paint grassLight = Paint()
      ..shader = ui.Gradient.linear(g0, g1, [Colors.transparent, Colors.white.withValues(alpha: 0.10 * dayAmt), Colors.transparent], const [0.0, 0.5, 1.0]);
    canvas.drawRect(grass, grassLight);

  // bande de terre
    final Rect soil = Rect.fromLTWH(0, size.y - _soilH, size.x, _soilH);
    final Paint soilPaint = Paint()
      ..shader = ui.Gradient.linear(
        soil.topLeft, soil.bottomLeft,
        [const Color(0xFF6D4C41), const Color(0xFF4E342E)],
        const [0.0, 1.0],
      );
    canvas.drawRect(soil, soilPaint);
    // clip pour que pierres/fossiles ne débordent jamais dans l'herbe
    canvas.save();
    canvas.clipRect(soil);
    // clip pour que pierres/fossiles ne débordent jamais dans l'herbe
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(soil.left, soil.top + 4, soil.width, soil.height - 4));
    for (final it in _soilItems) {
      it.render(canvas);
    }
    canvas.restore();
    canvas.restore();
    // ombre portée au bord de l'herbe sur la terre (relief)
  const double lipH = 14.0;
    final Rect lip = Rect.fromLTWH(0, soil.top, size.x, lipH);
  final Paint lipPaint = Paint()
      ..shader = ui.Gradient.linear(
        lip.topLeft, lip.bottomLeft,
        [Colors.black.withValues(alpha: 0.22), Colors.transparent],
        const [0.0, 1.0],
      );
  canvas.drawRect(lip, lipPaint);

  // (Les touffes d'herbe seront dessinées en tout premier plan, plus bas)

  // tronc (ancré sur l’herbe) plus détaillé
  final trunkW = _treeHeight * 0.14;
  final trunkRect = Rect.fromLTWH(_treeBase.dx - trunkW / 2, _treeBase.dy - _treeHeight, trunkW, _treeHeight);
  final Paint trunkGrad = Paint()
      ..shader = ui.Gradient.linear(trunkRect.topLeft, trunkRect.bottomLeft, [const Color(0xFF8D6E63), const Color(0xFF6D4C41), const Color(0xFF5D4037)], const [0.0, 0.6, 1.0]);
    canvas.drawRRect(RRect.fromRectAndRadius(trunkRect, const Radius.circular(8)), trunkGrad);
    // racines
  final Paint root = Paint()..color = const Color(0xFF5D4037).withValues(alpha: 0.6);
    canvas.drawOval(Rect.fromCenter(center: Offset(_treeBase.dx, _treeBase.dy + 4), width: trunkW * 1.8, height: 8), root);
    // ombre portée du tronc sur l'herbe (douce et directionnelle)
    final Offset shadowDir = dir * 1.0;
    final Offset shadowCenter = Offset(_treeBase.dx, _groundTop + 6) + Offset(shadowDir.dx * 18, max(0, shadowDir.dy) * 10);
    final Rect trunkShadow = Rect.fromCenter(center: shadowCenter, width: trunkW * 2.8, height: 10);
    final Paint trunkShadowPaint = Paint()
      ..shader = ui.Gradient.radial(trunkShadow.center, trunkShadow.width * 0.5, [Colors.black.withValues(alpha: 0.20 * dayAmt), Colors.transparent], const [0, 1]);
    canvas.drawOval(trunkShadow, trunkShadowPaint);

  // feuillage (multi-nappes) — couvre bien le haut du tronc (utilise les valeurs calculées)
  final canopyCenter = _canopyCenter;
  final canopyR = _canopyR;
    void blob(Offset c, double r, List<Color> colors) {
      final p = Paint()
        ..shader = ui.Gradient.radial(c.translate(-r * 0.2, -r * 0.15), r, colors, const [0.0, 1.0]);
      canvas.drawCircle(c, r, p);
    }
  blob(canopyCenter, canopyR * 1.00, const [Color(0xFF66BB6A), Color(0xFF2E7D32)]);
  blob(canopyCenter.translate(-canopyR * 0.35, -canopyR * 0.12), canopyR * 0.78, const [Color(0xFF81C784), Color(0xFF388E3C)]);
  blob(canopyCenter.translate(canopyR * 0.36, -canopyR * 0.08), canopyR * 0.74, const [Color(0xFF81C784), Color(0xFF2E7D32)]);
  blob(canopyCenter.translate(0, canopyR * 0.05), canopyR * 0.56, const [Color(0xFFA5D6A7), Color(0xFF43A047)]);
  // surbrillance et ombre directionnelles sur le feuillage
  final Paint foliageHL = Paint()
    ..shader = ui.Gradient.radial(canopyCenter - dir * (canopyR * 0.25), canopyR,
  [Colors.white.withValues(alpha: 0.10 * dayAmt), Colors.transparent], const [0, 1]);
  canvas.drawCircle(canopyCenter, canopyR * 1.1, foliageHL);
  final Paint foliageShade = Paint()
    ..shader = ui.Gradient.radial(canopyCenter + dir * (canopyR * 0.35), canopyR,
  [Colors.black.withValues(alpha: 0.12), Colors.transparent], const [0, 1]);
  canvas.drawCircle(canopyCenter, canopyR * 1.2, foliageShade);

    // fourmilière (petit dôme sur l'herbe)
    {
      final Offset base = _hillPos;
      final double r = _hillR;
      // ombre au sol
      canvas.drawOval(
        Rect.fromCenter(center: base.translate(0, 6), width: r * 2.3, height: 7),
        Paint()..color = Colors.black.withValues(alpha: 0.20),
      );
      // dôme
      final Rect dome = Rect.fromCenter(center: base.translate(0, -r * 0.4), width: r * 2.2, height: r * 1.6);
      final Paint domePaint = Paint()
        ..shader = ui.Gradient.linear(
          dome.topLeft, dome.bottomLeft,
          [const Color(0xFF7A5A4A), const Color(0xFF5A4034)],
          const [0, 1],
        );
      canvas.drawOval(dome, domePaint);
      // entrée sombre
      final Rect hole = Rect.fromCenter(center: base.translate(0, -r * 0.05), width: r * 0.9, height: r * 0.45);
      canvas.drawOval(hole, Paint()..color = const Color(0xFF2E1F1A).withValues(alpha: 0.85));
      // liseré léger
      canvas.drawOval(
        Rect.fromCenter(center: hole.center.translate(0, -hole.height * 0.12), width: hole.width, height: hole.height),
        Paint()..color = Colors.white.withValues(alpha: 0.06 * dayAmt),
      );
    }

    // pommes (dans l'arbre) avec ombrage/speculaire
    final appleBody = Paint()..color = const Color(0xFFE53935);
    for (final p in _apples) {
      canvas.drawCircle(p, 7, Paint()..color = Colors.black.withValues(alpha: 0.08));
      canvas.drawCircle(p.translate(-1.5, -1.5), 7, appleBody);
      canvas.drawLine(p.translate(0, -7), p.translate(0, -3), Paint()..color = const Color(0xFF5D4037)..strokeWidth = 2);
      // reflet côté lumière
      final Offset ldir = (p - sp);
      final double dlen = ldir.distance == 0 ? 1 : ldir.distance;
      final Offset n = Offset(ldir.dx / dlen, ldir.dy / dlen);
      final Offset hPos = p - n * 3;
      canvas.drawCircle(hPos, 2.2, Paint()..color = Colors.white.withValues(alpha: 0.32 * dayAmt));
    }
    // pommes tombées (au sol)
    for (final fa in _falling) {
      final center = fa.p;
  const double r = 7.0;
      // simple drop shadow
      canvas.drawCircle(center.translate(1.5, 2), r, Paint()..color = Colors.black.withValues(alpha: 0.1));
      // body
  final Paint body = Paint()..color = const Color(0xFFE53935);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(fa.spin * 0.1);
      canvas.drawCircle(Offset.zero, r, body);
      // petit highlight côté lumière
      final Offset ldir2 = (center - sp);
      final double d2 = ldir2.distance == 0 ? 1 : ldir2.distance;
      final Offset n2 = Offset(ldir2.dx / d2, ldir2.dy / d2);
      canvas.drawCircle(-n2 * 3, 2.0, Paint()..color = Colors.white.withValues(alpha: 0.30 * dayAmt));
      // mini tige seulement en chute
      if (!fa.rest) {
  const Offset a = Offset(0, -r * 0.9);
  const Offset b = Offset(0, -r * 0.4);
        final Paint stem = Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 2;
        canvas.drawLine(a, b, stem);
      }
      canvas.restore();
    }

  // (plus de fourmis de scénette)

  // ants (menu) — arrière-plan par rapport aux fleurs/touffes
  for (final a in _ants) {
      // shadow
  canvas.drawOval(Rect.fromCenter(center: a.p.translate(0, 2), width: 12, height: 4), Paint()..color = Colors.black.withValues(alpha: 0.26));
      final ang = a.dir;
      canvas.save();
      canvas.translate(a.p.dx, a.p.dy);
      canvas.rotate(ang);
  final body = Paint()..color = const Color(0xFF4E342E);
      canvas.drawCircle(const Offset(-6, 0), 3.8, body);
      canvas.drawCircle(const Offset(0, 0), 3.2, body);
      canvas.drawCircle(const Offset(6, 0), 2.7, body);
  // petit éclat côté lumière sur le thorax
  final Offset ap = a.p;
  final Offset ldir = (ap - sp);
  final double d = ldir.distance == 0 ? 1 : ldir.distance;
  final Offset n = Offset(ldir.dx / d, ldir.dy / d);
  canvas.drawCircle(n * -2.5, 1.0, Paint()..color = Colors.white.withValues(alpha: 0.22 * dayAmt));
      // legs (3 per side)
      final leg = Paint()
        ..color = const Color(0xFF3E2723)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (int i = -1; i <= 1; i++) {
        final double ox = i * 4.0;
        // left
        canvas.drawLine(Offset(ox, 0), Offset(ox - 3, 3), leg);
        // right
        canvas.drawLine(Offset(ox, 0), Offset(ox + 3, 3), leg);
      }
      canvas.restore();
    }

  // serpent façon in-game (dessin du trail) — arrière-plan
  _renderSnake(canvas, sp);

  // fleurs — deuxième plan (devant fourmis/serpent, derrière les touffes)
    for (int i = 0; i < _flowers.length; i++) {
      final c = _flowers[i];
      final col = _flowerColors[i];
      canvas.drawLine(c.translate(0, 8), c.translate(0, -6), Paint()..color = const Color(0xFF33691E)..strokeWidth = 2);
      final petal = Paint()..color = col;
      for (int k = 0; k < 5; k++) {
        final a = k * 2 * pi / 5;
        final Offset pc = c.translate(cos(a) * 5, sin(a) * 5 - 6);
        canvas.drawCircle(pc, 3.2, petal);
        // highlight sur le bord éclairé
        final Offset ldir = (pc - sp);
        final double d = ldir.distance == 0 ? 1 : ldir.distance;
        final Offset n = Offset(ldir.dx / d, ldir.dy / d);
  canvas.drawCircle(pc - n * 1.2, 0.9, Paint()..color = Colors.white.withValues(alpha: 0.26 * dayAmt));
      }
      canvas.drawCircle(c.translate(0, -6), 2.6, Paint()..color = const Color(0xFFFFF59D));
    }

  // touffes d'herbe en premier plan pour masquer fourmis/serpent/fleurs si nécessaire
  _drawTufts(canvas, sp, dayAmt);

  // fireflies (au-dessus du décor). Visible surtout la nuit
    if (nightAmt > 0) {
      for (final f in _flies) {
        final glow = 0.5 + 0.5 * sin(_time * 3.0 + f.phase);
  final Color c = const Color(0xFFFFF59D).withValues(alpha: 0.35 * nightAmt + 0.45 * glow * nightAmt);
        canvas.drawCircle(f.p, 2.6, Paint()..color = c);
        // small soft halo
        final Paint halo = Paint()
          ..shader = ui.Gradient.radial(f.p, 12, [c.withValues(alpha: 0.6), Colors.transparent], const [0, 1]);
        canvas.drawCircle(f.p, 12, halo);
      }
    }
  }
}
// Helper types
class _MStar {
  Offset pos;
  double phase;
  double speed;
  double radius;
  _MStar({required this.pos, required this.phase, required this.speed, required this.radius});
}

class _MAnt {
  Offset p;
  double dir;
  double speed;
  _MAnt({required this.p, required this.dir, required this.speed});
}

class _Cloud {
  Offset pos;
  double r;
  double speed;
  _Cloud({required this.pos, required this.r, required this.speed});
}

class _Tuft {
  Offset p;
  double s;
  _Tuft(this.p, this.s);
}

enum SoilKind { stone, fossilShell, fossilFish }

class _SoilItem {
  final SoilKind kind;
  final Offset pos;
  final double size;
  final double rot;
  final Color color;
  final double ex; // ellipse x-scale for stones

  _SoilItem._(this.kind, this.pos, this.size, this.rot, this.color, this.ex);
  factory _SoilItem.stone(Offset p, double r, Color c, {double ex = 1.0}) => _SoilItem._(SoilKind.stone, p, r, 0, c, ex);
  factory _SoilItem.fossil(Offset p, SoilKind k, double s, double rot) => _SoilItem._(k, p, s, rot, const Color(0xFFECE0C8), 1.0);

  void render(Canvas canvas) {
    switch (kind) {
      case SoilKind.stone:
        final Rect r = Rect.fromCenter(center: pos, width: size * 2 * ex, height: size * 2);
        final grad = Paint()
          ..shader = ui.Gradient.radial(pos, size * 1.2, [color, Colors.black.withValues(alpha: 0.18)], const [0, 1]);
        canvas.drawOval(r, grad);
        break;
      case SoilKind.fossilShell:
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(rot);
        final shell = Paint()
          ..color = const Color(0xFFEADBC2)
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;
        double rr = 7 * size;
        double ang = 0;
        for (int i = 0; i < 28; i++) {
          final a0 = ang;
          final a1 = ang + 0.35;
          final p0 = Offset(cos(a0) * rr, sin(a0) * rr);
          final p1 = Offset(cos(a1) * (rr * 0.96), sin(a1) * (rr * 0.96));
          canvas.drawLine(p0, p1, shell);
          rr *= 0.96;
          ang = a1;
        }
        canvas.restore();
        break;
      case SoilKind.fossilFish:
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(rot);
        final bone = Paint()
          ..color = const Color(0xFFEADBC2)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        // spine
        canvas.drawLine(const Offset(-10, 0), const Offset(10, 0), bone);
        // ribs
        for (int i = -4; i <= 4; i++) {
          final x = i * 3.0;
          if (x.abs() < 1) continue;
          canvas.drawLine(Offset(x, 0), Offset(x, i < 0 ? -3.5 : 3.5), bone);
        }
        // head triangle
        final head = Path()
          ..moveTo(10, 0)
          ..lineTo(14, -3)
          ..lineTo(14, 3)
          ..close();
        canvas.drawPath(head, bone);
        canvas.restore();
        break;
    }
  }
}

class _FallingApple {
  Offset p;
  Offset v;
  double spin;
  bool rest;
  _FallingApple({required this.p, required this.v, required this.spin}) : rest = false;
}

class _Firefly {
  Offset p;
  double phase;
  double speed;
  // bruit/stat
  double seed;
  // cible feuille dans la canopée
  Offset target;
  double targetT;
  double targetDur;
  // paramètres d'orbite indépendante
  double anchorPhase;
  double anchorSpeed;
  // paramètres de déplacement erratique
  double localSpeed;
  double maxSpd;
  double jitter;
  double damping;
  Offset v;

  _Firefly({required this.p, required this.phase, required this.speed})
      : seed = Random().nextDouble() * 6.283,
        target = Offset.zero,
        targetT = 0.0,
        targetDur = 0.0,
        anchorPhase = 0.0,
        anchorSpeed = 0.0,
        localSpeed = 1.0,
        maxSpd = 30.0,
        jitter = 30.0,
        damping = 1.0,
        v = Offset.zero;

}

extension _MenuRender on GardenMenuGame {
  void _renderSnake(Canvas canvas, Offset sp) {
    if (!_snakeAlive || _segments.isEmpty || _snakeHp <= 0) return;
    final int count = _segments.length;
    for (int i = count - 1; i >= 0; i--) {
      final double t = count <= 1 ? 0.0 : i / (count - 1);
      final double r = 4.5 + 5.0 * (1.0 - t);
      final Color col = Color.lerp(const Color(0xFF2E7D32), const Color(0xFF66BB6A), 1.0 - t)!.withValues(alpha: 0.95);
      final Offset p = _segments[i];
      canvas.drawCircle(p, r, Paint()..color = col);
      final Offset ldir = (p - sp);
      final double d = ldir.distance == 0 ? 1 : ldir.distance;
      final Offset n = Offset(ldir.dx / d, ldir.dy / d);
      final Paint hl = Paint()
        ..shader = ui.Gradient.radial(p - n * (r * 0.4), r, [Colors.white.withValues(alpha: 0.10), Colors.transparent], const [0, 1]);
      canvas.drawCircle(p, r, hl);
    }
    // head details (eyes)
    final Offset head = _mHead;
    final Offset perp = Offset(-_mDir.dy, _mDir.dx);
    void reptileEye(Offset c, {bool flip = false}) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(flip ? -0.12 : 0.12);
      final Rect er = Rect.fromCenter(center: Offset.zero, width: 3.2, height: 2.0);
      canvas.drawOval(er, Paint()..color = Colors.white);
      final Rect pr = Rect.fromCenter(center: Offset.zero, width: 0.6, height: 1.8);
      canvas.drawRRect(RRect.fromRectAndRadius(pr, const Radius.circular(0.4)), Paint()..color = Colors.black87);
      canvas.restore();
    }
  reptileEye(head + perp * -4.0 + const Offset(0, -0.6));
  reptileEye(head + perp * 4.0 + const Offset(0, -0.6), flip: true);
  }
}
// Petites fonctions utilitaires pour dessiner des touffes d'herbe
extension _TuftsRender on GardenMenuGame {
  void _drawTufts(Canvas canvas, Offset sp, double dayAmt) {
    for (final t in _tufts) {
      // ombre au sol
      canvas.drawOval(
        Rect.fromCenter(center: t.p.translate(0, 3 * t.s), width: 12 * t.s, height: 3.2 * t.s),
        Paint()..color = Colors.black.withValues(alpha: 0.16),
      );
      // lames remplies (feuilles), avec dégradé base->sommet
  const List<double> angles = [-24, -14, -6, 0, 6, 14, 24];
      for (int k = 0; k < angles.length; k++) {
        final double ang = angles[k] * pi / 180.0;
        final double baseW = (1.6 + (k % 3) * 0.3) * t.s;
        final double h = (11 + (k % 2) * 3 + (k == 3 ? 4 : 0)) * t.s;
        final Offset up = Offset(sin(ang), -cos(ang));
        final Offset right = Offset(cos(ang), sin(ang));
        final Offset base = t.p + right * (k - (angles.length - 1) / 2) * 1.2 * t.s;
        final Offset tip = base + up * h;
        final Path leaf = Path()
          ..moveTo(base.dx - right.dx * baseW, base.dy - right.dy * baseW)
          ..quadraticBezierTo(
            (base.dx + tip.dx) / 2 - up.dx * h * 0.15,
            (base.dy + tip.dy) / 2 - up.dy * h * 0.15,
            tip.dx,
            tip.dy,
          )
          ..quadraticBezierTo(
            (base.dx + tip.dx) / 2 + up.dx * h * 0.10,
            (base.dy + tip.dy) / 2 + up.dy * h * 0.10,
            base.dx + right.dx * baseW,
            base.dy + right.dy * baseW,
          )
          ..close();
        // dégradé directionnel selon le soleil
        final Offset ldir = (base - sp);
        final double d = ldir.distance == 0 ? 1 : ldir.distance;
        final Offset n = Offset(ldir.dx / d, ldir.dy / d);
  const Color c0 = Color(0xFF1E6020);
  const Color c1 = Color(0xFF4CAF50);
        final Paint leafPaint = Paint()
          ..shader = ui.Gradient.linear(
            base + n * -2.0,
            tip + n * 2.0,
            [c0, Color.lerp(c0, c1, 0.8)!.withValues(alpha: (0.85 + 0.1 * dayAmt))],
            const [0, 1],
          );
        canvas.drawPath(leaf, leafPaint);
      }
    }
  }
}
// End of file
