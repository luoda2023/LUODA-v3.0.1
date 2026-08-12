import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:win32/win32.dart';

import '../../common.dart';
import '../../common/widgets/docx_native_preview.dart';
import '../../common/widgets/dwg_preview_view.dart';
import '../../common/widgets/file_preview_types.dart';
import '../../common/widgets/office_preview_view.dart';
import '../../common/widgets/pdf_native_preview.dart';

String _formatFileSize(int fileSize) {
  if (fileSize < 1024) return '$fileSize B';
  if (fileSize < 1024 * 1024) {
    return '${(fileSize / 1024).toStringAsFixed(1)} KB';
  }
  return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Standalone file preview window — supports images (zoom/pan), audio playback,
/// text display, and basic file info for other types.
/// Pass [siblingPaths] for prev/next navigation between files in the same
/// conversation or directory.
class FilePreviewPage extends StatefulWidget {
  final int windowId;
  final String filePath;
  final String fileName;
  final List<String>? siblingPaths;

  const FilePreviewPage({
    Key? key,
    required this.windowId,
    required this.filePath,
    required this.fileName,
    this.siblingPaths,
  }) : super(key: key);

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  int _currentIndex = 0;
  late final List<String> _paths;
  final TransformationController _imageTransformController =
      TransformationController();
  double _imageScale = 1;
  int _rotationQuarterTurns = 0;
  bool _isMaximized = false;
  bool _isFullScreen = false;
  Timer? _windowDragTimer;
  Rect? _windowFrame;
  Rect? _windowDragStartFrame;
  Offset? _windowDragStartCursor;

  WindowController get _windowController =>
      WindowController.fromWindowId(widget.windowId);

  @override
  void initState() {
    super.initState();
    _paths = <String>{
      ...?widget.siblingPaths?.where((path) => path.trim().isNotEmpty),
      if (widget.filePath.trim().isNotEmpty) widget.filePath,
    }.toList(growable: true);
    if (_paths.isEmpty) _paths.add(widget.filePath);
    _currentIndex = _paths.indexOf(widget.filePath);
    if (_currentIndex < 0) _currentIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindowState());
  }

  @override
  void dispose() {
    _windowDragTimer?.cancel();
    _imageTransformController.dispose();
    super.dispose();
  }

  Offset? _windowsCursorPosition() {
    final cursorPoint = calloc<POINT>();
    try {
      if (GetCursorPos(cursorPoint) == 0) return null;
      return Offset(
        cursorPoint.ref.x.toDouble(),
        cursorPoint.ref.y.toDouble(),
      );
    } finally {
      calloc.free(cursorPoint);
    }
  }

  void _beginWindowDrag(PointerDownEvent _) {
    if (_isFullScreen || _isMaximized) return;
    if (!Platform.isWindows) {
      unawaited(_windowController.startDragging());
      return;
    }

    final frame = _windowFrame;
    final cursor = _windowsCursorPosition();
    if (frame == null || cursor == null) return;

    _windowDragTimer?.cancel();
    _windowDragStartFrame = frame;
    _windowDragStartCursor = cursor;
    _windowDragTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _updateWindowDrag(),
    );
    _updateWindowDrag();
  }

  void _updateWindowDrag() {
    final startFrame = _windowDragStartFrame;
    final startCursor = _windowDragStartCursor;
    final cursor = Platform.isWindows ? _windowsCursorPosition() : null;
    if (startFrame == null || startCursor == null || cursor == null) return;

    final delta = cursor - startCursor;
    if (delta.distanceSquared < 1) return;
    final frame = startFrame.shift(delta);
    _windowFrame = frame;
    unawaited(_windowController.setFrame(frame));
  }

  void _endWindowDrag() {
    _windowDragTimer?.cancel();
    _windowDragTimer = null;
    _updateWindowDrag();
    _windowDragStartFrame = null;
    _windowDragStartCursor = null;
  }

  Future<void> _syncWindowState() async {
    final fullScreen = await _windowController.isFullScreen();
    final maximized = await _windowController.isMaximized();
    final frame =
        !fullScreen && !maximized ? await _windowController.getFrame() : null;
    if (!mounted) return;
    setState(() {
      _isFullScreen = fullScreen;
      _isMaximized = maximized;
      if (frame != null) _windowFrame = frame;
    });
  }

  Future<void> _toggleFullScreen() async {
    final next = !_isFullScreen;
    await _windowController.setFullscreen(next);
    final frame = !next ? await _windowController.getFrame() : null;
    if (!mounted) return;
    setState(() {
      _isFullScreen = next;
      if (next) _isMaximized = false;
      if (frame != null) _windowFrame = frame;
    });
  }

  Future<void> _toggleMaximized() async {
    if (_isFullScreen) {
      await _windowController.setFullscreen(false);
    }
    final maximized = await _windowController.isMaximized();
    Rect? frame;
    if (maximized) {
      await _windowController.unmaximize();
      frame = await _windowController.getFrame();
    } else {
      await _windowController.maximize();
    }
    if (!mounted) return;
    setState(() {
      _isFullScreen = false;
      _isMaximized = !maximized;
      if (frame != null) _windowFrame = frame;
    });
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      _resetImageTransform(notify: false);
      setState(() {
        _rotationQuarterTurns = 0;
        _currentIndex--;
      });
    }
  }

  void _goNext() {
    if (_currentIndex < _paths.length - 1) {
      _resetImageTransform(notify: false);
      setState(() {
        _rotationQuarterTurns = 0;
        _currentIndex++;
      });
    }
  }

  void _zoomImage(double factor) {
    final nextScale = (_imageScale * factor).clamp(0.1, 10.0).toDouble();
    if (nextScale == _imageScale) return;
    setState(() => _imageScale = nextScale);
    _imageTransformController.value =
        Matrix4.diagonal3Values(nextScale, nextScale, 1);
  }

  void _resetImageTransform({bool notify = true}) {
    _imageTransformController.value = Matrix4.identity();
    if (notify) {
      setState(() => _imageScale = 1);
    } else {
      _imageScale = 1;
    }
  }

  void _rotateImage() {
    _resetImageTransform(notify: false);
    setState(() {
      _imageScale = 1;
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _updateImageScale() {
    final scale = _imageTransformController.value.getMaxScaleOnAxis();
    if ((scale - _imageScale).abs() < 0.001) return;
    setState(() => _imageScale = scale);
  }

  String get _currentName =>
      _paths[_currentIndex].split(Platform.pathSeparator).last;

  Widget _toolbarButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    double iconSize = 20,
  }) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      hoverColor: Colors.white12,
      highlightColor: Colors.white10,
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
    );
  }

  Widget _windowDragRegion({
    required Widget child,
    VoidCallback? onDoubleTap,
  }) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _beginWindowDrag,
      onPointerUp: (_) => _endWindowDrag(),
      onPointerCancel: (_) => _endWindowDrag(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onDoubleTap,
        child: child,
      ),
    );
  }

  Widget _imageNavigationButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0x66000000),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(icon),
          iconSize: 40,
          color: Colors.white,
          disabledColor: Colors.white30,
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          padding: EdgeInsets.zero,
          splashRadius: 25,
          onPressed: onPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _paths[_currentIndex];
    final fileName = _currentName;
    final hasMultiple = _paths.length > 1;
    final isImage = filePreviewKindForName(fileName) == FilePreviewKind.image;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = filePreviewKindForName(fileName) == FilePreviewKind.image
        ? Colors.black
        : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: _windowDragRegion(
          onDoubleTap: _toggleMaximized,
          child: SizedBox(
            height: kToolbarHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                fileName,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        leadingWidth: hasMultiple ? 72 : null,
        leading: hasMultiple
            ? _windowDragRegion(
                child: Center(
                  child: Text(
                    '${_currentIndex + 1} / ${_paths.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ),
              )
            : null,
        actions: [
          if (isImage) ...<Widget>[
            _toolbarButton(
              tooltip: translate('Zoom out'),
              icon: Icons.zoom_out_rounded,
              onPressed: _imageScale > 0.1 ? () => _zoomImage(0.8) : null,
            ),
            SizedBox(
              width: 52,
              child: Center(
                child: Text(
                  '${(_imageScale * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
            _toolbarButton(
              tooltip: translate('Zoom in'),
              icon: Icons.zoom_in_rounded,
              onPressed: _imageScale < 10 ? () => _zoomImage(1.25) : null,
            ),
            _toolbarButton(
              tooltip: translate('Reset zoom'),
              icon: Icons.center_focus_strong_rounded,
              iconSize: 19,
              onPressed: _imageScale == 1 ? null : _resetImageTransform,
            ),
            _toolbarButton(
              tooltip: translate('Rotate right'),
              icon: Icons.rotate_right_rounded,
              onPressed: _rotateImage,
            ),
          ],
          _toolbarButton(
            tooltip: translate('Open with system app'),
            icon: Icons.open_in_new_rounded,
            onPressed: () => OpenFilex.open(currentPath),
          ),
          _toolbarButton(
            tooltip: translate(
              _isFullScreen ? 'Exit Fullscreen' : 'Fullscreen',
            ),
            icon: _isFullScreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            onPressed: _toggleFullScreen,
          ),
          _toolbarButton(
            tooltip: translate('Minimize'),
            icon: Icons.remove_rounded,
            onPressed: _windowController.minimize,
          ),
          _toolbarButton(
            tooltip: translate(_isMaximized ? 'Restore' : 'Maximize'),
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: 18,
            onPressed: _toggleMaximized,
          ),
          _toolbarButton(
            tooltip: translate('Close'),
            icon: Icons.close_rounded,
            onPressed: _windowController.close,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _buildPreview(currentPath, fileName, dark)),
          if (isImage && hasMultiple)
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: _imageNavigationButton(
                  tooltip: translate('Previous'),
                  icon: Icons.chevron_left_rounded,
                  onPressed: _currentIndex > 0 ? _goPrevious : null,
                ),
              ),
            ),
          if (isImage && hasMultiple)
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: _imageNavigationButton(
                  tooltip: translate('Next'),
                  icon: Icons.chevron_right_rounded,
                  onPressed: _currentIndex < _paths.length - 1 ? _goNext : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview(String path, String fileName, bool dark) {
    final file = File(path);
    if (!file.existsSync()) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 64, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              translate('File not found'),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final kind = filePreviewKindForName(fileName);
    if (kind == FilePreviewKind.image) {
      return _buildImagePreview(path);
    }
    if (kind == FilePreviewKind.audio) {
      return _AudioPreview(path, fileName);
    }
    if (kind == FilePreviewKind.text || kind == FilePreviewKind.code) {
      return _TextPreview(path, fileName, dark);
    }
    if (kind == FilePreviewKind.pdf) {
      return PdfNativePreview(
        path: path,
        fileName: fileName,
        fileSize: file.statSync().size,
      );
    }
    if (kind == FilePreviewKind.document) {
      return DocxNativePreview(
        path: path,
        fileName: fileName,
        fileSize: file.statSync().size,
      );
    }
    if (isOfficeTextPreviewKind(kind)) {
      return OfficeTextPreviewView(
        path: path,
        fileName: fileName,
        fileSize: file.statSync().size,
      );
    }
    if (kind == FilePreviewKind.cad) {
      return DwgPreviewView(
        path: path,
        fileName: fileName,
        fileSize: file.statSync().size,
      );
    }
    // Other file types: show info + open button
    return _buildOtherPreview(path, fileName, dark);
  }

  Widget _buildImagePreview(String path) {
    return InteractiveViewer(
      transformationController: _imageTransformController,
      minScale: 0.1,
      maxScale: 10.0,
      boundaryMargin: const EdgeInsets.all(80),
      onInteractionUpdate: (_) => _updateImageScale(),
      child: Center(
        child: RotatedBox(
          quarterTurns: _rotationQuarterTurns,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined,
                      size: 64, color: Colors.white38),
                  const SizedBox(height: 12),
                  Text(
                    translate('Cannot preview this image'),
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtherPreview(String path, String fileName, bool dark) {
    final file = File(path);
    final size = file.statSync().size;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: filePreviewColor(fileName, 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    filePreviewIcon(fileName),
                    size: 38,
                    color: filePreviewColor(fileName, 0.95),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fileExtensionLabel(fileName),
                    style: TextStyle(
                      color: filePreviewColor(fileName, 0.95),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _formatFileSize(size),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(translate('Open with system app')),
              onPressed: () => OpenFilex.open(path),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audio preview
// ---------------------------------------------------------------------------
class _AudioPreview extends StatefulWidget {
  final String path;
  final String fileName;
  const _AudioPreview(this.path, this.fileName);

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
    if (_errored) {
      return Center(
        child: Text(
          translate('Unable to play this audio file.'),
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack_rounded,
                size: 72, color: Colors.white54),
            const SizedBox(height: 18),
            Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 18),
            Slider(
              activeColor: Colors.white70,
              inactiveColor: Colors.white24,
              value: _duration.inMilliseconds == 0
                  ? 0
                  : _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds)
                      .toDouble(),
              max: _duration.inMilliseconds.toDouble(),
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_clock(_position),
                    style: const TextStyle(color: Colors.white54)),
                IconButton(
                  icon: Icon(
                    _playing ? Icons.pause_circle : Icons.play_circle,
                  ),
                  iconSize: 44,
                  color: Colors.white70,
                  onPressed: () {
                    if (_playing) {
                      _player.pause();
                    } else {
                      _player.seek(_position);
                      _player.resume();
                    }
                  },
                ),
                Text(_clock(_duration),
                    style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text preview
// ---------------------------------------------------------------------------
class _TextPreview extends StatelessWidget {
  final String path;
  final String fileName;
  final bool dark;
  const _TextPreview(this.path, this.fileName, this.dark);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: File(path).readAsString().catchError((_) => ''),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Container(
          color: const Color(0xFF15171B),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              snapshot.data!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
            ),
          ),
        );
      },
    );
  }
}
