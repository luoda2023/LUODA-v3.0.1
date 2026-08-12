import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:url_launcher/url_launcher.dart';

const List<String> kChatEmojiFontFallback = <String>[
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
  'LDeskNotoColorEmoji',
  'LDeskNotoSansCJKSC',
];

bool isEmojiOnlyMessage(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;

  var sawEmoji = false;
  final hasKeycap = text.runes.contains(0x20E3);
  for (final rune in text.runes) {
    if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) {
      continue;
    }
    if (rune == 0x200D ||
        rune == 0xFE0E ||
        rune == 0xFE0F ||
        rune == 0x20E3 ||
        (rune >= 0xE0020 && rune <= 0xE007F)) {
      continue;
    }
    final isKeycapBase = hasKeycap &&
        (rune == 0x23 ||
            rune == 0x2A ||
            (rune >= 0x30 && rune <= 0x39));
    final isEmoji = isKeycapBase ||
        rune == 0x00A9 ||
        rune == 0x00AE ||
        rune == 0x203C ||
        rune == 0x2049 ||
        rune == 0x2122 ||
        rune == 0x2139 ||
        (rune >= 0x2190 && rune <= 0x21FF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2B00 && rune <= 0x2BFF) ||
        rune == 0x3030 ||
        rune == 0x303D ||
        rune == 0x3297 ||
        rune == 0x3299 ||
        (rune >= 0x1F000 && rune <= 0x1FAFF);
    if (!isEmoji) return false;
    sawEmoji = true;
  }
  return sawEmoji;
}

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
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// 是否允许长按选择文字。
  /// 手机端消息列表关闭选择（默认），让长按手势让给消息操作菜单
  /// （撤回/销毁/转发等，与微信手机版一致）；PC 端保留文字选择。
  final bool enableSelection;

  const RichChatText({
    super.key,
    required this.text,
    required this.foreground,
    this.defaultSize = 14,
    this.contextMenuBuilder,
    this.enableSelection = false,
  });

  /// Small LRU cache: maps text → parsed block list.
  /// Prevents re-parsing the same message text on every rebuild.
  static const int _maxCache = 100;
  static final Map<String, List<Object>> _cache = {};
  static final List<String> _cacheOrder = [];

  static List<Object> _cachedBlocks(String text) {
    final cached = _cache[text];
    if (cached != null) return cached;
    final blocks = _extractBlocks(text);
    if (_cacheOrder.length >= _maxCache) {
      final oldest = _cacheOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[text] = blocks;
    _cacheOrder.add(text);
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    // Use cached block extraction
    final blocks = _cachedBlocks(text);
    if (blocks.isEmpty) return const SizedBox.shrink();
    final inlineSize =
        isEmojiOnlyMessage(text) ? defaultSize * 1.5 : defaultSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        if (block is TableData) return _buildTable(block);
        if (block is _HeadingData) return _buildHeading(block);
        if (block is _QuoteData) return _buildQuote(block);
        if (block is _ListData) return _buildList(block);
        if (block is _HorizontalRule) return _buildHR();
        // String → inline rendered text
        return _buildInline(block as String, foreground, inlineSize);
      }).toList(),
    );
  }

  // ------------------------------------------------------------------
  // Block extraction: tables, headings, quotes, HR, lists
  // ------------------------------------------------------------------
  static List<Object> _extractBlocks(String text) {
    final parts = <Object>[];
    final lines = text.split('\n');
    int i = 0;

    // Accumulator for consecutive list items
    List<String>? pendingList;

    void flushList() {
      if (pendingList != null && pendingList!.isNotEmpty) {
        parts.add(_ListData(pendingList!));
        pendingList = null;
      }
    }

    while (i < lines.length) {
      final raw = lines[i];
      final trimmed = raw.trim();

      // ---- Table ----
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        flushList();
        final result = _tryExtractTable(lines, i);
        if (result != null) {
          parts.add(result.item1);
          i += result.item2;
          continue;
        }
        parts.add(raw);
        i++;
        continue;
      }

      // ---- Heading # or ## ----
      if (trimmed.startsWith('## ') && trimmed.length > 3) {
        flushList();
        parts.add(_HeadingData(trimmed.substring(3).trim(), 2));
        i++;
        continue;
      }
      if (trimmed.startsWith('# ') && trimmed.length > 2) {
        flushList();
        parts.add(_HeadingData(trimmed.substring(2).trim(), 1));
        i++;
        continue;
      }

      // ---- Horizontal rule --- (at least 3 dashes, only dashes)
      if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
        flushList();
        parts.add(_HorizontalRule());
        i++;
        continue;
      }

      // ---- Blockquote > ----
      if (trimmed.startsWith('> ')) {
        flushList();
        final quoteLines = <String>[trimmed.substring(2).trim()];
        i++;
        while (i < lines.length && lines[i].trim().startsWith('> ')) {
          quoteLines.add(lines[i].trim().substring(2).trim());
          i++;
        }
        parts.add(_QuoteData(quoteLines.join('\n')));
        continue;
      }

      // ---- Bullet list - or * ----
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final content = trimmed.startsWith('- ')
            ? trimmed.substring(2).trim()
            : trimmed.substring(2).trim();
        pendingList ??= [];
        pendingList!.add(content);
        i++;
        continue;
      }

      // ---- Plain text ----
      flushList();
      parts.add(raw);
      i++;
    }

    flushList();
    return parts;
  }

  /// Try to parse a table starting at line [i]. Returns (TableData, lineCount) or null.
  static _TableResult? _tryExtractTable(List<String> lines, int i) {
    final headerRow = _parseTableRow(lines[i].trim());
    if (headerRow.isEmpty) return null;
    if (i + 1 >= lines.length) return null;
    final sepLine = lines[i + 1].trim();
    final sepCells = _parseTableRow(sepLine);
    if (sepCells.length != headerRow.length) return null;
    if (!sepCells.every((c) => c.startsWith('---') || c.startsWith(':')))
      return null;

    final rows = <List<String>>[headerRow];
    i += 2;
    while (i < lines.length) {
      final rowLine = lines[i].trim();
      if (!rowLine.startsWith('|') || !rowLine.endsWith('|')) break;
      final rowCells = _parseTableRow(rowLine);
      if (rowCells.isEmpty) break;
      final padded = List<String>.from(rowCells);
      while (padded.length < headerRow.length) padded.add('');
      rows.add(padded);
      i++;
    }
    return _TableResult(TableData(headerRow, rows), i - (rows.length + 1));
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
                ) >
                0
            ? {
                for (int i = 0; i < table.columns.length; i++)
                  i: FlexColumnWidth()
              }
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
    final style = TextStyle(
      color: fg,
      fontSize: size,
      height: 1.42,
      letterSpacing: 0,
      fontFamilyFallback: kChatEmojiFontFallback,
    );
    if (enableSelection) {
      return SelectableText.rich(
        TextSpan(children: spans),
        contextMenuBuilder: contextMenuBuilder,
        style: style,
      );
    }
    // 不可选：避免 SelectableText 的长按文字选择吞掉消息操作菜单的长按。
    return Text.rich(
      TextSpan(children: spans),
      style: style,
    );
  }

  List<InlineSpan> _parseInline(String text, Color fg, double size) {
    // We parse in multiple passes:
    // 1. URLs (keep existing link detection)
    // 2. Inline formatting: **bold**, *italic*, `code`, ~~strike~~, [color=], [size=]
    // 3. Emoji placeholders

    final result = <InlineSpan>[];
    final urlRe = RegExp(
        r"https?:\/\/[^\s<>\[\]]+|www\.[^\s<>\[\]]+\.[a-zA-Z]{2,}[^\s<>\[\]]*");
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
        final first = text.codeUnitAt(pos);
        final hasSurrogatePair = first >= 0xD800 &&
            first <= 0xDBFF &&
            pos + 1 < text.length &&
            text.codeUnitAt(pos + 1) >= 0xDC00 &&
            text.codeUnitAt(pos + 1) <= 0xDFFF;
        final character = text.substring(
          pos,
          pos + (hasSurrogatePair ? 2 : 1),
        );
        tokens.add(_Token.text(character, fg, size));
        pos += character.length;
      }
    }

    final mergedTokens = <_Token>[];
    for (final token in tokens) {
      if (token.type == _TokenType.plain &&
          mergedTokens.isNotEmpty &&
          mergedTokens.last.type == _TokenType.plain &&
          mergedTokens.last.color == token.color &&
          mergedTokens.last.size == token.size) {
        final previous = mergedTokens.removeLast();
        mergedTokens.add(
          _Token.text(previous.text + token.text, token.color, token.size),
        );
      } else {
        mergedTokens.add(token);
      }
    }

    // Keep adjacent Unicode scalars in one span so emoji variation selectors
    // and ZWJ sequences are shaped as a single glyph run.
    for (final token in mergedTokens) {
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

/// Token types for inline formatting.
enum _TokenType { plain, bold, italic, code, strike, colored, url }

class _Token {
  final _TokenType type;
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
      case _TokenType.bold:
        return text.length + 4; // **text**
      case _TokenType.italic:
        return text.length + 2; // *text*
      case _TokenType.code:
        return text.length + 2; // `text`
      case _TokenType.strike:
        return text.length + 4; // ~~text~~
      case _TokenType.colored:
        // [color=xxx]text[/color] — approximate, ok for offset
        return text.length + 14;
      case _TokenType.url:
        return text.length;
      case _TokenType.plain:
        return text.length;
    }
  }

  factory _Token.text(String t, Color c, double s) =>
      _Token._(type: _TokenType.plain, text: t, color: c, size: s);
  factory _Token.bold(String t, Color c, double s) =>
      _Token._(type: _TokenType.bold, text: t, color: c, size: s);
  factory _Token.italic(String t, Color c, double s) =>
      _Token._(type: _TokenType.italic, text: t, color: c, size: s);
  factory _Token.code(String t, Color c, double s) =>
      _Token._(type: _TokenType.code, text: t, color: c, size: s);
  factory _Token.strike(String t, Color c, double s) =>
      _Token._(type: _TokenType.strike, text: t, color: c, size: s);
  factory _Token.colored(String t, Color c, double s) =>
      _Token._(type: _TokenType.colored, text: t, color: c, size: s);
  factory _Token.url(String t, Color c, double s, double defaultSize) =>
      _Token._(type: _TokenType.url, text: t, color: c, size: s);

  List<InlineSpan> toSpans() {
    switch (type) {
      case _TokenType.plain:
        return [TextSpan(text: text)];
      case _TokenType.bold:
        return [
          TextSpan(
            text: text,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ];
      case _TokenType.italic:
        return [
          TextSpan(
            text: text,
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ];
      case _TokenType.code:
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
      case _TokenType.strike:
        return [
          TextSpan(
            text: text,
            style: TextStyle(decoration: TextDecoration.lineThrough),
          ),
        ];
      case _TokenType.colored:
        return [
          TextSpan(
            text: text,
            style: TextStyle(color: color),
          ),
        ];
      case _TokenType.url:
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

// ------------------------------------------------------------------
// Block element data classes + builders
// ------------------------------------------------------------------
class _HeadingData {
  final String text;
  final int level; // 1 = ##, 2 = #
  _HeadingData(this.text, this.level);
}

class _QuoteData {
  final String text;
  _QuoteData(this.text);
}

class _ListData {
  final List<String> items;
  _ListData(this.items);
}

class _HorizontalRule {}

/// Helper tuple for table extraction.
class _TableResult {
  final TableData item1;
  final int item2;
  _TableResult(this.item1, this.item2);
}

extension _RichChatBuilders on RichChatText {
  Widget _buildHeading(_HeadingData h) {
    final size = h.level == 1 ? defaultSize + 6 : defaultSize + 3;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        h.text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: size,
          color: foreground,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildQuote(_QuoteData q) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: foreground.withOpacity(0.3),
            width: 3,
          ),
        ),
      ),
      child: Text(
        q.text,
        style: TextStyle(
          color: foreground.withOpacity(0.75),
          fontSize: defaultSize - 1,
          height: 1.4,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildList(_ListData list) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: list.items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ',
                    style: TextStyle(fontSize: defaultSize, color: foreground)),
                Expanded(
                  child: _buildInline(item, foreground, defaultSize),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHR() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        height: 1,
        color: foreground.withOpacity(0.15),
      ),
    );
  }
}
