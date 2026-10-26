import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';

class ChatSuggestion {
  const ChatSuggestion({
    required this.icon,
    required this.title,
    required this.prompt,
  });

  final IconData icon;
  final String title;
  final String prompt;
}

const defaultChatSuggestions = [
  ChatSuggestion(
    icon: Icons.event_note_outlined,
    title: 'Organize meu dia',
    prompt: 'Me ajude a organizar meu dia e priorizar o que é mais importante.',
  ),
  ChatSuggestion(
    icon: Icons.lightbulb_outline_rounded,
    title: 'Explique um assunto',
    prompt: 'Explique um assunto para mim de forma simples, com exemplos.',
  ),
  ChatSuggestion(
    icon: Icons.attach_file_rounded,
    title: 'Analise um arquivo',
    prompt: 'Analise o arquivo que vou anexar e faça um resumo dos pontos principais.',
  ),
];

/// Tela inicial enxuta, no espírito do ChatGPT: bastante respiro, uma
/// saudação curta e poucas sugestões de texto, sem cartões coloridos.
class EmptyChatView extends StatelessWidget {
  const EmptyChatView({
    super.key,
    required this.greeting,
    required this.memoryCount,
    required this.onSuggestion,
    this.suggestions = defaultChatSuggestions,
    this.compact = false,
  });

  final String greeting;
  final int memoryCount;
  final ValueChanged<String> onSuggestion;
  final List<ChatSuggestion> suggestions;
  final bool compact;

  String get _subtitle {
    final value = greeting.trim();
    if (value.isNotEmpty && value != 'Como posso ajudar?') return value;
    if (memoryCount > 0) {
      return 'Você tem $memoryCount memória(s) salva(s). '
          'Pergunte, anexe um arquivo ou peça algo no notebook.';
    }
    return 'Pergunte, anexe um arquivo ou peça uma tarefa no notebook.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final horizontal = compact ? 20.0 : 32.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 360;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    compact ? 18 : 28,
                    horizontal,
                    12,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Como posso ajudar?',
                          textAlign: TextAlign.center,
                          style: (compact
                                  ? Theme.of(context).textTheme.headlineSmall
                                  : Theme.of(context).textTheme.headlineMedium)
                              ?.copyWith(
                                color: palette.text,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _subtitle,
                          textAlign: TextAlign.center,
                          maxLines: tight ? 2 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: compact ? 13 : 13.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!tight)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 20,
                  0,
                  compact ? 10 : 20,
                  compact ? 4 : 8,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final suggestion in suggestions)
                          _SuggestionRow(
                            suggestion: suggestion,
                            onTap: () => onSuggestion(suggestion.prompt),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
        if (tight) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: compact ? 8 : 12),
            child: SizedBox(
              height: constraints.maxHeight,
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final ChatSuggestion suggestion;
  final VoidCallback onTap;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: widget.suggestion.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hover = value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _hover ? palette.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.suggestion.icon,
                    size: 21,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.suggestion.title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
