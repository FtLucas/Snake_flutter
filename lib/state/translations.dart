import 'settings.dart';

class Translations {
  static String get(String key) {
    final lang = AppSettings.instance.language;
    return _translations[lang]?[key] ?? _translations['fr']![key]!;
  }

  static const Map<String, Map<String, String>> _translations = {
    'fr': {
      // Menu principal
      'app_title': 'Snake Game',
      'play': 'Jouer',
      'shop': 'Boutique',
      'skills': 'Compétences',
      'settings': 'Paramètres',

      // Écran de jeu
      'score': 'Score',
      'level': 'Niveau',
      'high_score': 'Meilleur score',
      'enemies': 'Ennemis',
      'food': 'Nourriture',
      'game_over': 'GAME OVER',
      'reset': 'Recommencer',
      'demo': 'Démo',
      'wave': 'Vague++',
      'boss': 'Boss',
      'day_night': 'Jour/Nuit',
      'level_up': 'NIVEAU SUPÉRIEUR!',
      'choose_upgrade': 'Choisissez une amélioration:',
      'enemies_killed': 'Ennemis tués',
      'food_eaten': 'Nourriture mangée',

      // Paramètres
      'audio': 'Audio',
      'music': 'Musique',
      'effects': 'Effets',
      'gameplay': 'Gameplay',
      'left_handed_joystick': 'Joystick gaucher',
      'joystick_size': 'Taille joystick',
      'joystick_opacity': 'Opacité joystick',
      'joystick_margin': 'Marge joystick',
      'graphics_quality': 'Qualité graphique',
      'low': 'Basse',
      'medium': 'Moyenne',
      'high': 'Haute',
      'colorblind_mode': 'Mode daltonien',
      'language': 'Langue',
      'interface_language': 'Langue de l\'interface',

      // Réinitialisation
      'reset_game': 'Réinitialiser le jeu',
      'reset_game_title': 'Confirmer la réinitialisation',
      'reset_game_message': 'Êtes-vous sûr de vouloir réinitialiser le jeu ? Toutes vos pièces, compétences et cosmétiques seront perdus.',
      'reset_game_confirm': 'Réinitialiser',
      'cancel': 'Annuler',
      'reset_game_success': 'Jeu réinitialisé avec succès !',

      // Boutique
      'coins': 'Pièces',
      'buy': 'Acheter',
      'owned': 'Possédé',
      'locked': 'Verrouillé',
      'cosmetics': 'Cosmétiques',
      'coin_pack_100': 'Pack de pièces (100)',
      'coin_pack_500': 'Pack de pièces (500)',
      'skin_neon_snake': 'Skin Serpent Vert Néon',
      'trail_sparks': 'Trail Étincelles',
      'equip': 'Équiper',
      'equipped': 'Équipé',

      // Compétences
      'skill_points': 'Points de compétence',
      'skill_tree': 'Arbre de compétences',
      'unlock': 'Débloquer',
      'upgrade': 'Améliorer',
      'level_short': 'Niv.',
      'not_enough_coins': 'Pas assez de pièces',
      'speed_skill': 'Vitesse',
      'speed_skill_desc': 'Augmente la vitesse de base',

      // Récompenses
      'level_rewards': 'Récompenses de niveau',
      'all_rewards': 'Toutes les récompenses',
      'next_level': 'Prochain niveau',
      'points_needed': 'points nécessaires',
      'for_level': 'pour le niveau',
      'reward_unlocked': 'Récompense débloquée !',
      'new_level_reached': 'Nouveau niveau atteint !',
      'claim': 'Réclamer',
      'claimed': 'Réclamé',
      'claim_all': 'Tout réclamer',
      'shield_skill': 'Bouclier',
      'shield_skill_desc': 'Augmente la durée du bouclier de départ',
      'food_skill': 'Glouton',
      'food_skill_desc': 'Augmente les points gagnés en mangeant',
    },
    'en': {
      // Main menu
      'app_title': 'Snake Game',
      'play': 'Play',
      'shop': 'Shop',
      'skills': 'Skills',
      'settings': 'Settings',

      // Game screen
      'score': 'Score',
      'level': 'Level',
      'high_score': 'High Score',
      'enemies': 'Enemies',
      'food': 'Food',
      'game_over': 'GAME OVER',
      'reset': 'Rejouer',
      'demo': 'Demo',
      'wave': 'Wave++',
      'boss': 'Boss',
      'day_night': 'Day/Night',
      'level_up': 'LEVEL UP!',
      'choose_upgrade': 'Choose an upgrade:',
      'enemies_killed': 'Enemies killed',
      'food_eaten': 'Food eaten',

      // Settings
      'audio': 'Audio',
      'music': 'Music',
      'effects': 'Effects',
      'gameplay': 'Gameplay',
      'left_handed_joystick': 'Left-handed joystick',
      'joystick_size': 'Joystick size',
      'joystick_opacity': 'Joystick opacity',
      'joystick_margin': 'Joystick margin',
      'graphics_quality': 'Graphics quality',
      'low': 'Low',
      'medium': 'Medium',
      'high': 'High',
      'colorblind_mode': 'Colorblind mode',
      'language': 'Language',
      'interface_language': 'Interface language',

      // Reset
      'reset_game': 'Reset game',
      'reset_game_title': 'Confirm reset',
      'reset_game_message': 'Are you sure you want to reset the game? All your coins, skills and cosmetics will be lost.',
      'reset_game_confirm': 'Reset',
      'cancel': 'Cancel',
      'reset_game_success': 'Game reset successfully!',

      // Shop
      'coins': 'Coins',
      'buy': 'Buy',
      'owned': 'Owned',
      'locked': 'Locked',
      'cosmetics': 'Cosmetics',
      'coin_pack_100': 'Coin Pack (100)',
      'coin_pack_500': 'Coin Pack (500)',
      'skin_neon_snake': 'Neon Green Snake Skin',
      'trail_sparks': 'Sparks Trail',
      'equip': 'Equip',
      'equipped': 'Equipped',

      // Skills
      'skill_points': 'Skill points',
      'skill_tree': 'Skill tree',
      'unlock': 'Unlock',
      'upgrade': 'Upgrade',
      'level_short': 'Lvl.',
      'not_enough_coins': 'Not enough coins',
      'speed_skill': 'Speed',
      'speed_skill_desc': 'Increases base speed',
      'shield_skill': 'Shield',
      'shield_skill_desc': 'Increases starting shield duration',
      'food_skill': 'Glutton',
      'food_skill_desc': 'Increases points gained from eating',

      // Rewards
      'level_rewards': 'Level Rewards',
      'all_rewards': 'All Rewards',
      'next_level': 'Next Level',
      'points_needed': 'points needed',
      'for_level': 'for level',
      'reward_unlocked': 'Reward Unlocked!',
      'new_level_reached': 'New Level Reached!',
      'claim': 'Claim',
      'claimed': 'Claimed',
      'claim_all': 'Claim All',
    },
  };
}

// Helper pour faciliter l'utilisation
String tr(String key) => Translations.get(key);
