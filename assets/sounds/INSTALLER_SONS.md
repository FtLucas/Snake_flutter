# Fichiers audio requis

Pour que les sons fonctionnent, vous devez ajouter ces 5 fichiers MP3 dans ce dossier :

1. **eat.mp3** - Son court et aigu (100-200ms)
2. **gameover.mp3** - Son grave et descendant (300-500ms)
3. **levelup.mp3** - Mélodie ascendante joyeuse (500ms)
4. **reward.mp3** - Son de pièces/clochettes (200-300ms)
5. **click.mp3** - Clic très court (50ms)

## Option 1 : Télécharger des sons gratuits (RECOMMANDÉ)

### Sons prêts à l'emploi sur Mixkit (gratuits, pas d'inscription) :
1. Allez sur https://mixkit.co/free-sound-effects/game/
2. Téléchargez ces sons :
   - **eat.mp3** : "Game coin collect" ou "Game bonus"
   - **gameover.mp3** : "Game fail" ou "Game over arcade"
   - **levelup.mp3** : "Game level complete" ou "Achievement unlock"
   - **reward.mp3** : "Coins gain" ou "Achievement earned"
   - **click.mp3** : "Click" ou "Interface button"

3. Renommez les fichiers téléchargés avec les noms exacts ci-dessus
4. Placez-les dans `assets/sounds/`

### Alternative - Freesound.org (requiert compte gratuit) :
- https://freesound.org/search/?q=game+eat
- https://freesound.org/search/?q=game+over
- https://freesound.org/search/?q=level+up
- https://freesound.org/search/?q=coin
- https://freesound.org/search/?q=click

## Option 2 : Utiliser des sons système temporaires

Si vous voulez tester rapidement sans télécharger, vous pouvez utiliser des sons système Android.
Les logs dans la console vous diront si les fichiers sont trouvés ou non.

## Vérification

Une fois les fichiers ajoutés :
1. Relancez l'application : `flutter run`
2. Les sons devraient jouer automatiquement
3. Vérifiez la console pour voir les messages : "🔊 Playing sound: ..."
