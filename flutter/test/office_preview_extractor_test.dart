import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/office_preview_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<File> writeTemp(String name, List<int> bytes) async {
    final dir = await Directory.systemTemp.createTemp('luoda_preview_test');
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  test('docx text extraction', () async {
    final xml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>'
        '<w:p><w:r><w:t>Hello DOCX</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Second paragraph</w:t></w:r></w:p>'
        '</w:body></w:document>';
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
    final zip = ZipEncoder().encode(archive) ?? Uint8List(0);
    final f = await writeTemp('test.docx', zip);
    final text = await extractOfficePreviewText(f.path, 'test.docx');
    expect(text, contains('Hello DOCX'));
    expect(text, contains('Second paragraph'));
  });

  test('xlsx text extraction with shared strings', () async {
    final shared =
        '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>Alpha</t></si><si><t>Beta</t></si></sst>';
    final sheet =
        '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2"><v>42</v></c></row>'
        '</sheetData></worksheet>';
    final archive = Archive()
      ..addFile(ArchiveFile('xl/sharedStrings.xml', utf8.encode(shared).length, utf8.encode(shared)))
      ..addFile(ArchiveFile('xl/worksheets/sheet1.xml', utf8.encode(sheet).length, utf8.encode(sheet)));
    final zip = ZipEncoder().encode(archive) ?? Uint8List(0);
    final f = await writeTemp('test.xlsx', zip);
    final text = await extractOfficePreviewText(f.path, 'test.xlsx');
    expect(text, contains('Alpha'));
    expect(text, contains('Beta'));
    expect(text, contains('42'));
  });

  test('pptx text extraction', () async {
    final slide =
        '<?xml version="1.0"?><p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:sp><p:txBody><a:p><a:r><a:t>Slide One</a:t></a:r></a:p>'
        '<a:p><a:r><a:t>Second line</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:sld>';
    final archive = Archive()
      ..addFile(ArchiveFile('ppt/slides/slide1.xml', utf8.encode(slide).length, utf8.encode(slide)));
    final zip = ZipEncoder().encode(archive) ?? Uint8List(0);
    final f = await writeTemp('test.pptx', zip);
    final text = await extractOfficePreviewText(f.path, 'test.pptx');
    expect(text, contains('Slide One'));
    expect(text, contains('Second line'));
  });

  test('pdf text extraction from flate streams', () async {
    final content = 'BT /F1 12 Tf 72 720 Td (Hello PDF) Tj ET '
        'BT /F1 12 Tf 72 700 Td [(Hel) (lo) ( again)] TJ ET';
    final compressed = ZLibEncoder().encode(utf8.encode(content));
    final objects = StringBuffer()
      ..writeln('%PDF-1.4')
      ..writeln('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj')
      ..writeln('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj')
      ..writeln('3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents 4 0 R >> endobj')
      ..writeln('4 0 obj << /Length ${compressed.length} /Filter /FlateDecode >>')
      ..writeln('stream');
    final pdfBytes = <int>[
      ...utf8.encode(objects.toString()),
      ...compressed,
      ...utf8.encode('\nendstream\nendobj\n%%EOF\n'),
    ];
    final f = await writeTemp('test.pdf', pdfBytes);
    final text = await extractOfficePreviewText(f.path, 'test.pdf');
    expect(text, contains('Hello PDF'));
    expect(text, contains('Hello again'));
  });
}
