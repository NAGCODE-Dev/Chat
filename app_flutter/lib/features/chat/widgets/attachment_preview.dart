import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../models/chat_models.dart';

typedef AttachmentBytesLoader = Future<Uint8List?> Function(ChatAttachment);

class AttachmentPreview extends StatefulWidget {
  const AttachmentPreview({
    super.key,
    required this.attachment,
    this.loadBytes,
    this.onRemove,
    this.onOpen,
    this.compact = false,
  });

  final ChatAttachment attachment;
  final AttachmentBytesLoader? loadBytes;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;
  final bool compact;

  @override
  State<AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<AttachmentPreview> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant AttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.bytes != widget.attachment.bytes) {
      _prepare();
    }
  }

  void _prepare() {
    final bytes = widget.attachment.bytes;
    if (bytes != null) {
      _future = Future.value(bytes);
    } else if (widget.attachment.id != null && widget.loadBytes != null) {
      _future = widget.loadBytes!(widget.attachment);
    } else {
      _future = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachment.isImage) {
      return _buildImage(context);
    }
    return _buildFile(context);
  }

  Widget _buildImage(BuildContext context) {
    final palette = context.palette;
    final height = widget.compact ? 88.0 : 148.0;
    final width = widget.compact ? 112.0 : 196.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: width,
        height: height,
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: palette.input,
                  child: bytes != null
                      ? Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => _placeholder(palette),
                        )
                      : snapshot.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _placeholder(palette),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onOpen,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (widget.onRemove != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _RemoveButton(onPressed: widget.onRemove!),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _placeholder(AppPalette palette) => Center(
    child: Icon(Icons.image_outlined, color: palette.muted, size: 28),
  );

  Widget _buildFile(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: BoxConstraints(maxWidth: widget.compact ? 220 : 320),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.input.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _iconFor(widget.attachment),
              color: palette.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.attachment.sizeLabel,
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (widget.onRemove != null) ...[
            const SizedBox(width: 4),
            _RemoveButton(onPressed: widget.onRemove!),
          ],
        ],
      ),
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
    if (['py', 'dart', 'js', 'ts', 'html', 'css', 'json', 'sh', 'rs', 'go',
      'java', 'c', 'cpp', 'h', 'sql'].contains(extension)) {
      return Icons.code_rounded;
    }
    return Icons.insert_drive_file_outlined;
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.background.withValues(alpha: 0.75),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(Icons.close_rounded, size: 14, color: context.palette.text),
      ),
    ),
  );
}
