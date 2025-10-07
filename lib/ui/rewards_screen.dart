import 'package:flutter/material.dart';
import '../state/player_profile.dart';
import '../state/translations.dart';
import '../services/audio_manager.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  @override
  void initState() {
    super.initState();
    PlayerProfile.instance.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    PlayerProfile.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  bool _hasUnclaimedRewards(PlayerProfile profile) {
    for (int i = 1; i <= profile.level; i++) {
      if (!profile.claimedRewards.contains(i)) {
        return true;
      }
    }
    return false;
  }

  void _claimAllRewards(PlayerProfile profile) {
    int totalClaimed = 0;
    for (int i = 1; i <= profile.level; i++) {
      if (profile.claimLevelReward(i)) {
        totalClaimed++;
      }
    }

    if (totalClaimed > 0) {
      // Son de récompense
      AudioManager.instance.playRewardSound();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$totalClaimed ${tr('reward_unlocked')}'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = PlayerProfile.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Text(tr('level_rewards')),
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 0,
        actions: [
          if (_hasUnclaimedRewards(profile))
            TextButton.icon(
              onPressed: () => _claimAllRewards(profile),
              icon: const Icon(Icons.card_giftcard, color: Colors.white),
              label: Text(
                tr('claim_all'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CurrentLevelCard(level: profile.level, totalScore: profile.totalScore),
          const SizedBox(height: 24),
          _ProgressCard(currentScore: profile.totalScore),
          const SizedBox(height: 24),
          Text(
            tr('all_rewards'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          ...List.generate(20, (index) {
            final level = index + 1;
            final isUnlocked = profile.level >= level;
            final isClaimed = profile.claimedRewards.contains(level);
            return _RewardTile(
              level: level,
              isUnlocked: isUnlocked,
              isClaimed: isClaimed,
              reward: _getRewardForLevel(level),
              onClaim: () {
                if (profile.claimLevelReward(level)) {
                  // Son de récompense
                  AudioManager.instance.playRewardSound();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${tr('reward_unlocked')} +${_getRewardForLevel(level)['coins']} 💰'),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  );
                }
              },
            );
          }),
        ],
      ),
    );
  }

  Map<String, dynamic> _getRewardForLevel(int level) {
    final rewards = <int, Map<String, dynamic>>{
      1: {'coins': 0, 'icon': Icons.star, 'description': 'Bienvenue !'},
      2: {'coins': 50, 'icon': Icons.monetization_on, 'description': '+50 pièces'},
      3: {'coins': 100, 'icon': Icons.monetization_on, 'description': '+100 pièces'},
      4: {'coins': 150, 'icon': Icons.monetization_on, 'description': '+150 pièces'},
      5: {'coins': 250, 'icon': Icons.card_giftcard, 'description': '+250 pièces + Bonus'},
      6: {'coins': 200, 'icon': Icons.monetization_on, 'description': '+200 pièces'},
      7: {'coins': 250, 'icon': Icons.monetization_on, 'description': '+250 pièces'},
      8: {'coins': 300, 'icon': Icons.monetization_on, 'description': '+300 pièces'},
      9: {'coins': 350, 'icon': Icons.monetization_on, 'description': '+350 pièces'},
      10: {'coins': 500, 'icon': Icons.card_giftcard, 'description': '+500 pièces + Bonus'},
      11: {'coins': 400, 'icon': Icons.monetization_on, 'description': '+400 pièces'},
      12: {'coins': 450, 'icon': Icons.monetization_on, 'description': '+450 pièces'},
      13: {'coins': 500, 'icon': Icons.monetization_on, 'description': '+500 pièces'},
      14: {'coins': 550, 'icon': Icons.monetization_on, 'description': '+550 pièces'},
      15: {'coins': 750, 'icon': Icons.card_giftcard, 'description': '+750 pièces + Bonus'},
      16: {'coins': 600, 'icon': Icons.monetization_on, 'description': '+600 pièces'},
      17: {'coins': 650, 'icon': Icons.monetization_on, 'description': '+650 pièces'},
      18: {'coins': 700, 'icon': Icons.monetization_on, 'description': '+700 pièces'},
      19: {'coins': 800, 'icon': Icons.monetization_on, 'description': '+800 pièces'},
      20: {'coins': 1000, 'icon': Icons.card_giftcard, 'description': '+1000 pièces + Bonus'},
    };

    return rewards[level] ?? {'coins': level * 50, 'icon': Icons.monetization_on, 'description': '+${level * 50} pièces'};
  }
}

/// Carte du niveau actuel - Design vert
class _CurrentLevelCard extends StatelessWidget {
  final int level;
  final int totalScore;

  const _CurrentLevelCard({required this.level, required this.totalScore});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
          const SizedBox(height: 12),
          Text(
            '${tr('level')} $level',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Score Total: $totalScore',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte de progression - Design vert
class _ProgressCard extends StatelessWidget {
  final int currentScore;

  const _ProgressCard({required this.currentScore});

  int _getPreviousLevelThreshold(int level) {
    if (level <= 1) return 0;
    if (level == 2) return 0;
    if (level == 3) return 1000;
    if (level == 4) return 2500;
    if (level == 5) return 5000;
    if (level == 6) return 8000;
    if (level == 7) return 12000;
    if (level == 8) return 17000;
    if (level == 9) return 23000;
    if (level == 10) return 30000;
    if (level == 11) return 38000;
    if (level == 12) return 47000;
    if (level == 13) return 57000;
    if (level == 14) return 68000;
    if (level == 15) return 80000;
    if (level == 16) return 93000;
    if (level == 17) return 107000;
    if (level == 18) return 122000;
    if (level == 19) return 138000;
    if (level == 20) return 155000;
    if (level == 21) return 173000;
    return 192000 + ((level - 22) * 25000);
  }

  @override
  Widget build(BuildContext context) {
    final profile = PlayerProfile.instance;
    final currentLevel = profile.level;
    final nextLevelThreshold = profile.getPointsForNextLevel();
    final previousLevelThreshold = currentLevel == 1 ? 0 : _getPreviousLevelThreshold(currentLevel);
    final scoreInCurrentLevel = currentScore - previousLevelThreshold;
    final pointsForLevel = nextLevelThreshold - previousLevelThreshold;
    final progress = pointsForLevel > 0 ? scoreInCurrentLevel / pointsForLevel : 0.0;
    final pointsNeeded = nextLevelThreshold - currentScore;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('next_level'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 24,
              backgroundColor: const Color(0xFF1B5E20),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF66BB6A)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$pointsNeeded ${tr('points_needed')} ${tr('for_level')} ${currentLevel + 1}',
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Tuile de récompense avec bouton "Réclamer"
class _RewardTile extends StatelessWidget {
  final int level;
  final bool isUnlocked;
  final bool isClaimed;
  final Map<String, dynamic> reward;
  final VoidCallback onClaim;

  const _RewardTile({
    required this.level,
    required this.isUnlocked,
    required this.isClaimed,
    required this.reward,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final description = reward['description'] as String;

    Color bgColor;
    Color borderColor;
    if (isClaimed) {
      bgColor = const Color(0xFF1B5E20).withOpacity(0.3);
      borderColor = const Color(0xFF2E7D32);
    } else if (isUnlocked) {
      bgColor = const Color(0xFF4CAF50).withOpacity(0.2);
      borderColor = const Color(0xFF66BB6A);
    } else {
      bgColor = Colors.grey[800]!;
      borderColor = Colors.grey[700]!;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isClaimed
                ? const Color(0xFF2E7D32)
                : isUnlocked
                    ? const Color(0xFF4CAF50)
                    : Colors.grey[700],
            shape: BoxShape.circle,
          ),
          child: Icon(
            isClaimed ? Icons.check_circle : isUnlocked ? Icons.card_giftcard : Icons.lock,
            color: Colors.white,
          ),
        ),
        title: Text(
          '${tr('level')} $level',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isUnlocked ? Colors.white : Colors.grey[500],
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            color: isUnlocked ? Colors.white70 : Colors.grey[600],
          ),
        ),
        trailing: isUnlocked && !isClaimed
            ? ElevatedButton.icon(
                onPressed: onClaim,
                icon: const Icon(Icons.card_giftcard, size: 18),
                label: Text(tr('claim')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF66BB6A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              )
            : isClaimed
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, color: Color(0xFF66BB6A), size: 20),
                      const SizedBox(width: 4),
                      Text(
                        tr('claimed'),
                        style: const TextStyle(
                          color: Color(0xFF66BB6A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Icon(Icons.lock_outline, color: Colors.grey[600]),
      ),
    );
  }
}
