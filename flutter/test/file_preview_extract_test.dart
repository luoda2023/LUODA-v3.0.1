import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/file_preview_types.dart';
import 'package:luoda_flutter/common/widgets/office_preview_view.dart';

/// Builds a minimal DOCX in memory and returns its bytes.
List<int> buildMinimalDocx(List<String> paragraphs) {
  final documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
${paragraphs.map((p) => '<w:p><w:r><w:t>${_xmlEscape(p)}</w:t></w:r></w:p>').join()}
</w:body>
</w:document>''';
  final archive = Archive();
  archive.addFile(ArchiveFile.string('[Content_Types].xml', _contentTypesDocx));
  archive.addFile(ArchiveFile.string('_rels/.rels',
      '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'));
  archive.addFile(ArchiveFile.string('word/document.xml', documentXml));
  return ZipEncoder().encode(archive)!;
}

String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

const String _contentTypesDocx = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

void main() {
  group('filePreviewKindForName', () {
    test('maps common formats to preview kinds', () {
      expect(filePreviewKindForName('a.docx'), FilePreviewKind.document);
      expect(filePreviewKindForName('a.xlsx'), FilePreviewKind.spreadsheet);
      expect(filePreviewKindForName('a.pptx'), FilePreviewKind.presentation);
      expect(filePreviewKindForName('a.pdf'), FilePreviewKind.pdf);
      expect(filePreviewKindForName('a.dwg'), FilePreviewKind.cad);
      expect(filePreviewKindForName('a.md'), FilePreviewKind.text);
      expect(filePreviewKindForName('a.png'), FilePreviewKind.image);
      expect(filePreviewKindForName('a.jpg'), FilePreviewKind.image);
    });
  });

  group('extractOfficePreviewText', () {
    test('extracts DOCX paragraphs', () async {
      final dir = await Directory.systemTemp.createTemp('lpv_docx');
      final file = File('${dir.path}${Platform.pathSeparator}test.docx');
      await file.writeAsBytes(buildMinimalDocx(['Hello world', '第二行测试']));
      final text = await extractOfficePreviewText(file.path, 'test.docx');
      expect(text, contains('Hello world'));
      expect(text, contains('第二行测试'));
      await dir.delete(recursive: true);
    });

    test('returns empty for missing file', () async {
      final text = await extractOfficePreviewText(
          'C:/nonexistent/no_file_here.docx', 'no_file_here.docx');
      expect(text, isEmpty);
    });
  });
}
