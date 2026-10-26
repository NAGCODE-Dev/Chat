import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../models/chat_models.dart';

class ConversationAccordion extends StatefulWidget {
  const ConversationAccordion({
    super.key,
    required this.conversations,
    required this.selectedId,
    required this.busyIds,
    required this.search,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onDelete,
    required this.onNewConversation,
    this.loading = false,
    this.embedded = false,
    this.footer,
    this.onClose,
    this.showClose = false,
    this.showTitle = false,
  });

  final List<Map<String, dynamic>> conversations;
  final int? selectedId;
  final Set<int> busyIds;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onDelete;
  final VoidCallback onNewConversation;
  final bool loading;
  final bool embedded;
  final Widget? footer;
  final VoidCallback? onClose;
  final bool showClose;
  final bool showTitle;

  @override
  State<ConversationAccordion> createState() => _ConversationAccordionState();
}

class _ConversationAccordionState extends State<ConversationAccordion> {
  final Set<String> _collapsed = {};
  bool _searchOpen = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filtered = _filtered(widget.conversations);
    final groups = _group(filtered);
    final searching = widget.search.trim().isNotEmpty;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopBar(context),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (filtered.isEmpty)
          _buildEmpty(context, searching)
        else
          for (final entry in groups.entries) ...[
            _buildGroupHeader(context, entry.key, entry.value.length),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: (searching || !_collapsed.contains(entry.key))
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final conversation in entry.value)
                          ConversationTile(
                            conversation: conversation,
                            selected:
                                (conversation['id'] as num?)?.toInt() ==
                                widget.selectedId,
                            busy: widget.busyIds.contains(
                              (conversation['id'] as num?)?.toInt(),
                            ),
                            onTap: () {
                              final id = (conversation['id'] as num?)?.toInt();
                              if (id != null) widget.onSelect(id);
                            },
                            onDelete: () {
                              final id = (conversation['id'] as num?)?.toInt();
                              if (id != null) widget.onDelete(id);
                            },
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        if (widget.footer != null) ...[
          Divider(height: 24, color: palette.border),
          widget.footer!,
        ],
      ],
    );
    if (widget.embedded) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [content],
      );
    }
    return content;
  }

  Widget _buildTopBar(BuildContext context) {
    final palette = context.palette;
    final showSearch = !widget.showTitle || _searchOpen || widget.search.isNotEmpty;
    if (widget.showTitle && !showSearch) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Chat',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            _RoundIconButton(
              tooltip: 'Buscar conversas',
              icon: Icons.search_rounded,
              onPressed: () => setState(() => _searchOpen = true),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              tooltip: 'Nova conversa',
              icon: Icons.add_rounded,
              background: palette.primary,
              foreground: Colors.white,
              onPressed: widget.onNewConversation,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.showTitle ? 12 : 14,
        widget.showTitle ? 8 : 14,
        14,
        10,
      ),
      child: Row(
        children: [
          if (widget.showClose && !widget.showTitle) ...[
            IconButton(
              tooltip: 'Fechar histórico',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
            const SizedBox(width: 2),
          ],
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: palette.input,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: TextField(
                autofocus: widget.showTitle && _searchOpen,
                onChanged: widget.onSearchChanged,
                style: TextStyle(color: palette.text, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Buscar conversas…',
                  hintStyle: TextStyle(color: palette.disabled, fontSize: 13.5),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: palette.muted,
                  ),
                  suffixIcon: widget.search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            widget.onSearchChanged('');
                            if (widget.showTitle) {
                              setState(() => _searchOpen = false);
                            }
                          },
                        ),
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!(widget.showTitle && _searchOpen))
            _RoundIconButton(
              tooltip: 'Nova conversa',
              icon: Icons.add_rounded,
              background: palette.primary,
              foreground: Colors.white,
              onPressed: widget.onNewConversation,
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool searching) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.forum_outlined,
            color: palette.disabled,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            searching
                ? 'Nenhuma conversa encontrada.'
                : 'Nenhuma conversa ainda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          if (!searching) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: widget.onNewConversation,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Começar uma conversa'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupHeader(BuildContext context, String label, int count) {
    final palette = context.palette;
    final collapsed = _collapsed.contains(label) && widget.search.trim().isEmpty;
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(label);
        } else {
          _collapsed.add(label);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: palette.disabled,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: palette.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> source) {
    final query = widget.search.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((conversation) {
      final title = (conversation['title'] as String? ?? '').toLowerCase();
      final preview = (conversation['last_message'] as String? ?? '')
          .toLowerCase();
      return title.contains(query) || preview.contains(query);
    }).toList();
  }
}

class ConversationTile extends StatefulWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onDelete,
  });

  final Map<String, dynamic> conversation;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = (widget.conversation['title'] as String? ?? 'Conversa').trim();
    final updated = _parseDate(widget.conversation['updated_at']);
    final showMenu = _hover || widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: widget.onTap,
            onLongPress: () => _showActions(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: widget.selected
                    ? palette.selected
                    : _hover
                    ? palette.hover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.isEmpty ? 'Nova conversa' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13.5,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.busy)
                    SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: palette.primary,
                      ),
                    )
                  else if (showMenu)
                    _TileMenu(onDelete: widget.onDelete)
                  else
                    Text(
                      _timeLabel(updated),
                      style: TextStyle(
                        color: palette.disabled,
                        fontSize: 10.5,
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

  Future<void> _showActions(BuildContext context) async {
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
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Apagar conversa'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TileMenu extends StatelessWidget {
  const _TileMenu({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 26,
    child: PopupMenuButton<void>(
      tooltip: 'Opções da conversa',
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: Icon(Icons.more_horiz_rounded, color: context.palette.muted),
      onSelected: (_) {},
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: onDelete,
          child: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('Apagar conversa'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.background,
    this.foreground,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background ?? palette.input,
          foregroundColor: foreground ?? palette.text,
          minimumSize: const Size(38, 38),
          fixedSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

Map<String, List<Map<String, dynamic>>> _group(
  List<Map<String, dynamic>> conversations,
) {
  final groups = <String, List<Map<String, dynamic>>>{
    'Hoje': [],
    'Ontem': [],
    'Últimos 7 dias': [],
    'Anteriores': [],
  };
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final conversation in conversations) {
    final date = _parseDate(conversation['updated_at']);
    if (date == null) {
      groups['Anteriores']!.add(conversation);
      continue;
    }
    final day = DateTime(date.year, date.month, date.day);
    final difference = today.difference(day).inDays;
    if (difference <= 0) {
      groups['Hoje']!.add(conversation);
    } else if (difference == 1) {
      groups['Ontem']!.add(conversation);
    } else if (difference <= 7) {
      groups['Últimos 7 dias']!.add(conversation);
    } else {
      groups['Anteriores']!.add(conversation);
    }
  }
  groups.removeWhere((_, value) => value.isEmpty);
  return groups;
}

DateTime? _parseDate(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return parseBackendDate(raw);
}

String _timeLabel(DateTime? date) {
  if (date == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
  if (difference == 1) return 'Ontem';
  if (difference <= 7) {
    const weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    return weekdays[date.weekday - 1];
  }
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}';
}
