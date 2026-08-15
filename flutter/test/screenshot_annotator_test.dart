// Widget test for the PC screenshot annotator: selecting a region with a
// drag, drawing marks, and composing a cropped PNG of the expected size.
//
// Engine async calls (picture.toImage / decodeImageFromList) only complete
// inside tester.runAsync(), so every real-async step is wrapped there.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/desktop/widgets/screenshot_annotator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// In-memory path_provider so compose can write the PNG during tests.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

late String _fakeSupportRoot;

Future<Uint8List> _makeTestImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  canvas.drawCircle(
    const Offset(120, 90),
    40,
    Paint()..color = const Color(0xFFFFAA33),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Waits a short real-async window for engine callbacks (decode/compose).
Future<void> _realDelay([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() {
    _fakeSupportRoot = Directory.systemTemp
        .createTempSync('shot_test_')
        .path;
    PathProviderPlatform.instance = _FakePathProvider(_fakeSupportRoot);
  });

  tearDown(() {
    try {
      Directory(_fakeSupportRoot).deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('annotator selects a region, draws, and saves a cropped PNG',
      (tester) async {
    final bytes =
        await tester.runAsync(() => _makeTestImage(240, 160));
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
    // The dialog's initState registers decodeImageFromList; that engine
    // callback only completes inside runAsync.
    await tester.runAsync(() => _realDelay(120));
    await tester.pump(const Duration(milliseconds: 250));

    // Image is 240x160, test surface 800x600 -> scale 1, centered at
    // left=280, top=220. Drag a selection from (40,30) to (200,130) image px.
    final gesture = await tester.startGesture(const Offset(320, 250));
    await gesture.moveTo(const Offset(480, 350));
    await gesture.up();
    await tester.pump();

    // Toolbar (annotate phase) appears after a selection.
    expect(find.text('Send'), findsOneWidget);

    // Switch to the rectangle tool and draw inside the selection.
    await tester.tap(find.byIcon(Icons.crop_square_rounded));
    await tester.pump();
    final drawStart = await tester.startGesture(const Offset(340, 270));
    await drawStart.moveTo(const Offset(420, 330));
    await drawStart.up();
    await tester.pump();

    // Save -> composed image is selection-sized (160x100).
    await tester.runAsync(() async {
      await tester.tap(find.text('Send'));
      for (var i = 0; i < 40 && result == null; i++) {
        await _realDelay(50);
      }
    });
    await tester.pump();

    expect(result, isNotNull);
    final file = File(result!);
    expect(await tester.runAsync(file.exists), isTrue);
    final savedBytes = await tester.runAsync(file.readAsBytes);
    final decoded = await tester.runAsync(
      () => decodeImageFromList(savedBytes!),
    );
    expect(decoded!.width, 160);
    expect(decoded.height, 100);
    decoded.dispose();
    await tester.runAsync(file.delete);
  });

  testWidgets('annotator text tool places a label and saves', (tester) async {
    final bytes =
        await tester.runAsync(() => _makeTestImage(240, 160));
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

    // Select the whole-ish region.
    final gesture = await tester.startGesture(const Offset(300, 240));
    await gesture.moveTo(const Offset(500, 380));
    await gesture.up();
    await tester.pump();

    // Text tool: tap inside the selection, type a label, confirm.
    await tester.tap(find.byIcon(Icons.text_fields_rounded));
    await tester.pump();
    final tapPos = await tester.startGesture(const Offset(360, 300));
    await tapPos.up();
    await tester.pump();

    // 微信式图板内输入：点击图板后在原地出现输入框，直接输入文字，
    // 回车提交（无弹出对话框/完成按钮）。
    expect(find.byKey(const ValueKey<String>('shot-text-field')),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey<String>('shot-text-field')), 'Hello 标注');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Save and confirm the composed file exists.
    await tester.runAsync(() async {
      await tester.tap(find.text('Send'));
      for (var i = 0; i < 40 && result == null; i++) {
        await _realDelay(50);
      }
    });
    await tester.pump();
    expect(result, isNotNull);
    final file = File(result!);
    expect(await tester.runAsync(file.exists), isTrue);
    await tester.runAsync(file.delete);
  });

  testWidgets('annotator ellipse/mosaic/highlight tools draw and save',
      (tester) async {
    final bytes =
        await tester.runAsync(() => _makeTestImage(240, 160));
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
    // Give the async RGBA extraction (mosaic sampling) time to finish.
    await tester.runAsync(() => _realDelay(150));
    await tester.pump(const Duration(milliseconds: 250));

    // Select the whole-ish region.
    final gesture = await tester.startGesture(const Offset(300, 240));
    await gesture.moveTo(const Offset(500, 380));
    await gesture.up();
    await tester.pump();

    // 粗细滑块存在（工具条右下角：粗/细图标 + Slider）。
    expect(find.byIcon(Icons.add_rounded), findsWidgets);
    expect(find.byType(Slider), findsOneWidget);

    // Ellipse tool: drag a circle.
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pump();
    var drawStart = await tester.startGesture(const Offset(340, 270));
    await drawStart.moveTo(const Offset(420, 330));
    await drawStart.up();
    await tester.pump();

    // Mosaic tool: stroke across the middle.
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    drawStart = await tester.startGesture(const Offset(360, 300));
    await drawStart.moveTo(const Offset(440, 300));
    await drawStart.up();
    await tester.pump();

    // Highlight tool: stroke.
    expect(find.byIcon(Icons.border_color_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.border_color_rounded));
    await tester.pump();
    drawStart = await tester.startGesture(const Offset(340, 340));
    await drawStart.moveTo(const Offset(460, 340));
    await drawStart.up();
    await tester.pump();

    // Save -> composed file exists.
    await tester.runAsync(() async {
      await tester.tap(find.text('Send'));
      for (var i = 0; i < 40 && result == null; i++) {
        await _realDelay(50);
      }
    });
    await tester.pump();
    expect(result, isNotNull);
    final file = File(result!);
    expect(await tester.runAsync(file.exists), isTrue);
    await tester.runAsync(file.delete);
  });

  testWidgets('annotator cancel returns null', (tester) async {
    final bytes =
        await tester.runAsync(() => _makeTestImage(120, 80));
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

    // Cancel immediately (before selection) -> null. The top-right close
    // button is always visible, even during the selection phase.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(result, isNull);
  });

  testWidgets('annotator preselected region starts in annotate mode',
      (tester) async {
    // 新 Windows 流程：传入的已是框选好的区域图，直接进入标注阶段。
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
                    preselected: true,
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

    // 无需拖拽框选：工具条立即可见，提示条不显示。
    expect(find.byIcon(Icons.text_fields_rounded), findsOneWidget);
    expect(find.text('Drag to select area, hold Ctrl to pick a window'),
        findsNothing);

    // 画一个矩形标注。
    await tester.tap(find.byIcon(Icons.crop_square_rounded));
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(320, 260));
    await gesture.moveTo(const Offset(460, 350));
    await gesture.up();
    await tester.pump();

    // 发送：确认合成 PNG。
    await tester.runAsync(() async {
      await tester.tap(find.text('Send'));
      for (var i = 0; i < 40 && result == null; i++) {
        await _realDelay(50);
      }
    });
    await tester.pump();
    expect(result, isNotNull);
    final file = File(result!);
    expect(await tester.runAsync(file.exists), isTrue);
    await tester.runAsync(file.delete);
  });
}
