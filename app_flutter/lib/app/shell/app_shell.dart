import 'package:flutter/material.dart';

import '../../features/chat/widgets/conversation_accordion.dart';
import '../app_section.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';

/// Estrutura responsiva do Chat.
///
/// Desktop largo: barra lateral + histórico + conteúdo.
/// Desktop compacto: barra lateral em ícones + conteúdo, com histórico em
/// gaveta. Celular: conteúdo e histórico em gaveta, com a navegação principal
/// dentro dela para liberar a tela inteira para a conversa.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.onSection,
    required this.conversations,
    required this.selectedConversationId,
    required this.busyConversationIds,
    required this.conversationsLoading,
    required this.search,
    required this.onSearchChanged,
    required this.onSelectConversation,
    required this.onDeleteConversation,
    required this.onNewConversation,
    required this.builder,
    required this.connected,
    this.onVoice,
    this.voiceActive = false,
    this.busy = false,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSection;
  final List<Map<String, dynamic>> conversations;
  final int? selectedConversationId;
  final Set<int> busyConversationIds;
  final bool conversationsLoading;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onSelectConversation;
  final ValueChanged<int> onDeleteConversation;
  final VoidCallback onNewConversation;
  final Widget Function(
    BuildContext context,
    bool compact,
    VoidCallback openHistory,
  )
  builder;
  final bool connected;
  final VoidCallback? onVoice;
  final bool voiceActive;
  final bool busy;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _sidebarExpanded = true;

  void _openHistory() => _scaffoldKey.currentState?.openDrawer();

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _selectConversation(int id) {
    _closeDrawer();
    widget.onSelectConversation(id);
  }

  void _newConversation() {
    _closeDrawer();
    widget.onNewConversation();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 900;
        final expanded = width >= 1240 && _sidebarExpanded;
        final showHistory = width >= 1240;
        if (compact) {
          return Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: false,
            backgroundColor: context.palette.background,
            drawer: _buildDrawer(context),
            body: SafeArea(
              top: true,
              bottom: false,
              left: false,
              right: false,
              child: widget.builder(context, true, _openHistory),
            ),
          );
        }
        return Scaffold(
          key: _scaffoldKey,
          resizeToAvoidBottomInset: false,
          backgroundColor: context.palette.background,
          drawer: width < 1240 ? _buildDrawer(context) : null,
          body: SafeArea(
            top: false,
            bottom: false,
            left: false,
            right: false,
            child: Row(
              children: [
                _Sidebar(
                  section: widget.section,
                  onSection: widget.onSection,
                  expanded: expanded,
                  onToggle: () =>
                      setState(() => _sidebarExpanded = !_sidebarExpanded),
                  onNewConversation: _newConversation,
                  onVoice: widget.onVoice,
                  voiceActive: widget.voiceActive,
                  connected: widget.connected,
                ),
                if (showHistory)
                  SizedBox(
                    width: 324,
                    child: _HistoryPanel(
                      conversations: widget.conversations,
                      selectedId: widget.selectedConversationId,
                      busyIds: widget.busyConversationIds,
                      loading: widget.conversationsLoading,
                      search: widget.search,
                      onSearchChanged: widget.onSearchChanged,
                      onSelect: _selectConversation,
                      onDelete: widget.onDeleteConversation,
                      onNewConversation: _newConversation,
                    ),
                  ),
                Expanded(child: widget.builder(context, false, _openHistory)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final palette = context.palette;
    return Drawer(
      width: 342,
      backgroundColor: palette.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ConversationAccordion(
                embedded: true,
                showTitle: true,
                conversations: widget.conversations,
                selectedId: widget.selectedConversationId,
                busyIds: widget.busyConversationIds,
                loading: widget.conversationsLoading,
                search: widget.search,
                onSearchChanged: widget.onSearchChanged,
                onSelect: _selectConversation,
                onDelete: widget.onDeleteConversation,
                onNewConversation: _newConversation,
              ),
            ),
            _DrawerStatus(connected: widget.connected),
            _DrawerNavigation(
              section: widget.section,
              onSection: (section) {
                _closeDrawer();
                widget.onSection(section);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.onSection,
    required this.expanded,
    required this.onToggle,
    required this.onNewConversation,
    required this.onVoice,
    required this.voiceActive,
    required this.connected,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSection;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onNewConversation;
  final VoidCallback? onVoice;
  final bool voiceActive;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? 222 : 78,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(expanded ? 16 : 12, 18, 12, 16),
            child: expanded
                ? Row(
                    children: [
                      const AppLogo(size: 38),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Chat',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Recolher menu',
                        onPressed: onToggle,
                        icon: Icon(
                          Icons.keyboard_double_arrow_left_rounded,
                          size: 18,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      const AppLogo(size: 38),
                      const SizedBox(height: 6),
                      IconButton(
                        tooltip: 'Expandir menu',
                        onPressed: onToggle,
                        icon: Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          size: 18,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 14),
            child: expanded
                ? SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: onNewConversation,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Nova conversa'),
                    ),
                  )
                : Tooltip(
                    message: 'Nova conversa',
                    child: Material(
                      color: palette.primary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: onNewConversation,
                        child: const SizedBox(
                          height: 44,
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in const [
                  AppSection.chat,
                  AppSection.explore,
                  AppSection.files,
                  AppSection.settings,
                ])
                  _SidebarItem(
                    section: item,
                    selected: section == item,
                    expanded: expanded,
                    onTap: () => onSection(item),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: expanded ? 18 : 22,
                    vertical: 10,
                  ),
                  child: Divider(color: palette.border, height: 1),
                ),
                _SidebarItem(
                  section: AppSection.computer,
                  selected: section == AppSection.computer,
                  expanded: expanded,
                  onTap: () => onSection(AppSection.computer),
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Row(
                children: [
                  StatusDot(active: connected, size: 7),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      connected ? 'Conectado' : 'Offline',
                      style: TextStyle(
                        color: connected ? palette.muted : palette.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              expanded ? 12 : 12,
              4,
              expanded ? 12 : 12,
              14,
            ),
            child: _VoiceCommand(
              expanded: expanded,
              active: voiceActive,
              onTap: onVoice,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final AppSection section;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = widget.selected;
    final item = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.expanded ? 10 : 12,
        vertical: 2,
      ),
      child: Tooltip(
        message: widget.expanded ? '' : widget.section.label,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hover = value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 44,
              padding: EdgeInsets.symmetric(
                horizontal: widget.expanded ? 12 : 0,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? palette.selected
                    : _hover
                    ? palette.hover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                mainAxisAlignment: widget.expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    selected
                        ? widget.section.selectedIcon
                        : widget.section.icon,
                    size: 20,
                    color: selected ? palette.primary : palette.muted,
                  ),
                  if (widget.expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.section.label,
                        style: TextStyle(
                          color: selected ? palette.text : palette.muted,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: widget.section.label,
      child: item,
    );
  }
}

class _VoiceCommand extends StatelessWidget {
  const _VoiceCommand({
    required this.expanded,
    required this.active,
    required this.onTap,
  });

  final bool expanded;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: active ? palette.primary.withValues(alpha: 0.18) : palette.card,
        shape: BoxShape.circle,
        border: Border.all(
          color: active
              ? palette.primary.withValues(alpha: 0.5)
              : palette.border,
        ),
      ),
      child: Icon(
        active ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
        size: 19,
        color: active ? palette.primary : palette.muted,
      ),
    );
    return Tooltip(
      message: 'Comando de voz',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 6 : 0,
              vertical: 6,
            ),
            child: expanded
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          active ? 'Ouvindo…' : 'Voz',
                          style: TextStyle(
                            color: active ? palette.primary : palette.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({
    required this.conversations,
    required this.selectedId,
    required this.busyIds,
    required this.loading,
    required this.search,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onDelete,
    required this.onNewConversation,
  });

  final List<Map<String, dynamic>> conversations;
  final int? selectedId;
  final Set<int> busyIds;
  final bool loading;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onDelete;
  final VoidCallback onNewConversation;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ConversationAccordion(
              embedded: true,
              conversations: conversations,
              selectedId: selectedId,
              busyIds: busyIds,
              loading: loading,
              search: search,
              onSearchChanged: onSearchChanged,
              onSelect: onSelect,
              onDelete: onDelete,
              onNewConversation: onNewConversation,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerStatus extends StatelessWidget {
  const _DrawerStatus({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          StatusDot(active: connected, size: 7),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              connected ? 'Conectado ao backend' : 'Backend offline',
              style: TextStyle(
                color: connected ? palette.muted : palette.danger,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Navegação principal na gaveta: substitui a antiga barra inferior e deixa
/// a conversa ocupar toda a altura da tela.
class _DrawerNavigation extends StatelessWidget {
  const _DrawerNavigation({required this.section, required this.onSection});

  final AppSection section;
  final ValueChanged<AppSection> onSection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = AppSection.values.where((item) => item.isPrimary).toList();
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        children: [
          for (var row = 0; row < 2; row++)
            Row(
              children: [
                for (final item in items.skip(row * 2).take(2))
                  Expanded(
                    child: _DrawerNavItem(
                      key: ValueKey('drawer-nav-${item.name}'),
                      section: item,
                      selected: section == item,
                      onTap: () => onSection(item),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    super.key,
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      label: section.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? palette.primary.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  selected ? section.selectedIcon : section.icon,
                  size: 18,
                  color: selected ? palette.primary : palette.muted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    section.label,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected ? palette.text : palette.muted,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
