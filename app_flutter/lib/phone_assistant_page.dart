import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _deviceChannel = MethodChannel('chat/device');

/// Configurações exclusivas do Android: papel de assistente, notificações e
/// permissão para abrir apps/tocar música.
class PhoneAssistantPage extends StatefulWidget {
  const PhoneAssistantPage({super.key});

  @override
  State<PhoneAssistantPage> createState() => _PhoneAssistantPageState();
}

class _PhoneAssistantPageState extends State<PhoneAssistantPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _isAssistant = false;
  bool _hasNotificationAccess = false;
  bool _shareNotifications = false;
  bool _deviceActionsEnabled = true;
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _shareNotifications = preferences.getBool('share_notifications') ?? false;
      _deviceActionsEnabled =
          preferences.getBool('device_actions_enabled') ?? true;
    } catch (_) {
      // Mantém os padrões.
    }
    await _refreshStatus(loadRecent: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshStatus({bool loadRecent = false}) async {
    if (!Platform.isAndroid) return;
    try {
      final isAssistant =
          await _deviceChannel.invokeMethod<bool>('isAssistantRoleHeld') ??
          false;
      final hasAccess =
          await _deviceChannel.invokeMethod<bool>('hasNotificationAccess') ??
          false;
      final recent = loadRecent && hasAccess ? await _readRecent() : _recent;
      if (!mounted) return;
      setState(() {
        _isAssistant = isAssistant;
        _hasNotificationAccess = hasAccess;
        _recent = recent;
      });
    } catch (_) {
      // O canal pode não existir em versões antigas do app.
    }
  }

  Future<List<Map<String, dynamic>>> _readRecent() async {
    try {
      final raw = await _deviceChannel.invokeListMethod<dynamic>(
        'recentNotifications',
      );
      return (raw ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _requestAssistantRole() async {
    try {
      await _deviceChannel.invokeMethod<bool>('requestAssistantRole');
    } catch (error) {
      _showError(error);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshStatus();
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _deviceChannel.invokeMethod<void>('openNotificationSettings');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openBatterySettings() async {
    try {
      await _deviceChannel.invokeMethod<void>('openBatterySettings');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openAutostartSettings() async {
    try {
      await _deviceChannel.invokeMethod<void>('openAutostartSettings');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openAppSettings() async {
    try {
      await _deviceChannel.invokeMethod<void>('openAppSettings');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _setShareNotifications(bool value) async {
    if (value && !_hasNotificationAccess) {
      await _openNotificationSettings();
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('share_notifications', value);
    } catch (error) {
      _showError(error);
    }
    if (mounted) setState(() => _shareNotifications = value);
    await _refreshStatus(loadRecent: value);
  }

  Future<void> _setDeviceActions(bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('device_actions_enabled', value);
    } catch (error) {
      _showError(error);
    }
    if (mounted) setState(() => _deviceActionsEnabled = value);
  }

  Future<void> _showRecent() async {
    await _refreshStatus(loadRecent: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notificações recentes'),
        content: SizedBox(
          width: double.maxFinite,
          child: _recent.isEmpty
              ? const Text(
                  'Nenhuma notificação lida ainda. Confirme a permissão e '
                  'espere chegar uma notificação.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _recent.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = _recent[index];
                    final title = (item['title'] as String? ?? '').trim();
                    final text = (item['text'] as String? ?? '').trim();
                    final app = (item['app'] as String? ?? '').trim();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        title.isEmpty ? app : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [app, text].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Falha na configuração do celular: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente do celular')),
      body: !Platform.isAndroid
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Estes recursos existem apenas no aplicativo Android.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.assistant,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Assistente padrão'),
                    subtitle: Text(
                      _isAssistant
                          ? 'Este app é o assistente do aparelho. Use o botão '
                                'de assistente do Android para abrir o Chat.'
                          : 'Defina o Chat como assistente para abrir pelo '
                                'botão de assistente do Android.',
                    ),
                    trailing: _isAssistant
                        ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                        : FilledButton(
                            onPressed: _requestAssistantRole,
                            child: const Text('Definir'),
                          ),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: Icon(
                          Icons.notifications_active_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text('Ler notificações'),
                        subtitle: Text(
                          _hasNotificationAccess
                              ? 'As notificações recentes entram no contexto '
                                    'das conversas quando esta opção está ligada.'
                              : 'A permissão de acesso às notificações ainda '
                                    'não foi concedida.',
                        ),
                        value: _shareNotifications,
                        onChanged: _setShareNotifications,
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('Permissão de notificações'),
                        subtitle: Text(
                          _hasNotificationAccess
                              ? 'Concedida'
                              : 'Não concedida',
                        ),
                        trailing: TextButton(
                          onPressed: _openNotificationSettings,
                          child: const Text('Abrir ajustes'),
                        ),
                        onTap: _openNotificationSettings,
                      ),
                      ListTile(
                        leading: const Icon(Icons.list_alt_outlined),
                        title: const Text('Ver notificações recentes'),
                        subtitle: Text(
                          _recent.isEmpty
                              ? 'Nenhuma notificação capturada'
                              : '${_recent.length} notificação(ões) capturada(s)',
                        ),
                        trailing: TextButton(
                          onPressed: _showRecent,
                          child: const Text('Ver'),
                        ),
                        onTap: _showRecent,
                      ),
                    ],
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.battery_saver_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text('Bateria e segundo plano'),
                        subtitle: const Text(
                          'No MIUI, escolha “Sem restrições” para o Chat não '
                          'ser interrompido quando a tela apagar.',
                        ),
                        trailing: TextButton(
                          onPressed: _openBatterySettings,
                          child: const Text('Bateria'),
                        ),
                        onTap: _openBatterySettings,
                      ),
                      ListTile(
                        leading: const Icon(Icons.restart_alt),
                        title: const Text('Inicialização automática'),
                        subtitle: const Text(
                          'Permita que o Chat inicie sozinho depois de reiniciar '
                          'o celular.',
                        ),
                        trailing: TextButton(
                          onPressed: _openAutostartSettings,
                          child: const Text('Autostart'),
                        ),
                        onTap: _openAutostartSettings,
                      ),
                      ListTile(
                        leading: const Icon(Icons.app_settings_alt_outlined),
                        title: const Text('Permissões do app'),
                        subtitle: const Text(
                          'Revise notificações, bateria e outras permissões.',
                        ),
                        trailing: TextButton(
                          onPressed: _openAppSettings,
                          child: const Text('Abrir'),
                        ),
                        onTap: _openAppSettings,
                      ),
                    ],
                  ),
                ),
                Card(
                  child: SwitchListTile(
                    secondary: Icon(
                      Icons.open_in_new,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Ações no celular'),
                    subtitle: const Text(
                      'Permite ao assistente abrir aplicativos, tocar música, '
                      'controlar a mídia e abrir links no aparelho.',
                    ),
                    value: _deviceActionsEnabled,
                    onChanged: _setDeviceActions,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'O botão de assistente do Android abre este app. Para '
                      'falar a palavra “chat” sem tocar na tela, use a Conversa '
                      'contínua com o app aberto. Escuta em segundo plano '
                      'gastaria bateria e não é ativada por padrão.',
                      style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
