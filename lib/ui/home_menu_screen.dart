import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../menu_background_game.dart';
import '../state/player_profile.dart';
import '../state/translations.dart';

class HomeMenuScreen extends StatefulWidget {
  const HomeMenuScreen({super.key});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen> with TickerProviderStateMixin {
  late GardenMenuGame bg;
  late AnimationController _buttonAnimController;
  late AnimationController _statsAnimController;
  late AnimationController _rewardPulseController;

  @override
  void initState() {
    super.initState();
    bg = GardenMenuGame();

    // Écouter les changements du profil pour mettre à jour les stats
    PlayerProfile.instance.addListener(_onProfileChanged);

    // Animation des boutons (stagger)
    _buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    // Animation des stats
    _statsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    // Animation de pulsation pour les récompenses non réclamées
    _rewardPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    PlayerProfile.instance.removeListener(_onProfileChanged);
    _buttonAnimController.dispose();
    _statsAnimController.dispose();
    _rewardPulseController.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _resetAnimation() {
    setState(() {
      bg = GardenMenuGame();
      _buttonAnimController.reset();
      _buttonAnimController.forward();
      _statsAnimController.reset();
      _statsAnimController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = PlayerProfile.instance;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final pos = box.globalToLocal(d.globalPosition);
                bg.triggerTapEffect(Offset(pos.dx, pos.dy));
              },
              child: GameWidget(game: bg),
            ),
          ),
          // Settings icon top-left avec animation
          Positioned(
            top: 12,
            left: 12,
            child: FadeTransition(
              opacity: _statsAnimController,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-0.3, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _statsAnimController,
                  curve: Curves.easeOutCubic,
                )),
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.25)),
                  onPressed: () async {
                    await Navigator.of(context).pushNamed('/settings');
                    _resetAnimation();
                  },
                ),
              ),
            ),
          ),
          // Coins avec animation
          Positioned(
            top: 12,
            right: 12,
            child: FadeTransition(
              opacity: _statsAnimController,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.3, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _statsAnimController,
                  curve: Curves.easeOutCubic,
                )),
                child: _AnimatedCoinDisplay(coins: profile.coins),
              ),
            ),
          ),
          // Stats du joueur (niveau + high score) AU-DESSUS du logo
          Positioned(
            top: 70,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _statsAnimController,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.3),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _statsAnimController,
                  curve: Curves.easeOutCubic,
                )),
                child: _PlayerStats(
                  level: profile.level,
                  totalScore: profile.totalScore,
                  rewardPulseController: _rewardPulseController,
                ),
              ),
            ),
          ),
          // Logo placed lower, under stats
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _Logo(),
            ),
          ),
          // Centered buttons avec animations stagger
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedMenuButton(
                      controller: _buttonAnimController,
                      delay: 0.0,
                      label: tr('shop'),
                      icon: Icons.store,
                      onTap: () async {
                        await Navigator.of(context).pushNamed('/shop');
                        _resetAnimation();
                      },
                    ),
                    const SizedBox(height: 10),
                    _AnimatedMenuButton(
                      controller: _buttonAnimController,
                      delay: 0.15,
                      label: tr('skills'),
                      icon: Icons.auto_awesome,
                      onTap: () async {
                        await Navigator.of(context).pushNamed('/skills');
                        _resetAnimation();
                      },
                    ),
                    const SizedBox(height: 14),
                    _AnimatedMenuButton(
                      controller: _buttonAnimController,
                      delay: 0.30,
                      label: tr('play'),
                      icon: Icons.play_arrow,
                      isPrimary: true,
                      onTap: () {
                        Navigator.of(context).pushNamed('/game');
                      },
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    // Titre avec remplissage dégradé et léger contour sombre
  // style inlined in the ShaderMask child
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // ombre/contour léger
            const Text(
              'SNAKE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 64,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: Colors.black54,
              ),
            ),
            // remplissage dégradé par-dessus
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [Color(0xFF9EFF00), Color(0xFF00E676)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: const Text('SNAKE', textAlign: TextAlign.center, style: TextStyle(
                fontSize: 64,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              )),
            ),
          ],
        ),
      ],
    );
  }
}

/// Widget pour afficher les stats du joueur (niveau + high score)
class _PlayerStats extends StatelessWidget {
  final int level;
  final int totalScore;
  final AnimationController rewardPulseController;

  const _PlayerStats({
    required this.level,
    required this.totalScore,
    required this.rewardPulseController,
  });

  bool _hasUnclaimedRewards() {
    final profile = PlayerProfile.instance;
    print('🔍 Vérification des récompenses:');
    print('   - Niveau actuel: ${profile.level}');
    print('   - Récompenses réclamées: ${profile.claimedRewards}');

    for (int i = 1; i <= profile.level; i++) {
      if (!profile.claimedRewards.contains(i)) {
        print('   ⚠️ Récompense niveau $i non réclamée !');
        return true;
      }
    }
    print('   ✅ Toutes les récompenses sont réclamées');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasUnclaimed = _hasUnclaimedRewards();

    return Center(
      child: InkWell(
        onTap: () {
          Navigator.of(context).pushNamed('/rewards');
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Niveau (cliquable) avec pulsation si récompenses disponibles
              AnimatedBuilder(
                animation: rewardPulseController,
                builder: (context, child) {
                  final pulseValue = rewardPulseController.value;
                  return Container(
                    decoration: hasUnclaimed
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Color.lerp(
                                const Color(0xFFFFD700),
                                const Color(0xFFFFA000),
                                pulseValue,
                              )!,
                              width: 2 + pulseValue * 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.4 + pulseValue * 0.4),
                                blurRadius: 12 + pulseValue * 8,
                                spreadRadius: pulseValue * 3,
                              ),
                            ],
                          )
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: hasUnclaimed
                              ? [
                                  Color.lerp(const Color(0xFFFFD700), const Color(0xFFFFA000), pulseValue)!,
                                  Color.lerp(const Color(0xFFFFA000), const Color(0xFFFFD700), pulseValue)!,
                                ]
                              : [const Color(0xFF9EFF00), const Color(0xFF00E676)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasUnclaimed ? Icons.card_giftcard : Icons.star,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Niv. $level',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(width: 12),
            // Total Score
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text('$totalScore', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Widget pour afficher les pièces avec animation
class _AnimatedCoinDisplay extends StatefulWidget {
  final int coins;

  const _AnimatedCoinDisplay({required this.coins});

  @override
  State<_AnimatedCoinDisplay> createState() => _AnimatedCoinDisplayState();
}

class _AnimatedCoinDisplayState extends State<_AnimatedCoinDisplay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(_AnimatedCoinDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coins != oldWidget.coins) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.2);
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                const SizedBox(width: 6),
                Text(
                  '${widget.coins}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bouton de menu avec animation
class _AnimatedMenuButton extends StatefulWidget {
  final AnimationController controller;
  final double delay;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _AnimatedMenuButton({
    required this.controller,
    required this.delay,
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  State<_AnimatedMenuButton> createState() => _AnimatedMenuButtonState();
}

class _AnimatedMenuButtonState extends State<_AnimatedMenuButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const Color accent = Color(0xFF66BB6A);

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: widget.controller,
        curve: Interval(
          widget.delay,
          widget.delay + 0.4,
          curve: Curves.easeOutCubic,
        ),
      )),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: widget.controller,
            curve: Interval(
              widget.delay,
              widget.delay + 0.4,
              curve: Curves.easeOut,
            ),
          ),
        ),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: widget.isPrimary
                      ? accent.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.65),
                  width: widget.isPrimary ? 2 : 1,
                ),
                backgroundColor: widget.isPrimary
                    ? accent.withValues(alpha: 0.20)
                    : Colors.white.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: widget.isPrimary ? 4 : 0,
              ),
              onPressed: () {
                setState(() => _isPressed = true);
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) setState(() => _isPressed = false);
                });
                widget.onTap();
              },
              icon: Icon(
                widget.icon,
                color: Colors.white,
                size: widget.isPrimary ? 28 : 24,
              ),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  widget.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontSize: widget.isPrimary ? 18 : 16,
                        fontWeight: widget.isPrimary ? FontWeight.bold : FontWeight.normal,
                      ) ??
                      TextStyle(
                        fontSize: widget.isPrimary ? 18 : 16,
                        color: Colors.white,
                        fontWeight: widget.isPrimary ? FontWeight.bold : FontWeight.normal,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
