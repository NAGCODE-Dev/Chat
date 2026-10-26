import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Marca do Chat: bloco arredondado com gradiente azul-violeta.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 42, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.primary, palette.violet],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.38),
                  blurRadius: size * 0.55,
                  offset: Offset(0, size * 0.18),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.chat_bubble_rounded,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}

/// Avatar do assistente usado ao lado das respostas.
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, this.size = 40, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.primary, palette.violet],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.25),
                  blurRadius: size * 0.45,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: size * 0.48,
      ),
    );
  }
}

/// Bolinha de estado com rótulo; a cor nunca é o único indicador.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.active,
    this.activeColor,
    this.inactiveColor,
    this.size = 8,
  });

  final bool active;
  final Color? activeColor;
  final Color? inactiveColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active
            ? (activeColor ?? palette.success)
            : (inactiveColor ?? palette.danger),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (active ? (activeColor ?? palette.success) : (inactiveColor ?? palette.danger))
                .withValues(alpha: 0.45),
            blurRadius: size,
          ),
        ],
      ),
    );
  }
}
