import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app/app_section.dart';
import 'app/shell/app_shell.dart';
import 'app/theme/app_palette.dart';
import 'app/theme/app_theme.dart';
import 'app/widgets/app_logo.dart';
import 'core/attachment_picker.dart';
import 'core/backend_client.dart';
import 'core/clock_format.dart';
import 'core/conversation_mode.dart';
import 'core/screen_awake.dart';
import 'core/theme_controller.dart';
import 'core/token_store.dart';
import 'features/chat/models/chat_models.dart';
import 'features/chat/widgets/chat_message_bubble.dart';
import 'features/chat/widgets/empty_chat_view.dart';
import 'features/chat/widgets/message_composer.dart';
import 'features/chat/widgets/model_selector.dart';
import 'features/computer/computer_page.dart';
import 'features/explore/explore_page.dart';
import 'features/files/files_page.dart';
import 'features/pairing/pairing_qr_dialog.dart';
import 'features/settings/settings_page.dart';
import 'phone_assistant_page.dart';

const _audioChannel = MethodChannel('chat/audio');
const _deviceChannel = MethodChannel('chat/device');
const _windowChannel = MethodChannel('chat/window');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, this.tokenStore, this.screenAwake});

  final TokenStore? tokenStore;
  final ScreenAwake? screenAwake;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeController,
    builder: (context, _) => MaterialApp(
      title: 'Chat',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeController.mode,
      home: ChatPage(tokenStore: tokenStore, screenAwake: screenAwake),
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.tokenStore, this.screenAwake});

  final TokenStore? tokenStore;
  final ScreenAwake? screenAwake;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const _defaultUrl = 'http://127.0.0.1:8750';
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _composerFocus = FocusNode();
  final _recorder = AudioRecorder();
  Process? _audioPlaybackProcess;
  List<ChatMessage> _messages = [];
  List<ChatAttachment> _pendingAttachments = [];
  final List<_ChatRun> _runs = [];
  final Set<int> _busyConversations = {};
  List<Map<String, dynamic>> _conversations = [];
  String _backendUrl = _defaultUrl;
  String? _backendToken;
  String? _error;
  int? _conversationId;
  AppSection _section = AppSection.chat;
  String _historySearch = '';
  String _provider = '';
  String _model = '';
  String? _visionModel;
  List<Map<String, dynamic>> _models = [];
  bool _modelsLoading = false;
  String _greeting = 'Como posso ajudar?';
  int _memoryCount = 0;
  bool _offline = false;
  bool _loading = true;
  bool _conversationsLoading = true;
  bool _uploadingAttachment = false;
  bool _recording = false;
  bool _speaking = false;
  bool _sttAvailable = false;
  bool _ttsAvailable = false;
  String? _speechFilePath;
  String? _captureFilePath;
  Process? _linuxRecorder;
  String _linuxRecorderError = '';
  bool _continuousMode = false;
  String _wakeWord = 'chat';
  bool _wakeActive = false;
  bool _autoListening = false;
  bool _autoStopping = false;
  bool _muted = false;
  bool _shareNotifications = false;
  bool _deviceActionsEnabled = true;
  bool _isAssistant = false;
  bool _hasNotificationAccess = false;
  int _captureGeneration = 0;
  Timer? _continuousTimer;
  Timer? _metricsScrollTimer;
  bool _scrollScheduled = false;
  DateTime? _notificationsFetchedAt;
  String? _notificationsCache;
  bool _clockModeEnabled = false;
  bool _clockMode = false;
  bool _desktopFullscreen = false;
  bool _clock24h = true;
  int _hibernationMinutes = 5;
  DateTime _clockNow = DateTime.now();
  DateTime _lastInteraction = DateTime.now();
  Timer? _hibernationTimer;
  Timer? _clockTimer;
  late final ScreenAwake _screenAwake;

  BackendClient get _client =>
      BackendClient(_backendUrl, apiToken: _backendToken);

  bool get _supportsClockMode => !Platform.isAndroid && !Platform.isIOS;

  bool get _busy => _runs.any(
    (run) =>
        identical(run.messages, _messages) ||
        (run.conversationId != null && run.conversationId == _conversationId),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screenAwake = widget.screenAwake ?? ScreenAwake();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _backendUrl = preferences.getString('backend_url') ?? _defaultUrl;
      _continuousMode = preferences.getBool('continuous_mode') ?? false;
      _wakeWord = preferences.getString('wake_word') ?? 'chat';
      _muted = preferences.getBool('muted') ?? false;
      _shareNotifications = preferences.getBool('share_notifications') ?? false;
      _deviceActionsEnabled =
          preferences.getBool('device_actions_enabled') ?? true;
      _clockModeEnabled =
          _supportsClockMode &&
          (preferences.getBool('clock_mode_enabled') ?? false);
      _clock24h = preferences.getBool('clock_24h') ?? true;
      _hibernationMinutes = preferences.getInt('hibernation_minutes') ?? 5;
      if (_hibernationMinutes < 1) _hibernationMinutes = 1;
      _backendToken = await (widget.tokenStore ?? KeyringTokenStore()).read();
    } catch (error) {
      _error = 'Não foi possível acessar o cofre de senhas do sistema: $error';
    }
    await _loadCachedConversations();
    if (mounted) setState(() => _loading = false);
    unawaited(_refreshConversations());
    unawaited(_loadGreeting());
    unawaited(_refreshVoiceStatus());
    unawaited(_refreshDeviceStatus());
    unawaited(_refreshModelInfo());
    unawaited(_warmupModels());
    if (_clockModeEnabled) {
      await _enterClockMode();
    } else {
      _noteInteraction();
      if (_continuousMode) {
        _scheduleContinuousListen(delay: const Duration(milliseconds: 600));
      }
    }
  }

  @override
  void didChangeMetrics() {
    // Acompanha o teclado desde o primeiro frame. Antes, a lista só era
    // reposicionada 260 ms depois, o que produzia um salto no fim da animação.
    _metricsScrollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToEnd(force: true);
    });
    _metricsScrollTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _scrollToEnd(force: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDeviceStatus());
      unawaited(_warmupModels());
    }
    if (state == AppLifecycleState.paused) {
      if (_clockMode) unawaited(_screenAwake.disable());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (_clockMode) {
      unawaited(_screenAwake.enable());
      return;
    }
    if (_supportsClockMode &&
        _clockModeEnabled &&
        DateTime.now().difference(_lastInteraction) >=
            Duration(minutes: _hibernationMinutes)) {
      unawaited(_enterClockMode());
    }
  }

  void _noteInteraction() {
    _lastInteraction = DateTime.now();
    if (_clockModeEnabled && !_clockMode) _resetHibernationTimer();
  }

  void _resetHibernationTimer() {
    _hibernationTimer?.cancel();
    if (!_supportsClockMode || !_clockModeEnabled || _clockMode) return;
    _hibernationTimer = Timer(Duration(minutes: _hibernationMinutes), () {
      if (mounted) unawaited(_enterClockMode());
    });
  }

  Future<void> _enterClockMode() async {
    if (!_supportsClockMode || _clockMode || !_clockModeEnabled) return;
    _hibernationTimer?.cancel();
    await _abortCurrentCapture();
    await _stopPlayback();
    await _removeSpeechFile();
    if (!mounted) return;
    setState(() {
      _clockMode = true;
      _clockNow = DateTime.now();
      _speaking = false;
    });
    _startClockTicker();
    await _screenAwake.enable();
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // Em desktop o modo imersivo pode não existir; o relógio continua.
    }
  }

  Future<void> _leaveClockMode() async {
    if (!_clockMode) return;
    _clockTimer?.cancel();
    if (_desktopFullscreen) unawaited(_setDesktopFullscreen(false));
    setState(() {
      _clockMode = false;
      _clockNow = DateTime.now();
    });
    _noteInteraction();
    await _screenAwake.disable();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
          .catchError((Object _) {}),
    );
    if (_continuousMode) {
      _scheduleContinuousListen(delay: const Duration(milliseconds: 300));
    }
  }

  void _startClockTicker() {
    _clockTimer?.cancel();
    final now = DateTime.now();
    final delay = Duration(
      seconds: 60 - now.second,
      milliseconds: -now.millisecond,
    );
    _clockTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted || !_clockMode) return;
      setState(() => _clockNow = DateTime.now());
      _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted && _clockMode) {
          setState(() => _clockNow = DateTime.now());
        }
      });
    });
  }

  Future<void> _abortCurrentCapture() async {
    _continuousTimer?.cancel();
    _captureGeneration++;
    if (!_recording) return;
    try {
      final path = await _stopCapture();
      _captureFilePath = null;
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          // Arquivo já removido.
        }
      }
    } catch (_) {
      // Interromper a captura é melhor esforço.
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _autoListening = false;
      });
    }
  }

  Future<void> _showClockPreferences() async {
    final value = await showDialog<(bool, int, bool)>(
      context: context,
      builder: (_) => _ClockPreferencesDialog(
        enabled: _clockModeEnabled,
        hibernationMinutes: _hibernationMinutes,
        use24Hour: _clock24h,
      ),
    );
    if (value == null) return;
    final (enabled, minutes, use24Hour) = value;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('clock_mode_enabled', enabled);
      await preferences.setInt('hibernation_minutes', minutes);
      await preferences.setBool('clock_24h', use24Hour);
    } catch (error) {
      if (mounted) _showError(error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _clockModeEnabled = enabled;
      _hibernationMinutes = minutes;
      _clock24h = use24Hour;
    });
    if (enabled) {
      await _enterClockMode();
    } else {
      _hibernationTimer?.cancel();
      if (_clockMode) await _leaveClockMode();
    }
  }

  Future<void> _setDesktopFullscreen(bool value) async {
    if (!_supportsClockMode) return;
    try {
      await _windowChannel.invokeMethod<void>('setFullscreen', value);
    } catch (_) {
      // Canal ausente em Android, testes ou outros desktops.
      return;
    }
    if (mounted) setState(() => _desktopFullscreen = value);
  }

  Future<void> _toggleDesktopFullscreen() =>
      _setDesktopFullscreen(!_desktopFullscreen);

  Widget _buildClockScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const Key('clock-screen'),
        behavior: HitTestBehavior.opaque,
        onTap: _leaveClockMode,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.f11) {
              // F11 alterna a tela cheia sem sair do relógio.
              unawaited(_toggleDesktopFullscreen());
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent) {
              unawaited(_leaveClockMode());
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final timeSize = math.max(
                  64.0,
                  math.min(
                    constraints.maxWidth * 0.28,
                    constraints.maxHeight * 0.40,
                  ),
                );
                final dateSize = math.max(
                  16.0,
                  math.min(28.0, timeSize * 0.10),
                );
                return Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatClockTime(_clockNow, use24Hour: _clock24h),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: timeSize,
                                fontWeight: FontWeight.w200,
                                height: 1,
                                letterSpacing: -2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            formatPortugueseDate(_clockNow),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: dateSize,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 42),
                          Text(
                            'Toque na tela para conversar',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 15,
                              letterSpacing: 0.4,
                            ),
                          ),
                          if (Platform.isLinux) ...[
                            const SizedBox(height: 10),
                            Text(
                              'F11 alterna a tela cheia',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.32),
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 16,
                      child: Row(
                        children: [
                          Icon(
                            Icons.nightlight_round,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Hibernação ativa · microfone desligado',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.30),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 8,
                      child: IconButton(
                        tooltip: 'Configurar relógio',
                        onPressed: _showClockPreferences,
                        icon: Icon(
                          Icons.settings_outlined,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshConversations() async {
    try {
      final conversations = await _client.conversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _offline = false;
        _conversationsLoading = false;
      });
      await _cacheConversations(conversations);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _offline = true;
        _conversationsLoading = false;
        if (_conversations.isEmpty) {
          _error = _friendlyError(error);
        }
      });
    }
  }

  Future<void> _loadGreeting() async {
    try {
      final data = await _client.greeting();
      if (!mounted) return;
      final greeting = (data['greeting'] as String?)?.trim() ?? '';
      setState(() {
        _greeting = greeting.isEmpty ? 'Como posso ajudar?' : greeting;
        _memoryCount = (data['memory_count'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _greeting = 'Como posso ajudar?';
        _memoryCount = 0;
      });
    }
  }

  Future<void> _loadCachedConversations() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('cached_conversations_v1');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final cached = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted || cached.isEmpty || _conversations.isNotEmpty) return;
      setState(() => _conversations = cached);
    } catch (_) {
      // Cache é melhor esforço; a rede continua sendo a fonte de verdade.
    }
  }

  Future<void> _cacheConversations(
    List<Map<String, dynamic>> conversations,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'cached_conversations_v1',
        jsonEncode(conversations.take(60).toList()),
      );
    } catch (_) {
      // Sem cache, o app segue funcionando online.
    }
  }

  Future<void> _cacheMessages(
    int conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'cached_messages_v1_$conversationId',
        jsonEncode(messages.take(200).toList()),
      );
    } catch (_) {
      // Cache é melhor esforço.
    }
  }

  Future<List<Map<String, dynamic>>> _readCachedMessages(
    int conversationId,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('cached_messages_v1_$conversationId');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshVoiceStatus() async {
    try {
      final status = await _client.voiceStatus();
      if (!mounted) return;
      setState(() {
        _sttAvailable = status['stt_available'] ?? false;
        _ttsAvailable = status['tts_available'] ?? false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sttAvailable = false;
        _ttsAvailable = false;
      });
    }
  }

  Future<void> _warmupModels() async {
    try {
      await _client.warmupModels();
    } catch (_) {
      // Aquecimento é melhor esforço: não atrapalha a abertura do app.
    }
  }

  Future<void> _refreshModelInfo() async {
    try {
      final settings = await _client.settings();
      if (!mounted) return;
      final provider = (settings['provider'] as String? ?? '').trim();
      final model = (settings['model'] as String? ?? '').trim();
      setState(() {
        _provider = provider;
        _model = model;
        _visionModel = (settings['vision_model'] as String?)?.trim();
      });
      if (provider.isNotEmpty) {
        await _loadModels(provider);
      }
    } catch (_) {
      // O seletor mostra o estado vazio; o chat continua utilizável.
    }
  }

  Future<void> _loadModels(String provider) async {
    if (provider.isEmpty) return;
    if (mounted) setState(() => _modelsLoading = true);
    try {
      final models = await _client.models(provider);
      if (!mounted || provider != _provider) return;
      setState(() => _models = models);
    } catch (_) {
      if (!mounted) return;
      setState(() => _models = []);
    } finally {
      if (mounted) setState(() => _modelsLoading = false);
    }
  }

  Future<void> _selectModel(String model) async {
    if (_provider.isEmpty || model.trim().isEmpty) return;
    try {
      await _client.updateModel(_provider, model.trim());
      if (!mounted) return;
      setState(() => _model = model.trim());
      unawaited(_warmupModels());
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Modelo atualizado.')));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _openModelSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _ModelSettingsPage(client: _client)),
    );
    if (mounted) await _refreshModelInfo();
  }

  Future<void> _testConnection() async {
    try {
      final health = await _client.health();
      if (!mounted) return;
      setState(() => _offline = false);
      final provider = (health['provider'] as String? ?? '').trim();
      final model = (health['model'] as String? ?? '').trim();
      final healthy = health['provider_healthy'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            healthy
                ? 'Backend respondeu · ${provider.isEmpty ? 'provider' : provider}'
                      '${model.isEmpty ? '' : ' · $model'}'
                : 'Backend respondeu, mas o provider não está saudável.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _offline = true);
      _showError(error);
    }
  }

  Future<void> _pickAttachment({required bool imagesOnly}) async {
    if (_offline) {
      _showError(
        'Sem conexão com o notebook. Verifique a rede e tente de novo.',
      );
      return;
    }
    try {
      final picked = await pickAttachment(imagesOnly: imagesOnly);
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _uploadingAttachment = true);
      final metadata = await _client.uploadAttachment(
        picked.name,
        picked.bytes,
        mime: picked.mime,
      );
      final attachment = ChatAttachment.fromJson(metadata)
          .copyWith(bytes: picked.bytes);
      if (!mounted) return;
      setState(() => _pendingAttachments.add(attachment));
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  void _removePendingAttachment(ChatAttachment attachment) {
    final id = attachment.id;
    setState(
      () => _pendingAttachments.removeWhere((item) => item == attachment),
    );
    if (id == null) return;
    unawaited(
      _client.deleteAttachment(id).catchError((Object _) {
        // O anexo pode já ter sido removido; o envio não depende disso.
      }),
    );
  }

  Future<Uint8List?> _loadAttachmentBytes(ChatAttachment attachment) async {
    final bytes = attachment.bytes;
    if (bytes != null) return bytes;
    final id = attachment.id;
    if (id == null) return null;
    try {
      return await _client.attachmentBytes(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _insertLink() async {
    final urlController = TextEditingController();
    final labelController = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inserir link'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Texto do link'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                  hintText: 'https://…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              final label = labelController.text.trim();
              Navigator.pop(context, label.isEmpty ? url : '[$label]($url)');
            },
            child: const Text('Inserir'),
          ),
        ],
      ),
    );
    urlController.dispose();
    labelController.dispose();
    if (value == null || !mounted) return;
    final selection = _input.selection;
    final text = _input.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    _input.value = TextEditingValue(
      text: '${text.substring(0, start)}$value${text.substring(end)}',
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _composerFocus.requestFocus();
  }

  void _setSection(AppSection section) {
    if (_section == section) return;
    setState(() => _section = section);
    if (section == AppSection.chat) {
      unawaited(_refreshConversations());
    }
  }

  String get _conversationTitle {
    final id = _conversationId;
    if (id == null) return 'Nova conversa';
    for (final conversation in _conversations) {
      if ((conversation['id'] as num?)?.toInt() == id) {
        final title = (conversation['title'] as String? ?? '').trim();
        return title.isEmpty ? 'Conversa' : title;
      }
    }
    return 'Conversa';
  }

  Future<void> _refreshDeviceStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final isAssistant =
          await _deviceChannel.invokeMethod<bool>('isAssistantRoleHeld') ??
          false;
      final hasAccess =
          await _deviceChannel.invokeMethod<bool>('hasNotificationAccess') ??
          false;
      if (!mounted) return;
      setState(() {
        _isAssistant = isAssistant;
        _hasNotificationAccess = hasAccess;
      });
    } catch (_) {
      // O canal nativo pode não existir em builds antigos.
    }
  }

  bool _messageNeedsNotifications(String message) {
    final folded = message.toLowerCase();
    return const [
      'notifica',
      'celular',
      'android',
      'whatsapp',
      'telegram',
      'mensagem',
      'email',
      'e-mail',
      'alarme',
      'lembrete',
      'agenda',
      'aplicativo',
      'app ',
      'sms',
    ].any(folded.contains);
  }

  Future<String?> _buildDeviceContext({String? message}) async {
    if (!Platform.isAndroid) return null;
    final buffer = StringBuffer();
    buffer.writeln('Data e hora local: ${DateTime.now().toIso8601String()}');
    buffer.writeln(
      'Plataforma: Android (celular conectado). Ações de aplicativo, música, '
      'mídia e links devem usar phone_action.',
    );
    if (_shareNotifications &&
        _hasNotificationAccess &&
        _messageNeedsNotifications(message ?? '')) {
      final now = DateTime.now();
      final stale =
          _notificationsFetchedAt == null ||
          now.difference(_notificationsFetchedAt!) > const Duration(minutes: 2);
      if (stale) {
        try {
          final raw = await _deviceChannel.invokeListMethod<dynamic>(
            'recentNotifications',
          );
          final notifications = (raw ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .take(10)
              .toList();
          final cached = StringBuffer();
          if (notifications.isNotEmpty) {
            cached.writeln('Notificações recentes do celular:');
            for (final item in notifications) {
              final app = (item['app'] as String? ?? '').trim();
              final title = (item['title'] as String? ?? '').trim();
              final text = (item['text'] as String? ?? '').trim();
              cached.writeln('- [$app] $title: $text');
            }
          }
          _notificationsCache = cached.toString().trim();
          _notificationsFetchedAt = now;
        } catch (_) {
          // Sem permissão ou serviço indisponível: segue sem notificações.
          _notificationsCache = '';
          _notificationsFetchedAt = now;
        }
      }
      final cached = _notificationsCache;
      if (cached != null && cached.isNotEmpty) {
        buffer.writeln(cached);
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _toggleMuted() async {
    final muted = !_muted;
    if (muted) {
      await _stopPlayback();
    }
    if (!mounted) return;
    setState(() {
      _muted = muted;
      if (muted) _speaking = false;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('muted', muted);
    } catch (_) {
      // O estado vale para esta sessão.
    }
  }

  Future<void> _openPhoneAssistant() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const PhoneAssistantPage()),
    );
    try {
      final preferences = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _shareNotifications =
              preferences.getBool('share_notifications') ?? false;
          _deviceActionsEnabled =
              preferences.getBool('device_actions_enabled') ?? true;
        });
      }
    } catch (_) {
      // Mantém o estado atual.
    }
    await _refreshDeviceStatus();
  }

  _ChatRun? _runForConversation(int id) {
    for (final run in _runs) {
      if (run.conversationId == id) return run;
    }
    return null;
  }

  /// Histórico visível: só falas do usuário e respostas finais. Chamadas de
  /// ferramenta e respostas vazias de turnos interrompidos não viram bolha.
  List<ChatMessage> _messagesFromRows(List<Map<String, dynamic>> rows) {
    final messages = <ChatMessage>[];
    for (final row in rows) {
      final role = row['role'] as String? ?? '';
      if (role != 'user' && role != 'assistant') continue;
      final content = row['content'] as String? ?? '';
      if (role == 'assistant' && content.trim().isEmpty) continue;
      messages.add(ChatMessage.fromJson(row));
    }
    return messages;
  }

  Future<void> _openConversation(int id) async {
    final run = _runForConversation(id);
    if (run != null) {
      setState(() {
        _conversationId = id;
        _messages = run.messages;
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
      return;
    }
    setState(() {
      _conversationId = id;
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _client.messages(id);
      if (!mounted || _conversationId != id) return;
      setState(() {
        _messages = _messagesFromRows(rows);
        _offline = false;
      });
      await _cacheMessages(id, rows);
      if (!mounted || _conversationId != id) return;
      _scrollToEnd();
    } catch (error) {
      if (!mounted || _conversationId != id) return;
      final cached = await _readCachedMessages(id);
      if (!mounted || _conversationId != id) return;
      setState(() {
        _messages = _messagesFromRows(cached);
        _offline = true;
        if (cached.isEmpty) _error = _friendlyError(error);
      });
      _scrollToEnd();
    } finally {
      if (mounted && _conversationId == id) {
        setState(() => _loading = false);
      }
    }
  }

  void _newConversation() {
    setState(() {
      _conversationId = null;
      _messages = [];
      _error = null;
      _loading = false;
    });
    unawaited(_loadGreeting());
  }

  Future<void> _deleteConversation(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar conversa?'),
        content: const Text(
          'O histórico dessa conversa será removido do computador. '
          'Essa ação não pode ser desfeita.',
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
    if (_busyConversations.contains(id)) {
      _showError(
        'Espere a resposta dessa conversa terminar antes de apagá-la.',
      );
      return;
    }
    try {
      await _client.deleteConversation(id);
      if (!mounted) return;
      if (id == _conversationId) {
        setState(() {
          _conversationId = null;
          _messages = [];
        });
      }
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove('cached_messages_v1_$id');
      } catch (_) {
        // Cache é melhor esforço.
      }
      await _refreshConversations();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    if ((text.isEmpty && attachments.isEmpty) || _busy) return;
    if (_offline) {
      _showError(
        'Sem conexão com o notebook. Verifique a rede e tente de novo.',
      );
      return;
    }
    if (text.length > 12000) {
      _showError('A mensagem deve ter no máximo 12000 caracteres.');
      return;
    }
    _input.clear();
    final target = _messages;
    final run = _ChatRun(messages: target, assistantIndex: target.length + 1);
    setState(() {
      _error = null;
      _pendingAttachments = [];
      target.add(
        ChatMessage(
          role: 'user',
          content: text,
          attachments: attachments,
          createdAt: DateTime.now(),
        ),
      );
      target.add(
        ChatMessage(role: 'assistant', content: '', createdAt: DateTime.now()),
      );
      _runs.add(run);
    });
    _scrollToEnd(force: true);
    final deviceContextFuture = _buildDeviceContext(message: text);
    final tokenBuffer = StringBuffer();
    Timer? tokenTimer;

    void flushTokens() {
      if (tokenBuffer.isEmpty) return;
      final chunk = tokenBuffer.toString();
      tokenBuffer.clear();
      if (!mounted || run.assistantIndex >= target.length) return;
      setState(() {
        final previous = target[run.assistantIndex].content;
        target[run.assistantIndex] = ChatMessage(
          role: 'assistant',
          content: '$previous$chunk',
          createdAt: target[run.assistantIndex].createdAt,
        );
      });
      if (identical(_messages, target)) _scrollToEnd();
    }

    // Agrupa tokens em ~12 atualizações por segundo. Antes cada token
    // reconstruía a bolha inteira e reiniciava a rolagem.
    tokenTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => flushTokens(),
    );

    WebSocketChannel? channel;
    var completed = false;
    String? completedReply;
    final pendingActions = <Map<String, dynamic>>[];
    try {
      channel = _client.connectChat();
      final ready = channel.ready.timeout(const Duration(seconds: 20));
      final deviceContext = await deviceContextFuture;
      await ready;
      channel.sink.add(
        jsonEncode({
          'message': text,
          if (_conversationId != null) 'conversation_id': _conversationId,
          if (deviceContext != null && deviceContext.isNotEmpty)
            'device_context': deviceContext,
          if (attachments.isNotEmpty)
            'attachment_ids': [
              for (final attachment in attachments)
                if (attachment.id != null) attachment.id,
            ],
        }),
      );
      await for (final raw in channel.stream) {
        final event = jsonDecode(raw as String) as Map<String, dynamic>;
        if (!mounted) return;
        switch (event['type']) {
          case 'conversation':
            final id = event['conversation_id'] as int?;
            if (id == null) break;
            run.conversationId = id;
            setState(() {
              _busyConversations.add(id);
              if (!_conversations.any((item) => item['id'] == id)) {
                _conversations.insert(0, {
                  'id': id,
                  'title': (event['title'] as String? ?? text).trim(),
                  'last_message': text,
                  'updated_at': DateTime.now().toIso8601String(),
                });
              }
              if (identical(_messages, target) && _conversationId == null) {
                _conversationId = id;
              }
            });
            break;
          case 'token':
            tokenBuffer.write(event['content'] ?? '');
            break;
          case 'done':
            tokenTimer?.cancel();
            tokenTimer = null;
            flushTokens();
            completed = true;
            final id = event['conversation_id'] as int? ?? run.conversationId;
            run.conversationId = id;
            final sources = ChatSource.parseList(event['sources']);
            final streamed = target[run.assistantIndex].content;
            final finalContent = (event['content'] as String?)?.trim();
            final reply = finalContent != null && finalContent.isNotEmpty
                ? finalContent
                : streamed;
            setState(() {
              target[run.assistantIndex] = ChatMessage(
                role: 'assistant',
                content: reply,
                sources: sources,
                createdAt: target[run.assistantIndex].createdAt,
              );
              if (id != null) _busyConversations.remove(id);
              if (identical(_messages, target) && _conversationId == null) {
                _conversationId = id;
              }
            });
            completedReply = reply;
            if (id != null) {
              await _cacheMessages(
                id,
                target.map((message) => message.toJson()).toList(),
              );
            }
            await _refreshConversations();
            break;
          case 'device_action':
            pendingActions.add(Map<String, dynamic>.from(event));
            break;
          case 'confirmation_required':
            final approved = await _confirmTool(event);
            channel.sink.add(
              jsonEncode({
                'type': 'confirmation',
                'tool_call_id': event['tool_call_id'],
                'approved': approved,
              }),
            );
            break;
          case 'error':
            throw Exception(event['detail'] ?? 'Falha ao gerar resposta.');
        }
      }
      if (!completed) {
        throw Exception('A conexão foi encerrada antes do fim da resposta.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (run.assistantIndex < target.length) {
            target.removeAt(run.assistantIndex);
          }
          if (run.conversationId == null && attachments.isNotEmpty) {
            _pendingAttachments = attachments;
          }
          if (identical(_messages, target)) {
            _error = _friendlyError(error);
          }
        });
        if (!identical(_messages, target)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Falha na conversa: ${_friendlyError(error)}'),
            ),
          );
        }
      }
    } finally {
      tokenTimer?.cancel();
      tokenTimer = null;
      await channel?.sink.close();
      if (mounted) {
        setState(() {
          _runs.remove(run);
          final id = run.conversationId;
          if (id != null) _busyConversations.remove(id);
        });
      }
      if (identical(_messages, target)) _scrollToEnd();
    }
    final viewing = identical(_messages, target);
    if (completed && pendingActions.isNotEmpty && viewing) {
      for (final action in pendingActions) {
        await _runDeviceAction(action);
      }
    }
    if (completed &&
        viewing &&
        pendingActions.isEmpty &&
        _ttsAvailable &&
        !_muted &&
        completedReply != null) {
      await _speakText(_cleanForDisplay(completedReply));
    }
    if (completed && viewing && _continuousMode) {
      _scheduleContinuousListen();
    }
  }

  Future<void> _runDeviceAction(Map<String, dynamic> event) async {
    if (!_deviceActionsEnabled) return;
    if (!Platform.isAndroid) {
      _showError(
        'O assistente pediu uma ação de celular, mas este app não está no Android.',
      );
      return;
    }
    final action = event['action'] as String? ?? '';
    final target = event['target'] as String? ?? '';
    final method = switch (action) {
      'open_app' => 'openApp',
      'play_music' => 'playMusic',
      'media_control' => 'mediaControl',
      'open_url' => 'openUrl',
      _ => null,
    };
    if (method == null) return;
    try {
      final message = await _deviceChannel.invokeMethod<String>(method, {
        'target': target,
      });
      if (message != null && message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<bool> _confirmTool(Map<String, dynamic> event) async {
    final tool = event['tool'] as String? ?? 'ação';
    final args = event['arguments'];
    final description = switch (tool) {
      'wishlist_update' => 'Alterar sua lista de desejos com: $args',
      'web_search' =>
        'Enviar esta consulta para o serviço de busca configurado: $args',
      'open_url' => 'Abrir este link no navegador: $args',
      'agent_exec' => _describeAgentAction(args),
      _ => 'Permitir esta ação: $tool ($args)',
    };
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Confirmar ação'),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Recusar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _describeAgentAction(Object? arguments) {
    if (arguments is! Map) return 'Permitir esta ação no notebook: $arguments';
    final action = arguments['action'] as String? ?? '';
    final path = arguments['path'] as String? ?? '';
    final content = arguments['content'];
    return switch (action) {
      'open_app' => 'Abrir o aplicativo ${arguments['app']} no notebook.',
      'list_files' => 'Listar o conteúdo de $path.',
      'read_file' => 'Ler o arquivo $path.',
      'write_file' =>
        'Salvar ${content is String ? content.length : 0} caracteres em $path, substituindo o conteúdo atual.',
      'append_file' =>
        'Acrescentar ${content is String ? content.length : 0} caracteres ao final de $path.',
      'create_dir' => 'Criar a pasta $path.',
      'opencode' =>
        'Executar esta tarefa no notebook com OpenCode: '
            '${arguments['prompt'] ?? ''}',
      _ => 'Permitir esta ação no notebook: $arguments',
    };
  }

  Future<void> _toggleVoice() async {
    if (_speaking) {
      await _stopPlayback();
      if (mounted) setState(() => _speaking = false);
      await _removeSpeechFile();
      // Tocar o microfone durante a fala interrompe a reprodução e inicia a captura.
    }
    if (_recording) {
      await _completeCapture();
      return;
    }
    if (_busy) return;
    if (!_sttAvailable) {
      _showError('STT não está configurado no backend.');
      return;
    }
    _continuousTimer?.cancel();
    try {
      final path =
          '${Directory.systemTemp.path}/chat-${DateTime.now().microsecondsSinceEpoch}.wav';
      _captureGeneration++;
      await _startCapture(path);
      if (mounted) {
        setState(() {
          _recording = true;
          _autoListening = false;
        });
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _scheduleContinuousListen({
    Duration delay = const Duration(milliseconds: 350),
  }) {
    _continuousTimer?.cancel();
    if (!_continuousMode ||
        !_sttAvailable ||
        _busy ||
        _recording ||
        _speaking ||
        _autoStopping) {
      return;
    }
    _continuousTimer = Timer(delay, () {
      if (!mounted ||
          !_continuousMode ||
          !_sttAvailable ||
          _busy ||
          _recording ||
          _speaking ||
          _autoStopping) {
        return;
      }
      unawaited(_beginContinuousCapture());
    });
  }

  Future<void> _beginContinuousCapture() async {
    if (_recording || _busy || _speaking || _autoStopping) return;
    try {
      final path =
          '${Directory.systemTemp.path}/chat-${DateTime.now().microsecondsSinceEpoch}.wav';
      _captureGeneration++;
      final generation = _captureGeneration;
      await _startCapture(path);
      if (!mounted || generation != _captureGeneration) return;
      setState(() {
        _recording = true;
        _autoListening = true;
      });
      unawaited(_watchForSilence(path, generation));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _autoListening = false;
      });
      _showError(error);
      if (_continuousMode) {
        _scheduleContinuousListen(delay: const Duration(seconds: 3));
      }
    }
  }

  Future<void> _completeCapture() async {
    if (_autoStopping) return;
    _autoStopping = true;
    final wasAuto = _autoListening;
    _captureGeneration++;
    try {
      final path = await _stopCapture();
      if (mounted) {
        setState(() {
          _recording = false;
          _autoListening = false;
        });
      }
      if (path == null) {
        throw Exception('Não foi possível salvar a gravação.');
      }
      final recordingFile = File(path);
      final bytes = await recordingFile.readAsBytes();
      await recordingFile.delete();
      _captureFilePath = null;
      if (bytes.length <= 44) {
        _afterEmptyCapture(wasAuto);
        return;
      }
      final transcript = (await _client.transcribe(bytes)).trim();
      if (!mounted) return;
      if (transcript.isEmpty) {
        _afterEmptyCapture(wasAuto);
        return;
      }
      _noteInteraction();
      var spoken = transcript;
      if (wasAuto &&
          _continuousMode &&
          !_wakeActive &&
          _wakeWord.trim().isNotEmpty) {
        if (!containsWakeWord(transcript, _wakeWord)) {
          _scheduleContinuousListen(delay: const Duration(milliseconds: 250));
          return;
        }
        spoken = stripWakeWord(transcript, _wakeWord);
        _wakeActive = true;
        if (spoken.isEmpty) {
          _scheduleContinuousListen(delay: const Duration(milliseconds: 150));
          return;
        }
      }
      _input.text = spoken;
      await _send();
    } catch (error) {
      if (mounted) {
        setState(() => _recording = false);
        _showError(error);
      }
      if (_continuousMode) {
        _scheduleContinuousListen(delay: const Duration(seconds: 2));
      }
    } finally {
      _autoStopping = false;
      if (mounted) setState(() {});
      // O agendamento feito por _send/_afterEmptyCapture ocorre enquanto
      // _autoStopping ainda é true; aqui é o ponto seguro para retomar o loop.
      if (mounted && _continuousMode && !_recording && !_speaking && !_busy) {
        _scheduleContinuousListen();
      }
    }
  }

  void _afterEmptyCapture(bool wasAuto) {
    if (wasAuto && _continuousMode) {
      _scheduleContinuousListen(delay: const Duration(milliseconds: 200));
      return;
    }
    _showError('Não consegui reconhecer fala no áudio.');
  }

  Future<void> _watchForSilence(String path, int generation) async {
    var offset = 44;
    var headerChecked = false;
    var heardSpeech = false;
    DateTime? silenceStarted;
    final started = DateTime.now();
    const speechThreshold = 600.0;
    const silenceLimit = Duration(milliseconds: 1200);
    const noSpeechLimit = Duration(seconds: 8);
    const maxListen = Duration(seconds: 15);
    while (mounted && _recording && generation == _captureGeneration) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || !_recording || generation != _captureGeneration) return;
      List<int> bytes;
      try {
        bytes = await File(path).readAsBytes();
      } catch (_) {
        continue;
      }
      if (!headerChecked) {
        final dataIndex = _findWavDataChunk(bytes);
        if (dataIndex != null) {
          offset = dataIndex + 8;
          headerChecked = true;
        } else if (bytes.length >= 44) {
          offset = 44;
          headerChecked = true;
        }
      }
      if (bytes.length > offset) {
        final available = bytes.length - offset;
        final usable = available - (available % 2);
        if (usable > 0) {
          final chunk = bytes.sublist(offset, offset + usable);
          offset += usable;
          final rms = _rms16(chunk);
          if (rms >= speechThreshold) {
            heardSpeech = true;
            silenceStarted = null;
          } else if (heardSpeech) {
            silenceStarted ??= DateTime.now();
            if (DateTime.now().difference(silenceStarted) >= silenceLimit) {
              await _completeCapture();
              return;
            }
          }
        }
      }
      final elapsed = DateTime.now().difference(started);
      if (!heardSpeech && elapsed >= noSpeechLimit) {
        await _discardContinuousCapture();
        return;
      }
      if (elapsed >= maxListen) {
        if (heardSpeech) {
          await _completeCapture();
        } else {
          await _discardContinuousCapture();
        }
        return;
      }
    }
  }

  static int? _findWavDataChunk(List<int> bytes) {
    final limit = math.min(bytes.length - 8, 4096);
    for (var index = 0; index <= limit; index++) {
      if (bytes[index] == 0x64 &&
          bytes[index + 1] == 0x61 &&
          bytes[index + 2] == 0x74 &&
          bytes[index + 3] == 0x61) {
        return index;
      }
    }
    return null;
  }

  static double _rms16(List<int> chunk) {
    if (chunk.length < 2) return 0;
    var sum = 0.0;
    var count = 0;
    for (var index = 0; index + 1 < chunk.length; index += 2) {
      var sample = chunk[index] | (chunk[index + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      sum += sample * sample;
      count++;
    }
    return count == 0 ? 0 : math.sqrt(sum / count);
  }

  Future<void> _discardContinuousCapture() async {
    if (_autoStopping) return;
    _autoStopping = true;
    _captureGeneration++;
    try {
      final path = await _stopCapture();
      _captureFilePath = null;
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          // O arquivo pode ter sido removido ao interromper a captura.
        }
      }
    } catch (_) {
      // Uma captura já encerrada não impede o próximo ciclo.
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _autoListening = false;
      });
    }
    _autoStopping = false;
    if (_continuousMode) {
      _scheduleContinuousListen(delay: const Duration(milliseconds: 150));
    }
  }

  Future<void> _cancelContinuousCapture() async {
    _continuousTimer?.cancel();
    _captureGeneration++;
    if (_recording && _autoListening) {
      try {
        final path = await _stopCapture();
        _captureFilePath = null;
        if (path != null) {
          try {
            await File(path).delete();
          } on FileSystemException {
            // Arquivo já removido.
          }
        }
      } catch (_) {
        // Encerrar a captura é melhor esforço ao desligar o modo.
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _autoListening = false;
        });
      }
    }
  }

  Future<void> _showVoicePreferences() async {
    final value = await showDialog<(bool, String)>(
      context: context,
      builder: (_) => _VoicePreferencesDialog(
        continuousMode: _continuousMode,
        wakeWord: _wakeWord,
        sttAvailable: _sttAvailable,
      ),
    );
    if (value == null) return;
    final enabled = value.$1;
    final wakeWord = value.$2.trim();
    final wakeChanged = wakeWord != _wakeWord;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('continuous_mode', enabled);
      await preferences.setString('wake_word', wakeWord);
    } catch (error) {
      if (mounted) _showError(error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _continuousMode = enabled;
      _wakeWord = wakeWord;
      if (!enabled || wakeChanged) _wakeActive = false;
    });
    if (enabled) {
      _scheduleContinuousListen(delay: Duration.zero);
    } else {
      await _cancelContinuousCapture();
    }
  }

  Future<void> _disableContinuousMode() async {
    if (!_continuousMode) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('continuous_mode', false);
    } catch (_) {
      // O modo é desligado nesta sessão mesmo se a preferência falhar.
    }
    if (!mounted) return;
    setState(() {
      _continuousMode = false;
      _wakeActive = false;
    });
    await _cancelContinuousCapture();
  }

  Future<void> _startCapture(String path) async {
    _captureFilePath = path;
    if (Platform.isLinux) {
      _linuxRecorderError = '';
      final process = await Process.start('pw-record', [
        '--media-category',
        'Capture',
        '--rate',
        '16000',
        '--channels',
        '1',
        '--format',
        's16',
        '--container',
        'wav',
        path,
      ]);
      _linuxRecorder = process;
      process.stderr
          .transform(utf8.decoder)
          .listen((text) => _linuxRecorderError += text);
      final exitedEarly = await Future.any([
        process.exitCode.then((_) => true),
        Future<void>.delayed(const Duration(milliseconds: 250))
            .then((_) => false),
      ]);
      if (exitedEarly) {
        final exitCode = await process.exitCode;
        _linuxRecorder = null;
        throw Exception(
          _linuxRecorderError.trim().isEmpty
              ? 'pw-record encerrou com código $exitCode.'
              : _linuxRecorderError.trim(),
        );
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      throw Exception('Permissão do microfone não concedida.');
    }
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  Future<String?> _stopCapture() async {
    final process = _linuxRecorder;
    if (process != null) {
      _linuxRecorder = null;
      process.kill(ProcessSignal.sigint);
      await process.exitCode;
      return _captureFilePath;
    }
    return _recorder.stop();
  }

  Future<void> _speakText(String text) async {
    if (_muted || text.trim().isEmpty || !_ttsAvailable) return;
    setState(() => _speaking = true);
    try {
      final audio = await _client.synthesize(text);
      if (!mounted || !_speaking) return;
      final path =
          '${Directory.systemTemp.path}/chat-speech-${DateTime.now().microsecondsSinceEpoch}.wav';
      final file = File(path);
      _speechFilePath = path;
      await file.writeAsBytes(audio, flush: true);
      final result = await _playAudio(path);
      if (result != 0 && _speaking) {
        throw Exception('O reprodutor de áudio encerrou com código $result.');
      }
      if (mounted) setState(() => _speaking = false);
      await _removeSpeechFile();
    } catch (error) {
      if (mounted) {
        setState(() => _speaking = false);
        _showError(error);
      }
      await _removeSpeechFile();
    }
  }

  Future<void> _stopPlayback() async {
    if (Platform.isAndroid) {
      try {
        await _audioChannel.invokeMethod<void>('stop');
      } on PlatformException {
        // O canal pode não existir em testes ou em builds sem o player nativo.
      } on MissingPluginException {
        // Idem: a interrupção é best-effort.
      }
    }
    final process = _audioPlaybackProcess;
    _audioPlaybackProcess = null;
    process?.kill();
    await process?.exitCode;
  }

  Future<int> _playAudio(String path) async {
    if (Platform.isAndroid) {
      await _audioChannel.invokeMethod<void>('play', {'path': path});
      return 0;
    }
    Object? lastError;
    for (final (executable, arguments) in [
      ('aplay', ['-q', path]),
      ('ffplay', ['-nodisp', '-autoexit', '-loglevel', 'error', path]),
    ]) {
      try {
        final process = await Process.start(executable, arguments);
        _audioPlaybackProcess = process;
        unawaited(process.stdout.drain<void>());
        unawaited(process.stderr.drain<void>());
        final result = await process.exitCode;
        if (identical(_audioPlaybackProcess, process)) {
          _audioPlaybackProcess = null;
        } else {
          return result;
        }
        if (result == 0) return 0;
        lastError = Exception('$executable encerrou com código $result.');
      } on ProcessException catch (error) {
        lastError = error;
      }
    }
    throw Exception(
      'Nenhum reprodutor WAV disponível (aplay/ffplay): $lastError',
    );
  }

  Future<void> _showSettings() async {
    final value = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _ConnectionSettingsDialog(
        backendUrl: _backendUrl,
        backendToken: _backendToken,
      ),
    );
    if (value == null || value.$1.trim().isEmpty) return;
    // Campo em branco mantém o token atual; só um valor novo o substitui.
    final typedToken = value.$2?.trim();
    final token = typedToken == null || typedToken.isEmpty
        ? _backendToken
        : typedToken;
    await _applyConnection(value.$1, token);
  }

  Future<bool> _applyConnection(String rawUrl, String? rawToken) async {
    final normalized = rawUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted) _showError('Informe um endereço HTTP ou HTTPS válido.');
      return false;
    }
    final token = rawToken?.trim();
    try {
      await (widget.tokenStore ?? KeyringTokenStore()).write(
        token == null || token.isEmpty ? null : token,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('backend_url', normalized);
    } catch (error) {
      if (mounted) {
        _showError('Não foi possível salvar no cofre do sistema: $error');
      }
      return false;
    }
    if (!mounted) return false;
    setState(() {
      _backendUrl = normalized;
      _backendToken = token == null || token.isEmpty ? null : token;
      _error = null;
    });
    await _refreshConversations();
    await _refreshVoiceStatus();
    unawaited(_warmupModels());
    return true;
  }

  Future<void> _openQrPairing() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // No computador o Chat gera o QR; o celular apenas lê.
      await showPairingQrDialog(context, _client);
      return;
    }
    final raw = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrPairingPage()));
    if (raw == null || !mounted) return;
    final payload = _PairingPayload.parse(raw);
    if (payload == null) {
      _showError('Este QR code não é um pareamento válido do Chat.');
      return;
    }
    Object? lastError;
    for (final url in payload.urls) {
      try {
        final result = await BackendClient(url).claimPairing(payload.code);
        final token = (result['token'] as String?)?.trim();
        final returnedUrl = (result['url'] as String?)?.trim();
        final selected = returnedUrl == null || returnedUrl.isEmpty
            ? url
            : returnedUrl;
        final applied = await _applyConnection(selected, token);
        if (applied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Celular conectado ao Chat.')),
          );
        }
        return;
      } catch (error) {
        lastError = error;
      }
    }
    if (mounted) {
      _showError(
        'Não foi possível concluir o pareamento'
        '${lastError == null ? '.' : ': ${_friendlyError(lastError)}'}',
      );
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
  }

  String _friendlyError(Object error) {
    if (error is BackendException) return error.message;
    if (error is TimeoutException) {
      return 'O notebook demorou para responder. Verifique a conexão e tente de novo.';
    }
    if (error is SocketException) {
      return 'Não foi possível alcançar o notebook. Verifique se ele está ligado e na mesma rede.';
    }
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst(
          'ClientException: ',
          'Não foi possível acessar o backend: ',
        )
        .replaceFirst('TimeoutException after ', 'Tempo esgotado após ');
  }

  bool _isStreamingIndex(int index) => _runs.any(
    (run) => identical(run.messages, _messages) && run.assistantIndex == index,
  );

  void _scrollToEnd({bool force = false}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    final wasNearBottom =
        !_scroll.hasClients ||
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 180;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (!force && !wasNearBottom) return;
      final target = _scroll.position.maxScrollExtent;
      if ((target - _scroll.position.pixels).abs() < 2) return;
      // jumpTo é imediato: antes cada token reiniciava uma animação de 180 ms,
      // o que deixava a rolagem travada e o teclado com aparência lenta.
      _scroll.jumpTo(target);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _continuousTimer?.cancel();
    _metricsScrollTimer?.cancel();
    _hibernationTimer?.cancel();
    _clockTimer?.cancel();
    if (_desktopFullscreen) {
      unawaited(
        _windowChannel
            .invokeMethod<void>('setFullscreen', false)
            .catchError((Object _) {}),
      );
    }
    unawaited(_screenAwake.disable());
    _input.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    unawaited(_stopPlayback());
    unawaited(_removeSpeechFile());
    if (_linuxRecorder != null) unawaited(_stopCapture());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _removeSpeechFile() async {
    final path = _speechFilePath;
    _speechFilePath = null;
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // A reprodução interrompida pode já ter removido o arquivo.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_clockMode) return _buildClockScreen();
    return AppShell(
      section: _section,
      onSection: _setSection,
      conversations: _conversations,
      selectedConversationId: _conversationId,
      busyConversationIds: _busyConversations,
      conversationsLoading: _conversationsLoading,
      search: _historySearch,
      onSearchChanged: (value) => setState(() => _historySearch = value),
      onSelectConversation: (id) => unawaited(_openConversation(id)),
      onDeleteConversation: (id) => unawaited(_deleteConversation(id)),
      onNewConversation: _newConversation,
      builder: _buildSection,
      connected: !_offline,
      onVoice: _toggleVoice,
      voiceActive: _recording || _speaking,
      busy: _busy,
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool compact,
    VoidCallback openHistory,
  ) {
    return switch (_section) {
      AppSection.chat => _buildChatSection(context, compact, openHistory),
      AppSection.explore => ExplorePage(
        client: _client,
        connected: !_offline,
        conversationCount: _conversations.length,
        isAndroid: Platform.isAndroid,
        supportsClock: _supportsClockMode,
        assistantEnabled: _isAssistant,
        notificationsEnabled: _hasNotificationAccess,
        onOpenFeature: (feature) {
          unawaited(_openFeature(feature));
        },
        onOpenFinance: () {
          unawaited(_openFinance());
        },
        onOpenComputer: () => _setSection(AppSection.computer),
        onOpenFiles: () => _setSection(AppSection.files),
        onOpenSettings: () => _setSection(AppSection.settings),
        onOpenPhoneAssistant: () {
          unawaited(_openPhoneAssistant());
        },
        onOpenQr: () {
          unawaited(_openQrPairing());
        },
        onOpenClock: () {
          unawaited(_showClockPreferences());
        },
        onRetry: () {
          unawaited(_refreshConversations());
        },
      ),
      AppSection.files => FilesPage(
        client: _client,
        connected: !_offline,
        onOpenInChat: _useAttachmentInChat,
      ),
      AppSection.settings => SettingsPage(
        client: _client,
        connected: !_offline,
        provider: _provider,
        model: _model,
        visionModel: _visionModel,
        sttAvailable: _sttAvailable,
        ttsAvailable: _ttsAvailable,
        muted: _muted,
        continuousMode: _continuousMode,
        themeMode: themeController.mode,
        memoryCount: _memoryCount,
        conversationCount: _conversations.length,
        isAndroid: Platform.isAndroid,
        isAssistant: _isAssistant,
        hasNotificationAccess: _hasNotificationAccess,
        supportsClock: _supportsClockMode,
        clockEnabled: _clockModeEnabled,
        onEditConnection: () {
          unawaited(_showSettings());
        },
        onTestConnection: () {
          unawaited(_testConnection());
        },
        onThemeMode: (mode) {
          unawaited(themeController.setMode(mode));
        },
        onModelSettings: () {
          unawaited(_openModelSettings());
        },
        onVoicePreferences: () {
          unawaited(_showVoicePreferences());
        },
        onToggleMuted: () {
          unawaited(_toggleMuted());
        },
        onClockPreferences: () {
          unawaited(_showClockPreferences());
        },
        onOpenQr: () {
          unawaited(_openQrPairing());
        },
        onOpenPhoneAssistant: () {
          unawaited(_openPhoneAssistant());
        },
        onOpenComputer: () => _setSection(AppSection.computer),
        onOpenFiles: () => _setSection(AppSection.files),
        onOpenFinance: () {
          unawaited(_openFinance());
        },
        onOpenFeature: (feature) {
          unawaited(_openFeature(feature));
        },
        onRefresh: () {
          unawaited(_refreshConversations());
          unawaited(_refreshVoiceStatus());
          unawaited(_refreshModelInfo());
        },
      ),
      AppSection.computer => ComputerPage(
        client: _client,
        connected: !_offline,
      ),
    };
  }

  void _useAttachmentInChat(ChatAttachment attachment) {
    setState(() {
      final already = _pendingAttachments.any(
        (item) => item.id != null && item.id == attachment.id,
      );
      if (!already) _pendingAttachments.add(attachment);
      _section = AppSection.chat;
    });
    _composerFocus.requestFocus();
  }

  Widget _buildChatSection(
    BuildContext context,
    bool compact,
    VoidCallback openHistory,
  ) {
    final palette = context.palette;
    return Listener(
      onPointerDown: (_) => _noteInteraction(),
      child: _KeyboardAwareBody(
        child: Column(
          children: [
            _buildChatHeader(context, compact, openHistory),
            if (_continuousMode) _buildContinuousStatus(),
            if (_loading)
              LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: palette.border,
                color: palette.primary,
              ),
            if (_offline) _buildOfflineBanner(compact),
            if (_error != null) _buildErrorBanner(compact),
            Expanded(child: _buildMessages(compact)),
            _buildComposer(compact),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHeader(
    BuildContext context,
    bool compact,
    VoidCallback openHistory,
  ) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 20,
        compact ? 6 : 8,
        compact ? 8 : 14,
        compact ? 6 : 8,
      ),
      color: palette.background,
      child: Row(
        children: [
          if (compact) ...[
            _HeaderCircleButton(
              tooltip: 'Histórico de conversas',
              icon: Icons.menu_rounded,
              onPressed: openHistory,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: compact
                ? Center(
                    child: Text(
                      _conversationTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _conversationTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            StatusDot(active: !_offline, size: 6),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _offline
                                    ? 'Sem conexão'
                                    : _provider.isEmpty
                                    ? 'Conectado'
                                    : _provider,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _offline
                                      ? palette.danger
                                      : palette.muted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          ModelSelector(
            provider: _provider,
            model: _model,
            models: _models,
            loading: _modelsLoading,
            compact: compact,
            onSelect: (model) {
              unawaited(_selectModel(model));
            },
            onManage: () {
              unawaited(_openModelSettings());
            },
          ),
          if (compact) ...[
            const SizedBox(width: 4),
            _HeaderCircleButton(
              tooltip: 'Nova conversa',
              icon: Icons.add_comment_outlined,
              onPressed: _newConversation,
            ),
          ] else ...[
            IconButton(
              tooltip: 'Conversa contínua',
              onPressed: _showVoicePreferences,
              color: _continuousMode ? palette.primary : null,
              icon: Icon(
                _continuousMode
                    ? Icons.hearing_rounded
                    : Icons.hearing_outlined,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: _muted
                  ? 'Ativar respostas faladas'
                  : 'Silenciar respostas',
              onPressed: _toggleMuted,
              color: _muted ? palette.primary : null,
              icon: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_outlined,
                size: 20,
              ),
            ),
            if (_supportsClockMode)
              IconButton(
                tooltip: 'Modo relógio',
                onPressed: _showClockPreferences,
                color: _clockModeEnabled ? palette.primary : null,
                icon: Icon(
                  _clockModeEnabled
                      ? Icons.schedule_rounded
                      : Icons.schedule_outlined,
                  size: 20,
                ),
              ),
            IconButton(
              tooltip: 'Tarefas no computador',
              onPressed: () => _setSection(AppSection.computer),
              icon: Icon(
                Icons.terminal_rounded,
                size: 19,
                color: palette.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContinuousStatus() {
    final palette = context.palette;
    final String status;
    if (!_sttAvailable) {
      status = 'Conversa contínua ativa, mas o STT não está configurado.';
    } else if (_speaking) {
      status = 'Falando…';
    } else if (_busy) {
      status = 'Pensando…';
    } else if (_recording) {
      status = _wakeActive || _wakeWord.trim().isEmpty
          ? 'Ouvindo…'
          : 'Ouvindo a palavra “$_wakeWord”…';
    } else {
      status = _wakeActive
          ? 'Conversa ativa; pode falar sem repetir a palavra.'
          : 'Conversa contínua ativa.';
    }
    return Container(
      width: double.infinity,
      color: palette.selected,
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Icon(
            _recording ? Icons.mic_rounded : Icons.hearing_rounded,
            size: 16,
            color: palette.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: TextStyle(color: palette.muted, fontSize: 11.5),
            ),
          ),
          IconButton(
            tooltip: 'Desligar conversa contínua',
            visualDensity: VisualDensity.compact,
            onPressed: _disableContinuousMode,
            icon: Icon(Icons.close_rounded, size: 17, color: palette.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner(bool compact) {
    final palette = context.palette;
    final message = Text(
      'Sem conexão com o notebook. Mostrando conversas salvas; '
      'o envio fica indisponível até a conexão voltar.',
      style: TextStyle(
        color: palette.danger,
        fontSize: compact ? 10.5 : 11,
        height: 1.35,
      ),
    );
    final retry = TextButton(
      onPressed: () {
        unawaited(_refreshConversations());
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Tentar de novo', style: TextStyle(fontSize: 11)),
    );
    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 10 : 20, 8, compact ? 10 : 20, 0),
      padding: EdgeInsets.fromLTRB(12, 8, compact ? 6 : 8, compact ? 4 : 8),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.danger.withValues(alpha: 0.25)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 16,
                      color: palette.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: message),
                  ],
                ),
                Align(alignment: Alignment.centerRight, child: retry),
              ],
            )
          : Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 17, color: palette.danger),
                const SizedBox(width: 8),
                Expanded(child: message),
                retry,
              ],
            ),
    );
  }

  Widget _buildErrorBanner(bool compact) {
    final palette = context.palette;
    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 10 : 20, 8, compact ? 10 : 20, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: palette.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fechar aviso',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _error = null),
            icon: Icon(Icons.close_rounded, size: 16, color: palette.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(bool compact) {
    if (_messages.isEmpty) {
      return EmptyChatView(
        greeting: _greeting,
        memoryCount: _memoryCount,
        compact: compact,
        onSuggestion: (prompt) {
          _input.text = prompt;
          _input.selection = TextSelection.collapsed(offset: prompt.length);
          _composerFocus.requestFocus();
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 1000
            ? (constraints.maxWidth - 960) / 2
            : compact
            ? 12.0
            : 24.0;
        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            horizontal,
            compact ? 14 : 22,
            horizontal,
            10,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[index];
            final streaming = _isStreamingIndex(index);
            final display = message.isUser || streaming
                ? message
                : ChatMessage(
                    role: message.role,
                    content: _cleanForDisplay(message.content),
                    sources: message.sources,
                    attachments: message.attachments,
                    createdAt: message.createdAt,
                  );
            return ChatMessageBubble(
              message: display,
              isStreaming: streaming,
              onSpeak: _ttsAvailable
                  ? () => _speakText(_cleanForDisplay(message.content))
                  : null,
              onOpenSource: _openSource,
              loadAttachment: _loadAttachmentBytes,
            );
          },
        );
      },
    );
  }

  Widget _buildComposer(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 20,
        6,
        compact ? 10 : 20,
        compact ? 10 : 14,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: MessageComposer(
            controller: _input,
            focusNode: _composerFocus,
            attachments: _pendingAttachments,
            busy: _busy,
            offline: _offline,
            recording: _recording,
            speaking: _speaking,
            uploading: _uploadingAttachment,
            compact: compact,
            onSend: () {
              unawaited(_send());
            },
            onVoice: () {
              unawaited(_toggleVoice());
            },
            onPickFile: () {
              unawaited(_pickAttachment(imagesOnly: false));
            },
            onPickImage: () {
              unawaited(_pickAttachment(imagesOnly: true));
            },
            onRemoveAttachment: _removePendingAttachment,
            onOpenComputer: () => _setSection(AppSection.computer),
            onInsertLink: () {
              unawaited(_insertLink());
            },
            loadAttachment: _loadAttachmentBytes,
          ),
        ),
      ),
    );
  }

  Future<void> _openFinance() async {
    final base = _backendUrl.endsWith('/')
        ? _backendUrl.substring(0, _backendUrl.length - 1)
        : _backendUrl;
    final token = _backendToken?.trim();
    final fragment = token == null || token.isEmpty
        ? ''
        : '#token=${Uri.encodeComponent(token)}';
    final url = '$base/finance/$fragment';
    try {
      if (Platform.isAndroid) {
        final result = await _deviceChannel.invokeMethod<String>('openUrl', {
          'target': url,
        });
        if (mounted &&
            result != null &&
            result.startsWith('Não foi possível')) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result)));
        }
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else {
        throw UnsupportedError('plataforma sem navegador configurado');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o Meu Dinheiro: $error'),
          ),
        );
      }
    }
  }

  Future<void> _openSource(String url) async {
    if (url.isEmpty) return;
    try {
      if (Platform.isAndroid) {
        final result = await _deviceChannel.invokeMethod<String>('openUrl', {
          'target': url,
        });
        if (mounted &&
            result != null &&
            result.startsWith('Não foi possível')) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result)));
        }
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else {
        throw UnsupportedError('plataforma sem navegador configurado');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir a fonte: $error')),
        );
      }
    }
  }

  Future<void> _openFeature(String feature) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => feature == 'settings'
            ? _ModelSettingsPage(client: _client)
            : _CollectionPage(client: _client, feature: feature),
      ),
    );
    if (mounted) {
      await _refreshConversations();
      await _refreshVoiceStatus();
    }
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: palette.input,
          foregroundColor: palette.text,
          minimumSize: const Size(40, 40),
          fixedSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _ClockPreferencesDialog extends StatefulWidget {
  const _ClockPreferencesDialog({
    required this.enabled,
    required this.hibernationMinutes,
    required this.use24Hour,
  });

  final bool enabled;
  final int hibernationMinutes;
  final bool use24Hour;

  @override
  State<_ClockPreferencesDialog> createState() =>
      _ClockPreferencesDialogState();
}

class _ClockPreferencesDialogState extends State<_ClockPreferencesDialog> {
  late bool _enabled;
  late int _minutes;
  late bool _use24Hour;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _minutes = widget.hibernationMinutes;
    _use24Hour = widget.use24Hour;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Modo relógio'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Relógio sempre visível'),
            subtitle: const Text(
              'Mostra um relógio grande e entra em hibernação quando o app fica ocioso.',
            ),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _minutes,
            decoration: const InputDecoration(labelText: 'Hibernar após'),
            items: const [1, 2, 5, 10, 15, 30]
                .map(
                  (minutes) => DropdownMenuItem(
                    value: minutes,
                    child: Text('$minutes minuto${minutes == 1 ? '' : 's'}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _minutes = value);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Formato 24 horas'),
            value: _use24Hour,
            onChanged: (value) => setState(() => _use24Hour = value),
          ),
          Text(
            'Em hibernação o microfone, a rede e a fala ficam parados, e o relógio atualiza uma vez por minuto. Toque na tela para voltar à conversa.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (_enabled, _minutes, _use24Hour)),
        child: const Text('Salvar'),
      ),
    ],
  );
}

class _VoicePreferencesDialog extends StatefulWidget {
  const _VoicePreferencesDialog({
    required this.continuousMode,
    required this.wakeWord,
    required this.sttAvailable,
  });

  final bool continuousMode;
  final String wakeWord;
  final bool sttAvailable;

  @override
  State<_VoicePreferencesDialog> createState() =>
      _VoicePreferencesDialogState();
}

class _VoicePreferencesDialogState extends State<_VoicePreferencesDialog> {
  late bool _enabled;
  late final TextEditingController _wakeController;

  @override
  void initState() {
    super.initState();
    _enabled = widget.continuousMode;
    _wakeController = TextEditingController(text: widget.wakeWord);
  }

  @override
  void dispose() {
    _wakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Conversa contínua'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ouvir automaticamente'),
            subtitle: const Text(
              'Depois de cada resposta, o microfone volta a ouvir sem você tocar no botão.',
            ),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          if (!widget.sttAvailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'O reconhecimento de fala não está configurado no backend.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _wakeController,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Palavra de ativação',
              helperText: 'Deixe vazio para ouvir sem palavra de ativação.',
            ),
          ),
          Text(
            'A palavra inicia a conversa. Depois de ativada, você pode continuar falando sem repeti-la até desligar o modo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (_enabled, _wakeController.text)),
        child: const Text('Salvar'),
      ),
    ],
  );
}

class _QrPairingPage extends StatefulWidget {
  const _QrPairingPage();

  @override
  State<_QrPairingPage> createState() => _QrPairingPageState();
}

class _QrPairingPageState extends State<_QrPairingPage> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null || _PairingPayload.parse(raw) == null) return;
    _handled = true;
    unawaited(_controller.stop());
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Parear com QR code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white70,
                      size: 44,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Não foi possível abrir a câmera. '
                      'Confira a permissão de câmera do Chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onInverseSurface),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
              ),
              child: Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 28,
            child: Text(
              'Aponte para o QR gerado no notebook',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionSettingsDialog extends StatefulWidget {
  const _ConnectionSettingsDialog({
    required this.backendUrl,
    this.backendToken,
  });

  final String backendUrl;
  final String? backendToken;

  @override
  State<_ConnectionSettingsDialog> createState() =>
      _ConnectionSettingsDialogState();
}

class _ConnectionSettingsDialogState extends State<_ConnectionSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.backendUrl);
    // O token nunca é exibido. Em branco, o valor já salvo é preservado.
    _tokenController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Conexão com o backend'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Endereço base',
              hintText: 'http://127.0.0.1:8750',
              helperText:
                  'Fora de casa, use o IP do Tailscale do notebook '
                  '(100.x.y.z) com a porta 8750.',
              helperMaxLines: 2,
            ),
            keyboardType: TextInputType.url,
          ),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Novo token da API (opcional)',
              helperText: (widget.backendToken ?? '').isEmpty
                  ? 'Informe o token configurado no backend. '
                        'O valor fica no cofre de senhas do sistema.'
                  : 'Deixe em branco para manter o token atual. '
                        'O valor fica no cofre de senhas do sistema.',
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          _urlController.text,
          _tokenController.text,
        )),
        child: const Text('Salvar'),
      ),
    ],
  );
}

class _PairingPayload {
  const _PairingPayload({required this.code, required this.urls});

  final String code;
  final List<String> urls;

  static _PairingPayload? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'chatpair' || uri.host != 'pair') {
      return null;
    }
    final code = uri.queryParameters['code']?.trim() ?? '';
    if (code.length < 16) return null;
    final urls = <String>[];
    for (final candidate in uri.queryParametersAll['url'] ?? const <String>[]) {
      final parsed = Uri.tryParse(candidate.trim());
      if (parsed == null ||
          !parsed.hasAuthority ||
          !{'http', 'https'}.contains(parsed.scheme)) {
        continue;
      }
      final normalized = candidate.trim().replaceFirst(RegExp(r'/+$'), '');
      if (!urls.contains(normalized)) urls.add(normalized);
    }
    if (urls.isEmpty) return null;
    return _PairingPayload(code: code, urls: urls);
  }
}

String _cleanForDisplay(String text) {
  var value = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\((?:https?://|www\.)[^)]+\)', caseSensitive: false),
    (match) => match[1] ?? '',
  );
  value = value.replaceAll(
    RegExp(r'https?://\S+|www\.\S+', caseSensitive: false),
    '',
  );
  value = value.replaceAllMapped(
    RegExp(r'[ \t]+([,.;:!?])'),
    (match) => match[1] ?? '',
  );
  value = value.replaceAllMapped(
    RegExp(r'(Fonte:\s*[^\n]*?)\s*[—–-]\s*(?=\n|$)', caseSensitive: false),
    (match) => (match[1] ?? '').trimRight(),
  );
  value = value.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  value = value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  value = value.replaceAll(RegExp(r'\(\s*\)'), '');
  value = value.replaceAll(RegExp(r'^\s*Fonte:\s*$', multiLine: true), '');
  return value.trim();
}

class _ChatRun {
  _ChatRun({required this.messages, required this.assistantIndex});

  final List<ChatMessage> messages;
  final int assistantIndex;
  int? conversationId;
}

class _KeyboardAwareBody extends StatelessWidget {
  const _KeyboardAwareBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Só este Padding depende do teclado. O filho é a mesma instância criada
    // pelo build da página, então a lista e as bolhas não são reconstruídas
    // a cada frame da animação.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}

class _CollectionPage extends StatefulWidget {
  const _CollectionPage({required this.client, required this.feature});

  final BackendClient client;
  final String feature;

  @override
  State<_CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<_CollectionPage> {
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _embeddingStatus;
  bool _loading = true;
  bool _reindexing = false;
  bool _importing = false;
  String? _error;

  String get _title => switch (widget.feature) {
    'wishlist' => 'Lista de desejos',
    'memories' => 'Memórias',
    _ => 'Dispositivos',
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = switch (widget.feature) {
        'wishlist' => await widget.client.wishlist(),
        'memories' => await widget.client.memories(),
        _ => await widget.client.devices(),
      };
      Map<String, dynamic>? embeddingStatus;
      if (widget.feature == 'memories') {
        try {
          embeddingStatus = await widget.client.memoryEmbeddingStatus();
        } catch (_) {
          // O status é informativo; a lista de memórias continua disponível.
        }
      }
      if (mounted) {
        setState(() {
          _items = items;
          _embeddingStatus = embeddingStatus;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reindexEmbeddings() async {
    setState(() => _reindexing = true);
    try {
      final result = await widget.client.reindexMemoryEmbeddings();
      await _reload();
      if (mounted) {
        final indexed = result['indexed'] ?? 0;
        final skipped = result['skipped'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$indexed memória(s) indexada(s); $skipped sem alteração.',
            ),
          ),
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
      if (mounted) setState(() => _reindexing = false);
    }
  }

  Future<void> _importMemories() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar do ChatGPT'),
        content: SizedBox(
          width: 560,
          height: math.max(
            240.0,
            math.min(430.0, MediaQuery.sizeOf(context).height * 0.55),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No ChatGPT, abra Configurações > Personalização > Memória, '
                'copie a lista e cole abaixo. Uma memória por linha funciona '
                'melhor; também aceito JSON.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        '- Prefiro respostas curtas\n'
                        '- Moro em São Paulo\n'
                        '- Meu projeto atual é o Chat',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (accepted != true || text.isEmpty) return;
    setState(() => _importing = true);
    try {
      final result = await widget.client.importMemories(text);
      await _reload();
      if (mounted) {
        final imported = result['imported'] ?? 0;
        final skipped = result['skipped'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$imported memória(s) importada(s); $skipped ignorada(s).',
            ),
          ),
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
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _buildImportCard() => Card(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: ListTile(
      leading: const Icon(Icons.upload_file_outlined),
      title: const Text('Trazer memórias do ChatGPT'),
      subtitle: const Text(
        'Cole a lista que o ChatGPT guardou sobre você; eu separo e guardo aqui.',
      ),
      trailing: FilledButton.tonal(
        onPressed: _importing ? null : _importMemories,
        child: Text(_importing ? 'Importando…' : 'Colar lista'),
      ),
    ),
  );

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final detail = TextEditingController();
    final extra = TextEditingController();
    final fields = switch (widget.feature) {
      'wishlist' => [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Nome do item'),
        ),
        TextField(
          controller: detail,
          decoration: const InputDecoration(labelText: 'Observações'),
        ),
        TextField(
          controller: extra,
          decoration: const InputDecoration(labelText: 'Link (opcional)'),
        ),
      ],
      'memories' => [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Chave'),
        ),
        TextField(
          controller: detail,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Informação'),
        ),
      ],
      _ => [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        TextField(
          controller: detail,
          decoration: const InputDecoration(labelText: 'Endereço MAC'),
        ),
        TextField(
          controller: extra,
          decoration: const InputDecoration(
            labelText: 'IPv4 Tailscale (opcional)',
          ),
        ),
      ],
    };
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adicionar em $_title'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: fields),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (accepted != true || title.text.trim().isEmpty) return;
    switch (widget.feature) {
      case 'wishlist':
        await _run(
          () => widget.client.addWishlist({
            'title': title.text.trim(),
            if (detail.text.trim().isNotEmpty) 'notes': detail.text.trim(),
            if (extra.text.trim().isNotEmpty) 'url': extra.text.trim(),
          }),
        );
      case 'memories':
        if (detail.text.trim().isEmpty) return;
        await _run(
          () => widget.client.addMemory({
            'kind': 'fact',
            'key': title.text.trim(),
            'content': detail.text.trim(),
          }),
        );
      case 'devices':
        await _run(
          () => widget.client.addDevice({
            'name': title.text.trim(),
            'mac': detail.text.trim(),
            if (extra.text.trim().isNotEmpty) 'tailscale_ip': extra.text.trim(),
          }),
        );
    }
  }

  Future<void> _deleteMemory(int id) async {
    await _run(() => widget.client.deleteMemory(id));
  }

  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover dispositivo?'),
        content: Text('Remover ${device['name']} da lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.client.deleteDevice(device['id'] as int));
    }
  }

  Future<void> _updateWishlist(int id, String value) async {
    if (value == 'excluir') {
      await _run(() => widget.client.deleteWishlist(id));
    } else {
      await _run(() => widget.client.updateWishlist(id, {'status': value}));
    }
  }

  Future<void> _wake(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar pacote de ativação?'),
        content: Text(
          'Enviar Wake-on-LAN para ${device['name']}? O envio não confirma que o dispositivo iniciou.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final message = await widget.client.wakeDevice(device['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  Widget _buildEmbeddingCard() {
    final status = _embeddingStatus;
    final enabled = status?['enabled'] == true;
    final available = status?['available'] == true;
    final total = status?['total'] ?? 0;
    final indexed = status?['indexed'] ?? 0;
    final pending = status?['pending'] ?? 0;
    final model = status?['model'] as String? ?? '';
    final String detail;
    if (status == null) {
      detail = 'Status da indexação indisponível.';
    } else if (!enabled) {
      detail = 'Busca semântica desligada; a memória usa FTS5.';
    } else if (!available) {
      detail =
          'Modelo $model indisponível no Ollama; a busca lexical continua ativa.';
    } else {
      detail =
          'Busca semântica: $indexed de $total indexadas · $pending pendente(s).';
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: ListTile(
        leading: Icon(enabled ? Icons.auto_awesome : Icons.search),
        title: const Text('Memória semântica'),
        subtitle: Text(detail),
        trailing: enabled && available
            ? _reindexing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: _reindexEmbeddings,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Indexar'),
                    )
            : null,
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    switch (widget.feature) {
      case 'wishlist':
        return ListTile(
          leading: const Icon(Icons.shopping_bag_outlined),
          title: Text(item['title'] as String? ?? ''),
          subtitle: Text(
            '${item['status'] ?? ''}${(item['notes'] as String? ?? '').isEmpty ? '' : ' · ${item['notes']}'}',
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Alterar item',
            onSelected: (value) => _updateWishlist(item['id'] as int, value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'aberto', child: Text('Marcar em aberto')),
              PopupMenuItem(value: 'comprado', child: Text('Marcar comprado')),
              PopupMenuItem(value: 'descartado', child: Text('Descartar')),
              PopupMenuItem(value: 'excluir', child: Text('Excluir')),
            ],
          ),
        );
      case 'memories':
        return ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(item['key'] as String? ?? ''),
          subtitle: Text(item['content'] as String? ?? ''),
          trailing: IconButton(
            tooltip: 'Excluir memória',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteMemory(item['id'] as int),
          ),
        );
      default:
        return ListTile(
          leading: const Icon(Icons.devices_outlined),
          title: Text(item['name'] as String? ?? ''),
          subtitle: Text(
            '${item['mac'] ?? ''}${item['tailscale_ip'] == null ? '' : ' · ${item['tailscale_ip']}'}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Acordar dispositivo',
                icon: const Icon(Icons.power_settings_new),
                onPressed: () => _wake(item),
              ),
              IconButton(
                tooltip: 'Remover dispositivo',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteDevice(item),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_title),
      actions: [
        if (widget.feature == 'memories')
          IconButton(
            tooltip: 'Importar do ChatGPT',
            onPressed: _importing ? null : _importMemories,
            icon: _importing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('Adicionar'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!),
            ),
          )
        : Column(
            children: [
              if (widget.feature == 'memories') _buildImportCard(),
              if (widget.feature == 'memories') _buildEmbeddingCard(),
              Expanded(
                child: _items.isEmpty
                    ? Center(child: Text('Nenhum registro em $_title.'))
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) => _buildItem(_items[index]),
                        ),
                      ),
              ),
            ],
          ),
  );
}

class _ModelSettingsPage extends StatefulWidget {
  const _ModelSettingsPage({required this.client});
  final BackendClient client;

  @override
  State<_ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<_ModelSettingsPage> {
  final _model = TextEditingController();
  List<String> _providers = [];
  String _provider = 'ollama';
  Map<String, dynamic>? _configuration;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _modelsLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.client.settings();
      if (!mounted) return;
      setState(() {
        _configuration = settings;
        _providers = (settings['providers'] as List<dynamic>).cast<String>();
        _provider = settings['provider'] as String;
        _model.text = settings['model'] as String;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.client.updateModel(_provider, _model.text.trim());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Modelo atualizado.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseModel() async {
    setState(() => _modelsLoading = true);
    try {
      final models = await widget.client.models(_provider);
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final model in models)
                ListTile(
                  title: Text(model['id'] as String? ?? ''),
                  subtitle: Text(model['name'] as String? ?? ''),
                  onTap: () => Navigator.pop(context, model['id'] as String?),
                ),
            ],
          ),
        ),
      );
      if (selected != null) _model.text = selected;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _modelsLoading = false);
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Modelo e voz')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              DropdownButtonFormField<String>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: _providers
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _provider = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _model,
                      decoration: const InputDecoration(
                        labelText: 'ID do modelo',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Listar modelos disponíveis',
                    onPressed: _modelsLoading ? null : _chooseModel,
                    icon: _modelsLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.list_alt),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Salvando…' : 'Salvar modelo'),
              ),
              const Divider(height: 36),
              Text('Voz', style: Theme.of(context).textTheme.titleMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  (_configuration?['voice']?['stt_available'] as bool? ?? false)
                      ? Icons.check_circle
                      : Icons.info_outline,
                ),
                title: const Text('Reconhecimento de fala (STT)'),
                subtitle: Text(
                  (_configuration?['voice']?['stt_available'] as bool? ?? false)
                      ? 'Disponível'
                      : 'Não configurado no backend',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  (_configuration?['voice']?['tts_available'] as bool? ?? false)
                      ? Icons.check_circle
                      : Icons.info_outline,
                ),
                title: const Text('Síntese de fala (TTS)'),
                subtitle: Text(
                  (_configuration?['voice']?['tts_available'] as bool? ?? false)
                      ? 'Disponível'
                      : 'Não configurado no backend',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Busca na web'),
                subtitle: Text(switch (_configuration?['web_search_provider']
                    as String?) {
                  'searxng' => 'SearXNG configurado',
                  'bing' => 'Bing (sem chave de API)',
                  _ => 'Não configurada',
                }),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Agente Ubuntu'),
                subtitle: Text(
                  (_configuration?['agent_configured'] as bool? ?? false)
                      ? 'Configurado'
                      : 'Não configurado',
                ),
              ),
            ],
          ),
  );
}
