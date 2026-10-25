import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema claro/escuro/sistema, persistido no aparelho.
///
/// A cor-base continua sendo o azul do app; o modo escuro só troca a
/// luminosidade da paleta gerada pelo Material 3.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  String get label => switch (_mode) {
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Escuro',
    ThemeMode.system => 'Seguir o sistema',
  };

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _mode = switch (preferences.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Sem preferências salvas, segue o sistema.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('theme_mode', switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
    } catch (_) {
      // A troca vale para esta sessão mesmo se a persistência falhar.
    }
  }
}

final themeController = ThemeController();
