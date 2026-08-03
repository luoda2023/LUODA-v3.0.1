import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/file_preview_types.dart';

void main() {
  test('file preview classification is case insensitive', () {
    expect(filePreviewKindForName('photo.JPEG'), FilePreviewKind.image);
    expect(filePreviewKindForName('movie.MP4'), FilePreviewKind.video);
    expect(filePreviewKindForName('voice.m4a'), FilePreviewKind.audio);
    expect(filePreviewKindForName('manual.PDF'), FilePreviewKind.pdf);
    expect(filePreviewKindForName('report.docx'), FilePreviewKind.document);
    expect(filePreviewKindForName('table.xlsx'), FilePreviewKind.spreadsheet);
    expect(
      filePreviewKindForName('slides.pptx'),
      FilePreviewKind.presentation,
    );
    expect(filePreviewKindForName('backup.7z'), FilePreviewKind.archive);
    expect(filePreviewKindForName('setup.msi'), FilePreviewKind.executable);
    expect(filePreviewKindForName('notes.txt'), FilePreviewKind.text);
    expect(filePreviewKindForName('settings.yaml'), FilePreviewKind.code);
    expect(filePreviewKindForName('unknown.bin'), FilePreviewKind.other);
  });

  test('file preview metadata stays compact and format specific', () {
    expect(fileExtensionLabel('archive.longextension'), 'LONG');
    expect(fileExtensionLabel('README'), 'FILE');
    expect(filePreviewIcon('photo.png'), Icons.image_outlined);
    expect(filePreviewIcon('manual.pdf'), Icons.picture_as_pdf_outlined);
    expect(filePreviewIcon('table.csv'), Icons.table_chart_outlined);
    expect(filePreviewIcon('backup.zip'), Icons.folder_zip_outlined);
    expect(filePreviewIcon('unknown.bin'), Icons.insert_drive_file_outlined);
  });
}
