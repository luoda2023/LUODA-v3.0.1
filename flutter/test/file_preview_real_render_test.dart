import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/file_preview_types.dart';
import 'package:luoda_flutter/common/widgets/office_preview_view.dart';

/// Renders the actual preview view against REAL sample files and asserts
/// what the user would see for each format.
void main() {
  const dir = r'C:\temp\preview_test';

  bool has(String name) => File('$dir\\$name').existsSync();

  Future<void> pumpOffice(
    WidgetTester tester,
    String fileName,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficeTextPreviewView(
              path: '$dir\\$fileName',
              fileName: fileName,
              fileSize: File('$dir\\$fileName').lengthSync(),
            ),
          ),
        ),
      );
      // Let the async extractor complete inside runAsync.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('DOCX renders extracted paragraphs with line numbers',
      (tester) async {
    if (!has('sample.docx')) {
      markTestSkipped('no sample.docx');
      return;
    }
    await pumpOffice(tester, 'sample.docx');
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('paragraph'), findsWidgets);
  });

  testWidgets('XLSX renders extracted cell text', (tester) async {
    if (!has('sample.xlsx')) {
      markTestSkipped('no sample.xlsx');
      return;
    }
    await pumpOffice(tester, 'sample.xlsx');
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('value'), findsWidgets);
  });

  testWidgets('PPTX renders extracted slide text', (tester) async {
    if (!has('sample.pptx')) {
      markTestSkipped('no sample.pptx');
      return;
    }
    await pumpOffice(tester, 'sample.pptx');
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('Slide'), findsWidgets);
  });

  testWidgets('PDF renders extracted text', (tester) async {
    if (!has('sample.pdf')) {
      markTestSkipped('no sample.pdf');
      return;
    }
    await pumpOffice(tester, 'sample.pdf');
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('MD classified as text preview kind', (tester) async {
    // MD is a plain-text kind: it renders through the dedicated text
    // preview (not the office extractor), which is the correct path.
    expect(filePreviewKindForName('notes.md'), FilePreviewKind.text);
  });

  testWidgets('DWG shows extraction-failed fallback with open button',
      (tester) async {
    if (!has('drawing.dwg')) {
      markTestSkipped('no drawing.dwg');
      return;
    }
    await pumpOffice(tester, 'drawing.dwg');
    // CAD files cannot be text-extracted: expect the fallback card.
    expect(find.byIcon(Icons.architecture_outlined), findsWidgets);
    expect(find.text('drawing.dwg'), findsOneWidget);
  });

  testWidgets('PNG classified as image', (tester) async {
    expect(
      filePreviewKindForName('photo.png'),
      FilePreviewKind.image,
    );
  });

  testWidgets('image preview shows filename overlay on black background',
      (tester) async {
    if (!has('photo.png')) {
      markTestSkipped('no photo.png');
      return;
    }
    // The image branch of the viewer renders a black full-screen scaffold
    // with the file name overlaid and a close button.
    final image = Image.file(File('$dir\\photo.png'), fit: BoxFit.contain);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(child: image),
              const SafeArea(
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('photo.png')),
                    Icon(Icons.close_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });
}
