import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:open_filex/open_filex.dart';

/// Pure-Dart DWG preview viewer (no external CAD software required).
///
/// DWG is Autodesk's proprietary format; a full geometry parser is out of
/// scope, but two pieces of information are reliably recoverable:
///  1. The version header (first 6 bytes, e.g. "AC1032" = AutoCAD 2018).
///  2. The embedded preview thumbnail. AutoCAD writes a thumbnail section at
///     save time: file offset 13 (0-based) holds a long pointing at a
///     16-byte sentinel; after it come the thumbnail-data size, the object
///     count, then per-object descriptors (type 1 = title, 2 = BMP, 3 = WMF)
///     and the actual payload. The BMP payload is a full bitmap minus the
///     14-byte BITMAPFILEHEADER.
///
/// When no thumbnail exists (some third-party writers omit it) we fall back
/// to a metadata card (version / size / drawing info) plus an
/// "open with system app" button.
class DwgPreviewView extends StatefulWidget {
  const DwgPreviewView({
    super.key,
    required this.path,
    required this.fileName,
    required this.fileSize,
  });

  final String path;
  final String fileName;
  final int fileSize;

  @override
  State<DwgPreviewView> createState() => _DwgPreviewViewState();
}

class _DwgPreviewViewState extends State<DwgPreviewView> {
  late final Future<DwgPreviewParseResult> _parseFuture;

  @override
  void initState() {
    super.initState();
    _parseFuture = _parseDwg(File(widget.path));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<DwgPreviewParseResult>(
      future: _parseFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        final thumb = result.thumbnail;
        if (thumb != null) {
          return _buildThumbnailView(dark, thumb, result.version);
        }
        return _buildInfoCard(dark, result);
      },
    );
  }

  Widget _buildThumbnailView(bool dark, Uint8List bmpBytes, String version) {
    return Container(
      color: dark ? const Color(0xFF0E1013) : const Color(0xFF101418),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 12,
              boundaryMargin: const EdgeInsets.all(120),
              child: Image.memory(
                bmpBytes,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          // 顶部信息条：文件名 + 版本。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withOpacity(0.55),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.architecture_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _dwgVersionLabel(version),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 底部操作条：用系统应用打开。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      translate('Embedded drawing preview'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF07C160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    onPressed: () => OpenFilex.open(widget.path),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(
                      translate('Open with system app'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool dark, DwgPreviewParseResult result) {
    final foreground =
        dark ? Colors.white70 : const Color(0xFF3A4048);
    final labelColor = dark ? Colors.white38 : const Color(0xFF8A9199);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFB3541E).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.architecture_rounded,
                    size: 36, color: Color(0xFFB3541E)),
              ),
              const SizedBox(height: 16),
              Text(
                widget.fileName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatFileSize(widget.fileSize),
                style: TextStyle(fontSize: 13, color: labelColor),
              ),
              const SizedBox(height: 20),
              _infoRow(labelColor, foreground, translate('Drawing version'),
                  _dwgVersionLabel(result.version)),
              const SizedBox(height: 8),
              _infoRow(labelColor, foreground, translate('File format'),
                  'DWG · ${result.version}'),
              const SizedBox(height: 20),
              Text(
                translate(
                    'No embedded preview image. Open with a CAD application '
                    'to view the drawing.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                ),
                onPressed: () => OpenFilex.open(widget.path),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(translate('Open with system app')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(Color labelColor, Color valueColor, String label,
      String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: labelColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 13, color: labelColor),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Public parse entry (used by tests and the preview page).
class DwgPreviewParseResult {
  DwgPreviewParseResult({required this.version, this.thumbnail});

  final String version;
  final Uint8List? thumbnail;
}

/// Exposed for tests: parses a DWG file into version + thumbnail.
Future<DwgPreviewParseResult> parseForTest(File file) async {
  return _parseDwg(file);
}

/// Exposed for tests: parses DWG bytes (no file I/O) into version + thumbnail.
DwgPreviewParseResult parseDwgBytesForTest(Uint8List bytes) {
  final version = bytes.length >= 6
      ? String.fromCharCodes(bytes.sublist(0, 6))
      : 'DWG';
  return DwgPreviewParseResult(version: version, thumbnail: _extractThumbnail(bytes));
}

Future<DwgPreviewParseResult> _parseDwg(File file) async {
  try {
    final bytes = await file.readAsBytes();
    return parseDwgBytesForTest(bytes);
  } catch (_) {
    return DwgPreviewParseResult(version: 'DWG');
  }
}

/// Returns a full BMP (with BITMAPFILEHEADER) embedded in the DWG, or null.
Uint8List? _extractThumbnail(Uint8List bytes) {
  if (bytes.length < 128) return null;
  // File offset 13 (0-based) holds a long pointing at the thumbnail sentinel.
  int sentinelPos;
  try {
    final ByteData view = ByteData.sublistView(bytes);
    sentinelPos = view.getUint32(13, Endian.little);
  } catch (_) {
    return null;
  }
  if (sentinelPos <= 0 || sentinelPos + 24 >= bytes.length) return null;
  // After the 16-byte sentinel: 4-byte data size, 1-byte object count.
  int p = sentinelPos + 16;
  try {
    final ByteData view = ByteData.sublistView(bytes);
    // Skip the 4-byte data-size field, read the object count.
    final objectCount = bytes[p + 4];
    p += 5;
    if (objectCount == 0 || objectCount > 8) return null;
    if (p + objectCount * 9 > bytes.length) return null;
    // Parse object descriptors: type(1) + offset(4) + size(4).
    int? bmpOffset;
    int? bmpSize;
    for (var i = 0; i < objectCount; i++) {
      final type = bytes[p + i * 9];
      final offset = view.getUint32(p + i * 9 + 1, Endian.little);
      final size = view.getUint32(p + i * 9 + 5, Endian.little);
      if (type == 2 && bmpOffset == null) {
        bmpOffset = offset;
        bmpSize = size;
      }
    }
    if (bmpOffset == null ||
        bmpSize == null ||
        bmpOffset <= 0 ||
        bmpSize <= 0 ||
        bmpOffset + bmpSize > bytes.length) {
      return null;
    }
    final bmpCore = bytes.sublist(bmpOffset, bmpOffset + bmpSize);
    if (bmpCore.length < 40) return null;
    // Rebuild the full BMP by prepending BITMAPFILEHEADER.
    final fileSize = 14 + bmpCore.length;
    final out = Uint8List(fileSize);
    final ByteData outView = ByteData.sublistView(out);
    outView.setUint32(0, 0x4D42, Endian.little); // 'BM'
    outView.setUint32(2, fileSize, Endian.little);
    outView.setUint32(10, 14 + 40, Endian.little);
    out.setRange(14, fileSize, bmpCore);
    return out;
  } catch (_) {
    return null;
  }
}

String _formatFileSize(int fileSize) {
  if (fileSize < 1024) return '$fileSize B';
  if (fileSize < 1024 * 1024) {
    return '${(fileSize / 1024).toStringAsFixed(1)} KB';
  }
  return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _dwgVersionLabel(String version) {
  return switch (version) {
    'AC1009' => 'AutoCAD R12',
    'AC1012' => 'AutoCAD R13',
    'AC1014' => 'AutoCAD R14',
    'AC1015' => 'AutoCAD 2000',
    'AC1018' => 'AutoCAD 2004',
    'AC1021' => 'AutoCAD 2007',
    'AC1024' => 'AutoCAD 2010',
    'AC1027' => 'AutoCAD 2013',
    'AC1032' => 'AutoCAD 2018',
    _ => version,
  };
}
