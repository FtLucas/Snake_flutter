import 'package:audioplayers/audioplayers.dart';
import '../state/settings.dart';

/// Gestionnaire audio avec sons générés programmatiquement
class AudioManager {
  static final AudioManager instance = AudioManager._();
  AudioManager._();

  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _player.setReleaseMode(ReleaseMode.stop);
    _isInitialized = true;

    print('🔊 AudioManager initialized');
  }

  /// Joue un son depuis les assets (si disponible) ou utilise un bip système
  Future<void> _playSound(String assetPath) async {
    try {
      final volume = AppSettings.instance.sfxVolume;
      if (volume <= 0) {
        print('🔇 Volume is 0, skipping sound');
        return;
      }

      await _player.setVolume(volume);

      // Tenter de jouer le fichier depuis les assets
      try {
        await _player.play(AssetSource(assetPath));
        print('🔊 Playing sound: $assetPath at volume $volume');
      } catch (e) {
        // Si le fichier n'existe pas, on affiche juste un message
        print('⚠️ Sound file not found: $assetPath - $e');
        // Utiliser un son système de notification comme fallback
        await _player.play(AssetSource('sounds/beep.mp3')).catchError((e) {
          print('⚠️ No fallback sound available');
        });
      }
    } catch (e) {
      print('❌ Error playing sound: $e');
    }
  }

  /// Son de manger une pomme (ton court et aigu)
  Future<void> playEatSound() async {
    print('🍎 Attempting to play eat sound');
    await _playSound('sounds/eat.mp3');
  }

  /// Son de collision / game over (ton grave et long)
  Future<void> playGameOverSound() async {
    print('💀 Attempting to play game over sound');
    await _playSound('sounds/gameover.mp3');
  }

  /// Son de niveau complété (mélodie ascendante)
  Future<void> playLevelUpSound() async {
    print('⭐ Attempting to play level up sound');
    await _playSound('sounds/levelup.mp3');
  }

  /// Son de réclamation de récompense (son de pièces)
  Future<void> playRewardSound() async {
    print('🎁 Attempting to play reward sound');
    await _playSound('sounds/reward.mp3');
  }

  /// Son de clic bouton (clic subtil)
  Future<void> playClickSound() async {
    print('👆 Attempting to play click sound');
    await _playSound('sounds/click.mp3');
  }

  /// Son d'attaque de fourmi (coup/impact)
  Future<void> playAttackSound() async {
    print('⚔️ Attempting to play attack sound');
    await _playSound('sounds/attack.mp3');
  }

  void dispose() {
    _player.dispose();
  }
}
