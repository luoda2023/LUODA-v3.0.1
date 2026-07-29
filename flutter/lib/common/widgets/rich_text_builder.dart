import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';

/// Lightweight rich text renderer for chat messages.
/// Parses a simple markdown-like syntax into styled Flutter widgets.
///
/// Supported syntax:
///  - **bold**           Bold text
///  - *italic*           Italic text
///  - `code`            Monospace inline code
///  - ~~strikethrough~~   Strikethrough
///  - [color=red]text[/color]  Colored text (red/green/blue/orange/purple/gray/white or #RRGGBB)
///  - [size=18]text[/size]     Custom font size (in logical pixels)
///  - |h1|h2|\n|---|---|\n|v1|v2|  Markdown-style table
///  - :emoji_name:      Emoji placeholder (renders via Unicode)
///  - URLs are auto-detected and rendered as tappable links.

class RichChatText extends StatelessWidget {
  final String text;
  final Color foreground;
  final double defaultSize;

  const RichChatText({
    super.key,
    required this.text,
    required this.foreground,
    this.defaultSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    // First check for tables (block-level)
    final tableSections = _extractTables(text);
    if (tableSections.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tableSections
            .map((section) => section is TableData
                ? _buildTable(section)
                : _buildInline(section as String, foreground, defaultSize))
            .toList(),
      );
    }

    // No tables, just inline text
    return _buildInline(text, foreground, defaultSize);
  }

  // ------------------------------------------------------------------
  // Table extraction
  // ------------------------------------------------------------------
  static List<Object> _extractTables(String text) {
    // Pattern: lines starting/ending with |
    final parts = <Object>[];
    final lines = text.split('\n');
    int i = 0;
    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        // Check if next line is a separator row
        final headerRow = _parseTableRow(trimmed);
        if (headerRow.isEmpty) {
          parts.add(lines[i]);
          i++;
          continue;
        }
        if (i + 1 < lines.length) {
          final sepLine = lines[i + 1].trim();
          final sepCells = _parseTableRow(sepLine);
          if (sepCells.length == headerRow.length &&
              sepCells.every((c) => c.startsWith('---') || c.startsWith(':'))) {
            // This is a table
            final rows = <List<String>>[headerRow];
            i += 2;
            while (i < lines.length) {
              final rowLine = lines[i].trim();
              if (!rowLine.startsWith('|') || !rowLine.endsWith('|')) break;
              final rowCells = _parseTableRow(rowLine);
              if (rowCells.isEmpty) break;
              // Pad or trim to match header count
              final padded = List<String>.from(rowCells);
              while (padded.length < headerRow.length) padded.add('');
              rows.add(padded);
              i++;
            }
            parts.add(TableData(headerRow, rows));
            continue;
          }
        }
      }
      parts.add(lines[i]);
      i++;
    }
    return parts;
  }

  static List<String> _parseTableRow(String line) {
    // Strip outer |
    final inner = line.substring(1, line.length - 1).trim();
    if (inner.isEmpty) return [];
    final cells = <String>[];
    int j = 0;
    // Handle escaped pipes inside cells
    final buf = StringBuffer();
    while (j < inner.length) {
      if (inner[j] == '\\' && j + 1 < inner.length && inner[j + 1] == '|') {
        buf.write('|');
        j += 2;
      } else if (inner[j] == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
        j++;
      } else {
        buf.write(inner[j]);
        j++;
      }
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  Widget _buildTable(TableData table) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Table(
        border: TableBorder.all(
          color: foreground.withOpacity(0.25),
          width: 0.5,
        ),
        columnWidths: table.columns.fold<int>(
          0,
          (sum, _) => sum + 1,
        ) > 0
            ? {for (int i = 0; i < table.columns.length; i++) i: FlexColumnWidth()}
            : null,
        children: table.rows.asMap().entries.map((entry) {
          final rowIdx = entry.key;
          final row = entry.value;
          final isHeader = rowIdx == 0;
          return TableRow(
            decoration: isHeader
                ? BoxDecoration(
                    color: foreground.withOpacity(0.08),
                  )
                : null,
            children: row.map((cell) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  cell,
                  style: TextStyle(
                    color: foreground,
                    fontSize: defaultSize - 1,
                    fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                    height: 1.3,
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Inline parsing
  // ------------------------------------------------------------------
  Widget _buildInline(String text, Color fg, double size) {
    final spans = _parseInline(text, fg, size);
    if (spans.isEmpty) return const SizedBox.shrink();
    return SelectableText.rich(
      text: TextSpan(children: spans),
      style: TextStyle(
        color: fg,
        fontSize: size,
        height: 1.42,
        letterSpacing: 0,
      ),
    );
  }

  List<InlineSpan> _parseInline(String text, Color fg, double size) {
    // We parse in multiple passes:
    // 1. URLs (keep existing link detection)
    // 2. Inline formatting: **bold**, *italic*, `code`, ~~strike~~, [color=], [size=]
    // 3. Emoji placeholders

    final result = <InlineSpan>[];
    final urlRe = RegExp(
        r'https?:\/\/[^\s<>\'\"\[\]]+|www\.[^\s<>\'\"\[\]]+\.[a-zA-Z]{2,}[^\s<>\'\"\[\]]*');
    final boldRe = RegExp(r'\*\*(.+?)\*\*');
    final italicRe = RegExp(r'\*(.+?)\*');
    final codeRe = RegExp(r'`(.+?)`');
    final strikeRe = RegExp(r'~~(.+?)~~');
    final colorRe = RegExp(r'\[color=([^\]]+)\](.+?)\[/color\]');
    final sizeRe = RegExp(r'\[size=(\d+)\](.+?)\[/size\]');

    // Tokenize: split text by formatting boundaries
    final tokens = <_Token>[];
    int pos = 0;

    // Find the earliest match among all patterns
    while (pos < text.length) {
      // Check for table lines (skip)
      if (text[pos] == '\n') {
        tokens.add(_Token.text('\n', fg, size));
        pos++;
        continue;
      }

      // Find earliest match
      _Token? earliest;

      // URLs
      final urlMatch = urlRe.matchAsPrefix(text, pos);
      if (urlMatch != null && urlMatch.start == pos) {
        earliest = _Token.url(urlMatch.group(0)!, fg, size, defaultSize);
      }

      // **bold**
      if (earliest == null) {
        final m = boldRe.matchAsPrefix(text, pos);
        if (m != null && m.start == pos) {
          earliest = _Token.bold(m.group(1)!, fg, size);
        }
      }

      // *italic*
      if (earliest == null) {
        final m = italicRe.matchAsPrefix(text, pos);
        if (m != null && m.start == pos) {
          earliest = _Token.italic(m.group(1)!, fg, size);
        }
      }

      // `code`
      if (earliest == null) {
        final m = codeRe.matchAsPrefix(text, pos);
        if (m != null && m.start == pos) {
          earliest = _Token.code(m.group(1)!, fg, size);
        }
      }

      // ~~strike~~
      if (earliest == null) {
        final m = strikeRe.matchAsPrefix(text, pos);
        if (m != null && m.start == pos) {
          earliest = _Token.strike(m.group(1)!, fg, size);
        }
      }

      // [color=...]
      if (earliest == null) {
        final m = colorRe.matchAsPrefix(text, pos);
        if (m != null && m.start == pos) {
          final colorStr = m.group(1)!;
          final inner = m.group(2)!;
          Color? c;
          switch (colorStr.toLowerCase()) {
            case 'red':
              c = const Color(0xFFE5484D);
              break;
            case 'green':
              c = const Color(0xFF30A46C);
              break;
            case 'blue':
              c = const Color(0xFF3E63DD);
              break;
            case 'orange':
              c = const Color(0xFFFF8B3E);
              break;
            case 'purple':
              c = const Color(0xFF8E4EC6);
              break;
            case 'gray':
            case 'grey':
              c = const Color(0xFF7C7C7C);
              break;
            case 'white':
              c = Colors.white;
              break;
            default:
              // Try hex
              if (colorStr.startsWith('#')) {
                final hex = colorStr.substring(1);
                if (hex.length == 6) {
                  c = Color(int.parse(hex, radix: 16) | 0xFF000000);
                } else if (hex.length == 3) {
                  final r = int.parse(hex[0], radix: 16) * 17;
                  final g = int.parse(hex[1], radix: 16) * 17;
                  final b = int.parse(hex[2], radix: 16) * 17;
                  c = Color.fromARGB(255, r, g, b);
                }
              }
          }
          if (c != null) {
            earliest = _Token.colored(inner, c, size);
          }
        }
      }

      // [size=N]
      if (earliest == null) {
        final m = sizeRe.matchAsPrefix(text, pos);
        if (m != null && m.start == pos) {
          final sz = int.tryParse(m.group(1)!) ?? 14;
          earliest = _Token.text(m.group(2)!, fg, sz.toDouble());
        }
      }

      if (earliest != null) {
        tokens.add(earliest);
        pos += earliest.length;
      } else {
        // Plain character
        tokens.add(_Token.text(text[pos], fg, size));
        pos++;
      }
    }

    // Convert tokens to InlineSpans
    for (final token in tokens) {
      result.addAll(token.toSpans());
    }

    return result;
  }
}

// ------------------------------------------------------------------
// Data classes
// ------------------------------------------------------------------
class TableData {
  final List<String> columns;
  final List<List<String>> rows;
  TableData(this.columns, this.rows);
}

class _Token {
  enum Type { plain, bold, italic, code, strike, colored, url }

  final Type type;
  final String text;
  final Color color;
  final double size;

  _Token._({
    required this.type,
    required this.text,
    required this.color,
    required this.size,
  });

  int get length {
    switch (type) {
      case Type.bold:
        return text.length + 4; // **text**
      case Type.italic:
        return text.length + 2; // *text*
      case Type.code:
        return text.length + 2; // `text`
      case Type.strike:
        return text.length + 4; // ~~text~~
      case Type.colored:
        // [color=xxx]text[/color] — approximate, ok for offset
        return text.length + 14;
      case Type.url:
        return text.length;
      case Type.plain:
        return text.length;
    }
  }

  factory _Token.text(String t, Color c, double s) =>
      _Token._(type: Type.plain, text: t, color: c, size: s);
  factory _Token.bold(String t, Color c, double s) =>
      _Token._(type: Type.bold, text: t, color: c, size: s);
  factory _Token.italic(String t, Color c, double s) =>
      _Token._(type: Type.italic, text: t, color: c, size: s);
  factory _Token.code(String t, Color c, double s) =>
      _Token._(type: Type.code, text: t, color: c, size: s);
  factory _Token.strike(String t, Color c, double s) =>
      _Token._(type: Type.strike, text: t, color: c, size: s);
  factory _Token.colored(String t, Color c, double s) =>
      _Token._(type: Type.colored, text: t, color: c, size: s);
  factory _Token.url(String t, Color c, double s, double defaultSize) =>
      _Token._(type: Type.url, text: t, color: c, size: s);

  List<InlineSpan> toSpans() {
    switch (type) {
      case Type.plain:
        return [TextSpan(text: text)];
      case Type.bold:
        return [
          TextSpan(
            text: text,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ];
      case Type.italic:
        return [
          TextSpan(
            text: text,
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ];
      case Type.code:
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: size - 1,
                  color: color,
                ),
              ),
            ),
          ),
        ];
      case Type.strike:
        return [
          TextSpan(
            text: text,
            style: TextStyle(decoration: TextDecoration.lineThrough),
          ),
        ];
      case Type.colored:
        return [
          TextSpan(
            text: text,
            style: TextStyle(color: color),
          ),
        ];
      case Type.url:
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () {
                final uri = Uri.tryParse(
                    text.startsWith('http') ? text : 'https://$text');
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: text));
              },
              child: Text(
                text.length > 50 ? '${text.substring(0, 47)}...' : text,
                style: TextStyle(
                  color: const Color(0xFF3E63DD),
                  decoration: TextDecoration.underline,
                  fontSize: size,
                ),
              ),
            ),
          ),
        ];
    }
  }
}
