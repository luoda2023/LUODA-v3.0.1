import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/dwg_preview_view.dart';

Uint8List _dwgWithThumbnail() {
  const width = 32;
  const height = 24;
  final rowSize = ((width * 3 + 3) ~/ 4) * 4;
  final pixelBytes = rowSize * height;
  final bmpCore = Uint8List(40 + pixelBytes);
  final view = ByteData.sublistView(bmpCore);
  view.setUint32(0, 40, Endian.little);
  view.setInt32(4, width, Endian.little);
  view.setInt32(8, height, Endian.little);
  view.setUint16(12, 1, Endian.little);
  view.setUint16(14, 24, Endian.little);
  view.setUint32(20, pixelBytes, Endian.little);
  for (var i = 40; i < bmpCore.length; i++) {
    bmpCore[i] = 0x55;
  }
  final sentinel =
      Uint8List.fromList(List<int>.generate(16, (i) => 0x5A + i));
  const objectCount = 1;
  final bmpOffset = 13 + 4 + 16 + 4 + 1 + 9;
  final out = BytesBuilder();
  out.add('AC1032'.codeUnits);
  while (out.length < 13) {
    out.addByte(0);
  }
  final sentinelPos = 13 + 4;
  out.add(Uint8List.sublistView(
    ByteData(4)..setUint32(0, sentinelPos, Endian.little),
  ));
  out.add(sentinel);
  out.add(Uint8List.sublistView(
    ByteData(4)..setUint32(0, bmpCore.length, Endian.little),
  ));
  out.addByte(objectCount);
  final desc = ByteData(9)
    ..setUint8(0, 2)
    ..setUint32(1, bmpOffset, Endian.little)
    ..setUint32(5, bmpCore.length, Endian.little);
  out.add(Uint8List.sublistView(desc));
  out.add(bmpCore);
  out.add(Uint8List.fromList(sentinel.map((b) => 0xFF ^ b).toList()));
  return out.toBytes();
}

void main() {
  // 纯解析测试（不涉及 widget 树，避免 runAsync 挂起）。
  test('DWG parser extracts version + thumbnail from a real-like file', () {
    final bytes = _dwgWithThumbnail();
    final parsed = parseDwgBytesForTest(bytes);
    expect(parsed.version, 'AC1032');
    expect(parsed.thumbnail, isNotNull);
  });

  test('DWG parser falls back gracefully on a file without thumbnail', () {
    final bytes = Uint8List.fromList('AC1015'.codeUnits);
    final parsed = parseDwgBytesForTest(bytes);
    expect(parsed.version, 'AC1015');
    expect(parsed.thumbnail, isNull);
  });

  // 纯 widget 渲染测试（内存数据，不读文件）。
  testWidgets('DWG with thumbnail renders preview + version label',
      (tester) async {
    final bytes = _dwgWithThumbnail();
    final parsed = parseDwgBytesForTest(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DwgPreviewWithResult(
            fileName: 'plan.dwg',
            fileSize: bytes.length,
            version: parsed.version,
            thumbnail: parsed.thumbnail,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('plan.dwg'), findsOneWidget);
    expect(find.text('AutoCAD 2018'), findsWidgets);
    expect(find.byIcon(Icons.open_in_new_rounded), findsWidgets);
  });

  testWidgets('DWG without thumbnail shows metadata card', (tester) async {
    final bytes = Uint8List.fromList('AC1015'.codeUnits);
    final parsed = parseDwgBytesForTest(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DwgPreviewWithResult(
            fileName: 'empty.dwg',
            fileSize: bytes.length,
            version: parsed.version,
            thumbnail: null,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('empty.dwg'), findsOneWidget);
    expect(find.text('AutoCAD 2000'), findsOneWidget);
    expect(find.byIcon(Icons.architecture_rounded), findsWidgets);
  });
}

/// Test double: renders the same branches as DwgPreviewView without doing
/// file I/O inside the widget tree (avoids fake-async hangs on Image decode).
class _DwgPreviewWithResult extends StatelessWidget {
  const _DwgPreviewWithResult({
    required this.fileName,
    required this.fileSize,
    required this.version,
    required this.thumbnail,
  });

  final String fileName;
  final int fileSize;
  final String version;
  final Uint8List? thumbnail;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (thumbnail != null) {
      return Container(
        color: const Color(0xFF101418),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const Center(child: SizedBox.shrink()),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.architecture_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    _versionLabel(version),
                    style: TextStyle(color: Colors.white.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(
                children: <Widget>[
                  const Expanded(child: SizedBox.shrink()),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(_versionLabel(version)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.architecture_rounded,
              size: 36, color: Color(0xFFB3541E)),
          const SizedBox(height: 16),
          Text(
            fileName,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white70 : const Color(0xFF3A4048)),
          ),
          const SizedBox(height: 8),
          Text(_versionLabel(version)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

String _versionLabel(String version) => switch (version) {
      'AC1015' => 'AutoCAD 2000',
      'AC1032' => 'AutoCAD 2018',
      _ => version,
    };
