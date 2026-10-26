import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_surface.dart';
import '../../core/attachment_picker.dart';
import '../../core/backend_client.dart';
import '../chat/models/chat_models.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({
    super.key,
    required this.client,
    required this.connected,
    this.onOpenInChat,
  });

  final BackendClient client;
  final bool connected;
  final ValueChanged<ChatAttachment>? onOpenInChat;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  final Map<int, Future<Uint8List?>> _bytesCache = {};
  List<ChatAttachment> _items = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected && widget.connected) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.client.attachments();
      if (!mounted) return;
      setState(() {
        _items = rows.map(ChatAttachment.fromJson).toList();
        _bytesCache.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _bytes(ChatAttachment attachment) {
    final id = attachment.id;
    if (id == null) return Future.value(attachment.bytes);
    return _bytesCache.putIfAbsent(id, () async {
      try {
        return await widget.client.attachmentBytes(id);
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> _upload() async {
    if (!widget.connected) return;
    try {
      final picked = await pickAttachment();
      if (picked == null) return;
      setState(() => _uploading = true);
      await widget.client.uploadAttachment(
        picked.name,
        picked.bytes,
        mime: picked.mime,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo enviado para o backend.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(ChatAttachment attachment) async {
    final id = attachment.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar anexo?'),
        content: Text(
          'O arquivo “${attachment.filename}” será removido do backend. '
          'As mensagens que já usam esse anexo deixarão de exibir a prévia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.client.deleteAttachment(id);
      _bytesCache.remove(id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _open(ChatAttachment attachment) async {
    if (attachment.isImage) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: context.palette.panel,
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          attachment.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dialogContext.palette.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: FutureBuilder<Uint8List?>(
                    future: _bytes(attachment),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(48),
                          child: CircularProgressIndicator(),
                        );
                      }
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            'Não foi possível carregar a imagem.',
                            style: TextStyle(color: context.palette.muted),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final id = attachment.id;
    Map<String, dynamic>? detail;
    if (id != null) {
      try {
        detail = await widget.client.attachment(id);
      } catch (_) {
        detail = null;
      }
    }
    if (!mounted) return;
    final extracted = (detail?['extracted_text'] as String? ?? '').trim();
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Icon(
                      _iconFor(attachment),
                      color: palette.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attachment.filename,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${attachment.mime} · ${attachment.sizeLabel}',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (extracted.isNotEmpty)
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.input,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        extracted,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12.5,
                          height: 1.5,
                          fontFamily: attachment.isText ? 'monospace' : null,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    attachment.isText
                        ? 'Este arquivo não tem texto legível para prévia.'
                        : 'Prévia disponível apenas para imagens e arquivos de texto.',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    if (widget.onOpenInChat != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          widget.onOpenInChat!(attachment);
                        },
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                        label: const Text('Usar em uma conversa'),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _delete(attachment);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('Apagar'),
                      style: TextButton.styleFrom(foregroundColor: palette.danger),
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

  List<ChatAttachment> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where(
          (item) =>
              item.filename.toLowerCase().contains(query) ||
              item.mime.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filtered = _filtered;
    return Column(
      children: [
        AppPageHeader(
          title: 'Arquivos',
          subtitle: 'Anexos guardados no seu backend',
          actions: [
            IconButton(
              tooltip: 'Enviar arquivo',
              onPressed: widget.connected && !_uploading ? _upload : null,
              icon: _uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final horizontal = constraints.maxWidth >= 1000
                  ? (constraints.maxWidth - 900) / 2
                  : compact
                  ? 16.0
                  : 24.0;
              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      compact ? 12 : 18,
                      horizontal,
                      8,
                    ),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: palette.input,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: palette.border),
                      ),
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        style: TextStyle(color: palette.text, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou tipo…',
                          hintStyle: TextStyle(
                            color: palette.disabled,
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: palette.muted,
                          ),
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.connected)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        4,
                        horizontal,
                        8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 15,
                            color: palette.danger,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Backend offline. A lista pode estar desatualizada.',
                              style: TextStyle(
                                color: palette.danger,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        4,
                        horizontal,
                        8,
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: palette.danger, fontSize: 12),
                      ),
                    ),
                  Expanded(
                    child: _loading && _items.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: filtered.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      SizedBox(
                                        height: compact ? 360 : 440,
                                        child: AppEmptyState(
                                          icon: _query.isEmpty
                                              ? Icons.folder_open_rounded
                                              : Icons.search_off_rounded,
                                          title: _query.isEmpty
                                              ? 'Nenhum arquivo ainda'
                                              : 'Nenhum arquivo encontrado',
                                          message: _query.isEmpty
                                              ? 'Anexe uma imagem ou um arquivo na conversa, ou envie por aqui.'
                                              : 'Tente outro nome ou tipo de arquivo.',
                                          action: _query.isEmpty &&
                                                  widget.connected
                                              ? FilledButton.icon(
                                                  onPressed: _upload,
                                                  icon: const Icon(
                                                    Icons.upload_file_rounded,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Enviar arquivo',
                                                  ),
                                                )
                                              : null,
                                          compact: compact,
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(
                                      horizontal,
                                      2,
                                      horizontal,
                                      24,
                                    ),
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final attachment = filtered[index];
                                      return _AttachmentTile(
                                        attachment: attachment,
                                        bytes: _bytes,
                                        onTap: () => _open(attachment),
                                        onDelete: () => _delete(attachment),
                                      );
                                    },
                                  ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.bytes,
    required this.onTap,
    required this.onDelete,
  });

  final ChatAttachment attachment;
  final Future<Uint8List?> Function(ChatAttachment) bytes;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 46,
              height: 46,
              child: attachment.isImage
                  ? FutureBuilder<Uint8List?>(
                      future: bytes(attachment),
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        if (data == null) {
                          return _FileIcon(
                            icon: Icons.image_outlined,
                            color: palette.primary,
                          );
                        }
                        return Image.memory(
                          data,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => _FileIcon(
                            icon: Icons.broken_image_outlined,
                            color: palette.muted,
                          ),
                        );
                      },
                    )
                  : _FileIcon(
                      icon: _iconFor(attachment),
                      color: attachment.isText
                          ? palette.violet
                          : palette.primary,
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${attachment.sizeLabel} · ${_kindLabel(attachment)} · '
                  '${_formatDate(attachment.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Apagar anexo',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: palette.disabled,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: palette.disabled,
          ),
        ],
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    color: context.palette.input,
    child: Icon(icon, color: color, size: 22),
  );
}

IconData _iconFor(ChatAttachment attachment) {
  final extension = attachment.extension.toLowerCase();
  if (extension == 'pdf') return Icons.picture_as_pdf_outlined;
  if (['csv', 'xls', 'xlsx'].contains(extension)) {
    return Icons.table_chart_outlined;
  }
  if (['doc', 'docx', 'odt', 'rtf'].contains(extension)) {
    return Icons.description_outlined;
  }
  if (['zip', 'tar', 'gz', 'rar', '7z'].contains(extension)) {
    return Icons.folder_zip_outlined;
  }
  if ([
    'py', 'dart', 'js', 'ts', 'html', 'css', 'json', 'sh', 'rs', 'go',
    'java', 'c', 'cpp', 'h', 'sql',
  ].contains(extension)) {
    return Icons.code_rounded;
  }
  if (attachment.isImage) return Icons.image_outlined;
  return Icons.insert_drive_file_outlined;
}

String _kindLabel(ChatAttachment attachment) {
  if (attachment.isImage) return 'Imagem';
  if (attachment.isText) return 'Texto';
  return 'Arquivo';
}

String _formatDate(DateTime? date) {
  if (date == null) return 'sem data';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
