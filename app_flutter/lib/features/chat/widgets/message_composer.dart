import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../models/chat_models.dart';
import 'attachment_preview.dart';

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.attachments,
    required this.busy,
    required this.offline,
    required this.recording,
    required this.speaking,
    required this.uploading,
    required this.onSend,
    required this.onVoice,
    required this.onPickFile,
    required this.onPickImage,
    required this.onRemoveAttachment,
    required this.onOpenComputer,
    required this.onInsertLink,
    this.loadAttachment,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<ChatAttachment> attachments;
  final bool busy;
  final bool offline;
  final bool recording;
  final bool speaking;
  final bool uploading;
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final ValueChanged<ChatAttachment> onRemoveAttachment;
  final VoidCallback onOpenComputer;
  final VoidCallback onInsertLink;
  final AttachmentBytesLoader? loadAttachment;
  final bool compact;

  bool get _canSend =>
      !busy &&
      !offline &&
      !uploading &&
      (controller.text.trim().isNotEmpty || attachments.isNotEmpty);

  Future<void> _openTools(BuildContext context) async {
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Anexar arquivo'),
              onTap: () {
                Navigator.pop(sheetContext);
                onPickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Enviar imagem'),
              onTap: () {
                Navigator.pop(sheetContext);
                onPickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal_rounded),
              title: const Text('Tarefa no computador'),
              subtitle: const Text('Executar no Ubuntu com OpenCode'),
              onTap: () {
                Navigator.pop(sheetContext);
                onOpenComputer();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Inserir link'),
              onTap: () {
                Navigator.pop(sheetContext);
                onInsertLink();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mobile = Platform.isAndroid || Platform.isIOS;
    final actionSize = compact ? 42.0 : 44.0;
    return Container(
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 7 : 9,
        compact ? 7 : 8,
        compact ? 7 : 9,
        compact ? 7 : 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in attachments)
                      AttachmentPreview(
                        attachment: attachment,
                        loadBytes: loadAttachment,
                        compact: true,
                        onRemove: () => onRemoveAttachment(attachment),
                      ),
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ComposerIconButton(
                size: actionSize,
                tooltip: 'Anexar ou inserir',
                icon: Icons.add_rounded,
                onPressed: offline ? null : () => _openTools(context),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  enabled: !busy && !offline,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: mobile
                      ? TextInputAction.newline
                      : TextInputAction.send,
                  keyboardType: TextInputType.multiline,
                  onSubmitted: (_) {
                    if (!mobile && _canSend) onSend();
                  },
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: recording
                        ? 'Ouvindo…'
                        : offline
                        ? 'Sem conexão com o notebook'
                        : 'Perguntar ao Chat…',
                    hintStyle: TextStyle(
                      color: recording ? palette.danger : palette.disabled,
                      fontSize: 15,
                    ),
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasText =
                      value.text.trim().isNotEmpty || attachments.isNotEmpty;
                  return _ComposerAction(
                    size: actionSize,
                    hasText: hasText,
                    busy: busy || uploading,
                    enabled: _canSend,
                    offline: offline,
                    recording: recording,
                    speaking: speaking,
                    onSend: onSend,
                    onVoice: onVoice,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.size,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final double size;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: 23,
              color: onPressed == null ? palette.disabled : palette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.size,
    required this.hasText,
    required this.busy,
    required this.enabled,
    required this.offline,
    required this.recording,
    required this.speaking,
    required this.onSend,
    required this.onVoice,
  });

  final double size;
  final bool hasText;
  final bool busy;
  final bool enabled;
  final bool offline;
  final bool recording;
  final bool speaking;
  final VoidCallback onSend;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = recording || speaking;
    final sendMode = hasText;
    final canTap = sendMode ? enabled : !busy && !offline;
    final background = active
        ? palette.danger
        : sendMode
        ? palette.primary
        : palette.primary.withValues(alpha: 0.92);
    final icon = active
        ? Icons.stop_rounded
        : sendMode
        ? Icons.arrow_upward_rounded
        : Icons.mic_none_rounded;
    final tooltip = active
        ? 'Parar'
        : sendMode
        ? 'Enviar'
        : 'Falar';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: canTap
                ? (sendMode ? onSend : onVoice)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: canTap ? background : palette.card,
              ),
              child: busy
                  ? Padding(
                      padding: EdgeInsets.all(size * 0.28),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: canTap ? Colors.white : palette.disabled,
                      ),
                    )
                  : Icon(
                      icon,
                      color: canTap ? Colors.white : palette.disabled,
                      size: size * 0.46,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
