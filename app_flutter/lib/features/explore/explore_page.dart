import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_logo.dart';
import '../../app/widgets/app_surface.dart';
import '../../core/backend_client.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    super.key,
    required this.client,
    required this.connected,
    required this.conversationCount,
    required this.isAndroid,
    required this.supportsClock,
    required this.assistantEnabled,
    required this.notificationsEnabled,
    required this.onOpenFeature,
    required this.onOpenFinance,
    required this.onOpenComputer,
    required this.onOpenFiles,
    required this.onOpenSettings,
    required this.onOpenPhoneAssistant,
    required this.onOpenQr,
    required this.onOpenClock,
    required this.onRetry,
  });

  final BackendClient client;
  final bool connected;
  final int conversationCount;
  final bool isAndroid;
  final bool supportsClock;
  final bool assistantEnabled;
  final bool notificationsEnabled;
  final ValueChanged<String> onOpenFeature;
  final VoidCallback onOpenFinance;
  final VoidCallback onOpenComputer;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPhoneAssistant;
  final VoidCallback onOpenQr;
  final VoidCallback onOpenClock;
  final VoidCallback onRetry;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  int? _memories;
  int? _wishlist;
  int? _devices;
  int? _attachments;
  Map<String, dynamic>? _ubuntu;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExplorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected && widget.connected) {
      _load();
    }
  }

  Future<int?> _count(Future<List<Map<String, dynamic>>> future) async {
    try {
      return (await future).length;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (!widget.connected) {
      if (mounted) {
        setState(() {
          _memories = null;
          _wishlist = null;
          _devices = null;
          _attachments = null;
          _ubuntu = null;
        });
      }
      return;
    }
    setState(() => _loading = true);
    final counts = await Future.wait<int?>([
      _count(widget.client.memories()),
      _count(widget.client.wishlist()),
      _count(widget.client.devices()),
      _count(widget.client.attachments()),
    ]);
    Map<String, dynamic>? ubuntu;
    try {
      ubuntu = await widget.client.ubuntuStatus();
    } catch (_) {
      ubuntu = null;
    }
    if (!mounted) return;
    setState(() {
      _memories = counts[0];
      _wishlist = counts[1];
      _devices = counts[2];
      _attachments = counts[3];
      _ubuntu = ubuntu;
      _loading = false;
    });
  }

  String get _ubuntuLabel {
    final status = _ubuntu;
    if (status == null) return 'Status indisponível';
    if (status['configured'] != true) return 'Agente não configurado';
    if (status['reachable'] != true) return 'Agente offline';
    if (status['opencode_available'] != true) return 'OpenCode indisponível';
    return 'OpenCode pronto';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final features = <_ExploreFeature>[
      _ExploreFeature(
        icon: Icons.psychology_outlined,
        title: 'Memórias',
        subtitle: 'Fatos e preferências que você ensinou',
        count: _memories,
        color: palette.primary,
        onTap: () => widget.onOpenFeature('memories'),
      ),
      _ExploreFeature(
        icon: Icons.shopping_bag_outlined,
        title: 'Lista de desejos',
        subtitle: 'Itens para comprar, fazer ou guardar',
        count: _wishlist,
        color: palette.violet,
        onTap: () => widget.onOpenFeature('wishlist'),
      ),
      _ExploreFeature(
        icon: Icons.devices_outlined,
        title: 'Dispositivos',
        subtitle: 'Aparelhos cadastrados e Wake-on-LAN',
        count: _devices,
        color: palette.success,
        onTap: () => widget.onOpenFeature('devices'),
      ),
      _ExploreFeature(
        icon: Icons.folder_copy_outlined,
        title: 'Arquivos',
        subtitle: 'Anexos enviados nas conversas',
        count: _attachments,
        color: palette.primary,
        onTap: widget.onOpenFiles,
      ),
      _ExploreFeature(
        icon: Icons.savings_outlined,
        title: 'Meu Dinheiro',
        subtitle: 'Lançamentos, gastos e resumo do mês',
        color: palette.success,
        onTap: widget.onOpenFinance,
      ),
      _ExploreFeature(
        icon: Icons.terminal_rounded,
        title: 'Computador',
        subtitle: _ubuntuLabel,
        color: palette.violet,
        onTap: widget.onOpenComputer,
      ),
      if (widget.isAndroid)
        _ExploreFeature(
          icon: Icons.assistant_outlined,
          title: 'Assistente do celular',
          subtitle: widget.assistantEnabled
              ? 'Ativo${widget.notificationsEnabled ? ' · notificações liberadas' : ''}'
              : 'Definir como assistente padrão',
          color: palette.primary,
          onTap: widget.onOpenPhoneAssistant,
        ),
      if (widget.isAndroid)
        _ExploreFeature(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Parear celular',
          subtitle: 'Conectar sem copiar token',
          color: palette.muted,
          onTap: widget.onOpenQr,
        )
      else
        _ExploreFeature(
          icon: Icons.qr_code_2_rounded,
          title: 'Parear celular',
          subtitle: 'Gerar QR code para conectar',
          color: palette.muted,
          onTap: widget.onOpenQr,
        ),
      if (widget.supportsClock)
        _ExploreFeature(
          icon: Icons.schedule_outlined,
          title: 'Modo relógio',
          subtitle: 'Tela cheia com relógio e hibernação',
          color: palette.muted,
          onTap: widget.onOpenClock,
        ),
      _ExploreFeature(
        icon: Icons.tune_rounded,
        title: 'Configurações',
        subtitle: 'Conexão, modelo, voz e aparência',
        color: palette.muted,
        onTap: widget.onOpenSettings,
      ),
    ];

    return Column(
      children: [
        AppPageHeader(
          title: 'Explorar',
          subtitle: 'Recursos do seu assistente',
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final horizontal = constraints.maxWidth >= 1100
                  ? (constraints.maxWidth - 1040) / 2
                  : compact
                  ? 16.0
                  : 24.0;
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    compact ? 16 : 24,
                    horizontal,
                    28,
                  ),
                  children: [
                    _buildHero(context, compact),
                    const SizedBox(height: 22),
                    const SectionLabel('Recursos'),
                    _buildGrid(context, features, constraints.maxWidth),
                    const SizedBox(height: 18),
                    Text(
                      'Os números acima vêm do seu backend. Nada é simulado.',
                      style: TextStyle(color: palette.disabled, fontSize: 10.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context, bool compact) {
    final palette = context.palette;
    final connected = widget.connected;
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.card,
            palette.primary.withValues(alpha: palette.isDark ? 0.13 : 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        connected ? 'Conectado ao notebook' : 'Backend offline',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: compact ? 15 : 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusChip(
                      label: connected ? 'Online' : 'Offline',
                      color: connected ? palette.success : palette.danger,
                      icon: connected
                          ? Icons.check_circle_outline_rounded
                          : Icons.cloud_off_outlined,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? 'Seu assistente roda no seu notebook.'
                      : 'Verifique se o notebook está ligado.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MiniFact(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '${widget.conversationCount} conversa(s)',
                    ),
                    if (_memories != null)
                      _MiniFact(
                        icon: Icons.psychology_outlined,
                        label: '$_memories memória(s)',
                      ),
                    if (_attachments != null)
                      _MiniFact(
                        icon: Icons.folder_copy_outlined,
                        label: '$_attachments arquivo(s)',
                      ),
                  ],
                ),
                if (!connected) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Tentar de novo'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<_ExploreFeature> features,
    double width,
  ) {
    final columns = width >= 980 ? 3 : (width >= 620 ? 2 : 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final feature in features)
              SizedBox(
                width: itemWidth,
                child: _FeatureCard(feature: feature),
              ),
          ],
        );
      },
    );
  }
}

class _ExploreFeature {
  const _ExploreFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final int? count;
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.input.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.muted),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: palette.muted, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.feature});

  final _ExploreFeature feature;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final feature = widget.feature;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: feature.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 96,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hover ? palette.hover : palette.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: _hover
                    ? feature.color.withValues(alpha: 0.5)
                    : palette.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: feature.color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(feature.icon, color: feature.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              feature.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (feature.count != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.input,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                '${feature.count}',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feature.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 15,
                  color: palette.disabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
