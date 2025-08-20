class PlayerProfile {
  PlayerProfile._();
  static final PlayerProfile instance = PlayerProfile._();

  int coins = 0;
  final Map<String, int> skills = {
    'speed': 0, // +10 de vitesse par niveau
    'shield': 0, // +2s de bouclier de départ par niveau
    'food': 0, // +5% score nourriture par niveau
  };

  bool spend(int amount) {
    if (coins < amount) return false;
    coins -= amount;
    return true;
  }

  void addCoins(int amount) {
    coins += amount;
  }

  int skillLevel(String key) => skills[key] ?? 0;

  bool upgradeSkill(String key) {
    final level = skillLevel(key);
    final cost = upgradeCost(key, level);
    if (!spend(cost)) return false;
    skills[key] = level + 1;
    return true;
  }

  int upgradeCost(String key, int level) {
    // Coût croissant: base 50, +25% par niveau
    const base = 50;
    double cost = base * (1 + 0.25 * level);
    return cost.round();
  }
}
