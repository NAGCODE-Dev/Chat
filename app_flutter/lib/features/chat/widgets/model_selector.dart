import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({
    super.key,
    required this.provider,
    required this.model,
    required this.models,
    required this.onSelect,
    required this.onManage,
    this.loading = false,
    this.compact = false,
  });

  final String provider;
  final String model;
  final List<Map<String, dynamic>> models;
  final ValueChanged<String> onSelect;
  final VoidCallback onManage;
  final bool loading;
  final bool compact;

  String get _shortModel {
    if (model.trim().isEmpty) return 'Modelo';
    final value = model.split('/').last;
    return value.length > 30 ? '${value.substring(0, 28)}…' : value;
  }

  Future<void> _open(BuildContext context) async {
    final palette = context.palette;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final entries = <Map<String, dynamic>>[];
        final seen = <String>{};
        for (final item in models) {
          final id = (item['id'] as String? ?? '').trim();
          if (id.isEmpty || !seen.add(id)) continue;
          entries.add(item);
        }
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modelo',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.isEmpty ? 'Provider não carregado' : provider,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Text(
                      'Nenhum modelo listado pelo backend. Abra o gerenciador '
                      'para configurar o provider.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        final id = (item['id'] as String? ?? '').trim();
                        final name = (item['name'] as String? ?? '').trim();
                        final isSelected = id == model;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.memory_rounded,
                            size: 19,
                            color: isSelected
                                ? palette.primary
                                : palette.muted,
                          ),
                          title: Text(
                            id,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle:
                              name.isNotEmpty && name != id
                              ? Text(
                                  name,
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 11,
                                  ),
                                )
                              : null,
                          onTap: () => Navigator.pop(sheetContext, id),
                        );
                      },
                    ),
                  ),
                Divider(height: 1, color: palette.border),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.tune_rounded,
                    size: 19,
                    color: palette.muted,
                  ),
                  title: Text(
                    'Gerenciar modelo',
                    style: TextStyle(color: palette.text, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onManage();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && selected != model) onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (compact) {
      return IconButton(
        tooltip: model.trim().isEmpty ? 'Escolher modelo' : 'Modelo: $model',
        onPressed: () => _open(context),
        icon: loading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.memory_rounded,
                size: 19,
                color: palette.muted,
              ),
      );
    }
    return Tooltip(
      message: 'Trocar modelo',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => _open(context),
          child: Container(
            height: 34,
            padding: const EdgeInsets.fromLTRB(11, 0, 8, 0),
            decoration: BoxDecoration(
              color: palette.input,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.memory_rounded, size: 14, color: palette.muted),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: Text(
                    _shortModel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
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
