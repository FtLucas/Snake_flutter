import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'state/player_profile.dart';
// import 'state/player_profile.dart';

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
  int _baseFireflyCount = 0; // nombre de lucioles de base (jour), augmenté la nuit
  final List<_Cloud> _clouds = [];
  // Couche de nuages lointains, plus flous et plus lents
  final List<_Cloud> _farClouds = [];
  final List<_Tuft> _tufts = [];
  // cadence d'update pour lucioles (décimation)
  double _fireflyAcc = 0.0;
  double _shakeT = 0.0; // légère secousse du feuillage après tap
  // Horloge globale
  double _time = 0.0;
  // Textures (pré-rendues) pour performances
  ui.Picture? _grassTexPic;
  Rect? _grassTexRect; // zone de destination
  // (texture de feuilles retirée)
  // Pré-rendu supplémentaire pour réduire le travail par frame
  ui.Picture? _soilDecorPic; // pierres + fossiles
  ui.Picture? _canopyBlobsPic; // grosses nappes de feuillage (avant texture)
  ui.Picture? _staticDecorPic; // tronc + racines + fourmilière
  // Clé de cache pour le décor statique (rebuild si la fourmilière change)
  Offset? _staticKeyHillPos;
  double? _staticKeyHillR;
  // Variantes de touffes d'herbe pré‑rendu
  final List<ui.Picture> _tuftPics = [];
  final List<double> _tuftPicScales = [0.9, 1.2, 1.5, 1.8, 2.1, 2.4];

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
  // Contrôle d'errance plus organique du serpent
  double _wanderAng = 0.0;     // orientation actuelle (radians)
  double _wanderOmega = 0.0;   // vitesse angulaire actuelle
  double _wanderTimer = 0.0;   // temps restant avant de recalculer un nouvel omega

  // Cooldown de morsure et étourdissement (bloque mouvement)
  double _eatCooldown = 0.0; // secondes restantes avant de pouvoir remanger
  double _eatStunT = 0.0;    // secondes restantes de blocage après avoir mangé
  // Ralentissement temporaire quand le serpent se fait mordre
  double _biteSlowT = 0.0;   // durée restante du slow

  // Animation de menu: machine à états
  int _scene = 0;            // 0: spawn pomme, 1: chute, 2: roule vers fourmilière, 3: serpent attaqué/meurt, 4: vie sans serpent
  double _sceneTimer = 0.0;  // minuterie générique
  int? _scriptAppleIdx;      // index de la pomme scriptée dans _falling
  bool _disableRespawn = true;    // le serpent ne réapparaît plus (activé dès le début du menu)
  bool _sceneInit = false;         // init one-shot au premier update
  bool _sceneAntsSpawned = false;  // flag pour indiquer si les fourmis de la scène ont été spawnées

  // Temps de descente du serpent après l'apparition d'une pomme
  double _snakeDescendT = 0.0;
  // Paramètres et chemin de descente pour un mouvement plus naturel le long du tronc
  double _snakeDescendDur = 0.0; // durée totale de descente
  // (anciens champs start/end inutilisés après refonte des phases)
  // Phases: 0 = feuilles->tronc (Bezier), 1 = glisse sur tronc, 2 = sortie sur l'herbe
  int _snakeDescendPhase = 0;
  double _snakePhaseDur0 = 0.0, _snakePhaseDur1 = 0.0, _snakePhaseDur2 = 0.0;
  Offset? _snakeP0, _snakeP1, _snakeP2, _snakeP3, _snakeP4; // points clés
  // (ancien contrôle Bezier stocké — non utilisé explicitement)
  // Position de la pomme arrêtée (centre d'orbite des fourmis de scène)
  Offset? _sceneApplePos;
  // Délai avant l'apparition du serpent après l'arrivée de la pomme
  double _snakeAppearDelay = 0.0;

  // Burst de fourmis: spawn échelonné
  int _burstToSpawn = 0;           // combien restent à faire sortir
  double _burstSpawnInterval = 0;  // intervalle courant entre sorties
  double _burstSpawnTimer = 0;     // minuterie avant la prochaine sortie

  // (helper retiré: on ne déplace plus le tronc/canopée dynamiquement)

  @override
  Future<void> onLoad() async {
    _rebuildDecor();
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
      ..addAll(List.generate((size.x * 0.18).clamp(30, 90).toInt(), (i) {
        return _MStar(
          pos: Offset(_rng.nextDouble() * size.x, _rng.nextDouble() * (_groundTop * 0.9)),
          phase: _rng.nextDouble() * 6.283,
          speed: 1.0 + _rng.nextDouble() * 2.0,
          radius: 0.8 + _rng.nextDouble() * 1.6,
        );
      }));

  // Fourmilière: rayon puis position (légèrement plus haute que la lèvre herbe/terre)
  _hillR = (size.x * 0.03).clamp(14.0, 24.0);
  _hillPos = Offset(size.x * 0.74, (size.y - _soilH) - _hillR * 1.5);

  // Ants: aucune au départ (elles sortiront pendant la scène scriptée)
  _ants.clear();

  // Snake: préparer mais ne pas l'afficher au départ (il apparaîtra plus tard via la scène)
    _trailSpacing = 12.0;
    _mSpeed = 90.0;
    _snakeMaxHp = (size.x / 20).clamp(12, 26).toInt();
    _snakeHp = 0;
    _snakeAlive = false;
    _respawnT = 0.0;
  _segments.clear();
  _trail.clear();
  _wanderAng = 0.0;
  _wanderOmega = 0.0;
  _wanderTimer = 0.0;

    // Soil decor items (stones and fossils), stable via size-derived seed
    _soilItems.clear();
    final seed = (size.x.floor() * 73856093) ^ (size.y.floor() * 19349663);
    final rnd = Random(seed);
    final double soilTop = size.y - _soilH;
    final double soilBottom = size.y;
    final int stones = (size.x / 30).clamp(8, 44).toInt();
    // Palette des cailloux identique au jeu
    const List<Color> stonePalette = [
      Color(0xFFECEFF1), // very light
      Color(0xFFCFD8DC),
      Color(0xFFB0BEC5),
      Color(0xFF90A4AE),
      Color(0xFF757575),
      Color(0xFF616161),
      Color(0xFF424242), // dark
    ];
    for (int i = 0; i < stones; i++) {
      final x = rnd.nextDouble() * size.x;
      final r = 2.4 + rnd.nextDouble() * 5.6;
      final double margin = r + 1.0; // garder la pierre dans la terre
      final y = rnd.nextDouble() * (soilBottom - soilTop - margin * 2) + soilTop + margin;
      final Color col = stonePalette[rnd.nextInt(stonePalette.length)].withValues(alpha: 0.95);
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
        // variante de picture la plus proche
        int vi = 0; double best = double.infinity;
        for (int k = 0; k < _tuftPicScales.length; k++) {
          final d = (scale - _tuftPicScales[k]).abs();
          if (d < best) { best = d; vi = k; }
        }
        return _Tuft(Offset(x, y), scale, vi);
      }));
    // Construire/cacher les variantes de touffes si vide
    if (_tuftPics.isEmpty) {
      for (final s in _tuftPicScales) {
        _tuftPics.add(_makeTuftPicture(s));
      }
    }

    // Effects: reset falling apples and fireflies
    _falling.clear();
    _baseFireflyCount = (size.x / 40).clamp(14, 36).toInt();
    _flies
      ..clear()
      ..addAll(List.generate(_baseFireflyCount, (i) {
        // spawn uniformément dans toute la canopée visible (union des nappes circulaires)
        final Offset base = _sampleLeafPoint();
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
    _farClouds
      ..clear()
      ..addAll(List.generate((size.x / 320).clamp(2, 4).toInt(), (i) {
        final x = _rng.nextDouble() * size.x;
        final y = _rng.nextDouble() * (_groundTop * 0.55) + 6; // plus haut et plus loin
        final r = 34.0 + _rng.nextDouble() * 28.0; // un peu plus gros
        final speed = 1.5 + _rng.nextDouble() * 2.2; // beaucoup plus lents
        return _Cloud(pos: Offset(x, y), r: r, speed: speed);
      }));
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
    _snakeHp = 0;
    _snakeAlive = false;
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
    // Construire les textures pré-rendues (herbe + canopée)
    _buildCachedTextures();
  }

  // Appelée depuis l'UI pour un tap sur le fond
  void triggerTapEffect(Offset pos) {
    _shakeT = 0.35;
    int boosted = 0;
    for (final f in _flies) {
      if ((f.p - pos).distance < 100 && boosted < 12) {
        f.v = Offset(f.v.dx, f.v.dy - (60 + _rng.nextDouble() * 120));
        boosted++;
      }
      if (boosted >= 12) break;
    }
  }

  // Construit les textures pré-rendues pour l'herbe et la canopée
  void _buildCachedTextures() {
    // Texture d'herbe
    final Rect grass = Rect.fromLTWH(0, _groundTop, size.x, size.y - _groundTop);
    _grassTexRect = grass;
    _grassTexPic = _makeGrassTexturePicture(Size(grass.width, grass.height));

  // Texture de canopée retirée

  // Blocs de feuillage (gros gradients) pré-rendus
  final Rect canopyBlobsRect = Rect.fromCircle(center: _canopyCenter, radius: _canopyR * 1.05);
  _canopyBlobsPic = _makeCanopyBlobsPicture(canopyBlobsRect);

  // Décor de sol (pierres + fossiles) pré-rendu
  final Rect soil = Rect.fromLTWH(0, size.y - _soilH, size.x, _soilH);
  _soilDecorPic = _makeSoilDecorPicture(soil);

  // Décor statique (tronc, racines, fourmilière)
  _staticDecorPic = _makeStaticDecorPicture();
  }

  // Génère une image de texture d'herbe (pré-rendue)
  ui.Picture _makeGrassTexturePicture(Size texSize) {
    final recorder = ui.PictureRecorder();
    final Canvas c = Canvas(recorder);
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, texSize.width, texSize.height));
    final double gStep = max(12.0, min(26.0, texSize.width / 40));
    final randGrass = Random(2025);
    final Paint bladeDark = Paint()
      ..color = const Color(0xFF0F3D16).withValues(alpha: 0.10)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Paint bladeLight = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (double y = 6; y < texSize.height; y += gStep) {
      for (double x = 0; x < texSize.width; x += gStep) {
        final double ox = x + (randGrass.nextDouble() - 0.5) * gStep * 0.6;
        final double oy = y + (randGrass.nextDouble() - 0.5) * gStep * 0.6;
        final double h = gStep * (0.7 + randGrass.nextDouble() * 0.6);
        final double bend = (randGrass.nextDouble() * 0.6 - 0.3);
        final Path p = Path()
          ..moveTo(ox, oy)
          ..quadraticBezierTo(ox + h * bend * 0.3, oy - h * 0.6, ox + h * bend, oy - h);
        c.drawPath(p, bladeDark);
        final Path p2 = Path()
          ..moveTo(ox + 1.0, oy)
          ..quadraticBezierTo(ox + h * bend * 0.35 + 1.0, oy - h * 0.55, ox + h * bend + 1.0, oy - h * 0.95);
        c.drawPath(p2, bladeLight);
      }
    }
    c.restore();
    return recorder.endRecording();
  }


  // Grosse forme de canopée (nappes circulaires) pré-rendue
  ui.Picture _makeCanopyBlobsPicture(Rect canopyRect) {
    final recorder = ui.PictureRecorder();
    final Canvas c = Canvas(recorder);
    // Décaler l'origine pour dessiner en coordonnées locales du picture
    c.translate(-canopyRect.left, -canopyRect.top);
    void blob(Offset center, double r, List<Color> colors) {
      final Paint p = Paint()
        ..shader = ui.Gradient.radial(center.translate(-r * 0.2, -r * 0.15), r, colors, const [0.0, 1.0]);
      c.drawCircle(center, r, p);
    }
    final Offset canopyCenter = _canopyCenter;
    final double canopyR = _canopyR;
    blob(canopyCenter, canopyR * 1.00, const [Color(0xFF66BB6A), Color(0xFF2E7D32)]);
    blob(canopyCenter.translate(-canopyR * 0.35, -canopyR * 0.12), canopyR * 0.78, const [Color(0xFF81C784), Color(0xFF388E3C)]);
    blob(canopyCenter.translate(canopyR * 0.36, -canopyR * 0.08), canopyR * 0.74, const [Color(0xFF81C784), Color(0xFF2E7D32)]);
    blob(canopyCenter.translate(0, canopyR * 0.05), canopyR * 0.56, const [Color(0xFFA5D6A7), Color(0xFF43A047)]);
    return recorder.endRecording();
  }

  // Pierres + fossiles pré-rendus
  ui.Picture _makeSoilDecorPicture(Rect soilRect) {
    final recorder = ui.PictureRecorder();
    final Canvas c = Canvas(recorder);
    // Clip pour rester dans la terre
    c.clipRect(Rect.fromLTWH(soilRect.left, soilRect.top + 4, soilRect.width, soilRect.height - 4));
    for (final it in _soilItems) {
      it.render(c);
    }
    return recorder.endRecording();
  }

  // Picture d'une touffe d'herbe (base à l'origine, pousse vers -Y)
  ui.Picture _makeTuftPicture(double s) {
    final recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    // feuilles remplies avec dégradé base->sommet (statique)
    const List<double> angles = [-24, -14, -6, 0, 6, 14, 24];
    for (int k = 0; k < angles.length; k++) {
      final double ang = angles[k] * pi / 180.0;
      final double baseW = (1.6 + (k % 3) * 0.3) * s;
      final double h = (11 + (k % 2) * 3 + (k == 3 ? 4 : 0)) * s;
      final Offset up = Offset(sin(ang), -cos(ang));
      final Offset right = Offset(cos(ang), sin(ang));
      final Offset base = Offset.zero;
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
      const Color c0 = Color(0xFF1E6020);
      const Color c1 = Color(0xFF4CAF50);
      final Paint leafPaint = Paint()
        ..shader = ui.Gradient.linear(
          base.translate(0, 0),
          tip,
          [c0, Color.lerp(c0, c1, 0.8)!.withValues(alpha: 0.92)],
          const [0, 1],
        );
      canvas.drawPath(leaf, leafPaint);
    }
    return recorder.endRecording();
  }

  // Tronc, racines et fourmilière pré-rendus (statique)
  ui.Picture _makeStaticDecorPicture() {
    final recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    // tronc
    final double trunkW = _treeHeight * 0.14;
    final Rect trunkRect = Rect.fromLTWH(_treeBase.dx - trunkW / 2, _treeBase.dy - _treeHeight, trunkW, _treeHeight);
    final Paint trunkGrad = Paint()
      ..shader = ui.Gradient.linear(trunkRect.topLeft, trunkRect.bottomLeft, [const Color(0xFF8D6E63), const Color(0xFF6D4C41), const Color(0xFF5D4037)], const [0.0, 0.6, 1.0]);
    canvas.drawRRect(RRect.fromRectAndRadius(trunkRect, const Radius.circular(8)), trunkGrad);
    // texture d'écorce
    const int lines = 9;
    for (int i = 0; i < lines; i++) {
      final double fx = (i + 1) / (lines + 1);
      final double amp = 0.8 + (i % 3) * 0.5;
      final double phase = i * 0.9;
      final Paint darkStroke = Paint()
        ..color = const Color(0xFF3E2723).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final Path path = Path();
      double y = trunkRect.top + 6;
      const double step = 10;
      final double x0 = trunkRect.left + trunkW * fx;
      path.moveTo(x0, y);
      while (y < trunkRect.bottom - 6) {
        y += step;
        final double t = (y - trunkRect.top) / trunkRect.height;
        final double x = x0 + sin(t * pi * 2.0 + phase) * amp;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, darkStroke);
    }
    const List<double> hi = [0.22, 0.48, 0.74];
    for (int i = 0; i < hi.length; i++) {
      final double fx = hi[i];
      final double amp = 0.6 + i * 0.2;
      final double phase = 0.4 + i * 0.7;
      final Paint lightStroke = Paint()
        ..color = Colors.white.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round;
      final Path path = Path();
      double y = trunkRect.top + 8;
      const double step = 12;
      final double x0 = trunkRect.left + trunkW * fx;
      path.moveTo(x0, y);
      while (y < trunkRect.bottom - 8) {
        y += step;
        final double t = (y - trunkRect.top) / trunkRect.height;
        final double x = x0 + sin(t * pi * 2.0 + phase) * amp;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, lightStroke);
    }
    final List<Offset> knots = <Offset>[
      Offset(trunkRect.left + trunkW * 0.30, trunkRect.top + trunkRect.height * 0.28),
      Offset(trunkRect.left + trunkW * 0.55, trunkRect.top + trunkRect.height * 0.38),
      Offset(trunkRect.left + trunkW * 0.40, trunkRect.top + trunkRect.height * 0.52),
      Offset(trunkRect.left + trunkW * 0.66, trunkRect.top + trunkRect.height * 0.62),
      Offset(trunkRect.left + trunkW * 0.34, trunkRect.top + trunkRect.height * 0.72),
      Offset(trunkRect.left + trunkW * 0.58, trunkRect.top + trunkRect.height * 0.82),
    ];
    for (final k in knots) {
      final Rect r = Rect.fromCenter(center: k, width: trunkW * 0.12, height: trunkW * 0.08);
      final Paint knot = Paint()
        ..shader = ui.Gradient.radial(r.center, r.width * 0.6, [const Color(0xFF5D4037), const Color(0xFF3E2723)], const [0, 1]);
      canvas.drawOval(r, knot);
      canvas.drawOval(r.deflate(0.6), Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);
    }
    // racines
    final Offset base = _treeBase;
    final double moundW = trunkW * 2.1;
    final Rect mound = Rect.fromCenter(center: base.translate(0, 2), width: moundW, height: 8);
    final Paint moundPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(mound.center.dx, mound.top), Offset(mound.center.dx, mound.bottom), [const Color(0xFF6D4C41), const Color(0xFF4E342E)], const [0, 1]);
    canvas.drawOval(mound, moundPaint);
    const List<double> offs = [-0.7, -0.45, -0.2, 0.0, 0.2, 0.45, 0.7];
    for (int i = 0; i < offs.length; i++) {
      final double d = offs[i].abs();
      final double dx = offs[i] * trunkW * 0.72;
      final double w = trunkW * (0.70 - 0.18 * d);
      final double h = 6.5 + 2.5 * (1.0 - d);
      final Rect bump = Rect.fromCenter(center: base.translate(dx, -2.0), width: w, height: h);
      final Paint bumpPaint = Paint()
        ..shader = ui.Gradient.linear(Offset(bump.center.dx, bump.top), Offset(bump.center.dx, bump.bottom), [const Color(0xFF8D6E63), const Color(0xFF5D4037)], const [0, 1]);
      canvas.drawOval(bump, bumpPaint);
      final Path cap = Path()..addArc(bump.deflate(1.2), pi, pi);
      canvas.drawPath(cap, Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
    }
    // fourmilière
    final Offset hBase = _hillPos;
    final double hr = _hillR;
  final Offset domeCenter = hBase.translate(0, -hr * 0.4);
  final Rect dome = Rect.fromCenter(center: domeCenter, width: hr * 2.2, height: hr * 1.6);
    final Paint domePaint = Paint()
      ..shader = ui.Gradient.linear(dome.topLeft, dome.bottomLeft, [const Color(0xFF7A5A4A), const Color(0xFF5A4034)], const [0, 1]);
    canvas.drawOval(dome, domePaint);
  // Trou légèrement plus bas depuis le sommet du dôme
  final Offset holeCenter = Offset(dome.center.dx, dome.top + hr * 0.30);
  final Rect hole = Rect.fromCenter(center: holeCenter, width: hr * 0.9, height: hr * 0.35);
    canvas.drawOval(hole, Paint()..color = const Color(0xFF2E1F1A).withValues(alpha: 0.85));
    // liseré léger (statique)
  canvas.drawOval(Rect.fromCenter(center: hole.center.translate(0, -hole.height * 0.12), width: hole.width, height: hole.height),
      Paint()..color = Colors.white.withValues(alpha: 0.06));

    return recorder.endRecording();
  }

  // (vision culling désactivé)

  // Spawn irrégulier des fourmis depuis la fourmilière
  void _spawnAntsIrregularly(double deltaTime) {
    return; // désactivé pour la scène scriptée
  }

  @override
  void update(double dt) {
    super.update(dt);

  // Pilotage de la scène en tout premier (permet d'ajouter la pomme avant la physique)
  _updateScene(dt);

    // Gestion du spawn échelonné du burst de fourmis
    if (_burstToSpawn > 0) {
      _burstSpawnTimer -= dt;
      if (_burstSpawnTimer <= 0) {
        // spawn d'une fourmi du burst
        final double ang = _rng.nextDouble() * pi * 2;
        final Offset dir = Offset(cos(ang), sin(ang));
        final ant = _MAnt(p: _hillPos + dir * 2.0, dir: ang, speed: 22 + _rng.nextDouble() * 14);
        ant.emerging = true;
        ant.emergeDir = dir;
        ant.emergeT = 0.0;
        ant.emergeDur = 0.9 + _rng.nextDouble() * 0.6;
        ant.fromBurst = true;
        _ants.add(ant);
        _burstToSpawn--;
        _burstSpawnInterval = 0.25 + _rng.nextDouble() * 0.35; // 0.25..0.6s
        _burstSpawnTimer = _burstSpawnInterval;
      }
    }

    // Mise à jour des timers
    if (_snakeAlive) {
      if (_biteSlowT > 0) _biteSlowT = max(0, _biteSlowT - dt);
    }

    _spawnAntsIrregularly(dt); // Gestion du spawn irrégulier des fourmis

  // Désactivation du culling pour éviter la disparition des fourmis pendant la scénette
  // et lors des attaques. Garder toutes les fourmis améliore la stabilité visuelle.
  // Ancien code conservé ci-dessous pour référence si besoin de réactiver avec des règles plus strictes.
  // if (_snakeAlive && !(_scene == 2 || _scene == 3 || _scene == 4)) {
  //   _ants.removeWhere((ant) => !ant.emerging && !ant.fromBurst && !_isAntInVision(ant.p));
  // }

  // Décroissance de la secousse
  if (_shakeT > 0) _shakeT = max(0.0, _shakeT - dt);

  _t = (_t + dt / cycleSeconds) % 1.0;
    _time += dt;
    // ants wander/chase or orbit (scripted)
  for (final a in _ants) {
      // Emergence: sortir brièvement de la fourmilière puis passer en orbite
      if (a.emerging) {
        a.emergeT += dt;
        final double t = (a.emergeDur <= 0) ? 1.0 : (a.emergeT / a.emergeDur).clamp(0.0, 1.0);
  final double spd = 18.0 + (36.0 - 18.0) * (1.0 - (t * 0.6)); // démarre plus vite puis ralentit
        a.p += a.emergeDir * spd * dt;
        a.dir = atan2(a.emergeDir.dy, a.emergeDir.dx);
        if (t >= 1.0) {
          a.emerging = false;
          if (a.fromBurst) {
            // fourmis d'éclaireuse: restent en errance libre
            a.orbiting = false;
          } else {
            // accroche à une orbite aléatoire autour de la fourmilière
            a.orbiting = true;
            a.orbitCenter = _hillPos;
            a.orbitR = (_hillR * 1.1) + _rng.nextDouble() * (_hillR * 0.7);
            a.orbitEccY = 0.6;
            a.orbitOmega = (_rng.nextBool() ? 1.0 : -1.0) * (0.6 + _rng.nextDouble() * 0.6);
            // calculer phase à partir de sa position actuelle
            final Offset rel = a.p - a.orbitCenter;
            a.orbitPhase = atan2(rel.dy / max(0.0001, a.orbitEccY), rel.dx);
          }
        }
        continue;
      }
      if (a.orbiting) {
        // Détection attaque: serpent proche de la fourmilière ou de la fourmi
  final double snakeDistHill = (_mHead - _hillPos).distance;
        final double snakeDistAnt = (a.p - _mHead).distance;
  a.isAttacking = (snakeDistHill < _hillR * 2.2) || (snakeDistAnt < 36.0);
        if (a.isAttacking && _snakeAlive) {
          // Attaque: choisir/viser un segment spécifique du serpent
          a.retargetT -= dt;
          if (a.retargetT <= 0 || a.attackTargetSegIdx < 0 || a.attackTargetSegIdx >= _segments.length) {
            // choisir un segment aléatoire, en évitant parfois la tête
            final int maxIdx = max(1, _segments.length - 1);
            a.attackTargetSegIdx = 1 + _rng.nextInt(maxIdx); // 1..last (évite la tête)
            a.retargetT = 0.6 + _rng.nextDouble() * 0.9; // retarget régulier
          }
          final Offset target = a.attackTargetSegIdx >= 0 && a.attackTargetSegIdx < _segments.length
              ? _segments[a.attackTargetSegIdx]
              : _mHead;
          final Offset toHead = target - a.p;
          final double d = toHead.distance;
          if (d > 0.0001) {
            final Offset v = toHead / d;
            final double atkSpd = max(a.speed * 2.0, 32.0);
            a.p += v * atkSpd * dt;
            a.dir = atan2(v.dy, v.dx);
          }
        } else {
          // Orbitage par défaut autour de la fourmilière
          double omega = a.orbitOmega;
          a.orbitPhase += omega * dt;
          final Offset center = a.orbitCenter;
          a.p = center + Offset(cos(a.orbitPhase) * a.orbitR, sin(a.orbitPhase) * a.orbitR * a.orbitEccY);
          final Offset tanRaw = Offset(-sin(a.orbitPhase), cos(a.orbitPhase) * a.orbitEccY);
          final double tLen = tanRaw.distance;
          final Offset tangent = tLen > 1e-6 ? tanRaw / tLen : const Offset(1, 0);
          a.dir = atan2(tangent.dy, tangent.dx);
        }
        continue;
      }
      // Pendant la scénette, empêcher les fourmis non-burst d'abandonner l'orbite pour la pomme
      if ((_scene == 2 || _scene == 3) && !a.fromBurst) {
        continue;
      }
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
      // Après la scénette, garder les fourmis proches de la fourmilière (retour doux)
  if (_scene >= 4 && !a.fromBurst) {
        final Offset toHome = _hillPos - a.p;
        final double dist = toHome.distance;
        if (dist > 1.0) {
          final Offset curV = Offset(cos(a.dir), sin(a.dir));
          final Offset homeV = toHome / dist;
          final double pull = dist > _hillR * 3.0 ? 0.6 : 0.25; // plus fort si trop loin
          final Offset blended = curV * (1 - pull) + homeV * pull;
          a.dir = atan2(blended.dy, blended.dx);
        }
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
  // Bloquer l'errance pendant la descente scriptée (scène 2)
  if (_snakeAlive && _eatStunT <= 0 && !(_scene == 2 && _snakeDescendT > 0)) {
      // steering: errance lissée + maintien doux à l'intérieur de la zone verte
      final double minX = 12, maxX = size.x - 12;
      final double minY = _groundTop + 12, maxY = size.y - _soilH - 16;

      // errance lissée: oméga bruité
      _wanderTimer -= dt;
      if (_wanderTimer <= 0) {
        final double target = (_rng.nextDouble() - 0.5) * 1.2; // rad/s (un peu moins prononcé)
        _wanderOmega = _wanderOmega * 0.7 + target * 0.3;
        _wanderTimer = 0.35 + _rng.nextDouble() * 0.55; // 0.35..0.9s
      }
      final double omega = _wanderOmega * (_biteSlowT > 0 ? 0.6 : 1.0);
      _wanderAng = atan2(_mDir.dy, _mDir.dx) + omega * dt;
      Offset dir = Offset(cos(_wanderAng), sin(_wanderAng));

      // force douce vers l'intérieur (centre de la zone verte)
      final Offset center = Offset(size.x * 0.5, (_groundTop + (size.y - _soilH)) * 0.5);
      final Offset toCenter = center - _mHead;
      final double distC = toCenter.distance;
      Offset centerPull = Offset.zero;
      if (distC > 0.001) {
        final Offset nC = toCenter / distC;
        // calculer marge aux bords
        final double marginX = min(_mHead.dx - minX, maxX - _mHead.dx);
        final double marginY = min(_mHead.dy - minY, maxY - _mHead.dy);
        final double margin = min(marginX, marginY);
        // plus le serpent est proche d’un bord, plus on accentue le pull
    final double pull = (margin < 40)
      ? ui.lerpDouble(0.15, 0.85, (40 - margin) / 40)!.clamp(0.15, 0.85)
      : 0.0;
        centerPull = nC * pull;
      }

      // évitement prédictif des bords (sans ricochet): corriger la direction
      const double lookAhead = 28.0;
      final Offset ahead = _mHead + dir * lookAhead;
      double steerX = 0, steerY = 0;
      if (ahead.dx < minX) steerX = (minX - ahead.dx) / lookAhead;
      if (ahead.dx > maxX) steerX = (maxX - ahead.dx) / lookAhead;
      if (ahead.dy < minY) steerY = (minY - ahead.dy) / lookAhead;
      if (ahead.dy > maxY) steerY = (maxY - ahead.dy) / lookAhead;
      final Offset boundarySteer = Offset(steerX, steerY);

      // Anti-bloquage dans les coins: petite poussée diagonale pour sortir d'un coin
      Offset cornerAvoid = Offset.zero;
      {
        final double dL = _mHead.dx - minX;
        final double dR = maxX - _mHead.dx;
        final double dT = _mHead.dy - minY;
        final double dB = maxY - _mHead.dy;
        final double nearX = min(dL, dR);
        final double nearY = min(dT, dB);
        const double cornerThresh = 28.0;
        if (nearX < cornerThresh && nearY < cornerThresh) {
          final double sx = dL < dR ? 1.0 : -1.0; // pousser vers le centre en X
          final double sy = dT < dB ? 1.0 : -1.0; // pousser vers le centre en Y
          final double fx = (cornerThresh - nearX) / cornerThresh;
          final double fy = (cornerThresh - nearY) / cornerThresh;
          final double f = max(fx, fy).clamp(0.0, 1.0);
          final double n = sqrt(sx * sx + sy * sy);
          cornerAvoid = Offset(sx / n, sy / n) * f; // vecteur diagonal normalisé
        }
      }

      // Fuite des fourmis: vecteur de répulsion si des fourmis sont proches (optimisé: distances au carré)
      const double fleeR = 70.0; // rayon d'influence de la fuite
      const double fleeR2 = fleeR * fleeR;
      Offset flee = Offset.zero;
      int fleeCount = 0;
      for (final ant in _ants) {
        final Offset dv = _mHead - ant.p; // vecteur loin de la fourmi
        final double dd2 = dv.dx * dv.dx + dv.dy * dv.dy;
        if (dd2 > 1e-6 && dd2 < fleeR2) {
          final double dd = sqrt(dd2);
          final double w = (fleeR - dd) / fleeR; // 0..1 (plus fort si très proche)
          flee += dv / dd * w;
          fleeCount++;
        }
      }
      if (fleeCount > 0) {
        final double mag = flee.distance;
        if (mag > 1e-6) flee = flee / mag; // normaliser le vecteur de fuite
      }

  // combiner: errance + recentrage + évitement bords + anti-corner + fuite des fourmis
  Offset blended = dir * 0.70 + centerPull * 0.45 + boundarySteer * 0.90 + cornerAvoid * 0.95 + flee * 1.15;
      final double m = blended.distance;
      if (m > 1e-6) blended = blended / m;
      _mDir = blended;

      final double speedMul = _biteSlowT > 0 ? 0.55 : 1.0; // ralentir pendant le slow
      _mHead += _mDir * (_mSpeed * speedMul) * dt;
      // clamp final (sécurité, rarement déclenché)
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

  // interactions: désactivées — le serpent ne mange plus les fourmis dans le menu
      // Dégâts des fourmis: si une fourmi touche un segment, réduire la longueur (HP)
      if (_dmgCooldown <= 0) {
        const double biteR = 8.0; // rayon d'impact légèrement plus grand
        const double biteR2 = biteR * biteR;
        bool gotBitten = false;
        // tester tête + segments
        for (final ant in _ants) {
          final Offset dvh = ant.p - _mHead;
          if (dvh.dx * dvh.dx + dvh.dy * dvh.dy <= biteR2) { gotBitten = true; break; }
          for (int i = 1; i < _segments.length; i++) {
            final Offset dvs = ant.p - _segments[i];
            if (dvs.dx * dvs.dx + dvs.dy * dvs.dy <= biteR2) { gotBitten = true; break; }
          }
          if (gotBitten) break;
        }
        if (gotBitten) {
          if (_snakeHp > 1) {
            _snakeHp = max(1, _snakeHp - 1);
            _segments.removeRange(min(_segments.length, _snakeHp), _segments.length);
          } else {
            // Dernière morsure: mort de la tête
            _snakeHp = 0;
            _snakeAlive = false;
            _respawnT = 9999; // ne pas respawn dans le menu
          }
          _dmgCooldown = 0.35;
          // appliquer un ralentissement temporaire
          _biteSlowT = 1.2; // ralenti pendant 1.2s
        }
      }
  } else if (!_snakeAlive) {
      _respawnT -= dt;
      if (_respawnT <= 0) {
        if (_disableRespawn) {
          // Rester sans serpent mais continuer à mettre à jour la scène
        } else {
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
          // Construire les textures pré-rendues (herbe + canopée)
          _buildCachedTextures();
  }
      }
    }

  // falling apples update + occasional spawn (désactivé pendant la scénette)
  if (_scene >= 4 && _falling.length < 6 && _rng.nextDouble() < 0.25 * dt) {
      // Spawn proche du haut de la canopée (comme avant)
      final ang = _rng.nextDouble() * pi * 2;
      final rr = _canopyR * (0.2 + _rng.nextDouble() * 0.6);
      final start = _canopyCenter + Offset(cos(ang) * rr, sin(ang) * rr * 0.6);
      final vx = (_rng.nextDouble() * 40 - 20);
      _falling.add(_FallingApple(p: start, v: Offset(vx, -10), spin: _rng.nextDouble() * 6.283));
    }
  final double groundY = _groundTop - 3; // surface herbe (haut de l'herbe)
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
          // On ne déplace plus le tronc/canopée dynamiquement
        }
      }
    }

  // fireflies: déplacement erratique 2D (décimation d'update pour réduire le coût)
    const double fireflyStep = 1.0 / 45.0; // ~45 Hz
    _fireflyAcc += dt;
    final bool doUpdateFireflies = _fireflyAcc >= fireflyStep;
    if (doUpdateFireflies) _fireflyAcc -= fireflyStep;

    // Danse de paire: de temps en temps, deux lucioles proches tournent ensemble puis se séparent
    if (_flies.length >= 2 && _rng.nextDouble() < min(0.5 * dt, 0.02)) {
      // choisir une luciole non appariée
      final int i = _rng.nextInt(_flies.length);
      if (!_flies[i].pairing && _flies[i].pairWith == -1) {
        // trouver une voisine proche
        int j = -1; double best = 9999999;
        for (int k = 0; k < _flies.length; k++) {
          if (k == i) continue;
          if (_flies[k].pairing || _flies[k].pairWith != -1) continue;
          final double d2 = (_flies[k].p - _flies[i].p).distanceSquared;
          if (d2 < best) { best = d2; j = k; }
        }
        if (j != -1 && best < 80 * 80) {
          final Offset mid = (_flies[i].p + _flies[j].p) * 0.5;
          final double rad = 10 + _rng.nextDouble() * 12;
          final double omega = (_rng.nextBool() ? 1 : -1) * (1.8 + _rng.nextDouble() * 1.8);
          final double dur = 1.2 + _rng.nextDouble() * 1.0;
          _flies[i].pairing = true; _flies[i].pairWith = j; _flies[i].pairT = dur; _flies[i].pairCenter = mid; _flies[i].pairOmega = omega;
          _flies[j].pairing = true; _flies[j].pairWith = i; _flies[j].pairT = dur; _flies[j].pairCenter = mid; _flies[j].pairOmega = omega;
          // aligner phases opposées pour la rotation
          _flies[j].phase = _flies[i].phase + pi;
          // léger ajustement positions initiales
          _flies[i].p = mid + Offset(rad, 0);
          _flies[j].p = mid - Offset(rad, 0);
        }
      }
    }

    for (int i = 0; i < _flies.length; i++) {
      final f = _flies[i];
      // phase pour bruit pseudo-aléatoire et scintillement
      f.phase += dt * f.localSpeed;
      if (!doUpdateFireflies) continue; // sauter l'intégration positionnelle cette frame

      // gérer la durée de la danse en paire
      if (f.pairing) {
        f.pairT -= dt;
        if (f.pairT <= 0) {
          final int j = f.pairWith;
          f.pairing = false;
          f.pairWith = -1;
          f.pairT = 0;
          if (j >= 0 && j < _flies.length) {
            final g = _flies[j];
            g.pairing = false;
            g.pairWith = -1;
            g.pairT = 0;
          }
        }
      }

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

      // force principale
      Offset toT;
      if (f.pairing) {
        // orbitage autour du centre partagé
        Offset toC = f.p - f.pairCenter;
        double r = toC.distance;
        if (r < 0.001) {
          // éviter une tangente indéfinie
          toC = const Offset(1, 0);
          r = 1;
        }
        final Offset tangent = Offset(-toC.dy / r, toC.dx / r) * (f.pairOmega * 12.0);
        final Offset keep = (f.pairCenter - f.p) * 4.0; // attraction douce vers le centre
        toT = tangent + keep;
      } else {
        toT = f.target - f.p;
        final double d = toT.distance;
        if (d > 0.001) {
          toT = toT / d * 12.0;
        } else {
          toT = Offset.zero; // ~px/s^2
        }
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

  // contrainte: rester DANS une grande ellipse englobante de la canopée (beaucoup plus large)
  final double rx = _fireflyRx(); // demi-axe horizontal
  final double ry = _fireflyRy(); // demi-axe vertical
    Offset rel = p - _canopyCenter;
    double norm = (rel.dx * rel.dx) / (rx * rx) + (rel.dy * rel.dy) / (ry * ry);
    if (norm > 1.0) {
      final double k = 1 / sqrt(norm);
      final Offset newPos = _canopyCenter + Offset(rel.dx * k, rel.dy * k);
      // normale de l'ellipse: gradient de x^2/rx^2 + y^2/ry^2 - 1 = 0
      Offset nrm = Offset(rel.dx / (rx * rx), rel.dy / (ry * ry));
      final double nlen = nrm.distance == 0 ? 1 : nrm.distance;
      nrm = nrm / nlen;
      final double vn = f.v.dx * nrm.dx + f.v.dy * nrm.dy;
      f.v = f.v - nrm * (vn * 1.4);
      p = newPos;
    }

  // (ancienne contrainte union-de-blobs supprimée)

  // éviter la terre tout en respectant l'ellipse d'aire verticale
  final double minY = max(0.0, _canopyCenter.dy - _fireflyRy());
  final double maxY = min(size.y - _soilH - 12, _canopyCenter.dy + _fireflyRy());
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
    for (final cl in _farClouds) {
      cl.pos = cl.pos.translate(cl.speed * dt, 0);
      if (cl.pos.dx - cl.r * 2 > size.x) {
        cl.pos = Offset(-cl.r * 2, cl.pos.dy);
      }
    }
    for (final cl in _clouds) {
      cl.pos = cl.pos.translate(cl.speed * dt, 0);
      if (cl.pos.dx - cl.r * 2 > size.x) {
        cl.pos = Offset(-cl.r * 2, cl.pos.dy);
      }
    }

  // Cooldowns morsure / étourdissement
    if (_eatCooldown > 0) _eatCooldown = max(0, _eatCooldown - dt);
    if (_eatStunT > 0) {
      _eatStunT = max(0, _eatStunT - dt);
      // On n'arrête plus la frame; le bloc de mouvement du serpent va simplement s'auto-désactiver.
    }

  // (la FSM a été gérée en début de frame)

  // Ajuster la population de lucioles: +30% la nuit, -0% le jour
    {
      final double theta = _t * 2 * pi;
      final double dayAmt = 0.5 + 0.5 * sin(theta);
      final double nightAmt = 1.0 - dayAmt;
      final int desired = (_baseFireflyCount * (1.0 + 0.30 * nightAmt)).round();
      if (_flies.length < desired && _rng.nextDouble() < min(3.0 * dt, 0.5)) {
  // spawn 1 luciole uniforme dans la canopée visible
  final Offset base = _sampleLeafPoint();
        final f = _Firefly(
          p: base + Offset(_rng.nextDouble() * 30 - 15, _rng.nextDouble() * 20 - 10),
          phase: _rng.nextDouble() * pi * 2,
          speed: 0.6 + _rng.nextDouble() * 0.8,
        );
        f.localSpeed = 1.0 + _rng.nextDouble() * 1.6;
        f.maxSpd = 24.0 + _rng.nextDouble() * 36.0;
        f.jitter = 30.0 + _rng.nextDouble() * 45.0;
        f.damping = 1.2 + _rng.nextDouble() * 1.2;
        f.v = Offset(_rng.nextDouble() * 10 - 5, _rng.nextDouble() * 10 - 5);
        f.target = _sampleLeafPoint();
        f.targetDur = 2.0 + _rng.nextDouble() * 3.0;
        _flies.add(f);
      } else if (_flies.length > desired && _rng.nextDouble() < min(2.0 * dt, 0.4)) {
        // retirer en douceur
        _flies.removeLast();
      }
    }
  }

  // Paramètres ellipse d'aire des lucioles (très large)
  double _fireflyRx() => _canopyR * 1.85;
  double _fireflyRy() => _canopyR * 1.70;

  // Échantillonner uniformément dans une grande ellipse englobant la canopée
  Offset _sampleLeafPoint() {
    final double rx = _fireflyRx();
    final double ry = _fireflyRy();
    final double a = _rng.nextDouble() * pi * 2;
    final double r = sqrt(_rng.nextDouble()); // uniforme en aire sur le disque unité
    return _canopyCenter + Offset(cos(a) * rx * r, sin(a) * ry * r);
  }

  // (anciens helpers union-de-blobs supprimés; ellipse englobante utilisée à la place)

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

  // Twinkling stars crossfaded by nightAmt (no abrupt pop); skip when quasi-jour
    if (nightAmt > 0.05) {
      for (final s in _stars) {
        final a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * s.speed + s.phase));
        final Paint p = Paint()..color = Colors.white.withValues(alpha: a * (nightAmt * nightAmt));
        canvas.drawCircle(s.pos, s.radius, p);
      }
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
  // Couleur du ciel au niveau Y pour occlure les étoiles sous le soleil
  final Color skyBottom = Color.lerp(const Color(0xFF0D47A1), const Color(0xFF061126), nightAmt)!;
  final Color skyTop = Color.lerp(const Color(0xFF90CAF9), const Color(0xFF0B1530), nightAmt)!;
  double vSun = (_groundTop - sp.dy) / _groundTop; vSun = vSun.clamp(0.0, 1.0);
  final Color skyAtSun = Color.lerp(skyBottom, skyTop, vSun)!;
  canvas.drawCircle(sp, sunR, Paint()..color = skyAtSun);
  // Disque solaire avec estompage (alpha selon dayAmt) rendu au-dessus
  final Paint body = Paint()
    ..shader = ui.Gradient.radial(sp, sunR, const [Color(0xFFFFF176), Color(0xFFFFC107)], const [0, 1])
    ..colorFilter = ui.ColorFilter.mode(Colors.white.withValues(alpha: dayAmt.clamp(0.0, 1.0)), BlendMode.modulate);
  canvas.drawCircle(sp, sunR, body);

    // lune en opposition de phase
  const double moonR = 13.0;
    final Offset mp = c + Offset(cos(theta + pi) * rx, -sin(theta + pi) * ry);
  // Halo (estompage par nightAmt)
  final Paint mHalo = Paint()
      ..shader = ui.Gradient.radial(mp, moonR * 2.4, [const Color(0xFFB3E5FC).withValues(alpha: 0.28 * nightAmt), Colors.transparent], const [0, 1]);
  canvas.drawCircle(mp, moonR * 2.4, mHalo);
  // Occlusion étoiles sous la lune avec la couleur du ciel à cette hauteur
  double vMoon = (_groundTop - mp.dy) / _groundTop; vMoon = vMoon.clamp(0.0, 1.0);
  final Color skyAtMoon = Color.lerp(skyBottom, skyTop, vMoon)!;
  canvas.drawCircle(mp, moonR, Paint()..color = skyAtMoon);
  // Disque lunaire avec estompage par nightAmt
  canvas.drawCircle(mp, moonR, Paint()..color = const Color(0xFFE0E6EA).withValues(alpha: nightAmt));

    // Nuages lointains (plus flous, alpha réduit la nuit) — dessinés d'abord
    for (final cl in _farClouds) {
      final double a = (0.10 + 0.38 * dayAmt).clamp(0.08, 0.50);
      final Paint cp = Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: cl.r * 0.20, sigmaY: cl.r * 0.20)
        ..color = const Color(0xFFF5F7FA).withValues(alpha: a);
      canvas.drawCircle(cl.pos.translate(-cl.r * 0.7, -cl.r * 0.1), cl.r * 0.95, cp);
      canvas.drawCircle(cl.pos, cl.r * 1.15, cp);
      canvas.drawCircle(cl.pos.translate(cl.r * 0.7, -cl.r * 0.05), cl.r * 0.9, cp);
    }

    // Nuages visibles jour et nuit (alpha réduit la nuit)
    for (final cl in _clouds) {
      final double a = (0.18 + 0.55 * dayAmt).clamp(0.12, 0.85);
      final Paint cp = Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: cl.r * 0.08, sigmaY: cl.r * 0.08)
        ..color = const Color(0xFFF5F7FA).withValues(alpha: a);
      // forme blobby (plusieurs cercles)
      canvas.drawCircle(cl.pos.translate(-cl.r * 0.6, 0), cl.r * 0.8, cp);
      canvas.drawCircle(cl.pos, cl.r, cp);
      canvas.drawCircle(cl.pos.translate(cl.r * 0.6, 0), cl.r * 0.75, cp);
      // (ombre douce retirée des nuages)
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
    // Dessiner la texture d'herbe pré-rendue (si disponible)
    if (_grassTexPic != null && _grassTexRect != null) {
      canvas.save();
      canvas.translate(_grassTexRect!.left, _grassTexRect!.top);
      canvas.drawPicture(_grassTexPic!);
      canvas.restore();
    }
  // bande lumineuse directionnelle retirée pour un rendu plus plat sous les fourmis
  // plus de besoin de direction de lumière pour le feuillage (ombres statiques supprimées)

  // bande de terre
    final Rect soil = Rect.fromLTWH(0, size.y - _soilH, size.x, _soilH);
    final Paint soilPaint = Paint()
      ..shader = ui.Gradient.linear(
        soil.topLeft, soil.bottomLeft,
        [const Color(0xFF6D4C41), const Color(0xFF4E342E)],
        const [0.0, 1.0],
      );
    canvas.drawRect(soil, soilPaint);
  // décor de sol: utiliser l'image pré-rendue si dispo
  if (_soilDecorPic != null) {
    canvas.drawPicture(_soilDecorPic!);
  } else {
    // fallback: rendu direct (plus coûteux)
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(soil.left, soil.top + 4, soil.width, soil.height - 4));
    for (final it in _soilItems) {
      it.render(canvas);
    }
    canvas.restore();
  }
  // suppression de l'ombre du bord d'herbe sur la terre

  // (Les touffes d'herbe seront dessinées en tout premier plan, plus bas)

  // décor statique (tronc + racines + fourmilière) pré-rendu
  // Rebuild décor statique si la fourmilière a changé (position/rayon)
  if (_staticDecorPic == null || _staticKeyHillPos != _hillPos || _staticKeyHillR != _hillR) {
    _staticDecorPic = _makeStaticDecorPicture();
    _staticKeyHillPos = _hillPos;
    _staticKeyHillR = _hillR;
    // S'assurer que les fourmis orbitent autour de la nouvelle position
    for (final a in _ants) {
      if (a.orbiting) a.orbitCenter = _hillPos;
    }
  }
  canvas.drawPicture(_staticDecorPic!);

  // feuillage (multi-nappes) — couvre bien le haut du tronc (utilise les valeurs calculées)
  final double shake = _shakeT > 0 ? (sin(_time * 18.0) * _shakeT * 3.0) : 0.0;
  final canopyCenter = _canopyCenter.translate(shake * 0.4, shake);
  final canopyR = _canopyR;
  // Pendant la phase 0 de descente, dessiner le serpent sous la canopée pour éviter l'effet "dans les airs"
  final bool snakeUnderCanopyNow = _snakeAlive && _scene == 2 && _snakeDescendT > 0 && _snakeDescendPhase == 0;
  if (snakeUnderCanopyNow) {
    _renderSnake(canvas, sp);
  }
  // nappes de feuillage: utiliser l'image pré-rendue si dispo
  if (_canopyBlobsPic != null) {
    final Rect canopyBlobsRect = Rect.fromCircle(center: canopyCenter, radius: canopyR * 1.05);
    canvas.save();
    canvas.translate(canopyBlobsRect.left, canopyBlobsRect.top);
    canvas.drawPicture(_canopyBlobsPic!);
    canvas.restore();
  } else {
    // fallback: dessiner les blobs directement
    void blob(Offset c, double r, List<Color> colors) {
      final p = Paint()
        ..shader = ui.Gradient.radial(c.translate(-r * 0.2, -r * 0.15), r, colors, const [0.0, 1.0]);
      canvas.drawCircle(c, r, p);
    }
    blob(canopyCenter, canopyR * 1.00, const [Color(0xFF66BB6A), Color(0xFF2E7D32)]);
    blob(canopyCenter.translate(-canopyR * 0.35, -canopyR * 0.12), canopyR * 0.78, const [Color(0xFF81C784), Color(0xFF388E3C)]);
    blob(canopyCenter.translate(canopyR * 0.36, -canopyR * 0.08), canopyR * 0.74, const [Color(0xFF81C784), Color(0xFF2E7D32)]);
    blob(canopyCenter.translate(0, canopyR * 0.05), canopyR * 0.56, const [Color(0xFFA5D6A7), Color(0xFF43A047)]);
  }
  // Texture de feuilles retirée (plus de motif par-dessus la canopée)
  // (surbrillance/ombre statiques du feuillage supprimées pour retirer l'ombre des feuilles)

  // fourmilière déjà incluse dans le décor statique

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
    // shadow pilotée par le soleil (directionnelle)
    final Offset ldirA = (center - sp);
    final double dlA = ldirA.distance == 0 ? 1 : ldirA.distance;
    final Offset nvA = Offset(ldirA.dx / dlA, ldirA.dy / dlA);
  final Rect appleShadow = Rect.fromCenter(center: center + nvA * 4.0, width: r * 2.8, height: r * 1.3);
  canvas.drawOval(appleShadow, Paint()..color = Colors.black.withValues(alpha: 0.22 * dayAmt));
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

  // serpent façon in-game (dessin du trail) — arrière-plan
  if (!snakeUnderCanopyNow) {
    _renderSnake(canvas, sp);
  }

  // fourmis — sous les fleurs et les touffes (masquées par la végétation)
  for (final a in _ants) {
      // ombre directionnelle en fonction du soleil
      final Offset ldir = (a.p - sp);
      final double dl = ldir.distance == 0 ? 1 : ldir.distance;
      final Offset nv = Offset(ldir.dx / dl, ldir.dy / dl);
  final Rect antShadow = Rect.fromCenter(center: a.p + nv * 3.2, width: 14, height: 4.6);
  canvas.drawOval(antShadow, Paint()..color = Colors.black.withValues(alpha: 0.28 * dayAmt));
      final ang = a.dir;
      canvas.save();
      canvas.translate(a.p.dx, a.p.dy);
      canvas.rotate(ang);
      final body = Paint()..color = const Color(0xFF4E342E);
      canvas.drawCircle(const Offset(-6, 0), 3.8, body);
      canvas.drawCircle(const Offset(0, 0), 3.2, body);
      canvas.drawCircle(const Offset(6, 0), 2.7, body);
  final Offset ap = a.p;
  final Offset ldirAnt = (ap - sp);
  final double d = ldirAnt.distance == 0 ? 1 : ldirAnt.distance;
  final Offset n = Offset(ldirAnt.dx / d, ldirAnt.dy / d);
      canvas.drawCircle(n * -2.5, 1.0, Paint()..color = Colors.white.withValues(alpha: 0.22 * dayAmt));
      final leg = Paint()
        ..color = const Color(0xFF3E2723)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (int i = -1; i <= 1; i++) {
        final double ox = i * 4.0;
        canvas.drawLine(Offset(ox, 0), Offset(ox - 3, 3), leg);
        canvas.drawLine(Offset(ox, 0), Offset(ox + 3, 3), leg);
      }
      canvas.restore();
    }

  // touffes d'herbe en deuxième plan (dessinées avant les fleurs pour que les fleurs passent au-dessus)
  _drawTufts(canvas, sp, dayAmt);

  // fleurs — au-dessus des touffes
    for (int i = 0; i < _flowers.length; i++) {
      final c = _flowers[i];
      final col = _flowerColors[i];
  // Ombre directionnelle au sol de la fleur
  final Offset ldirF = (c - sp);
  final double dlF = ldirF.distance == 0 ? 1 : ldirF.distance;
  final Offset nvF = Offset(ldirF.dx / dlF, ldirF.dy / dlF);
  final Rect flowerShadow = Rect.fromCenter(center: c.translate(0, 4) + nvF * 2.4, width: 10, height: 3.0);
  canvas.drawOval(flowerShadow, Paint()..color = Colors.black.withValues(alpha: 0.20 * dayAmt));
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

  // lucioles (au-dessus du décor). Visible surtout la nuit — halo doux (cosmétique halo boost optionnel)
    if (nightAmt > 0) {
      final bool haloBoost = PlayerProfile.instance.haloFireflies;
      for (final f in _flies) {
        final glow = 0.5 + 0.5 * sin(_time * 3.0 + f.phase);
        final double coreA = (0.25 * nightAmt + 0.45 * glow * nightAmt).clamp(0.0, 0.85);
        final double haloA = ((0.08 + (haloBoost ? 0.06 : 0.0)) * nightAmt + (0.20 + (haloBoost ? 0.10 : 0.0)) * glow * nightAmt).clamp(0.0, 0.5);
        // halo large et très doux
        final double r = haloBoost ? 13 : 10;
        canvas.drawCircle(f.p, r, Paint()..color = const Color(0xFFFFF59D).withValues(alpha: haloA));
        // coeur
        canvas.drawCircle(f.p, 2.6, Paint()..color = const Color(0xFFFFF59D).withValues(alpha: coreA));
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
  // Scripted orbit params (menu scene)
  bool orbiting;
  Offset orbitCenter;
  double orbitR;
  double orbitEccY; // ellipse vertical scaling
  double orbitOmega; // angular speed (rad/s), sign=direction
  double orbitPhase;
  bool isAttacking;
  // Emerging state: ants coming out of the hill then blending into orbit
  bool emerging;
  Offset emergeDir;
  double emergeT;
  double emergeDur;
  // Attack targeting: choose a specific segment index on the snake body
  int attackTargetSegIdx;
  double retargetT;
  // Origin flag: true for ants spawned by the apple-impact burst
  bool fromBurst;
  _MAnt({required this.p, required this.dir, required this.speed})
      : orbiting = false,
        orbitCenter = Offset.zero,
        orbitR = 0,
        orbitEccY = 1,
        orbitOmega = 1,
        orbitPhase = 0,
        isAttacking = false,
        emerging = false,
        emergeDir = const Offset(1, 0),
        emergeT = 0.0,
        emergeDur = 0.0,
        attackTargetSegIdx = -1,
  retargetT = 0.0,
  fromBurst = false;
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
  int v; // index de variante picture
  _Tuft(this.p, this.s, this.v);
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
        // Pierre polygonale irrégulière avec léger ombrage
        final int sides = 6 + (size * 0.6).clamp(0, 3).toInt(); // 6..9 côtés
        final Path poly = Path();
        final double baseR = size * 0.9;
        final double tilt = (rot + 0.8) % (pi * 2);
        for (int i = 0; i < sides; i++) {
          final double a = tilt + i * (2 * pi / sides);
          final double rr = baseR * (0.85 + (i % 2 == 0 ? 0.20 : 0.10));
          final Offset v = Offset(cos(a) * rr * ex, sin(a) * rr);
          final Offset p = pos + v;
          if (i == 0) poly.moveTo(p.dx, p.dy); else poly.lineTo(p.dx, p.dy);
        }
        poly.close();
        // Remplissage
        canvas.drawPath(poly, Paint()..color = color);
        // Ombrage latéral (simple)
        final Paint edge = Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawPath(poly, edge);
        // Facettes internes
        final Paint facet = Paint()..color = Colors.white.withValues(alpha: 0.05);
        final Rect bounds = poly.getBounds();
        final Offset c = bounds.center;
        final Path facet1 = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(bounds.left + bounds.width * 0.25, bounds.top + bounds.height * 0.55)
          ..lineTo(bounds.left + bounds.width * 0.55, bounds.top + bounds.height * 0.25)
          ..close();
        canvas.drawPath(facet1, facet);
        final Path facet2 = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(bounds.right - bounds.width * 0.20, bounds.top + bounds.height * 0.35)
          ..lineTo(bounds.left + bounds.width * 0.65, bounds.bottom - bounds.height * 0.15)
          ..close();
        canvas.drawPath(facet2, facet);
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
  // pairing temporaire
  bool pairing;
  int pairWith; // index de l'autre luciole, -1 si aucun
  double pairT; // temps restant de la danse
  Offset pairCenter;
  double pairOmega;

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
        v = Offset.zero,
        pairing = false,
        pairWith = -1,
        pairT = 0.0,
        pairCenter = Offset.zero,
        pairOmega = 0.0;

}

// Projection helper for canopy boundary response
// FSM du menu: extrait pour exécuter au début de update
extension _MenuScene on GardenMenuGame {
  void _updateScene(double dt) {
    if (!_sceneInit) {
      _sceneInit = true;
      _scene = 0;
      _sceneTimer = 0.0;
      _disableRespawn = true; // empêcher le respawn avant l'apparition scriptée
      _scriptAppleIdx = null;
      _sceneAntsSpawned = false;
    }
    _sceneTimer += dt;
    switch (_scene) {
      case 0:
        if (_scriptAppleIdx == null) {
          // Revenir au spawn d'avant: un point plausible sous la canopée
          final ang = _rng.nextDouble() * pi * 2;
          final rr = _canopyR * (0.2 + _rng.nextDouble() * 0.6);
          final start = _canopyCenter + Offset(cos(ang) * rr, -_canopyR * 0.2);
          final vx = (_rng.nextDouble() * 20 - 10);
          _falling.add(_FallingApple(p: start, v: Offset(vx, 0), spin: _rng.nextDouble() * 6.283));
          _scriptAppleIdx = _falling.length - 1;
        }
        if (_sceneTimer > 1.0) {
          _scene = 1;
          _sceneTimer = 0.0;
        }
        break;
      case 1:
        if (_scriptAppleIdx != null && _scriptAppleIdx! < _falling.length) {
          final fa = _falling[_scriptAppleIdx!];
          if (fa.rest) {
            // Ligne droite vers l'entrée de la fourmilière (légèrement à gauche du trou)
            final Offset target = _hillPos.translate(-_hillR * 0.9, -_hillR * 0.05);
            final Offset toT = target - fa.p;
            final double d = toT.distance;
            if (d > 1.0) {
              const double rollSpeed = 80.0; // px/s (encore un peu plus rapide)
              final Offset step = toT / d * (rollSpeed * dt);
              Offset next = fa.p + step;
              if ((next - target).distance > d) next = target; // pas de dépassement
              fa.p = next; // pas de clamp Y -> vraie ligne droite
            } else {
              _sceneApplePos = fa.p;
              // Attendre 1s avant de faire apparaître le serpent
              _snakeAppearDelay = 1.0;
              // Burst de fourmis sortant de la fourmilière (échelonné)
              _burstToSpawn = 5 + _rng.nextInt(4); // 5..8
              _burstSpawnInterval = 0.25 + _rng.nextDouble() * 0.35; // 0.25..0.6s
              _burstSpawnTimer = 0.1; // légère latence avant la première sortie
              _scene = 2;
              _sceneTimer = 0.0;
            }
          }
        } else {
          // Récupération: si l'index est invalide (rare), on recrée une pomme scriptée et on reste en scène 1
          final ang = _rng.nextDouble() * pi * 2;
          final rr = _canopyR * (0.2 + _rng.nextDouble() * 0.6);
          final start = _canopyCenter + Offset(cos(ang) * rr, -_canopyR * 0.2);
          final vx = (_rng.nextDouble() * 20 - 10);
          _falling.add(_FallingApple(p: start, v: Offset(vx, 0), spin: _rng.nextDouble() * 6.283));
          _scriptAppleIdx = _falling.length - 1;
        }
        break;
      case 2:
        // Apparition du serpent avec délai de 1s après l'arrivée de la pomme
        if (_snakeAppearDelay > 0) {
          _snakeAppearDelay = max(0.0, _snakeAppearDelay - dt);
          if (_snakeAppearDelay == 0.0 && !_snakeAlive) {
            _snakeHp = _snakeMaxHp;
            // Rester invisibile visuellement pendant la phase feuilles (rendu sous canopée)
            _snakeAlive = true;
            // Points clés du chemin (canopée -> tronc -> sol -> herbe)
            final double trunkW = _treeHeight * 0.14;
            final Offset trunkTop = _treeBase - Offset(0, _treeHeight * 0.82);
            // spawn sur la canopée (bord des feuilles) proche de l'axe du tronc
            final double startAng = -pi / 2 + (_rng.nextBool() ? -0.5 : 0.5);
            // Départ précisément sur le bord intérieur de la canopée
            final Offset p0 = _canopyCenter + Offset(cos(startAng) * _canopyR * 0.85, sin(startAng) * _canopyR * 0.85);
            // point d'accroche proche du haut du tronc (contrôle Bezier)
            final Offset p1 = Offset(ui.lerpDouble(p0.dx, trunkTop.dx, 0.6)!, ui.lerpDouble(p0.dy, trunkTop.dy, 0.6)! - trunkW * 0.2);
            final Offset p2 = trunkTop.translate(0, trunkW * 0.20);
            final Offset p3 = _treeBase.translate(0, -10);
            // petite sortie sur l'herbe, côté aléatoire
            final double side = _rng.nextBool() ? 1.0 : -1.0;
            final Offset p4 = _treeBase.translate(side * max(36.0, trunkW * 1.8), -8);
            _snakeP0 = p0; _snakeP1 = p1; _snakeP2 = p2; _snakeP3 = p3; _snakeP4 = p4;
            // position initiale: feuilles
            _mHead = p0;
            final Offset initDirV = _snakeP2! - _snakeP0!;
            final double initDirLen = initDirV.distance == 0 ? 1.0 : initDirV.distance;
            _mDir = Offset(initDirV.dx / initDirLen, initDirV.dy / initDirLen);
            _segments
              ..clear()
              ..addAll(List.generate(_snakeHp, (i) => _mHead - _mDir * (_trailSpacing * i)));
            // préparer les phases: feuilles->tronc, tronc, herbe
            _snakePhaseDur0 = 0.9; // Bezier sur les feuilles
            _snakePhaseDur1 = 1.2; // glisse tronc
            _snakePhaseDur2 = 0.6; // petite sortie herbe
            _snakeDescendPhase = 0;
            _snakeDescendDur = _snakePhaseDur0;
            _snakeDescendT = _snakeDescendDur;
          }
        }
          if (_snakeDescendT > 0 && _snakeAlive) {
          final double t = (_snakeDescendDur - _snakeDescendT) / (_snakeDescendDur <= 0 ? 1.0 : _snakeDescendDur);
          // easing doux (easeInOutCubic)
          double te;
          if (t < 0.5) {
            te = 4 * t * t * t;
          } else {
            final double u = 2 * t - 2;
            te = 0.5 * u * u * u + 1;
          }
          Offset newHead = _mHead;
          if (_snakeDescendPhase == 0 && _snakeP0 != null && _snakeP1 != null && _snakeP2 != null) {
            // Bezier quadratique feuilles -> haut du tronc
            final Offset a = _snakeP0!;
            final Offset b = _snakeP1!;
            final Offset c = _snakeP2!;
            final double s = 1.0 - te;
            newHead = a * (s * s) + b * (2 * s * te) + c * (te * te);
          } else if (_snakeDescendPhase == 1 && _snakeP2 != null && _snakeP3 != null) {
            // glisse verticale le long du tronc avec légère ondulation
            final Offset start = _snakeP2!;
            final Offset end = _snakeP3!;
            final double swayAmp = (_treeHeight * 0.14) * 0.12;
            final double sway = sin(te * pi * 1.5) * swayAmp * (1.0 - te);
            final double y = ui.lerpDouble(start.dy, end.dy, te)!;
            final double x = _treeBase.dx + sway;
            newHead = Offset(x, y);
          } else if (_snakeDescendPhase == 2 && _snakeP3 != null && _snakeP4 != null) {
            // petite sortie sur l'herbe
            final Offset start = _snakeP3!;
            final Offset end = _snakeP4!;
            newHead = Offset(ui.lerpDouble(start.dx, end.dx, te)!, ui.lerpDouble(start.dy, end.dy, te)!);
          }
          // orienter la tête vers le mouvement
          final Offset delta = newHead - _mHead;
          final double d = delta.distance;
          if (d > 0.0001) {
            _mDir = delta / d;
          }
          _mHead = newHead;
          _segments
            ..clear()
            ..addAll(List.generate(_snakeHp, (i) => _mHead - _mDir * (_trailSpacing * i)));
          _snakeDescendT = max(0.0, _snakeDescendT - dt);
          // phase suivante
          if (_snakeDescendT == 0.0) {
            _snakeDescendPhase += 1;
            if (_snakeDescendPhase == 1) {
              _snakeDescendDur = _snakePhaseDur1; _snakeDescendT = _snakeDescendDur;
            } else if (_snakeDescendPhase == 2) {
              _snakeDescendDur = _snakePhaseDur2; _snakeDescendT = _snakeDescendDur;
            } else {
              // fin du script: libérer l'errance
              _snakeDescendDur = 0.0;
              _snakeDescendT = 0.0;
            }
          }
        }
        // Ne faire sortir les fourmis que lorsque la pomme a atteint sa position finale
        if (!_sceneAntsSpawned && _sceneTimer > 0.1 && _sceneApplePos != null) {
          _sceneAntsSpawned = true;
          // Les fourmis orbitent autour de la fourmilière, pas autour de la pomme
          final Offset center = _hillPos;
          for (int i = 0; i < 10; i++) {
            final double phase = (i / 10.0) * 2 * pi + _rng.nextDouble() * 0.6;
            final double r = (_hillR * 1.1) + _rng.nextDouble() * (_hillR * 0.7);
            const double eccY = 0.6;
            final double omega = (_rng.nextBool() ? 1.0 : -1.0) * (0.6 + _rng.nextDouble() * 0.6);
            final Offset pos = center + Offset(cos(phase) * r, sin(phase) * r * eccY);
            final ant = _MAnt(
              p: pos,
              dir: phase + pi / 2,
              speed: 16 + _rng.nextDouble() * 20,
            );
            ant.orbiting = true;
            ant.orbitCenter = center;
            ant.orbitR = r;
            ant.orbitEccY = eccY;
            ant.orbitOmega = omega;
            ant.orbitPhase = phase;
            _ants.add(ant);
          }
        }
        if (_sceneTimer > 1.5) {
          // Aller directement à l'état final sans tuer le serpent
          _scene = 4;
          _sceneTimer = 0.0;
        }
        break;
      case 3:
        // Scène de transition (plus de mort forcée)
        _disableRespawn = true;
        if (_sceneTimer > 0.5) {
          _scene = 4;
          _sceneTimer = 0.0;
        }
        break;
      case 4:
        _disableRespawn = true;
        // Maintenir un anneau d'orbite pour les fourmis non-burst; laisser les burst errer indéfiniment
        for (final a in _ants) {
          if (!a.fromBurst) {
            a.orbiting = true;
            a.orbitCenter = _hillPos;
            if (a.orbitR == 0) {
              a.orbitR = (_hillR * 1.1) + _rng.nextDouble() * (_hillR * 0.7);
              a.orbitPhase = _rng.nextDouble() * pi * 2;
              a.orbitOmega = (_rng.nextBool() ? 1.0 : -1.0) * (0.6 + _rng.nextDouble() * 0.6);
              a.orbitEccY = 0.6;
            }
          }
        }
        break;
    }
  }
}

extension _MenuRender on GardenMenuGame {
  void _renderSnake(Canvas canvas, Offset sp) {
    if (!_snakeAlive || _segments.isEmpty || _snakeHp <= 0) return;
    bool clipped = false;
    if (_scene == 2 && _snakeDescendT > 0 && _snakeDescendPhase == 0) {
      final Path canopyClip = Path();
      final Rect canopyOval = Rect.fromCircle(center: _canopyCenter, radius: _canopyR);
      canopyClip.addOval(canopyOval);
      canvas.save();
      canvas.clipPath(canopyClip);
      clipped = true;
    }
    final int count = _segments.length;
    // Resolve cosmetic skin color
    final String skin = PlayerProfile.instance.equippedSnakeSkin ?? 'default';
    Color segColor(int idx, int total) {
      final double t = total <= 1 ? 0.0 : idx / (total - 1);
      switch (skin) {
        case 'skin_neon':
          return Color.lerp(const Color(0xFF00FF88), const Color(0xFF00E676), 1.0 - t)!.withValues(alpha: 0.95);
        case 'skin_red':
          return Color.lerp(const Color(0xFFE53935), const Color(0xFFFF7043), 1.0 - t)!.withValues(alpha: 0.95);
        case 'skin_blue':
          return Color.lerp(const Color(0xFF1E88E5), const Color(0xFF26C6DA), 1.0 - t)!.withValues(alpha: 0.95);
        case 'skin_gold':
          return Color.lerp(const Color(0xFFFFD54F), const Color(0xFFFFB300), 1.0 - t)!.withValues(alpha: 0.98);
        case 'skin_stripes':
          final Color a = const Color(0xFF66BB6A);
          final Color b = const Color(0xFF2E7D32);
          return (idx % 2 == 0 ? a : b).withValues(alpha: 0.96);
        default:
          return Color.lerp(const Color(0xFF2E7D32), const Color(0xFF66BB6A), 1.0 - t)!.withValues(alpha: 0.95);
      }
    }
    for (int i = count - 1; i >= 0; i--) {
      final double t = count <= 1 ? 0.0 : i / (count - 1);
      final double r = 4.5 + 5.0 * (1.0 - t);
      final Offset ldirS = (_segments[i] - sp);
      final double dlS = ldirS.distance == 0 ? 1 : ldirS.distance;
      final Offset nvS = Offset(ldirS.dx / dlS, ldirS.dy / dlS);
      final Rect segShadow = Rect.fromCenter(center: _segments[i] + nvS * 3.0, width: r * 2.0, height: r * 0.9);
      canvas.drawOval(segShadow, Paint()..color = Colors.black.withValues(alpha: 0.24 * 0.9));
      final Color col = segColor(i, count);
      final Offset p = _segments[i];
      canvas.drawCircle(p, r, Paint()..color = col);
      // highlight simple (sans gradient) côté lumière
      final Offset ldir = (p - sp);
      final double d = ldir.distance == 0 ? 1 : ldir.distance;
      final Offset n = Offset(ldir.dx / d, ldir.dy / d);
      canvas.drawCircle(p - n * (r * 0.4), r * 0.35, Paint()..color = Colors.white.withValues(alpha: 0.07));
    }
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
    if (clipped) {
      canvas.restore();
    }
  }
}
// Petites fonctions utilitaires pour dessiner des touffes d'herbe
extension _TuftsRender on GardenMenuGame {
  void _drawTufts(Canvas canvas, Offset sp, double dayAmt) {
    for (final t in _tufts) {
      // ombre simple
      final Offset ldir = (t.p - sp);
      final double dl = ldir.distance == 0 ? 1 : ldir.distance;
      final Offset nv = Offset(ldir.dx / dl, ldir.dy / dl);
  final double shW = (8.0 * t.s).clamp(5.0, 11.0);
  final double shH = (2.6 * t.s).clamp(1.8, 3.2);
  final Rect tuftShadow = Rect.fromCenter(center: t.p.translate(0, -0.6 * t.s) + nv * (0.7 * t.s), width: shW, height: shH);
  canvas.drawOval(tuftShadow, Paint()..color = Colors.black.withValues(alpha: 0.16 * dayAmt));
      // picture de touffe
      if (t.v >= 0 && t.v < _tuftPics.length) {
        canvas.save();
        canvas.translate(t.p.dx, t.p.dy);
        canvas.drawPicture(_tuftPics[t.v]);
        canvas.restore();
      }
    }
  }
}
// End of file
