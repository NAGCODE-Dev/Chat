import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
import '../../core/backend_client.dart';

/// Gera o QR de pareamento no próprio computador.
///
/// O celular lê o código, troca o segredo temporário pelo token e passa a
/// falar com o backend. A interface nunca mostra o endereço do notebook nem
/// o token: o QR carrega as URLs internamente e o token só existe no celular.
Future<void> showPairingQrDialog(BuildContext context, BackendClient client) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PairingQrDialog(client: client),
    );

class _PairingQrDialog extends StatefulWidget {
  const _PairingQrDialog({required this.client});

  final BackendClient client;

  @override
  State<_PairingQrDialog> createState() => _PairingQrDialogState();
}

class _PairingQrDialogState extends State<_PairingQrDialog> {
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;
  int _remaining = 0;
  Timer? _ticker;

  bool get _expired => _session != null && _remaining <= 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _ticker?.cancel();
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
        _session = null;
        _remaining = 0;
      });
    }
    try {
      final session = await widget.client.createPairingSession();
      Map<String, dynamic> status = const {};
      try {
        status = await widget.client.pairingStatus();
      } catch (_) {
        // O QR continua válido mesmo se o status da VPN não responder.
      }
      if (!mounted) return;
      final expires = (session['expires_in'] as num?)?.toInt() ?? 120;
      setState(() {
        _session = session;
        _status = status;
        _remaining = expires;
        _loading = false;
      });
      _startTicker();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remaining <= 1) {
        timer.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  String get _payload => (_session?['qr_payload'] as String? ?? '').trim();

  String _remainingLabel(int seconds) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      final rest = seconds % 60;
      return '${minutes}m ${rest.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code_2_rounded, size: 22),
          SizedBox(width: 8),
          Text('Parear celular'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(),
                ),
                Text(
                  'Gerando um código novo…',
                  style: TextStyle(color: palette.muted, fontSize: 12.5),
                ),
              ] else if (_error != null) ...[
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 44,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  'Não foi possível gerar o QR code agora.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Confira se o notebook está ligado e tente de novo.',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 11.5),
                ),
              ] else ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _expired
                      ? Container(
                          key: const ValueKey('expired'),
                          width: 236,
                          height: 236,
                          decoration: BoxDecoration(
                            color: palette.input,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: palette.border),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timer_off_outlined,
                                size: 44,
                                color: palette.muted,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Código expirado',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          key: const ValueKey('qr'),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: QrImageView(
                            data: _payload,
                            version: QrVersions.auto,
                            size: 236,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  _expired
                      ? 'Gere um novo código para continuar.'
                      : 'Abra o Chat no celular e escaneie o código.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!_expired) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Válido por ${_remainingLabel(_remaining)}',
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
                const SizedBox(height: 14),
                _PairingStatusLine(status: _status),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Novo código'),
        ),
      ],
    );
  }
}

class _PairingStatusLine extends StatelessWidget {
  const _PairingStatusLine({required this.status});

  final Map<String, dynamic>? status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = status;
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    final installed = data['tailscale_installed'] == true;
    final online = data['tailscale_online'] == true;
    final lan = data['lan_available'] == true;
    final (icon, color, label) = online
        ? (Icons.cloud_done_outlined, palette.success, 'Tailscale conectado')
        : installed
        ? (Icons.cloud_off_outlined, palette.danger, 'Tailscale desconectado')
        : (Icons.cloud_off_outlined, palette.muted, 'Tailscale não instalado');
    final detail = !online && lan
        ? ' · Wi-Fi local disponível'
        : online
        ? ' · funciona fora de casa'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label$detail',
              style: TextStyle(color: palette.muted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
