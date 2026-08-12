import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/widgets/file_preview_types.dart';

/// 全量覆盖用户要求的常见文件格式：
/// DOCX / EXCEL(XLS,XLSX) / PPT / PDF / DWG / MD / 所有图片格式，
/// 以及发送路径的文件大小保护逻辑。
void main() {
  test('covers every user-required document format', () {
    // DOCX 与旧版 Word
    expect(filePreviewKindForName('a.docx'), FilePreviewKind.document);
    expect(filePreviewKindForName('a.doc'), FilePreviewKind.document);
    expect(filePreviewKindForName('a.odt'), FilePreviewKind.document);
    expect(filePreviewKindForName('a.rtf'), FilePreviewKind.document);
    // Excel
    expect(filePreviewKindForName('a.xlsx'), FilePreviewKind.spreadsheet);
    expect(filePreviewKindForName('a.xls'), FilePreviewKind.spreadsheet);
    expect(filePreviewKindForName('a.csv'), FilePreviewKind.spreadsheet);
    // PPT
    expect(filePreviewKindForName('a.pptx'), FilePreviewKind.presentation);
    expect(filePreviewKindForName('a.ppt'), FilePreviewKind.presentation);
    // PDF
    expect(filePreviewKindForName('a.pdf'), FilePreviewKind.pdf);
    // DWG 系列
    expect(filePreviewKindForName('a.dwg'), FilePreviewKind.cad);
    expect(filePreviewKindForName('a.dxf'), FilePreviewKind.cad);
    expect(filePreviewKindForName('a.dgn'), FilePreviewKind.cad);
    // Markdown
    expect(filePreviewKindForName('a.md'), FilePreviewKind.text);
    expect(filePreviewKindForName('a.markdown'), FilePreviewKind.text);
  });

  test('covers every common image format', () {
    for (final ext in <String>[
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'heic',
      'heif',
    ]) {
      expect(
        filePreviewKindForName('photo.$ext'),
        FilePreviewKind.image,
        reason: '$ext should preview as image',
      );
    }
  });

  test('handles edge-case file names safely', () {
    expect(filePreviewKindForName(''), FilePreviewKind.other);
    expect(filePreviewKindForName('README'), FilePreviewKind.other);
    expect(filePreviewKindForName('.gitignore'), FilePreviewKind.other);
    expect(filePreviewKindForName('archive.'), FilePreviewKind.other);
    // 隐藏扩展名不误判
    expect(filePreviewKindForName('a.pdf '), FilePreviewKind.other);
    // 多级扩展名取最后一个
    expect(filePreviewKindForName('archive.tar.gz'), FilePreviewKind.archive);
  });

  test('small files are inlined, large files go through transfer', () {
    // 内联阈值：<= 5 MiB 走消息内联（图片与小文档），更大走直连文件传输。
    expect(canInlineDirectChatFile(1024 * 1024), isTrue);
    expect(canInlineDirectChatFile(5 * 1024 * 1024), isTrue);
    expect(canInlineDirectChatFile(5 * 1024 * 1024 + 1), isFalse);
    expect(canInlineDirectChatFile(500 * 1024 * 1024), isFalse);
    expect(canInlineDirectChatFile(0), isFalse);
  });

  test('file preview icons match each format family', () {
    expect(filePreviewIcon('a.docx'), Icons.description_outlined);
    expect(filePreviewIcon('a.xlsx'), Icons.table_chart_outlined);
    expect(filePreviewIcon('a.pptx'), Icons.slideshow_outlined);
    expect(filePreviewIcon('a.pdf'), Icons.picture_as_pdf_outlined);
    expect(filePreviewIcon('a.dwg'), Icons.architecture_outlined);
    expect(filePreviewIcon('a.md'), Icons.article_outlined);
    expect(filePreviewIcon('a.png'), Icons.image_outlined);
  });
}
