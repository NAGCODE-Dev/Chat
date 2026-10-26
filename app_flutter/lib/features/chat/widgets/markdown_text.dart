import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';

/// Renderizador de Markdown enxuto, sem dependências externas.
///
/// Cobre o que o assistente realmente produz: títulos, listas, negrito,
/// itálico, código inline, blocos de código e tabelas simples.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.text, {super.key, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: palette.text,
          height: compact ? 1.4 : 1.55,
          fontSize: compact ? 13.5 : 14.5,
        );
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].tightAfter ? 2 : 10),
          _buildBlock(context, blocks[i], base),
        ],
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _Block block, TextStyle base) {
    final palette = context.palette;
    switch (block.type) {
      case _BlockType.code:
        return _CodeBlock(code: block.text);
      case _BlockType.table:
        return _MarkdownTable(rows: block.rows);
      case _BlockType.heading:
        final factor = switch (block.level) {
          1 => 1.45,
          2 => 1.26,
          _ => 1.12,
        };
        return Padding(
          padding: EdgeInsets.only(top: block.level == 1 ? 4 : 2),
          child: SelectableText.rich(
            TextSpan(
              children: _inlineSpans(
                block.text,
                base.copyWith(
                  fontSize: (base.fontSize ?? 14) * factor,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              style: base,
            ),
          ),
        );
      case _BlockType.bullet:
        return _ListLine(
          marker: '•',
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(block.text, base), style: base),
          ),
        );
      case _BlockType.number:
        return _ListLine(
          marker: block.marker,
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(block.text, base), style: base),
          ),
        );
      case _BlockType.quote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: palette.input.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border(left: BorderSide(color: palette.primary, width: 3)),
          ),
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(block.text, base), style: base),
          ),
        );
      case _BlockType.paragraph:
        return SelectableText.rich(
          TextSpan(children: _inlineSpans(block.text, base), style: base),
        );
    }
  }
}

enum _BlockType { paragraph, heading, bullet, number, quote, code, table }

class _Block {
  const _Block(
    this.type,
    this.text, {
    this.level = 1,
    this.marker = '',
    this.rows = const [],
    this.tightAfter = false,
  });

  final _BlockType type;
  final String text;
  final int level;
  final String marker;
  final List<List<String>> rows;
  final bool tightAfter;
}

List<_Block> _parseBlocks(String input) {
  final lines = input.split('\n');
  final blocks = <_Block>[];
  var index = 0;
  while (index < lines.length) {
    final raw = lines[index];
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      index++;
      continue;
    }
    if (trimmed.startsWith('```')) {
      final language = trimmed.substring(3).trim();
      final code = <String>[];
      index++;
      while (index < lines.length && !lines[index].trim().startsWith('```')) {
        code.add(lines[index]);
        index++;
      }
      if (index < lines.length) index++;
      blocks.add(
        _Block(
          _BlockType.code,
          code.join('\n'),
          marker: language,
          tightAfter: true,
        ),
      );
      continue;
    }
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      final rows = <List<String>>[];
      while (index < lines.length) {
        final candidate = lines[index].trim();
        if (!candidate.startsWith('|') || !candidate.endsWith('|')) break;
        final cells = candidate
            .substring(1, candidate.length - 1)
            .split('|')
            .map((cell) => cell.trim())
            .toList();
        final isSeparator = cells.every(
          (cell) => RegExp(r'^:?-{2,}:?$').hasMatch(cell),
        );
        if (!isSeparator) rows.add(cells);
        index++;
      }
      if (rows.isNotEmpty) {
        blocks.add(_Block(_BlockType.table, '', rows: rows));
      }
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      blocks.add(
        _Block(
          _BlockType.heading,
          heading[2]!,
          level: heading[1]!.length,
          tightAfter: true,
        ),
      );
      index++;
      continue;
    }
    final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      blocks.add(_Block(_BlockType.bullet, bullet[1]!, tightAfter: true));
      index++;
      continue;
    }
    final numbered = RegExp(r'^(\d+[.)])\s+(.*)$').firstMatch(trimmed);
    if (numbered != null) {
      blocks.add(
        _Block(
          _BlockType.number,
          numbered[2]!,
          marker: numbered[1]!,
          tightAfter: true,
        ),
      );
      index++;
      continue;
    }
    if (trimmed.startsWith('> ')) {
      blocks.add(
        _Block(_BlockType.quote, trimmed.substring(2).trim(), tightAfter: true),
      );
      index++;
      continue;
    }
    final paragraph = <String>[trimmed];
    index++;
    while (index < lines.length) {
      final next = lines[index].trim();
      if (next.isEmpty ||
          next.startsWith('#') ||
          next.startsWith('```') ||
          next.startsWith('|') ||
          next.startsWith('> ') ||
          RegExp(r'^[-*•]\s+').hasMatch(next) ||
          RegExp(r'^\d+[.)]\s+').hasMatch(next)) {
        break;
      }
      paragraph.add(next);
      index++;
    }
    blocks.add(_Block(_BlockType.paragraph, paragraph.join(' ')));
  }
  return blocks;
}

class _ListLine extends StatelessWidget {
  const _ListLine({required this.marker, required this.child});

  final String marker;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: marker == '•' ? 16 : 24,
          child: Text(
            marker,
            style: TextStyle(color: context.palette.muted, height: 1.55),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                Text(
                  'código',
                  style: TextStyle(
                    color: palette.disabled,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copiar código',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado.')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.5,
                color: palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final columns = rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: palette.border, width: 0.6),
            verticalInside: BorderSide(color: palette.border, width: 0.6),
          ),
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
              TableRow(
                decoration: BoxDecoration(
                  color: rowIndex == 0 ? palette.selected : null,
                ),
                children: [
                  for (var column = 0; column < columns; column++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        column < rows[rowIndex].length
                            ? rows[rowIndex][column]
                            : '',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: rowIndex == 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: palette.text,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

List<InlineSpan> _inlineSpans(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'(\*\*[^*]+\*\*|__[^_]+__|\*[^*\n]+\*|_[^_\n]+_|`[^`]+`|\[[^\]]+\]\((?:https?://|www\.)[^)]+\))',
  );
  var index = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    final token = match.group(0)!;
    if (token.startsWith('**') || token.startsWith('__')) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (token.startsWith('`')) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.92,
            backgroundColor: base.color?.withValues(alpha: 0.08),
          ),
        ),
      );
    } else if (token.startsWith('[')) {
      final label = token.substring(1, token.indexOf(']'));
      spans.add(
        TextSpan(
          text: label,
          style: TextStyle(color: base.color, decoration: TextDecoration.underline),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return spans;
}
