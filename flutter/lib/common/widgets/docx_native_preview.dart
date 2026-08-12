import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:open_filex/open_filex.dart';
import 'package:xml/xml.dart';

/// 解析 DOCX 文件为结构化块（段落/表格/图片），供预览渲染或测试使用。
DocxDocument parseDocx(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('file missing');
  }
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());

  String? xmlText(String name) {
    for (final f in archive) {
      if (f.name == name) {
        final c = f.content;
        if (c is Uint8List) return utf8.decode(c, allowMalformed: true);
        if (c is List<int>) {
          return utf8.decode(Uint8List.fromList(c), allowMalformed: true);
        }
      }
    }
    return null;
  }

  // 媒体文件：word/media/* -> rId 映射（word/_rels/document.xml.rels）。
  final mediaByRid = <String, Uint8List>{};
  final relsText = xmlText('word/_rels/document.xml.rels');
  if (relsText != null) {
    try {
      final rels = XmlDocument.parse(relsText);
      for (final rel in rels.rootElement.children.whereType<XmlElement>()) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id == null || target == null || id.isEmpty) continue;
        final name = target.startsWith('media/')
            ? 'word/$target'
            : target.contains('media/')
                ? 'word/${target.substring(target.indexOf('media/'))}'
                : null;
        if (name == null) continue;
        for (final f in archive) {
          if (f.name == name || f.name.endsWith('/$name')) {
            final c = f.content;
            if (c is Uint8List) {
              mediaByRid[id] = c;
            } else if (c is List<int>) {
              mediaByRid[id] = Uint8List.fromList(c);
            }
            break;
          }
        }
      }
    } catch (_) {}
  }

  // 标题层级：styles.xml 中 pStyle 名 -> 标题级别。
  final headingLevels = <String, int>{};
  final stylesText = xmlText('word/styles.xml');
  if (stylesText != null) {
    try {
      final styles = XmlDocument.parse(stylesText);
      for (final style in styles.rootElement.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'style')) {
        final id = style.getAttribute('w:styleId') ?? style.getAttribute('styleId');
        final name = style
            .descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'name')
            .map((e) => e.getAttribute('w:val') ?? e.getAttribute('val') ?? '')
            .firstOrNull;
        if (id == null || name == null) continue;
        final lower = name.toLowerCase();
        final headingMatch = RegExp(r'heading\s*(\d)|标题\s*(\d)|^标题(\d)')
            .firstMatch(lower);
        if (headingMatch != null) {
          final num = headingMatch.group(1) ??
              headingMatch.group(2) ??
              headingMatch.group(3) ??
              '1';
          final level = int.tryParse(num) ?? 1;
          headingLevels[id] = level.clamp(1, 6);
        } else if (RegExp(r'heading|标题').hasMatch(lower)) {
          headingLevels[id] = 1;
        }
      }
    } catch (_) {}
  }

  // 编号格式：numbering.xml numId -> numFmt。
  final numFmts = <String, String>{};
  final numberingText = xmlText('word/numbering.xml');
  if (numberingText != null) {
    try {
      final numbering = XmlDocument.parse(numberingText);
      final abstractByNum = <String, String>{};
      for (final num in numbering.rootElement.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'num')) {
        final id = num.getAttribute('w:numId') ?? num.getAttribute('numId');
        final abs = num.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'abstractNumId')
            .map((e) => e.getAttribute('w:val') ?? e.getAttribute('val') ?? '')
            .firstOrNull;
        if (id != null && abs != null) abstractByNum[id] = abs;
      }
      for (final abs in numbering.rootElement.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'abstractNum')) {
        final id = abs.getAttribute('w:abstractNumId') ??
            abs.getAttribute('abstractNumId');
        final fmt = abs.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'numFmt')
            .map((e) => e.getAttribute('w:val') ?? e.getAttribute('val') ?? '')
            .firstOrNull;
        if (id != null && fmt != null) {
          for (final entry in abstractByNum.entries) {
            if (entry.value == id) numFmts[entry.key] = fmt;
          }
        }
      }
    } catch (_) {}
  }

  final docText = xmlText('word/document.xml');
  if (docText == null) throw StateError('no document.xml');

  final root = XmlDocument.parse(docText).rootElement;
  final body = root.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'body')
      .firstOrNull;
  if (body == null) throw StateError('no body');

  final blocks = <DocxBlock>[];
  for (final el in body.children.whereType<XmlElement>()) {
    final local = el.name.local;
    if (local == 'p') {
      final para = _parseParagraph(el, headingLevels, numFmts);
      if (para != null) blocks.add(para);
    } else if (local == 'tbl') {
      final table = _parseTable(el, mediaByRid);
      if (table != null) blocks.add(table);
    }
  }
  return DocxDocument(
    blocks: blocks,
    media: mediaByRid,
    headingLevels: headingLevels,
    numFmts: numFmts,
  );
}
DocxParagraph? _parseParagraph(
    XmlElement p,
    Map<String, int> headingLevels,
    Map<String, String> numFmts,
  ) {
    XmlElement? pPr;
    final runs = <DocxRun>[];
    for (final child in p.children.whereType<XmlElement>()) {
      final local = child.name.local;
      if (local == 'pPr') {
        pPr = child;
      } else if (local == 'r') {
        final run = _parseRun(child);
        if (run != null) runs.add(run);
      } else if (local == 'hyperlink') {
        for (final r in child.children.whereType<XmlElement>()) {
          final run = _parseRun(r);
          if (run != null) runs.add(run);
        }
      }
    }

    // 图片可能在 run 里（_parseRun 返回 DocxImage），单独收集。
    final imageRuns = runs.whereType<DocxImage>().toList();
    if (imageRuns.isNotEmpty) {
      return DocxParagraph(runs: <DocxRun>[imageRuns.first]);
    }

    if (runs.isEmpty) return null;

    // 编号列表。
    final numPr = pPr?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'numPr')
        .firstOrNull;
    String? numId;
    int? ilvl;
    if (numPr != null) {
      numId = numPr.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'numId')
          .map((e) => e.getAttribute('w:val') ?? e.getAttribute('val') ?? '')
          .firstOrNull;
      ilvl = numPr.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'ilvl')
          .map((e) => int.tryParse(
                  e.getAttribute('w:val') ?? e.getAttribute('val') ?? ''))
          .firstOrNull;
    }

    // 对齐。
    TextAlign? align;
    final jc = pPr?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'jc')
        .map((e) => e.getAttribute('w:val') ?? e.getAttribute('val') ?? '')
        .firstOrNull;
    switch (jc) {
      case 'center':
        align = TextAlign.center;
        break;
      case 'right':
        align = TextAlign.right;
        break;
      case 'both':
      case 'distribute':
        align = TextAlign.justify;
        break;
    }

    // 样式 ID -> 标题层级。
    final pStyle = pPr?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'pStyle')
        .map((e) => e.getAttribute('w:val') ?? e.getAttribute('val') ?? '')
        .firstOrNull;
    int? headingLevel;
    if (pStyle != null) {
      headingLevel = headingLevels[pStyle];
      if (headingLevel == null) {
        final lower = pStyle.toLowerCase();
        final m = RegExp(r'heading\s*(\d)|标题\s*(\d)').firstMatch(lower);
        if (m != null) headingLevel = int.tryParse(m.group(1) ?? '1') ?? 1;
      }
    }

    // 缩进。
    double? leftIndent;
    final ind = pPr?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'ind')
        .firstOrNull;
    if (ind != null) {
      final left = ind.getAttribute('w:left') ?? ind.getAttribute('left');
      if (left != null) {
        final twips = int.tryParse(left);
        if (twips != null) leftIndent = twips / 20.0;
      }
    }

    return DocxParagraph(
      runs: runs,
      align: align,
      headingLevel: headingLevel,
      numId: numId,
      ilvl: ilvl ?? 0,
      isBullet: numId != null && numFmts[numId] == 'bullet',
      leftIndent: leftIndent,
    );
  }

DocxRun? _parseRun(XmlElement r) {
  final children = r.children.whereType<XmlElement>().toList();

  // 内嵌图片。
  for (final drawing in children.where((e) =>
      e.name.local == 'drawing' || e.name.local == 'pict')) {
    for (final blip in drawing.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'blip')) {
      final rid = blip.getAttribute('r:embed') ?? blip.getAttribute('embed');
      if (rid != null && rid.isNotEmpty) return DocxImage(rid: rid);
    }
  }

  final rPr = children.where((e) => e.name.local == 'rPr').firstOrNull;
  final text = StringBuffer();
  for (final c in children.where((e) =>
      e.name.local == 't' || e.name.local == 'tab' || e.name.local == 'br')) {
    if (c.name.local == 't') {
      text.write(c.innerText);
    } else if (c.name.local == 'tab') {
      text.write('\t');
    } else if (c.name.local == 'br') {
      text.write('\n');
    }
  }
  if (text.isEmpty) return null;

  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  Color? color;
  double? fontSize;
  if (rPr != null) {
    for (final prop in rPr.children.whereType<XmlElement>()) {
      switch (prop.name.local) {
        case 'b':
          final v = prop.getAttribute('w:val') ?? prop.getAttribute('val');
          bold = v != '0' && v != 'false';
          break;
        case 'i':
          final v = prop.getAttribute('w:val') ?? prop.getAttribute('val');
          italic = v != '0' && v != 'false';
          break;
        case 'u':
          final v = prop.getAttribute('w:val') ?? prop.getAttribute('val');
          underline = v != null && v != 'none' && v != '0' && v != 'false';
          break;
        case 'strike':
          final v = prop.getAttribute('w:val') ?? prop.getAttribute('val');
          strike = v != '0' && v != 'false';
          break;
        case 'color':
          final v = prop.getAttribute('w:val') ?? prop.getAttribute('val');
          if (v != null && v.isNotEmpty && v != 'auto') {
            final hex = int.tryParse(v, radix: 16);
            if (hex != null) color = Color(0xFF000000 | hex);
          }
          break;
        case 'sz':
          final v = prop.getAttribute('w:val') ?? prop.getAttribute('val');
          final half = int.tryParse(v ?? '');
          if (half != null) fontSize = half / 2.0;
          break;
      }
    }
  }

  return DocxText(
    text: text.toString(),
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    color: color,
    fontSize: fontSize,
  );
}

DocxTable? _parseTable(XmlElement tbl, Map<String, Uint8List> media) {
  final rows = <DocxTableRow>[];
  for (final tr in tbl.children.whereType<XmlElement>()) {
    if (tr.name.local != 'tr') continue;
    final cells = <DocxTableCell>[];
    for (final tc in tr.children.whereType<XmlElement>()) {
      if (tc.name.local != 'tc') continue;
      final cellRuns = <DocxRun>[];
      bool isHeader = false;
      final tcPr = tc.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'tcPr')
          .firstOrNull;
      if (tcPr != null) {
        final shade = tcPr.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'shd')
            .firstOrNull;
        if (shade != null) {
          final fill = shade.getAttribute('w:fill') ?? shade.getAttribute('fill');
          if (fill != null && fill.isNotEmpty && fill != 'auto') {
            isHeader = true;
          }
        }
      }
      for (final p in tc.children.whereType<XmlElement>()) {
        if (p.name.local != 'p') continue;
        for (final child in p.children.whereType<XmlElement>()) {
          if (child.name.local == 'r') {
            final run = _parseRun(child);
            if (run != null) cellRuns.add(run);
          } else if (child.name.local == 'hyperlink') {
            for (final r in child.children.whereType<XmlElement>()) {
              final run = _parseRun(r);
              if (run != null) cellRuns.add(run);
            }
          }
        }
      }
      // 单元格里的图片。
      final images = cellRuns.whereType<DocxImage>().toList();
      if (images.isNotEmpty) {
        cellRuns
          ..clear()
          ..add(images.first);
      }
      cells.add(DocxTableCell(runs: cellRuns, isHeader: isHeader));
    }
    rows.add(DocxTableRow(cells: cells));
  }
  if (rows.isEmpty) return null;
  return DocxTable(rows: rows);
}

/// DOCX 结构化版式预览：解析 word/document.xml，按原文渲染
/// 标题层级、加粗/斜体/下划线、对齐、编号列表、表格与内嵌图片。
/// 版式与原文接近（非像素级，但保留结构与样式）。
class DocxNativePreview extends StatefulWidget {
  const DocxNativePreview({
    super.key,
    required this.path,
    required this.fileName,
    this.fileSize = 0,
  });

  final String path;
  final String fileName;
  final int fileSize;

  @override
  State<DocxNativePreview> createState() => _DocxNativePreviewState();
}

class _DocxNativePreviewState extends State<DocxNativePreview> {
  bool _loading = true;
  bool _failed = false;
  List<DocxBlock> _blocks = const <DocxBlock>[];
  final Map<String, Uint8List> _media = <String, Uint8List>{};
  final Map<String, int> _headingLevels = <String, int>{};
  final Map<String, String> _numFmts = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Future<DocxDocument>.sync(() => parseDocx(widget.path));
      if (!mounted) return;
      setState(() {
        _blocks = result.blocks;
        _media.addAll(result.media);
        _headingLevels.addAll(result.headingLevels);
        _numFmts.addAll(result.numFmts);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final canvas = dark ? const Color(0xFF15191D) : Colors.white;
    final textColor = dark ? Colors.white : Colors.black87;

    if (_loading) {
      return ColoredBox(
        color: canvas,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed) {
      return ColoredBox(
        color: canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.description_outlined,
                    size: 56, color: textColor.withOpacity(0.4)),
                const SizedBox(height: 12),
                Text(translate('This document cannot be rendered in-app'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textColor.withOpacity(0.6))),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => OpenFilex.open(widget.path),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(translate('Open with system app')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    for (final block in _blocks) {
      if (block is DocxParagraph) {
        children.add(_buildParagraph(block, textColor));
      } else if (block is DocxTable) {
        children.add(_buildTable(block, dark, media: _media));
      }
    }

    return ColoredBox(
      color: canvas,
      child: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          children: <Widget>[
            // 顶部文件名栏。
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withOpacity(0.06)
                    : const Color(0xFFF3F5F7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.description_outlined,
                      size: 18, color: textColor.withOpacity(0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: translate('Open with system app'),
                    icon: Icon(Icons.open_in_new_rounded,
                        size: 17, color: textColor.withOpacity(0.6)),
                    onPressed: () => OpenFilex.open(widget.path),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildParagraph(DocxParagraph para, Color textColor) {
    final style = TextStyle(
      color: textColor,
      height: 1.55,
    );
    final defaultSize = 14.0;

    final spans = <InlineSpan>[];
    for (final run in para.runs) {
      if (run is DocxText) {
        final size = run.fontSize ??
            (para.headingLevel != null
                ? (17.0 - (para.headingLevel ?? 1) * 1.2)
                : defaultSize);
        spans.add(TextSpan(
          text: run.text,
          style: TextStyle(
            fontWeight: run.bold || para.headingLevel != null
                ? FontWeight.w600
                : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            decoration: run.underline
                ? TextDecoration.underline
                : run.strike
                    ? TextDecoration.lineThrough
                    : null,
            color: run.color ?? textColor,
            fontSize: size,
          ),
        ));
      } else if (run is DocxImage) {
        final data = _media[run.rid];
        if (data != null) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Image.memory(
                data,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ));
        }
      }
    }

    if (spans.isEmpty) return const SizedBox(height: 2);

    final isList = para.numId != null;
    final prefix = isList
        ? para.isBullet
            ? '•  '
            : '${para.ilvl + 1}. '
        : '';

    final headingSize = para.headingLevel != null
        ? (21.0 - para.headingLevel! * 1.5)
        : null;

    Widget content;
    if (para.headingLevel != null) {
      content = Padding(
        padding: EdgeInsets.only(
          top: (para.headingLevel ?? 1) >= 3 ? 10 : 16,
          bottom: 6,
        ),
        child: Text.rich(
          TextSpan(children: spans),
          style: TextStyle(
            fontSize: headingSize,
            fontWeight: FontWeight.w700,
            color: textColor,
            height: 1.4,
          ),
          textAlign: para.align ?? TextAlign.left,
        ),
      );
    } else {
      content = Padding(
        padding: EdgeInsets.only(
          left: (para.leftIndent ?? 0) + (isList ? 12.0 : 0),
          bottom: isList ? 2 : 6,
        ),
        child: Text.rich(
          TextSpan(children: spans),
          style: style,
          textAlign: para.align ?? TextAlign.left,
        ),
      );
      if (isList) {
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 22,
              child: Text(prefix, style: style),
            ),
            Expanded(child: content),
          ],
        );
      }
    }
    return content;
  }

  Widget _buildTable(DocxTable table, bool dark,
      {required Map<String, Uint8List> media}) {
    final textColor = dark ? Colors.white : Colors.black87;
    final borderColor = dark
        ? Colors.white.withOpacity(0.18)
        : Colors.black.withOpacity(0.15);
    final headerColor = dark
        ? Colors.white.withOpacity(0.1)
        : const Color(0xFFF0F3F6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: borderColor, width: 0.5),
              verticalInside: BorderSide(color: borderColor, width: 0.5),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              for (final row in table.rows)
                TableRow(
                  decoration: BoxDecoration(
                    color: row.cells.any((c) => c.isHeader)
                        ? headerColor
                        : null,
                  ),
                  children: <Widget>[
                    for (final cell in row.cells)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: _buildCellRuns(cell.runs, textColor, media),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCellRuns(
      List<DocxRun> runs, Color textColor, Map<String, Uint8List> media) {
    if (runs.isEmpty) return const SizedBox(height: 16);
    final first = runs.first;
    if (first is DocxImage) {
      final data = media[first.rid];
      if (data != null) {
        return Image.memory(data,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
      }
    }
    final children = <TextSpan>[];
    for (final run in runs) {
      if (run is DocxText) {
        children.add(TextSpan(
          text: run.text,
          style: TextStyle(
            fontWeight: run.bold ? FontWeight.w600 : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            decoration: run.underline ? TextDecoration.underline : null,
            color: run.color ?? textColor,
          ),
        ));
      }
    }
    return Text.rich(TextSpan(children: children),
        style: TextStyle(fontSize: 12.5, color: textColor, height: 1.4));
  }
}

/// ---------- 解析模型 ----------

class DocxDocument {
  DocxDocument({
    required this.blocks,
    required this.media,
    required this.headingLevels,
    required this.numFmts,
  });

  final List<DocxBlock> blocks;
  final Map<String, Uint8List> media;
  final Map<String, int> headingLevels;
  final Map<String, String> numFmts;
}

sealed class DocxBlock {}

class DocxParagraph extends DocxBlock {
  DocxParagraph({
    required this.runs,
    this.align,
    this.headingLevel,
    this.numId,
    this.ilvl = 0,
    this.isBullet = false,
    this.leftIndent,
  });

  final List<DocxRun> runs;
  final TextAlign? align;
  final int? headingLevel;
  final String? numId;
  final int ilvl;
  final bool isBullet;
  final double? leftIndent;
}

class DocxTable extends DocxBlock {
  DocxTable({required this.rows});

  final List<DocxTableRow> rows;
}

class DocxTableRow {
  DocxTableRow({required this.cells});

  final List<DocxTableCell> cells;
}

class DocxTableCell {
  DocxTableCell({required this.runs, this.isHeader = false});

  final List<DocxRun> runs;
  final bool isHeader;
}

sealed class DocxRun {}

class DocxText extends DocxRun {
  DocxText({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color,
    this.fontSize,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final Color? color;
  final double? fontSize;
}

class DocxImage extends DocxRun {
  DocxImage({required this.rid});

  final String rid;
}
