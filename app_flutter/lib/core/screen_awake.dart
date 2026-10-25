import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Mantém a tela ligada enquanto o modo relógio está ativo.
///
/// No Linux usa `systemd-inhibit` para bloquear a suspensão por ociosidade.
/// No Android usa um canal nativo que aplica `FLAG_KEEP_SCREEN_ON`. Em outros
/// alvos, ou quando o recurso não está disponível, a operação é silenciosa:
/// o relógio continua funcionando, apenas sujeito ao bloqueio de tela do SO.
class ScreenAwake {
  Process? _inhibitor;
  static const MethodChannel _channel = MethodChannel('chat/screen');

  Future<void> enable() async {
    if (Platform.isLinux) {
      if (_inhibitor != null) return;
      try {
        final process = await Process.start('systemd-inhibit', [
          '--what=idle',
          '--who=Chat',
          '--why=Modo relógio',
          'sleep',
          'infinity',
        ]);
        _inhibitor = process;
        unawaited(
          process.exitCode.then((_) {
            if (identical(_inhibitor, process)) _inhibitor = null;
          }),
        );
      } catch (_) {
        // Sem systemd-inhibit, o relógio ainda funciona.
      }
      return;
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('keepAwake', {'enabled': true});
      } on PlatformException {
        // Canal indisponível em builds antigos.
      } on MissingPluginException {
        // Execução em teste ou plataforma sem o canal nativo.
      }
    }
  }

  Future<void> disable() async {
    final process = _inhibitor;
    _inhibitor = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('keepAwake', {'enabled': false});
      } on PlatformException {
        // Ignora canal indisponível.
      } on MissingPluginException {
        // Execução em teste ou plataforma sem o canal nativo.
      }
    }
  }
}

/// Implementação inerte para testes de widget.
class NoopScreenAwake extends ScreenAwake {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}
