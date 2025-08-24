import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerProfile {
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

  // Spend/add
  bool spend(int amount) {
    if (coins < amount) return false;
    coins -= amount;
    _save();
    return true;
  }

  void addCoins(int amount) {
    coins += amount;
    _save();
  }

  int skillLevel(String key) => skills[key] ?? 0;

  bool upgradeSkill(String key) {
    final level = skillLevel(key);
    final cost = upgradeCost(key, level);
    if (!spend(cost)) return false;
    skills[key] = level + 1;
    _save();
    return true;
  }

  int upgradeCost(String key, int level) {
    // Coût croissant: base 50, +25% par niveau
    const base = 50;
    double cost = base * (1 + 0.25 * level);
    return cost.round();
  }

  // Cosmetics helpers
  bool isOwned(String id) => ownedCosmetics.contains(id);
  void grant(String id) { ownedCosmetics.add(id); _save(); }
  void equipSkin(String id) { if (isOwned(id)) { equippedSnakeSkin = id; _save(); } }
  void equipTrailFx(String id) { if (isOwned(id)) { equippedTrail = id; _save(); } }
  void equipUiStyle(String id) { if (isOwned(id)) { equippedUiStyle = id; _save(); } }

  // Persistence
  static const _kKey = 'player_profile_v1';
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map;
    coins = (map['coins'] ?? 0) as int;
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
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      'coins': coins,
      'skills': skills,
      'owned': ownedCosmetics.toList(),
      'skin': equippedSnakeSkin,
      'trail': equippedTrail,
      'ui': equippedUiStyle,
      'halo': haloFireflies,
      'lastDaily': lastDailyGift?.toIso8601String(),
    };
    await sp.setString(_kKey, jsonEncode(map));
  }
}
