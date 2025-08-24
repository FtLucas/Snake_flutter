import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // Audio
  double musicVolume = 0.6; // 0..1
  double sfxVolume = 0.8; // 0..1
  bool vibrations = true;

  // Gameplay/UI
  bool leftHandedJoystick = false;
  double joystickSize = 1.0; // 0.6..1.6 scale
  double joystickOpacity = 1.0; // 0.2..1.0
  double joystickMargin = 16; // px
  String language = 'fr'; // 'fr', 'en' (placeholder)
  GraphicsQuality graphics = GraphicsQuality.medium;
  bool colorBlindMode = false;

  void setMusic(double v) { musicVolume = v.clamp(0, 1); notifyListeners(); save(); }
  void setSfx(double v) { sfxVolume = v.clamp(0, 1); notifyListeners(); save(); }
  void setVibrations(bool v) { vibrations = v; notifyListeners(); save(); }
  void setLeftHanded(bool v) { leftHandedJoystick = v; notifyListeners(); save(); }
  void setJoystickSize(double v) { joystickSize = v.clamp(0.6, 1.6); notifyListeners(); save(); }
  void setJoystickOpacity(double v) { joystickOpacity = v.clamp(0.2, 1.0); notifyListeners(); save(); }
  void setJoystickMargin(double v) { joystickMargin = v.clamp(0, 48); notifyListeners(); save(); }
  void setLanguage(String v) { language = v; notifyListeners(); save(); }
  void setGraphics(GraphicsQuality q) { graphics = q; notifyListeners(); save(); }
  void setColorBlind(bool v) { colorBlindMode = v; notifyListeners(); save(); }

  // Persistence
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    musicVolume = sp.getDouble('music') ?? musicVolume;
    sfxVolume = sp.getDouble('sfx') ?? sfxVolume;
    vibrations = sp.getBool('vib') ?? vibrations;
    leftHandedJoystick = sp.getBool('leftJoy') ?? leftHandedJoystick;
    joystickSize = sp.getDouble('joySize') ?? joystickSize;
    joystickOpacity = sp.getDouble('joyOpacity') ?? joystickOpacity;
    joystickMargin = sp.getDouble('joyMargin') ?? joystickMargin;
    language = sp.getString('lang') ?? language;
    graphics = GraphicsQuality.values[sp.getInt('gfx') ?? graphics.index];
    colorBlindMode = sp.getBool('cb') ?? colorBlindMode;
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('music', musicVolume);
    await sp.setDouble('sfx', sfxVolume);
    await sp.setBool('vib', vibrations);
    await sp.setBool('leftJoy', leftHandedJoystick);
    await sp.setDouble('joySize', joystickSize);
    await sp.setDouble('joyOpacity', joystickOpacity);
    await sp.setDouble('joyMargin', joystickMargin);
    await sp.setString('lang', language);
    await sp.setInt('gfx', graphics.index);
    await sp.setBool('cb', colorBlindMode);
  }
}

enum GraphicsQuality { low, medium, high }
