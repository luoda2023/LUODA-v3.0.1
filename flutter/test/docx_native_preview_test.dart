import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/docx_native_preview.dart';

/// Build a minimal but real .docx (zip with word/ parts) exercising
/// headings, bold/italic runs, a bullet list, a table and an inline image.
File buildTestDocx(String path) {
  final archive = Archive();

  void addText(String name, String content) {
    archive.addFile(ArchiveFile.string(name, content));
  }

  addText('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''');

  addText('word/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:style w:type="paragraph" w:styleId="Heading1">
  <w:name w:val="heading 1"/>
</w:style>
<w:style w:type="paragraph" w:styleId="Heading2">
  <w:name w:val="heading 2"/>
</w:style>
</w:styles>''');

  addText('word/numbering.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:abstractNum w:abstractNumId="10">
  <w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/></w:lvl>
</w:abstractNum>
<w:num w:numId="7"><w:abstractNumId w:val="10"/></w:num>
</w:numbering>''');

  addText('word/_rels/document.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rIdImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
</Relationships>''');

  // A tiny 1x1 PNG.
  final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  archive.addFile(ArchiveFile('word/media/image1.png', pngBytes.length,
      Uint8List.fromList(pngBytes)));

  addText('word/document.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<w:body>
  <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
    <w:r><w:t>Chapter One</w:t></w:r></w:p>
  <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
    <w:r><w:t>Section A</w:t></w:r></w:p>
  <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
    <w:r><w:rPr><w:b/></w:rPr><w:t>Bold center</w:t></w:r>
    <w:r><w:rPr><w:i/><w:color w:val="FF0000"/></w:rPr><w:t> red italic</w:t></w:r></w:p>
  <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr>
    <w:r><w:t>Bullet item</w:t></w:r></w:p>
  <w:p><w:pPr><w:ind w:left="360"/></w:pPr>
    <w:r><w:drawing><w:inline><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
      <a:graphicData><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <pic:blipFill><a:blip r:embed="rIdImg1"/></pic:blipFill>
      </pic:pic></a:graphicData></a:graphic></w:inline></w:drawing></w:r></w:p>
  <w:tbl>
    <w:tr>
      <w:tc><w:tcPr><w:shd w:fill="D9E2F3"/></w:tcPr>
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Header</w:t></w:r></w:p></w:tc>
      <w:tc><w:p><w:r><w:t>Value</w:t></w:r></w:p></w:tc>
    </w:tr>
    <w:tr>
      <w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc>
      <w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc>
    </w:tr>
  </w:tbl>
  <w:sectPr/>
</w:body>
</w:document>''');

  final bytes = ZipEncoder().encode(archive)!;
  final file = File(path);
  file.writeAsBytesSync(bytes);
  return file;
}

void main() {
  test('parseDocx extracts headings, formatting, lists, tables and images',
      () {
    final dir = Directory.systemTemp.createTempSync('docx_test');
    final file = buildTestDocx('${dir.path}${Platform.pathSeparator}doc.docx');
    final doc = parseDocx(file.path);

    // Heading paragraphs.
    final heading1 = doc.blocks.whereType<DocxParagraph>().firstWhere(
        (p) => p.headingLevel == 1,
        orElse: () => throw StateError('no h1'));
    expect(
        (heading1.runs.first as DocxText).text, 'Chapter One',
        reason: 'H1 text');

    final heading2 = doc.blocks.whereType<DocxParagraph>().firstWhere(
        (p) => p.headingLevel == 2,
        orElse: () => throw StateError('no h2'));
    expect((heading2.runs.first as DocxText).text, 'Section A');

    // Center-aligned bold + italic red run.
    final centered = doc.blocks.whereType<DocxParagraph>().firstWhere(
        (p) => p.align == TextAlign.center,
        orElse: () => throw StateError('no centered'));
    expect(centered.runs.length, 2);
    final bold = centered.runs[0] as DocxText;
    expect(bold.bold, isTrue);
    expect(bold.text, 'Bold center');
    final italic = centered.runs[1] as DocxText;
    expect(italic.italic, isTrue);
    expect(italic.color, const Color(0xFFFF0000));

    // Bullet list.
    final bullet = doc.blocks.whereType<DocxParagraph>().firstWhere(
        (p) => p.numId != null,
        orElse: () => throw StateError('no list'));
    expect(bullet.isBullet, isTrue, reason: 'numFmt bullet');
    expect((bullet.runs.first as DocxText).text, 'Bullet item');

    // Inline image resolves to media bytes.
    final imagePara = doc.blocks.whereType<DocxParagraph>().firstWhere(
        (p) => p.runs.any((r) => r is DocxImage),
        orElse: () => throw StateError('no image'));
    final img = imagePara.runs.firstWhere((r) => r is DocxImage) as DocxImage;
    expect(doc.media[img.rid], isNotNull, reason: 'rIdImg1 -> png bytes');
    expect(doc.media[img.rid]!.length, greaterThan(50));

    // Table with header shading.
    final table = doc.blocks.whereType<DocxTable>().first;
    expect(table.rows.length, 2);
    expect(table.rows[0].cells.length, 2);
    expect(table.rows[0].cells[0].isHeader, isTrue,
        reason: 'shd fill marks header');
    expect(table.rows[1].cells[1].runs.first is DocxText, isTrue);
    expect((table.rows[1].cells[1].runs.first as DocxText).text, 'B1');

    dir.deleteSync(recursive: true);
  });

  test('parseDocx throws on a non-docx file', () {
    final dir = Directory.systemTemp.createTempSync('docx_bad');
    final f = File('${dir.path}${Platform.pathSeparator}bad.docx');
    f.writeAsStringSync('not a zip');
    expect(() => parseDocx(f.path), throwsA(anything));
    dir.deleteSync(recursive: true);
  });
}
