import 'package:flutter/material.dart';

/// Destinos principais do aplicativo. Os quatro primeiros aparecem na
/// navegação da gaveta no celular; o computador fica na barra lateral, na
/// gaveta e no compositor.
enum AppSection {
  chat(
    'Conversas',
    Icons.chat_bubble_outline_rounded,
    Icons.chat_bubble_rounded,
  ),
  explore('Explorar', Icons.explore_outlined, Icons.explore_rounded),
  files('Arquivos', Icons.folder_outlined, Icons.folder_rounded),
  settings('Configurações', Icons.settings_outlined, Icons.settings_rounded),
  computer('Computador', Icons.terminal_rounded, Icons.terminal_rounded);

  const AppSection(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  bool get isPrimary => this != AppSection.computer;
}
