import 'package:flutter/foundation.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // Audio
  double musicVolume = 0.6; // 0..1
  double sfxVolume = 0.8; // 0..1
  bool vibrations = true;

  // Gameplay/UI
  bool leftHandedJoystick = false;
  String language = 'fr'; // 'fr', 'en' (placeholder)
  GraphicsQuality graphics = GraphicsQuality.medium;
  bool colorBlindMode = false;

  void setMusic(double v) { musicVolume = v.clamp(0, 1); notifyListeners(); }
  void setSfx(double v) { sfxVolume = v.clamp(0, 1); notifyListeners(); }
  void setVibrations(bool v) { vibrations = v; notifyListeners(); }
  void setLeftHanded(bool v) { leftHandedJoystick = v; notifyListeners(); }
  void setLanguage(String v) { language = v; notifyListeners(); }
  void setGraphics(GraphicsQuality q) { graphics = q; notifyListeners(); }
  void setColorBlind(bool v) { colorBlindMode = v; notifyListeners(); }
}

enum GraphicsQuality { low, medium, high }
