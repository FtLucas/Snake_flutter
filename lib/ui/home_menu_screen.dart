import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../menu_background_game.dart';
import '../state/player_profile.dart';

class HomeMenuScreen extends StatefulWidget {
  const HomeMenuScreen({super.key});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen> {
  final GardenMenuGame bg = GardenMenuGame();

  @override
  Widget build(BuildContext context) {
    final profile = PlayerProfile.instance;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: GameWidget(game: bg)),
          Positioned(
            top: 12,
            right: 12,
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
                  Text('${profile.coins}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          // Logo placed higher, independent from buttons
          Align(
            alignment: const Alignment(0, -0.82),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _Logo(),
              ),
            ),
          ),
          // Centered buttons: Boutique & Skills as before, Play below Skills
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MenuButton(
                      label: 'Boutique',
                      icon: Icons.store,
                      onTap: () async {
                        await Navigator.of(context).pushNamed('/shop');
                        setState(() {}); // refresh coins
                      },
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      label: 'Arbre de compétences',
                      icon: Icons.auto_awesome,
                      onTap: () async {
                        await Navigator.of(context).pushNamed('/skills');
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    _MenuButton(
                      label: 'Jouer',
                      icon: Icons.play_arrow,
                      onTap: () => Navigator.of(context).pushNamed('/game'),
                    ),
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
        const SizedBox(height: 4),
        const Text('Arcade Survival', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70)),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _MenuButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isPrimary = label.toLowerCase().contains('jouer');
  const Color accent = Color(0xFF66BB6A);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: isPrimary ? accent.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.65)),
          backgroundColor: isPrimary ? accent.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: isPrimary ? Colors.white : Colors.white),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: Colors.white) ?? const TextStyle(fontSize: 16, color: Colors.white)),
        ),
      ),
    );
  }
}
