import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:open_filex/open_filex.dart';
import 'package:xml/xml.dart';

import 'file_preview_types.dart';

/// True when [kind] can be previewed in-app by extracting its text content
/// (DOCX / XLSX / PPTX / PDF). Other kinds keep their existing viewers.
bool isOfficeTextPreviewKind(FilePreviewKind kind) =>
    kind == FilePreviewKind.document ||
    kind == FilePreviewKind.spreadsheet ||
    kind == FilePreviewKind.presentation ||
    kind == FilePreviewKind.pdf;

const int _maxPreviewChars = 600000;

/// Best-effort text extraction for Office/PDF files (no heavy renderer).
/// Returns an empty string when the format cannot be extracted.
Future<String> extractOfficePreviewText(String path, String fileName) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return '';
    switch (filePreviewKindForName(fileName)) {
      case FilePreviewKind.document:
        return _extractDocx(file);
      case FilePreviewKind.spreadsheet:
        return _extractXlsx(file);
      case FilePreviewKind.presentation:
        return _extractPptx(file);
      case FilePreviewKind.pdf:
        return _extractPdfText(file);
      default:
        return '';
    }
  } catch (_) {
    return '';
  }
}

String _cap(String value) {
  final compact = value.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (compact.length <= _maxPreviewChars) return compact;
  return '${compact.substring(0, _maxPreviewChars)}\n? (truncated)';
}

Uint8List _entryBytes(ArchiveFile f) {
  final content = f.content;
  if (content is Uint8List) return content;
  if (content is List<int>) return Uint8List.fromList(content);
  return Uint8List(0);
}

Archive _openZip(File file) =>
    ZipDecoder().decodeBytes(file.readAsBytesSync());

String _decodeUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

Iterable<XmlElement> _localElements(XmlElement root, String localName) =>
    root.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == localName);

String _joinTextElements(XmlElement parent) => parent.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == 't')
    .map((e) => e.innerText)
    .join();

String _extractDocx(File file) {
  final archive = _openZip(file);
  XmlElement? documentXml;
  for (final f in archive) {
    if (f.name == 'word/document.xml') {
      documentXml = XmlDocument.parse(_decodeUtf8(_entryBytes(f))).rootElement;
      break;
    }
  }
  if (documentXml == null) return '';
  final buffer = StringBuffer();
  for (final para in _localElements(documentXml, 'p')) {
    final line = _joinTextElements(para).trim();
    if (line.isNotEmpty) buffer.writeln(line);
  }
  return _cap(buffer.toString());
}

String _extractXlsx(File file) {
  final archive = _openZip(file);
  final sharedStrings = <String>[];
  for (final f in archive) {
    if (f.name == 'xl/sharedStrings.xml') {
      final doc = XmlDocument.parse(_decodeUtf8(_entryBytes(f)));
      for (final si in _localElements(doc.rootElement, 'si')) {
        sharedStrings.add(si.innerText.replaceAll(RegExp(r'[\r\n]+'), ' '));
      }
      break;
    }
  }
  final sheets = <ArchiveFile>[];
  final sheetRe = RegExp(r'^xl/worksheets/sheet\d+\.xml$');
  for (final f in archive) {
    if (sheetRe.hasMatch(f.name)) sheets.add(f);
  }
  int sheetNumber(String name) {
    final m = RegExp(r'(\d+)').firstMatch(name);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  sheets.sort((a, b) => sheetNumber(a.name).compareTo(sheetNumber(b.name)));
  final buffer = StringBuffer();
  for (final sheet in sheets) {
    final doc = XmlDocument.parse(_decodeUtf8(_entryBytes(sheet)));
    for (final row in _localElements(doc.rootElement, 'row')) {
      final cells = <String>[];
      for (final c in _localElements(row, 'c')) {
        final t = c.getAttribute('t') ?? '';
        String value = '';
        XmlElement? v;
        XmlElement? isNode;
        for (final d in c.descendants.whereType<XmlElement>()) {
          if (d.name.local == 'v' && v == null) v = d;
          if (d.name.local == 'is' && isNode == null) isNode = d;
        }
        if (t == 's' && v != null) {
          final idx = int.tryParse(v.innerText.trim());
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            value = sharedStrings[idx];
          }
        } else if (t == 'inlineStr' && isNode != null) {
          value = isNode.innerText;
        } else if (v != null) {
          value = v.innerText;
        }
        cells.add(value.replaceAll(RegExp(r'[\r\n]+'), ' '));
      }
      if (cells.any((c) => c.trim().isNotEmpty)) {
        buffer.writeln(cells.join('\t'));
      }
    }
    buffer.writeln();
    if (buffer.length > _maxPreviewChars) break;
  }
  return _cap(buffer.toString());
}

String _extractPptx(File file) {
  final archive = _openZip(file);
  final slides = <ArchiveFile>[];
  final slideRe = RegExp(r'^ppt/slides/slide\d+\.xml$');
  for (final f in archive) {
    if (slideRe.hasMatch(f.name)) slides.add(f);
  }
  int slideNumber(String name) {
    final m = RegExp(r'(\d+)').firstMatch(name);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  slides.sort((a, b) => slideNumber(a.name).compareTo(slideNumber(b.name)));
  final buffer = StringBuffer();
  for (final slide in slides) {
    final doc = XmlDocument.parse(_decodeUtf8(_entryBytes(slide)));
    for (final para in _localElements(doc.rootElement, 'p')) {
      final line = _joinTextElements(para).trim();
      if (line.isNotEmpty) buffer.writeln(line);
    }
    buffer.writeln();
  }
  return _cap(buffer.toString());
}

String _extractPdfText(File file) {
  final bytes = file.readAsBytesSync();
  final out = StringBuffer();
  final streamMark = 'stream'.codeUnits;
  final endMark = 'endstream'.codeUnits;
  int pos = 0;
  while (pos < bytes.length) {
    final start = _indexOf(bytes, streamMark, pos);
    if (start < 0) break;
    int dataStart = start + streamMark.length;
    if (dataStart < bytes.length && bytes[dataStart] == 13) dataStart++;
    if (dataStart < bytes.length && bytes[dataStart] == 10) dataStart++;
    final end = _indexOf(bytes, endMark, dataStart);
    if (end < 0) break;
    int dataEnd = end;
    while (dataEnd > dataStart &&
        (bytes[dataEnd - 1] == 10 || bytes[dataEnd - 1] == 13)) {
      dataEnd--;
    }
    List<int> decoded;
    try {
      decoded = ZLibDecoder().decodeBytes(bytes.sublist(dataStart, dataEnd));
    } catch (_) {
      pos = end + endMark.length;
      continue;
    }
    final content = latin1.decode(decoded, allowInvalid: true);
    if (content.contains('Tj') ||
        content.contains('TJ') ||
        content.contains('BT')) {
      final text = _pdfContentToText(content);
      if (text.isNotEmpty) out.writeln(text);
    }
    if (out.length > _maxPreviewChars) break;
    pos = end + endMark.length;
  }
  return _cap(out.toString());
}

String _pdfContentToText(String content) {
  final buffer = StringBuffer();
  final tjRe = RegExp(r'\((?:[^()\\]|\\.)*\)\s*Tj');
  final tjArrayRe = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
  for (final m in tjRe.allMatches(content)) {
    final token = m.group(0)!;
    buffer.write(_pdfUnescape(token.substring(1, token.lastIndexOf(')'))));
    buffer.write(' ');
  }
  final arrayTokenRe =
      RegExp(r'\((?:[^()\\]|\\.)*\)|[-+]?\d+(?:\.\d+)?');
  for (final m in tjArrayRe.allMatches(content)) {
    // In a TJ array, numbers are kerning adjustments: negative values
    // tighten the gap, so adjacent string literals are joined directly.
    for (final s in arrayTokenRe.allMatches(m.group(1)!)) {
      final token = s.group(0)!;
      if (!token.startsWith('(')) continue;
      buffer.write(
          _pdfUnescape(token.substring(1, token.length - 1)));
    }
  }
  return buffer.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

String _pdfUnescape(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length) {
      final next = s[i + 1];
      if (next == 'n') {
        b.write('\n');
        i++;
      } else if (next == 'r') {
        b.write('\r');
        i++;
      } else if (next == 't') {
        b.write('\t');
        i++;
      } else if (next == 'b') {
        b.write('\b');
        i++;
      } else if (next == 'f') {
        b.write('\f');
        i++;
      } else if (next == '(' || next == ')' || next == r'\') {
        b.write(next);
        i++;
      } else if (RegExp(r'[0-7]').hasMatch(next)) {
        var oct = next;
        var j = i + 2;
        while (j < s.length &&
            oct.length < 3 &&
            RegExp(r'[0-7]').hasMatch(s[j])) {
          oct += s[j];
          j++;
        }
        b.writeCharCode(int.parse(oct, radix: 8));
        i = j - 1;
      } else {
        b.write(next);
        i++;
      }
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

int _indexOf(List<int> haystack, List<int> needle, int start) {
  if (needle.isEmpty || start < 0 || start >= haystack.length) return -1;
  if (start > haystack.length - needle.length) return -1;
  outer:
  for (var i = start; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// In-app viewer for extracted Office/PDF text. Falls back to an "open with
/// system app" card when nothing can be extracted.
class OfficeTextPreviewView extends StatefulWidget {
  const OfficeTextPreviewView({
    super.key,
    required this.path,
    required this.fileName,
    required this.fileSize,
  });

  final String path;
  final String fileName;
  final int fileSize;

  @override
  State<OfficeTextPreviewView> createState() => _OfficeTextPreviewViewState();
}

class _OfficeTextPreviewViewState extends State<OfficeTextPreviewView> {
  late final Future<String> _extractFuture;

  @override
  void initState() {
    super.initState();
    _extractFuture = extractOfficePreviewText(widget.path, widget.fileName);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<String>(
      future: _extractFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final text = snapshot.data ?? '';
        if (text.trim().isEmpty) {
          return _ExtractionFailedView(
            path: widget.path,
            fileName: widget.fileName,
            fileSize: widget.fileSize,
          );
        }
        final lines = text.split('\n');
        return Container(
          color: dark ? const Color(0xFF15171B) : const Color(0xFFFAFAFA),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lines.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 0.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              fontFamily: 'monospace',
                              color: dark
                                  ? const Color(0xFF4A4D53)
                                  : const Color(0xFFB0B0B0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            lines[i].isEmpty ? ' ' : lines[i],
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              fontFamily: 'monospace',
                              color: dark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExtractionFailedView extends StatelessWidget {
  const _ExtractionFailedView({
    required this.path,
    required this.fileName,
    required this.fileSize,
  });

  final String path;
  final String fileName;
  final int fileSize;

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: filePreviewColor(fileName, dark ? 0.24 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    filePreviewIcon(fileName),
                    size: 36,
                    color: filePreviewColor(fileName, dark ? 0.9 : 0.8),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fileExtensionLabel(fileName),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: filePreviewColor(fileName, dark ? 0.9 : 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _formatSize(fileSize),
              style: TextStyle(
                fontSize: 13,
                color: dark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              translate('Unable to extract a text preview for this file.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: dark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(translate('Open with system app')),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => OpenFilex.open(path),
            ),
          ],
        ),
      ),
    );
  }
}
