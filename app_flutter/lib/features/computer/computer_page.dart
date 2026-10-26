import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_surface.dart';
import '../../core/backend_client.dart';
import '../chat/models/chat_models.dart';

class ComputerPage extends StatefulWidget {
  const ComputerPage({
    super.key,
    required this.client,
    required this.connected,
  });

  final BackendClient client;
  final bool connected;

  @override
  State<ComputerPage> createState() => _ComputerPageState();
}

class _ComputerPageState extends State<ComputerPage> {
  final _prompt = TextEditingController();
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _tasks = [];
  String? _error;
  bool _loading = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ComputerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected != widget.connected && widget.connected) {
      _load();
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic>? status;
    List<Map<String, dynamic>> tasks = [];
    String? error;
    try {
      status = await widget.client.ubuntuStatus();
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    }
    try {
      tasks = await widget.client.ubuntuTasks();
    } catch (exception) {
      error ??= exception.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _tasks = tasks;
      _error = error;
      _loading = false;
    });
  }

  bool get _agentReady =>
      _status?['configured'] == true &&
      _status?['reachable'] == true &&
      _status?['opencode_available'] == true;

  Future<void> _reviewAndRun() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _running) return;
    if (!_agentReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O agente Ubuntu ou o OpenCode não está disponível.'),
        ),
      );
      return;
    }
    final palette = context.palette;
    final workspace = (_status?['workspace'] as String? ?? '').trim();
    final writeDirs =
        (_status?['write_dirs'] as List<dynamic>? ?? const [])
            .map((item) => '$item')
            .where((item) => item.isNotEmpty)
            .toList();
    var checked = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Executar no computador?'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'O OpenCode vai trabalhar na pasta autorizada e pode criar, '
                    'alterar ou apagar arquivos dentro dela.',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.input,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: SelectableText(
                      prompt,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _KeyValue(
                    label: 'Pasta de trabalho',
                    value: workspace.isEmpty ? 'não informada' : workspace,
                  ),
                  if (writeDirs.isNotEmpty)
                    _KeyValue(
                      label: 'Pastas de escrita',
                      value: writeDirs.join('\n'),
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: checked,
                    onChanged: (value) =>
                        setDialogState(() => checked = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: palette.primary,
                    title: Text(
                      'Confirmo que revisei a tarefa e a pasta.',
                      style: TextStyle(color: palette.text, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: checked
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Executar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _running = true);
    try {
      final task = await widget.client.runUbuntuTask(prompt);
      if (!mounted) return;
      final status = task['status'] as String? ?? 'failed';
      _prompt.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'ok'
                ? 'Tarefa concluída no computador.'
                : 'A tarefa terminou com falha; veja a saída no histórico.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        AppPageHeader(
          title: 'Computador',
          subtitle: 'Tarefas no notebook com OpenCode',
          actions: [
            IconButton(
              tooltip: 'Atualizar status',
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
              final horizontal = constraints.maxWidth >= 1000
                  ? (constraints.maxWidth - 900) / 2
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
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: palette.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: palette.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: palette.danger,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _buildStatusCard(context),
                  const SizedBox(height: 20),
                  const SectionLabel('Nova tarefa'),
                  SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _prompt,
                          minLines: 3,
                          maxLines: 8,
                          enabled: !_running && _agentReady,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Descreva o que o OpenCode deve fazer na pasta '
                                'de trabalho…',
                            hintStyle: TextStyle(
                              color: palette.disabled,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: palette.muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'A execução pede confirmação e fica limitada às '
                                'pastas de escrita do agente.',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 10.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _running || !_agentReady
                                ? null
                                : _reviewAndRun,
                            icon: _running
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded, size: 19),
                            label: Text(
                              _running ? 'Executando…' : 'Revisar e executar',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_agentReady && !_loading) ...[
                    const SizedBox(height: 10),
                    Text(
                      _status?['configured'] != true
                          ? 'Configure CHAT_AGENT_URL e CHAT_AGENT_TOKEN no backend '
                                'para liberar as tarefas.'
                          : _status?['reachable'] != true
                          ? 'O agente Ubuntu não respondeu. Verifique o serviço '
                                'chat-agent no notebook.'
                          : 'O OpenCode não foi encontrado. Configure '
                                'CHAT_AGENT_OPENCODE_BIN no agente.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SectionLabel(
                    'Tarefas recentes',
                    trailing: _tasks.isEmpty
                        ? null
                        : Text(
                            '${_tasks.length}',
                            style: TextStyle(
                              color: palette.disabled,
                              fontSize: 10.5,
                            ),
                          ),
                  ),
                  if (_tasks.isEmpty)
                    SurfaceCard(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            color: palette.disabled,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Nenhuma tarefa executada ainda.',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final task in _tasks) ...[
                      _TaskCard(task: task),
                      const SizedBox(height: 8),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final palette = context.palette;
    final status = _status;
    final configured = status?['configured'] == true;
    final reachable = status?['reachable'] == true;
    final opencode = status?['opencode_available'] == true;
    final workspace = (status?['workspace'] as String? ?? '').trim();
    final model = (status?['opencode_model'] as String? ?? '').trim();
    final sandbox = status?['opencode_sandbox'] == true;
    final detail = (status?['detail'] as String? ?? '').trim();
    final color = !configured || !reachable
        ? palette.danger
        : !opencode
        ? palette.violet
        : palette.success;
    final label = !configured
        ? 'Não configurado'
        : !reachable
        ? 'Agente offline'
        : !opencode
        ? 'OpenCode indisponível'
        : 'Pronto';
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      borderColor: color.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.terminal_rounded, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agente Ubuntu',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail.isEmpty
                          ? 'Executa o OpenCode na pasta autorizada do notebook.'
                          : detail,
                      maxLines: 3,
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
              const SizedBox(width: 8),
              StatusChip(label: label, color: color, compact: true),
            ],
          ),
          if (workspace.isNotEmpty || model.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: palette.border),
            const SizedBox(height: 10),
            if (workspace.isNotEmpty)
              _KeyValue(label: 'Pasta', value: workspace),
            if (model.isNotEmpty)
              _KeyValue(label: 'Modelo do OpenCode', value: model),
            _KeyValue(
              label: 'Sandbox',
              value: sandbox
                  ? 'ativo · escrita limitada ao workspace'
                  : 'desligado · apenas diretório de trabalho',
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(color: palette.disabled, fontSize: 10.5),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: palette.muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({required this.task});

  final Map<String, dynamic> task;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = widget.task['status'] as String? ?? 'failed';
    final color = status == 'ok'
        ? palette.success
        : status == 'running'
        ? palette.primary
        : palette.danger;
    final label = switch (status) {
      'ok' => 'Concluída',
      'running' => 'Em execução',
      _ => 'Falhou',
    };
    final output = (widget.task['output'] as String? ?? '').trim();
    final prompt = (widget.task['prompt'] as String? ?? '').trim();
    final created = parseBackendDate(widget.task['created_at'] as String?);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      status == 'ok'
                          ? Icons.check_rounded
                          : status == 'running'
                          ? Icons.hourglass_top_rounded
                          : Icons.close_rounded,
                      color: color,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatDate(created),
                          style: TextStyle(
                            color: palette.disabled,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusChip(label: label, color: color, compact: true),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: palette.disabled,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.input,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: SelectableText(
                      output.isEmpty ? 'Sem saída registrada.' : output,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 11.5,
                        height: 1.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'sem data';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
