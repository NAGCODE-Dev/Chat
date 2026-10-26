import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/widgets/app_surface.dart';
import '../../core/backend_client.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.client,
    required this.connected,
    required this.provider,
    required this.model,
    required this.visionModel,
    required this.sttAvailable,
    required this.ttsAvailable,
    required this.muted,
    required this.continuousMode,
    required this.themeMode,
    required this.memoryCount,
    required this.conversationCount,
    required this.isAndroid,
    required this.isAssistant,
    required this.hasNotificationAccess,
    required this.supportsClock,
    required this.clockEnabled,
    required this.onEditConnection,
    required this.onTestConnection,
    required this.onThemeMode,
    required this.onModelSettings,
    required this.onVoicePreferences,
    required this.onToggleMuted,
    required this.onClockPreferences,
    required this.onOpenQr,
    required this.onOpenPhoneAssistant,
    required this.onOpenComputer,
    required this.onOpenFiles,
    required this.onOpenFinance,
    required this.onOpenFeature,
    required this.onRefresh,
  });

  final BackendClient client;
  final bool connected;
  final String provider;
  final String model;
  final String? visionModel;
  final bool sttAvailable;
  final bool ttsAvailable;
  final bool muted;
  final bool continuousMode;
  final ThemeMode themeMode;
  final int memoryCount;
  final int conversationCount;
  final bool isAndroid;
  final bool isAssistant;
  final bool hasNotificationAccess;
  final bool supportsClock;
  final bool clockEnabled;
  final VoidCallback onEditConnection;
  final VoidCallback onTestConnection;
  final ValueChanged<ThemeMode> onThemeMode;
  final VoidCallback onModelSettings;
  final VoidCallback onVoicePreferences;
  final VoidCallback onToggleMuted;
  final VoidCallback onClockPreferences;
  final VoidCallback onOpenQr;
  final VoidCallback onOpenPhoneAssistant;
  final VoidCallback onOpenComputer;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFinance;
  final ValueChanged<String> onOpenFeature;
  final VoidCallback onRefresh;

  String get _voiceLabel {
    if (!sttAvailable && !ttsAvailable) return 'Voz não configurada';
    final parts = <String>[
      if (sttAvailable) 'microfone',
      if (ttsAvailable) 'respostas faladas',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        AppPageHeader(
          title: 'Configurações',
          subtitle: 'Conexão, modelo, voz e dados',
          actions: [
            IconButton(
              tooltip: 'Atualizar status',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final horizontal = constraints.maxWidth >= 1000
                  ? (constraints.maxWidth - 860) / 2
                  : compact
                  ? 16.0
                  : 24.0;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  compact ? 16 : 22,
                  horizontal,
                  30,
                ),
                children: [
                  SettingsGroup(
                    title: 'Conexão',
                    children: [
                      SettingsTile(
                        icon: connected
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        iconColor: connected ? palette.success : palette.danger,
                        title: connected
                            ? 'Backend conectado'
                            : 'Backend offline',
                        subtitle: connected
                            ? 'Conexão protegida com o seu notebook.'
                            : 'Verifique se o notebook está ligado.',
                        trailing: StatusChip(
                          label: connected ? 'Online' : 'Offline',
                          color: connected ? palette.success : palette.danger,
                          compact: true,
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.settings_ethernet_rounded,
                        title: 'Endereço e token',
                        subtitle:
                            'Trocar o endereço do notebook ou o token da API.',
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: onEditConnection,
                      ),
                      SettingsTile(
                        icon: Icons.network_check_rounded,
                        title: 'Testar conexão',
                        subtitle: 'Faz uma chamada curta ao backend e mostra o resultado.',
                        onTap: onTestConnection,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingsGroup(
                    title: 'Aparência',
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: palette.primary.withValues(
                                      alpha: 0.13,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.palette_outlined,
                                    size: 18,
                                    color: palette.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Tema',
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final mode in ThemeMode.values)
                                  ChoiceChip(
                                    selected: themeMode == mode,
                                    onSelected: (_) => onThemeMode(mode),
                                    label: Text(_themeLabel(mode)),
                                    avatar: Icon(
                                      _themeIcon(mode),
                                      size: 16,
                                      color: themeMode == mode
                                          ? palette.primary
                                          : palette.muted,
                                    ),
                                    showCheckmark: false,
                                    selectedColor: palette.selected,
                                    backgroundColor: palette.input,
                                    side: BorderSide(
                                      color: themeMode == mode
                                          ? palette.primary.withValues(
                                              alpha: 0.5,
                                            )
                                          : palette.border,
                                    ),
                                    labelStyle: TextStyle(
                                      color: themeMode == mode
                                          ? palette.text
                                          : palette.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingsGroup(
                    title: 'Modelo',
                    children: [
                      SettingsTile(
                        icon: Icons.memory_rounded,
                        title: model.trim().isEmpty
                            ? 'Modelo não carregado'
                            : model,
                        subtitle: provider.trim().isEmpty
                            ? 'Provider não carregado'
                            : 'Provider: $provider',
                        trailing: TextButton(
                          onPressed: onModelSettings,
                          child: const Text('Alterar'),
                        ),
                      ),
                      if (visionModel != null && visionModel!.trim().isNotEmpty)
                        SettingsTile(
                          icon: Icons.visibility_outlined,
                          title: 'Visão: ${visionModel!}',
                          subtitle:
                              'Modelo usado quando a conversa recebe imagens.',
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingsGroup(
                    title: 'Voz',
                    children: [
                      SettingsTile(
                        icon: Icons.record_voice_over_outlined,
                        title: _voiceLabel,
                        subtitle: sttAvailable
                            ? 'Transcrição e fala processadas no notebook.'
                            : 'Configure o Whisper/Piper no backend para falar.',
                        trailing: TextButton(
                          onPressed: onVoicePreferences,
                          child: const Text('Ajustar'),
                        ),
                      ),
                      SwitchListTile(
                        value: continuousMode,
                        onChanged: (_) => onVoicePreferences(),
                        activeThumbColor: palette.primary,
                        title: Text(
                          'Conversa contínua',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          continuousMode
                              ? 'O microfone volta a ouvir depois de cada resposta.'
                              : 'Desligada; use o microfone para falar.',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 11.5,
                          ),
                        ),
                        secondary: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: palette.violet.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.hearing_outlined,
                            size: 18,
                            color: palette.violet,
                          ),
                        ),
                      ),
                      SwitchListTile(
                        value: !muted,
                        onChanged: (_) => onToggleMuted(),
                        activeThumbColor: palette.primary,
                        title: Text(
                          'Respostas faladas',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          muted
                              ? 'Silenciadas.'
                              : ttsAvailable
                              ? 'O assistente lê as respostas em voz alta.'
                              : 'TTS não configurado no backend.',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 11.5,
                          ),
                        ),
                        secondary: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: palette.success.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            muted
                                ? Icons.volume_off_outlined
                                : Icons.volume_up_outlined,
                            size: 18,
                            color: palette.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (supportsClock) ...[
                    const SizedBox(height: 20),
                    SettingsGroup(
                      title: 'Relógio',
                      children: [
                        SettingsTile(
                          icon: Icons.schedule_outlined,
                          title: clockEnabled
                              ? 'Modo relógio ativado'
                              : 'Modo relógio desativado',
                          subtitle: 'Tela cheia com relógio e hibernação do assistente.',
                          trailing: StatusChip(
                            label: clockEnabled ? 'Ativo' : 'Inativo',
                            color: clockEnabled
                                ? palette.success
                                : palette.muted,
                            compact: true,
                          ),
                          onTap: onClockPreferences,
                        ),
                      ],
                    ),
                  ],
                  if (isAndroid) ...[
                    const SizedBox(height: 20),
                    SettingsGroup(
                      title: 'Celular',
                      children: [
                        SettingsTile(
                          icon: Icons.assistant_outlined,
                          title: 'Assistente do celular',
                          subtitle: isAssistant
                              ? 'Ativo${hasNotificationAccess ? ' · notificações liberadas' : ' · sem acesso a notificações'}'
                              : 'Definir como assistente padrão',
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                          ),
                          onTap: onOpenPhoneAssistant,
                        ),
                        SettingsTile(
                          icon: Icons.qr_code_scanner_rounded,
                          title: 'Parear com QR code',
                          subtitle: 'Conectar este aparelho sem copiar token.',
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                          ),
                          onTap: onOpenQr,
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    SettingsGroup(
                      title: 'Pareamento e Tailscale',
                      children: [
                        SettingsTile(
                          icon: Icons.qr_code_2_rounded,
                          title: 'Conectar um celular',
                          subtitle:
                              'Gere um QR code para parear sem copiar token.',
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                          ),
                          onTap: onOpenQr,
                        ),
                        _TailscaleStatusTile(client: client),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SettingsGroup(
                    title: 'Dados',
                    children: [
                      SettingsTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: '$conversationCount conversa(s)',
                        subtitle: 'Histórico salvo no backend local.',
                      ),
                      SettingsTile(
                        icon: Icons.psychology_outlined,
                        title: '$memoryCount memória(s)',
                        subtitle:
                            'Fatos e preferências que personalizam o chat.',
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: () => onOpenFeature('memories'),
                      ),
                      SettingsTile(
                        icon: Icons.folder_copy_outlined,
                        title: 'Arquivos e anexos',
                        subtitle: 'Ver imagens e documentos enviados.',
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: onOpenFiles,
                      ),
                      SettingsTile(
                        icon: Icons.savings_outlined,
                        title: 'Meu Dinheiro',
                        subtitle: 'Abrir o painel de lançamentos e orçamento.',
                        trailing: const Icon(
                          Icons.open_in_new_rounded,
                          size: 17,
                        ),
                        onTap: onOpenFinance,
                      ),
                      SettingsTile(
                        icon: Icons.terminal_rounded,
                        title: 'Tarefas no computador',
                        subtitle: 'Executar OpenCode na pasta autorizada.',
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: onOpenComputer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Chat · dados no seu backend local',
                      style: TextStyle(color: palette.disabled, fontSize: 10.5),
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

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Escuro',
    ThemeMode.system => 'Sistema',
  };

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };
}

/// Mostra apenas o estado da VPN. O endereço do Tailscale nunca chega aqui.
class _TailscaleStatusTile extends StatefulWidget {
  const _TailscaleStatusTile({required this.client});

  final BackendClient client;

  @override
  State<_TailscaleStatusTile> createState() => _TailscaleStatusTileState();
}

class _TailscaleStatusTileState extends State<_TailscaleStatusTile> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await widget.client.pairingStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = _status;
    final installed = status?['tailscale_installed'] == true;
    final online = status?['tailscale_online'] == true;
    final loggedIn = status?['tailscale_logged_in'] == true;
    final lan = status?['lan_available'] == true;
    final title = _loading
        ? 'Verificando Tailscale…'
        : _error != null
        ? 'Tailscale indisponível'
        : !installed
        ? 'Tailscale não instalado'
        : online
        ? 'Tailscale conectado'
        : loggedIn
        ? 'Tailscale sem conexão'
        : 'Tailscale desconectado';
    final subtitle = _loading
        ? 'Consultando o estado da VPN.'
        : _error != null
        ? 'Não foi possível consultar o estado agora.'
        : online
        ? 'O celular pode se conectar de qualquer rede.'
        : installed
        ? lan
              ? 'Na mesma rede Wi-Fi o pareamento já funciona.'
              : 'Abra o Tailscale no notebook para conectar de fora de casa.'
        : 'Instale o Tailscale para acessar o Chat fora de casa.';
    final color = _loading
        ? palette.muted
        : online
        ? palette.success
        : installed
        ? palette.danger
        : palette.muted;
    return SettingsTile(
      icon: online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      trailing: _loading
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primary,
              ),
            )
          : StatusChip(
              label: online ? 'Ativo' : 'Inativo',
              color: color,
              compact: true,
            ),
      onTap: _loading ? null : _load,
    );
  }
}
