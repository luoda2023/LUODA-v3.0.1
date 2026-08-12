// Temporary test: does the annotator respond to MOUSE drags (PC input)?

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/desktop/widgets/screenshot_annotator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Future<Uint8List> _makeTestImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _realDelay([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider(
      Directory.systemTemp.createTempSync('shot_mouse_').path,
    );
  });

  testWidgets('mouse drag selects a region', (tester) async {
    final bytes = await tester.runAsync(() => _makeTestImage(240, 160));
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showScreenshotAnnotator(
                    context,
                    imageBytes: bytes!,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.runAsync(() => _realDelay(120));
    await tester.pump(const Duration(milliseconds: 250));

    // Mouse primary-button drag across the image (image 240x160 centered in
    // 800x600 -> left=280, top=220).
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(320, 250));
    await tester.pump();
    await mouse.down(const Offset(320, 250));
    await tester.pump();
    await mouse.moveTo(const Offset(480, 350));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    final saveVisible = find.text('Save').evaluate().isNotEmpty;
    debugPrint('MOUSE SELECTION -> toolbar visible: $saveVisible');
    expect(saveVisible, isTrue,
        reason: 'Mouse drag should complete a selection and show the toolbar');
  });
}
