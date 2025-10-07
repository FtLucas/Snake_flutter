# Sons du jeu

## État actuel ✅
Le jeu utilise maintenant de **vrais sons audibles** via `AudioManager` et `audioplayers` !

## Sons implémentés (Mise à jour v5 - Son d'attaque ajouté!)
- ✅ **eat.mp3** - Son de croquer une pomme (personnalisé par l'utilisateur)
- ✅ **gameover.mp3** - Son de game over style arcade classique
- ✅ **levelup.mp3** - Son de pièce/succès doux et agréable
- ✅ **reward.mp3** - Clochettes douces pour les récompenses
- ✅ **click.mp3** - Clic UI subtil et professionnel
- ✅ **attack.mp3** - Son d'attaque/impact quand le serpent frappe une fourmi

## Test des sons
1. Lancez le jeu : `flutter run`
2. Vérifiez que le volume des effets n'est pas à 0 dans les paramètres
3. Jouez et mangez une pomme → vous devriez **ENTENDRE** un son !
4. Les logs dans la console affichent : "🔊 Playing sound: ..."

## Sources des sons
Tous les sons proviennent de **Mixkit.co** (licence gratuite pour usage commercial et personnel)
- https://mixkit.co/free-sound-effects/game/

## Pour améliorer les sons
Pour ajouter de vrais fichiers audio MP3, placez-les dans ce dossier et modifiez `lib/services/audio_manager.dart` :

### Fichiers suggérés :
- `eat.mp3` - Son de manger (crunch, miam)
- `gameover.mp3` - Son de défaite (alarme, explosion)
- `levelup.mp3` - Son de succès (fanfare, victoire)
- `reward.mp3` - Son de pièces/cadeau
- `click.mp3` - Clic subtil

### Recommandations :
- Format : MP3 ou OGG
- Durée : < 1 seconde (sauf musiques)
- Volume : Normalisé à -3dB
- Taille : < 50KB par fichier
- Sample rate : 44.1kHz

### Sources gratuites :
- https://freesound.org/
- https://mixkit.co/free-sound-effects/
- https://opengameart.org/
- https://sonniss.com/gameaudiogdc (packs annuels gratuits)
- https://www.zapsplat.com/
