import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_logo.dart';
import '../models/chat_models.dart';
import 'attachment_preview.dart';
import 'markdown_text.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.onSpeak,
    this.onOpenSource,
    this.loadAttachment,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isStreaming;
  final VoidCallback? onSpeak;
  final ValueChanged<String>? onOpenSource;
  final AttachmentBytesLoader? loadAttachment;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _buildUser(context) : _buildAssistant(context);
  }

  Widget _buildUser(BuildContext context) {
    final palette = context.palette;
    final hasText = message.content.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: 48, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.userBubbleStart, palette.userBubbleEnd],
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.attachments.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final attachment in message.attachments)
                        AttachmentPreview(
                          attachment: attachment,
                          loadBytes: loadAttachment,
                          compact: true,
                        ),
                    ],
                  ),
                  if (hasText) const SizedBox(height: 10),
                ],
                if (hasText)
                  Text(
                    message.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              _timeLabel(message.createdAt),
              style: TextStyle(color: palette.disabled, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final palette = context.palette;
    final hasContent = message.content.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 22),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AssistantAvatar(size: 30, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isStreaming && !hasContent)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: _TypingIndicator(),
                      )
                    else if (isStreaming)
                      Text(
                        message.content,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 14.5,
                          height: 1.6,
                        ),
                      )
                    else if (hasContent)
                      MarkdownText(message.content)
                    else
                      Text(
                        'Não consegui gerar uma resposta.',
                        style: TextStyle(color: palette.muted),
                      ),
                    if (message.sources.isNotEmpty)
                      _SourcesButton(
                        sources: message.sources,
                        onOpen: onOpenSource,
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (!isStreaming && hasContent) ...[
                          _MessageAction(
                            tooltip: 'Copiar resposta',
                            icon: Icons.copy_rounded,
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: message.content),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Resposta copiada.'),
                                ),
                              );
                            },
                          ),
                          if (onSpeak != null)
                            _MessageAction(
                              tooltip: 'Ouvir resposta',
                              icon: Icons.volume_up_outlined,
                              onTap: onSpeak!,
                            ),
                        ],
                        if (onRetry != null && !isStreaming)
                          _MessageAction(
                            tooltip: 'Tentar de novo',
                            icon: Icons.refresh_rounded,
                            onTap: onRetry!,
                          ),
                        const Spacer(),
                        Text(
                          _timeLabel(message.createdAt),
                          style: TextStyle(
                            color: palette.disabled,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 16, color: context.palette.muted),
      ),
    ),
  );
}

class _SourcesButton extends StatelessWidget {
  const _SourcesButton({required this.sources, this.onOpen});

  final List<ChatSource> sources;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            backgroundColor: palette.panel,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Fontes usadas',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  for (final source in sources)
                    ListTile(
                      leading: const Icon(Icons.link_rounded, size: 20),
                      title: Text(
                        source.title.isEmpty ? source.url : source.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        source.snippet.isEmpty ? source.url : source.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: source.url.isEmpty
                          ? null
                          : const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: source.url.isEmpty
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              onOpen?.call(source.url);
                            },
                    ),
                ],
              ),
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: palette.muted,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 34),
            textStyle: const TextStyle(fontSize: 11.5),
          ),
          icon: const Icon(Icons.link_rounded, size: 14),
          label: Text('Fontes · ${sources.length}'),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5, top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: palette.primary.withValues(
                  alpha:
                      0.25 +
                      0.75 *
                          (0.5 +
                              0.5 *
                                  (1 -
                                      ((_controller.value - i * 0.2).abs() *
                                              2.5)
                                          .clamp(0.0, 1.0))),
                ),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime? date) {
  final value = date ?? DateTime.now();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
