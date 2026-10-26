import 'package:flutter/material.dart';

/// Tokens visuais do Chat.
///
/// Nenhuma tela deve declarar cores cruas: tudo passa por este ThemeExtension,
/// o que permite trocar o tema sem reescrever componentes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.panel,
    required this.card,
    required this.border,
    required this.primary,
    required this.primaryDeep,
    required this.violet,
    required this.text,
    required this.muted,
    required this.disabled,
    required this.success,
    required this.danger,
    required this.userBubbleStart,
    required this.userBubbleEnd,
    required this.assistantBubble,
    required this.sidebar,
    required this.input,
    required this.hover,
    required this.selected,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color panel;
  final Color card;
  final Color border;
  final Color primary;
  final Color primaryDeep;
  final Color violet;
  final Color text;
  final Color muted;
  final Color disabled;
  final Color success;
  final Color danger;
  final Color userBubbleStart;
  final Color userBubbleEnd;
  final Color assistantBubble;
  final Color sidebar;
  final Color input;
  final Color hover;
  final Color selected;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF080D17),
    surface: Color(0xFF0D1422),
    panel: Color(0xFF111B2C),
    card: Color(0xFF172238),
    border: Color(0xFF26334A),
    primary: Color(0xFF4F6BFF),
    primaryDeep: Color(0xFF3158D8),
    violet: Color(0xFF8170FF),
    text: Color(0xFFF2F5FC),
    muted: Color(0xFFA2AEC5),
    disabled: Color(0xFF69758C),
    success: Color(0xFF48D597),
    danger: Color(0xFFFF667A),
    userBubbleStart: Color(0xFF4F6BFF),
    userBubbleEnd: Color(0xFF6A5BFF),
    assistantBubble: Color(0xFF172238),
    sidebar: Color(0xFF0B1220),
    input: Color(0xFF141F33),
    hover: Color(0xFF1B2940),
    selected: Color(0xFF1C2C4D),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF3F6FC),
    surface: Color(0xFFFAFBFE),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFDCE3F1),
    primary: Color(0xFF3158D8),
    primaryDeep: Color(0xFF2445B8),
    violet: Color(0xFF6A5BFF),
    text: Color(0xFF101828),
    muted: Color(0xFF5B667A),
    disabled: Color(0xFF8D97A8),
    success: Color(0xFF159A69),
    danger: Color(0xFFD93B53),
    userBubbleStart: Color(0xFF3158D8),
    userBubbleEnd: Color(0xFF5A4FE8),
    assistantBubble: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF8FAFF),
    input: Color(0xFFF1F4FA),
    hover: Color(0xFFEDF1FA),
    selected: Color(0xFFE6ECFF),
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? panel,
    Color? card,
    Color? border,
    Color? primary,
    Color? primaryDeep,
    Color? violet,
    Color? text,
    Color? muted,
    Color? disabled,
    Color? success,
    Color? danger,
    Color? userBubbleStart,
    Color? userBubbleEnd,
    Color? assistantBubble,
    Color? sidebar,
    Color? input,
    Color? hover,
    Color? selected,
  }) => AppPalette(
    brightness: brightness ?? this.brightness,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    panel: panel ?? this.panel,
    card: card ?? this.card,
    border: border ?? this.border,
    primary: primary ?? this.primary,
    primaryDeep: primaryDeep ?? this.primaryDeep,
    violet: violet ?? this.violet,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    disabled: disabled ?? this.disabled,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    userBubbleStart: userBubbleStart ?? this.userBubbleStart,
    userBubbleEnd: userBubbleEnd ?? this.userBubbleEnd,
    assistantBubble: assistantBubble ?? this.assistantBubble,
    sidebar: sidebar ?? this.sidebar,
    input: input ?? this.input,
    hover: hover ?? this.hover,
    selected: selected ?? this.selected,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      panel: mix(panel, other.panel),
      card: mix(card, other.card),
      border: mix(border, other.border),
      primary: mix(primary, other.primary),
      primaryDeep: mix(primaryDeep, other.primaryDeep),
      violet: mix(violet, other.violet),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      disabled: mix(disabled, other.disabled),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
      userBubbleStart: mix(userBubbleStart, other.userBubbleStart),
      userBubbleEnd: mix(userBubbleEnd, other.userBubbleEnd),
      assistantBubble: mix(assistantBubble, other.assistantBubble),
      sidebar: mix(sidebar, other.sidebar),
      input: mix(input, other.input),
      hover: mix(hover, other.hover),
      selected: mix(selected, other.selected),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
