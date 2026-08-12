import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/file_preview_types.dart';
import 'package:luoda_flutter/common/widgets/office_preview_view.dart';

/// End-to-end check: the actual preview extractor must handle real
/// DOCX / XLSX / PPTX / PDF / MD files produced by standard tools.
void main() {
  const dir = r'C:\temp\preview_test';

  test('DOCX real file extracts paragraphs', () async {
    final path = '$dir\\sample.docx';
    expect(File(path).existsSync(), isTrue);
    final text = await extractOfficePreviewText(path, 'sample.docx');
    expect(text, contains('paragraph one'));
    expect(text, contains('Second paragraph'));
  }, skip: !File('$dir\\sample.docx').existsSync());

  test('XLSX real file extracts shared strings and cells', () async {
    final path = '$dir\\sample.xlsx';
    final text = await extractOfficePreviewText(path, 'sample.xlsx');
    expect(text, contains('Alpha shared string'));
    expect(text, contains('Beta value'));
    expect(text, contains('42'));
  }, skip: !File('$dir\\sample.xlsx').existsSync());

  test('PPTX real file extracts slide text', () async {
    final path = '$dir\\sample.pptx';
    final text = await extractOfficePreviewText(path, 'sample.pptx');
    expect(text, contains('Slide title text'));
    expect(text, contains('Slide body content'));
  }, skip: !File('$dir\\sample.pptx').existsSync());

  test('PDF real file extracts text from flate streams', () async {
    final path = '$dir\\sample.pdf';
    final text = await extractOfficePreviewText(path, 'sample.pdf');
    expect(text, contains('LUODA PDF preview works'));
  }, skip: !File('$dir\\sample.pdf').existsSync());

  test('MD and PNG classified correctly', () {
    expect(filePreviewKindForName('notes.md'), FilePreviewKind.text);
    expect(filePreviewKindForName('photo.png'), FilePreviewKind.image);
    expect(filePreviewKindForName('drawing.dwg'), FilePreviewKind.cad);
  });

  test('kind mapping for requested formats', () {
    expect(filePreviewKindForName('report.docx'), FilePreviewKind.document);
    expect(filePreviewKindForName('data.xlsx'), FilePreviewKind.spreadsheet);
    expect(filePreviewKindForName('deck.pptx'), FilePreviewKind.presentation);
    expect(filePreviewKindForName('doc.pdf'), FilePreviewKind.pdf);
    expect(filePreviewKindForName('notes.md'), FilePreviewKind.text);
    expect(filePreviewKindForName('photo.jpg'), FilePreviewKind.image);
  });
}
