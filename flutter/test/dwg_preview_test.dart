import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/dwg_preview_view.dart';

/// Builds a minimal DWG-shaped file with an embedded BMP thumbnail so the
/// parser's sentinel + object-descriptor logic can be exercised.
Uint8List _buildDwgWithThumbnail({
  String version = 'AC1032',
  required int width,
  required int height,
}) {
  // A minimal 24-bit BMP core (no BITMAPFILEHEADER, as AutoCAD stores it).
  final rowSize = ((width * 3 + 3) ~/ 4) * 4;
  final pixelBytes = rowSize * height;
  final bmpCore = Uint8List(40 + pixelBytes);
  final view = ByteData.sublistView(bmpCore);
  view.setUint32(0, 40, Endian.little); // BITMAPINFOHEADER size
  view.setInt32(4, width, Endian.little);
  view.setInt32(8, height, Endian.little);
  view.setUint16(12, 1, Endian.little); // planes
  view.setUint16(14, 24, Endian.little); // bpp
  view.setUint32(16, 0, Endian.little); // BI_RGB
  view.setUint32(20, pixelBytes, Endian.little);
  // Fill with a green gradient so the image is not blank.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = 40 + y * rowSize + x * 3;
      bmpCore[i] = (x * 255 ~/ width); // B
      bmpCore[i + 1] = 120 + (y * 100 ~/ height); // G
      bmpCore[i + 2] = 30; // R
    }
  }

  // Assemble the DWG: header + sentinel + descriptors + payload.
  final sentinel = Uint8List.fromList(
      List<int>.generate(16, (i) => 0x5A + i)); // arbitrary 16 bytes
  const objectCount = 1;
  final bmpOffset = 13 + 4 + sentinel.length + 4 + 1 + objectCount * 9;

  final out = BytesBuilder();
  out.add(version.codeUnits);
  // Pad header to offset 13 then write sentinel pointer.
  while (out.length < 13) {
    out.addByte(0);
  }
  // Sentinel position is fixed by the layout below: offset 13 holds the
  // 4-byte pointer, then the 16-byte sentinel follows immediately.
  final sentinelPos = 13 + 4;
  out.add(Uint8List.sublistView(
    (ByteData(4)..setUint32(0, sentinelPos, Endian.little)),
  ));
  out.add(sentinel);
  out.add(Uint8List.sublistView(
    (ByteData(4)..setUint32(0, bmpCore.length, Endian.little)),
  ));
  out.addByte(objectCount);
  // Object descriptor: type 2 (BMP), offset, size.
  final desc = ByteData(9)
    ..setUint8(0, 2)
    ..setUint32(1, bmpOffset, Endian.little)
    ..setUint32(5, bmpCore.length, Endian.little);
  out.add(Uint8List.sublistView(desc));
  // Payload.
  out.add(bmpCore);
  // Inverted sentinel.
  out.add(Uint8List.fromList(sentinel.map((b) => 0xFF ^ b).toList()));
  return out.toBytes();
}

void main() {
  test('parses version header AC1032', () async {
    final dir = await Directory.systemTemp.createTemp('dwg_test');
    final file = File('${dir.path}/plan.dwg')
      ..writeAsBytesSync(_buildDwgWithThumbnail(width: 64, height: 48));
    addTearDown(() => dir.delete(recursive: true));

    final result = await parseForTest(file);
    expect(result.version, 'AC1032');
    expect(result.thumbnail, isNotNull);
  });

  test('extracts embedded BMP thumbnail with correct BMP header', () async {
    final dir = await Directory.systemTemp.createTemp('dwg_test');
    final file = File('${dir.path}/plan.dwg')
      ..writeAsBytesSync(_buildDwgWithThumbnail(width: 64, height: 48));
    addTearDown(() => dir.delete(recursive: true));

    final result = await parseForTest(file);
    final bmp = result.thumbnail!;
    // Rebuilt BMP must start with 'BM' and report a sane file size.
    expect(bmp[0], 0x42); // 'B'
    expect(bmp[1], 0x4D); // 'M'
    final view = ByteData.sublistView(bmp);
    expect(view.getUint32(2, Endian.little), bmp.length);
    expect(view.getUint32(10, Endian.little), 54); // data offset
  });

  test('returns version without thumbnail for empty DWG', () async {
    final dir = await Directory.systemTemp.createTemp('dwg_test');
    final file = File('${dir.path}/empty.dwg')
      ..writeAsBytesSync(Uint8List.fromList('AC1015'.codeUnits));
    addTearDown(() => dir.delete(recursive: true));

    final result = await parseForTest(file);
    expect(result.version, 'AC1015');
    expect(result.thumbnail, isNull);
  });
}
