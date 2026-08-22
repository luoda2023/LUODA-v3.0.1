import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:luoda_flutter/common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:luoda_flutter/utils/multi_window_manager.dart';

import 'docx_native_preview.dart';
import 'dwg_preview_view.dart';
import 'system_share.dart';
import 'file_preview_types.dart';

import 'office_preview_view.dart';
import 'pdf_native_preview.dart';


String formatFileSize(int fileSize) {
  if (fileSize < 1024) return '$fileSize B';
  if (fileSize < 1024 * 1024) {
    return '${(fileSize / 1024).toStringAsFixed(1)} KB';
  }
  return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Best-effort resolution of an incoming file's on-disk path by matching the
/// file name (and optionally size) inside well-known download/storage folders.
/// Files larger than the inline limit arrive through the transfer subsystem
/// and land in the peer's home directory, so that location is searched too.
Future<String?> resolveReceivedFilePath(String fileName, int fileSize) async {
  if (fileName.isEmpty) return null;
  final dirs = <Directory>[];
  // The app's own persistent store for clipboard-pasted chat images.
  // Must be searched FIRST: after a restart the in-memory path cache is
  // gone and this is the only stable location for those files.
  try {
    final support = await getApplicationSupportDirectory();
    final chatImages = Directory(
      '${support.path}${Platform.pathSeparator}chat_images',
    );
    if (await chatImages.exists()) dirs.add(chatImages);
  } catch (_) {}
  try {
    dirs.add(await getTemporaryDirectory());
  } catch (_) {}
  try {
    dirs.add(await getApplicationDocumentsDirectory());
  } catch (_) {}
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) dirs.add(downloads);
  } catch (_) {}
  try {
    final ext = await ExternalPath.getExternalStorageDirectories();
    for (final directory in ext) {
      dirs.add(Directory(directory));
    }
  } catch (_) {}
  // Transfer-subsystem files land in the peer home dir: `~` on desktop,
  // external storage root on Android (already covered above), and the
  // internal data dir on iOS (covered by getApplicationDocumentsDirectory).
  try {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      final homeDir = Directory(home);
      if (!dirs.contains(homeDir)) dirs.add(homeDir);
    }
  } catch (_) {}
  // The "DotChat" folder used by the Rust core as the Android receive root.
  try {
    final ext = await ExternalPath.getExternalStorageDirectories();
    for (final directory in ext) {
      final dotChat = Directory('$directory${Platform.pathSeparator}DotChat');
      if (await dotChat.exists() && !dirs.contains(dotChat)) dirs.add(dotChat);
    }
  } catch (_) {}

  String? fallback;
  DateTime? fallbackTime;
  for (final dir in dirs) {
    if (!await dir.exists()) continue;
    final candidates = <File>[];
    try {
      for (final ent in dir.listSync(followLinks: false)) {
        if (ent is File && p.basename(ent.path) == fileName) {
          candidates.add(ent);
        } else if (ent is Directory) {
          try {
            for (final sub in ent.listSync(followLinks: false)) {
              if (sub is File && p.basename(sub.path) == fileName) {
                candidates.add(sub);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    for (final f in candidates) {
      FileStat stat;
      try {
        stat = f.statSync();
      } catch (_) {
        continue;
      }
      if (fileSize > 0 && stat.size == fileSize) return f.path;
      final t = stat.modified;
      if (fallbackTime == null || t.isAfter(fallbackTime)) {
        fallbackTime = t;
        fallback = f.path;
      }
    }
  }
  return fallback;
}

/// Open file preview in an independent OS window (desktop) or in-app page
/// (mobile). Supports image zoom, audio playback, text display, and
/// prev/next navigation via [siblingPaths].
Future<void> showFileViewer(
BuildContext context, {
required String fileName,
required int fileSize,
String? localPath,
List<String>? siblingPaths,
}) async {
String? path = localPath?.isNotEmpty == true ? localPath : null;
if (path == null || !(await File(path).exists())) {
path = await resolveReceivedFilePath(fileName, fileSize);
}
final resolved = path != null && await File(path).exists();

// Desktop: open as a real independent OS window via desktop_multi_window.
// The FilePreviewPage (desktop/pages/file_preview_page.dart) renders a
// custom title bar with drag-to-move, minimize / maximize / close buttons.
// Mobile: open in-app full-screen page.
if (isDesktop) {
final filePath = resolved ? path : '';
final msg = jsonEncode({
'type': WindowType.FilePreview.index,
'file_path': filePath,
'file_name': fileName,
'file_size': fileSize,
if (siblingPaths != null) 'sibling_paths': siblingPaths,
});
final windowController = await DesktopMultiWindow.createWindow(msg);
if (isWindows) {
// White init background: if the child engine is slow to paint its first
// frame the user sees a neutral white, never an alarming black window.
windowController.setInitBackgroundColor(Colors.white);
}
windowController
..setFrame(
const Offset(0, 0) & const Size(900, 640))
..center()
..setTitle(fileName);
// Do NOT call show() here. Exactly like the session windows
// (LUODAMultiWindowManager.newSessionWindow), the child window shows
// ITSELF from main.dart's runMultiWindow once its first frame is ready.
// Parent-side show() exposes the window before the child engine has
// created its surface, which intermittently leaves the window stuck on
// the raw background (the all-black / all-white preview bug).
} else {
await Navigator.of(context).push(
MaterialPageRoute<void>(
fullscreenDialog: true,
builder: (_) => _FileViewerPage(
fileName: fileName,
fileSize: fileSize,
path: resolved ? path : null,
siblingPaths: siblingPaths,
),
),
);
}
}

class _FileViewerPage extends StatefulWidget {
  const _FileViewerPage({
    required this.fileName,
    required this.fileSize,
    this.path,
    this.siblingPaths,
  });

  final String fileName;
  final int fileSize;
  final String? path;
  final List<String>? siblingPaths;

  @override
  State<_FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<_FileViewerPage> {
  late final List<String> _paths;
  late int _currentIndex;
  final TransformationController _transformController = TransformationController();
  int _rotationQuarterTurns = 0;

  @override
  void initState() {
    super.initState();
    _paths = <String>{
      ...?widget.siblingPaths?.where((p) => p.trim().isNotEmpty),
      if (widget.path != null && widget.path!.trim().isNotEmpty) widget.path!,
    }.toList(growable: true);
    if (_paths.isEmpty && widget.path != null) _paths.add(widget.path!);
    _currentIndex = _paths.indexOf(widget.path ?? '');
    if (_currentIndex < 0) _currentIndex = 0;
  }

  Future<void> _closePreview() async {
    if (mounted) Navigator.of(context).pop();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      unawaited(_closePreview());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goPrevious();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _goNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
      _zoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _resetTransform();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.25).clamp(0.1, 10.0);
    _transformController.value = Matrix4.identity()..scale(newScale);
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.25).clamp(0.1, 10.0);
    _transformController.value = Matrix4.identity()..scale(newScale);
  }
  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  String get _fileName =>
      _paths.isNotEmpty ? p.basename(_paths[_currentIndex]) : widget.fileName;
  String? get _path =>
      _paths.isNotEmpty ? _paths[_currentIndex] : widget.path;
  bool get _hasMultiple => _paths.length > 1;

  void _goPrevious() {
    if (_currentIndex <= 0) return;
    setState(() {
      _currentIndex -= 1;
      _rotationQuarterTurns = 0;
      _transformController.value = Matrix4.identity();
    });
  }

  void _goNext() {
    if (_currentIndex >= _paths.length - 1) return;
    setState(() {
      _currentIndex += 1;
      _rotationQuarterTurns = 0;
      _transformController.value = Matrix4.identity();
    });
  }

  void _rotate() {
    setState(() => _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4);
  }

  void _resetTransform() {
    setState(() {
      _rotationQuarterTurns = 0;
      _transformController.value = Matrix4.identity();
    });
  }

  /// Windows Photos style top toolbar for image preview.
  Widget _buildImageToolbar(String path) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          _toolbarBtn(Icons.push_pin_outlined, translate('Pin'), () {}),
          if (_hasMultiple) ...<Widget>[
            _toolbarBtn(Icons.chevron_left, translate('Previous'),
                _currentIndex > 0 ? _goPrevious : null),
            _toolbarBtn(Icons.chevron_right, translate('Next'),
                _currentIndex < _paths.length - 1 ? _goNext : null),
          ],
          const SizedBox(width: 4),
          _toolbarBtn(Icons.add_circle_outline, translate('Zoom in'),
              _zoomIn),
          _toolbarBtn(Icons.remove_circle_outline, translate('Zoom out'),
              _zoomOut),
          _toolbarBtn(Icons.center_focus_strong_rounded, translate('Fit to window'),
              _resetTransform),
          const SizedBox(width: 4),
          _toolbarBtn(Icons.rotate_right_rounded, translate('Rotate right'), _rotate),
          _toolbarBtn(Icons.edit_outlined, translate('Edit'), () {}),
          _toolbarBtn(Icons.download_rounded, translate('Save as'), () {}),
          _toolbarBtn(Icons.more_horiz_rounded, translate('More'), () {}),
          const Spacer(),
          IconButton(
            tooltip: translate('Open with system app'),
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            color: const Color(0xFF333333),
            onPressed: () => OpenFilex.open(path),
          ),
          IconButton(
            tooltip: translate('Close'),
            icon: const Icon(Icons.close_rounded, size: 22),
            color: const Color(0xFF333333),
            onPressed: () => unawaited(_closePreview()),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 36, height: 36,
          child: Icon(icon, size: 20, color: const Color(0xFF333333)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final kind = filePreviewKindForName(_fileName);
    final path = _path;
    if (path != null && kind == FilePreviewKind.image) {
      // Windows Photos style: light background + top toolbar
      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_closePreview());
        },
        child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Column(
          children: <Widget>[
            // Top toolbar
            _buildImageToolbar(path),
            // Image body
            Expanded(child: _buildPreview(context)),
          ],
        ),
      ),
      ),
      );
    }
    final canOpen = path != null;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15171B) : const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1C1E23) : Colors.white,
        foregroundColor: dark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text(
          _fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          if (canOpen) ...<Widget>[
            IconButton(
              tooltip: translate('Share to WeChat'),
              icon: const Icon(Icons.share_outlined),
              onPressed: () => unawaited(shareFileToSystemApp(path)),
            ),
            IconButton(
              tooltip: translate('Open with system app'),
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => OpenFilex.open(path),
            ),
          ],
          IconButton(
            tooltip: translate('Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => unawaited(_closePreview()),
          ),
        ],
      ),
      body: path == null ? _buildMissingState(context) : _buildPreview(context),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final kind = filePreviewKindForName(_fileName);
    if (kind == FilePreviewKind.image) {
      return Listener(
        onPointerSignal: (event) {
          // 鼠标滚轮缩放
          if (event is PointerScrollEvent) {
            final delta = -event.scrollDelta.dy * 0.001;
            final current = _transformController.value;
            final currentScale = current.getMaxScaleOnAxis();
            final newScale = (currentScale * (1 + delta)).clamp(0.1, 10.0);
            final focalPoint = event.localPosition;
            // 以鼠标位置为中心缩放
            final Matrix4 m = Matrix4.identity()
              ..translate(focalPoint.dx, focalPoint.dy)
              ..scale(newScale / currentScale)
              ..translate(-focalPoint.dx, -focalPoint.dy);
            _transformController.value = m * current;
          }
        },
        child: GestureDetector(
          onDoubleTap: () {
            // 双击切换缩放：已放大则还原，否则放大到 2x
            final currentScale =
                _transformController.value.getMaxScaleOnAxis();
            if (currentScale > 1.5) {
              // 还原
              _transformController.value = Matrix4.identity();
            } else {
              // 放大到 2x
              _transformController.value = Matrix4.identity()..scale(2.0);
            }
          },
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.1,
            maxScale: 10.0,
            boundaryMargin: const EdgeInsets.all(80),
            child: Center(
              child: RotatedBox(
                quarterTurns: _rotationQuarterTurns,
                child: Image.file(
                  File(_path!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.broken_image_outlined,
                          size: 64,
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white38
                              : Colors.black26),
                      const SizedBox(height: 12),
                      Text(
                        translate('Cannot preview this image'),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white54
                              : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (kind == FilePreviewKind.audio) return _AudioPreview(_path!, _fileName);
    if (kind == FilePreviewKind.text || kind == FilePreviewKind.code) {
      return _TextPreview(_path!, _fileName);
    }
    if (kind == FilePreviewKind.pdf) {
      return PdfNativePreview(
        path: _path!,
        fileName: _fileName,
        fileSize: widget.fileSize,
      );
    }
    if (kind == FilePreviewKind.document) {
      return DocxNativePreview(
        path: _path!,
        fileName: _fileName,
        fileSize: widget.fileSize,
      );
    }
    if (isOfficeTextPreviewKind(kind)) {
      return OfficeTextPreviewView(
        path: _path!,
        fileName: _fileName,
        fileSize: widget.fileSize,
      );
    }
    if (kind == FilePreviewKind.cad) {
      return DwgPreviewView(
        path: _path!,
        fileName: _fileName,
        fileSize: widget.fileSize,
      );
    }
    return _OtherPreview(_path!, _fileName, widget.fileSize);
  }

  Widget _buildMissingState(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white70 : Colors.black54;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(filePreviewIcon(widget.fileName), size: 56, color: foreground),
            const SizedBox(height: 16),
            Text(
              translate('File not found on this device'),
              style: TextStyle(fontSize: 16, color: foreground),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${translate('Name')}: ${widget.fileName}\n'
              '${translate('Size')}: ${formatFileSize(widget.fileSize)}',
              style: TextStyle(fontSize: 13, color: foreground),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              translate(
                  'Receive the file via File Transfer to preview it here.'),
              style: TextStyle(fontSize: 12, color: foreground),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPreview extends StatefulWidget {
  const _AudioPreview(this.path, this.fileName);
  final String path;
  final String fileName;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setSource(DeviceFileSource(widget.path));
    } catch (_) {
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_errored) {
      return Center(
        child: Text(
          translate('Unable to play this audio file.'),
          style: TextStyle(color: dark ? Colors.white70 : Colors.black54),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Animated audio icon
            Icon(
              _playing ? Icons.graphic_eq_rounded : Icons.audiotrack_rounded,
              size: 72,
              color: dark ? const Color(0xFF4CAF50) : const Color(0xFF07C160),
            ),
            const SizedBox(height: 18),
            Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            // Progress bar with track
            Slider(
              value: _duration.inMilliseconds == 0
                  ? 0
                  : _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds)
                      .toDouble(),
              max: _duration.inMilliseconds.toDouble(),
              activeColor:
                  dark ? const Color(0xFF4CAF50) : const Color(0xFF07C160),
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _clock(_position),
                  style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: dark ? Colors.white54 : Colors.black45,
                  ),
                ),
                IconButton(
                  icon: Icon(_playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  iconSize: 48,
                  color:
                      dark ? const Color(0xFF4CAF50) : const Color(0xFF07C160),
                  onPressed: () {
                    if (_playing) {
                      _player.pause();
                    } else {
                      _player.seek(_position);
                      _player.resume();
                    }
                  },
                ),
                Text(
                  _clock(_duration),
                  style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: dark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            if (_errored)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  translate('Cannot play this audio file'),
                  style: TextStyle(fontSize: 13, color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview(this.path, this.fileName);
  final String path;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<String>(
      future: File(path).readAsString().catchError((_) => ''),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lines = snapshot.data!.split('\n');
        return Container(
          color: dark ? const Color(0xFF15171B) : const Color(0xFFFAFAFA),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lines.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 0.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              fontFamily: 'monospace',
                              color: dark
                                  ? const Color(0xFF4A4D53)
                                  : const Color(0xFFB0B0B0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            lines[i],
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              fontFamily: 'monospace',
                              color: dark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OtherPreview extends StatelessWidget {
  const _OtherPreview(this.path, this.fileName, this.fileSize);
  final String path;
  final String fileName;
  final int fileSize;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ext = fileExtensionLabel(fileName);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: filePreviewColor(fileName, dark ? 0.24 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(filePreviewIcon(fileName),
                      size: 36,
                      color: filePreviewColor(fileName, dark ? 0.9 : 0.8)),
                  const SizedBox(height: 4),
                  Text(
                    ext,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: filePreviewColor(fileName, dark ? 0.9 : 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              formatFileSize(fileSize),
              style: TextStyle(
                fontSize: 13,
                color: dark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(translate('Open with system app')),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => OpenFilex.open(path),
            ),
          ],
        ),
      ),
    );
  }
}
