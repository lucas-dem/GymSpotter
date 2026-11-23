import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Si la persona ocultó la tarjeta de pasos con la "×"; se guarda en este teléfono, fuera de la copia.
class StepsCardPref {
  StepsCardPref._();

  static const _key = 'infyter_steps_card_hidden_v1';
  static final ValueNotifier<bool> hidden = ValueNotifier(false);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      hidden.value = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> setHidden(bool value) async {
    hidden.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}
