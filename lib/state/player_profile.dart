import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerProfile extends ChangeNotifier {
  PlayerProfile._();
  static final PlayerProfile instance = PlayerProfile._();

  int coins = 0;
  final Map<String, int> skills = {
    'speed': 0, // +10 de vitesse par niveau
    'shield': 0, // +2s de bouclier de départ par niveau
    'food': 0, // +5% score nourriture par niveau
  };

  // Cosmétiques
  final Set<String> ownedCosmetics = <String>{};
  String? equippedSnakeSkin; // e.g. 'skin_neon'
  String? equippedTrail; // e.g. 'trail_sparks'
  String? equippedUiStyle; // e.g. 'ui_dark_glass'
  bool haloFireflies = false; // simple toggle cosmetic

  // Daily/timers
  DateTime? lastDailyGift;

  // Statistiques de jeu
  int highScore = 0; // Meilleur score obtenu
  int totalScore = 0; // Score cumulé de toutes les parties
  int totalGamesPlayed = 0; // Nombre total de parties jouées
  int level = 1; // Niveau du joueur basé sur totalScore
  final Set<int> claimedRewards = {}; // Niveaux dont les récompenses ont été réclamées

  // Spend/add
  bool spend(int amount) {
    if (coins < amount) return false;
    coins -= amount;
    _save();
    notifyListeners();
    return true;
  }

  void addCoins(int amount) {
    coins += amount;
    _save();
    notifyListeners();
  }

  // Mise à jour des statistiques après une partie
  void updateStats(int score) {
    print('📊 updateStats appelé avec score: $score');
    print('📊 Avant: totalGamesPlayed=$totalGamesPlayed, highScore=$highScore, totalScore=$totalScore, level=$level');

    totalGamesPlayed++;
    if (score > highScore) {
      highScore = score;
    }
    // Ajouter le score à totalScore (cumul de toutes les parties)
    totalScore += score;
    // Recalculer le niveau basé sur le score total
    level = _calculateLevel(totalScore);

    print('📊 Après: totalGamesPlayed=$totalGamesPlayed, highScore=$highScore, totalScore=$totalScore, level=$level');

    _save();
    notifyListeners();

    print('📊 Stats sauvegardées et listeners notifiés');
  }

  // Calcul du niveau avec progression exponentielle
  int _calculateLevel(int total) {
    if (total < 1000) return 1;
    if (total < 2500) return 2;
    if (total < 5000) return 3;
    if (total < 8000) return 4;
    if (total < 12000) return 5;
    if (total < 17000) return 6;
    if (total < 23000) return 7;
    if (total < 30000) return 8;
    if (total < 38000) return 9;
    if (total < 47000) return 10;
    if (total < 57000) return 11;
    if (total < 68000) return 12;
    if (total < 80000) return 13;
    if (total < 93000) return 14;
    if (total < 107000) return 15;
    if (total < 122000) return 16;
    if (total < 138000) return 17;
    if (total < 155000) return 18;
    if (total < 173000) return 19;
    if (total < 192000) return 20;
    // Au-delà du niveau 20 : +25000 points par niveau
    return 20 + ((total - 192000) ~/ 25000);
  }

  // Obtenir le score nécessaire pour le prochain niveau
  int getPointsForNextLevel() {
    final nextLevel = level + 1;
    if (nextLevel == 2) return 1000;
    if (nextLevel == 3) return 2500;
    if (nextLevel == 4) return 5000;
    if (nextLevel == 5) return 8000;
    if (nextLevel == 6) return 12000;
    if (nextLevel == 7) return 17000;
    if (nextLevel == 8) return 23000;
    if (nextLevel == 9) return 30000;
    if (nextLevel == 10) return 38000;
    if (nextLevel == 11) return 47000;
    if (nextLevel == 12) return 57000;
    if (nextLevel == 13) return 68000;
    if (nextLevel == 14) return 80000;
    if (nextLevel == 15) return 93000;
    if (nextLevel == 16) return 107000;
    if (nextLevel == 17) return 122000;
    if (nextLevel == 18) return 138000;
    if (nextLevel == 19) return 155000;
    if (nextLevel == 20) return 173000;
    if (nextLevel == 21) return 192000;
    // Au-delà du niveau 21
    return 192000 + ((nextLevel - 21) * 25000);
  }

  // Réclamer une récompense de niveau
  bool claimLevelReward(int lv) {
    if (level < lv || claimedRewards.contains(lv)) return false;
    claimedRewards.add(lv);
    final reward = _getRewardForLevel(lv);
    coins += reward;
    _save();
    notifyListeners();
    return true;
  }

  int _getRewardForLevel(int lv) {
    final rewards = <int, int>{
      1: 0, 2: 50, 3: 100, 4: 150, 5: 250,
      6: 200, 7: 250, 8: 300, 9: 350, 10: 500,
      11: 400, 12: 450, 13: 500, 14: 550, 15: 750,
      16: 600, 17: 650, 18: 700, 19: 800, 20: 1000,
    };
    return rewards[lv] ?? (lv * 50);
  }

  int skillLevel(String key) => skills[key] ?? 0;

  bool upgradeSkill(String key) {
    final lvl = skillLevel(key);
    final cost = upgradeCost(key, lvl);
    if (!spend(cost)) return false;
    skills[key] = lvl + 1;
    _save();
    notifyListeners();
    return true;
  }

  int upgradeCost(String key, int lvl) {
    // Coût croissant: base 50, +25% par niveau
    const base = 50;
    double cost = base * (1 + 0.25 * lvl);
    return cost.round();
  }

  // Cosmetics helpers
  bool isOwned(String id) => ownedCosmetics.contains(id);
  void grant(String id) {
    ownedCosmetics.add(id);
    _save();
    notifyListeners();
  }
  void equipSkin(String id) {
    if (isOwned(id)) {
      equippedSnakeSkin = id;
      _save();
      notifyListeners();
    }
  }
  void equipTrailFx(String id) {
    if (isOwned(id)) {
      equippedTrail = id;
      _save();
      notifyListeners();
    }
  }
  void equipUiStyle(String id) {
    if (isOwned(id)) {
      equippedUiStyle = id;
      _save();
      notifyListeners();
    }
  }

  // Persistence
  static const _kKey = 'player_profile_v1';
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) {
      // Nouveau joueur : marquer le niveau 1 comme déjà réclamé (0 pièces de toute façon)
      claimedRewards.add(1);
      print('🆕 Nouveau joueur - Niveau 1 automatiquement réclamé');
      await _save(); // Sauvegarder pour la prochaine fois
      return;
    }
    final map = jsonDecode(raw) as Map;
    coins = (map['coins'] ?? 0) as int;
    highScore = (map['highScore'] ?? 0) as int;
    totalScore = (map['totalScore'] ?? 0) as int;
    totalGamesPlayed = (map['totalGamesPlayed'] ?? 0) as int;
    level = (map['level'] ?? 1) as int;
    claimedRewards
      ..clear()
      ..addAll(List<int>.from(map['claimedRewards'] ?? const []));

    // Si le niveau 1 n'est pas réclamé, le marquer automatiquement (récompense = 0)
    bool needsSave = false;
    if (!claimedRewards.contains(1)) {
      claimedRewards.add(1);
      needsSave = true;
      print('✅ Niveau 1 ajouté automatiquement aux récompenses réclamées');
    }

    final skillsMap = Map<String, dynamic>.from(map['skills'] ?? {});
    skills
      ..clear()
      ..addAll(skillsMap.map((k, v) => MapEntry(k, (v as num).toInt())));
    ownedCosmetics
      ..clear()
      ..addAll(List<String>.from(map['owned'] ?? const []));
    equippedSnakeSkin = map['skin'] as String?;
    equippedTrail = map['trail'] as String?;
    equippedUiStyle = map['ui'] as String?;
    haloFireflies = (map['halo'] ?? false) as bool;
    final last = map['lastDaily'] as String?;
    lastDailyGift = last != null ? DateTime.tryParse(last) : null;

    // Sauvegarder si on a modifié les récompenses réclamées
    if (needsSave) {
      await _save();
    }
  }

  Future<void> _save() async {
    print('💾 Sauvegarde des stats...');
    final sp = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      'coins': coins,
      'highScore': highScore,
      'totalScore': totalScore,
      'totalGamesPlayed': totalGamesPlayed,
      'level': level,
      'claimedRewards': claimedRewards.toList(),
      'skills': skills,
      'owned': ownedCosmetics.toList(),
      'skin': equippedSnakeSkin,
      'trail': equippedTrail,
      'ui': equippedUiStyle,
      'halo': haloFireflies,
      'lastDaily': lastDailyGift?.toIso8601String(),
    };
    await sp.setString(_kKey, jsonEncode(map));
    print('💾 Stats sauvegardées: totalScore=$totalScore, level=$level, highScore=$highScore');
  }

  // Réinitialiser complètement le profil
  Future<void> resetProfile() async {
    coins = 0;
    highScore = 0;
    totalScore = 0;
    totalGamesPlayed = 0;
    level = 1;
    claimedRewards.clear();
    skills.clear();
    skills.addAll({
      'speed': 0,
      'shield': 0,
      'food': 0,
    });
    ownedCosmetics.clear();
    equippedSnakeSkin = null;
    equippedTrail = null;
    equippedUiStyle = null;
    haloFireflies = false;
    lastDailyGift = null;
    await _save();
    notifyListeners();
  }
}
