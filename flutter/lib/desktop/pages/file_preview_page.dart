import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../common.dart';
import '../../common/widgets/docx_native_preview.dart';
import '../../common/widgets/dwg_preview_view.dart';
import '../../common/widgets/file_preview_types.dart';
import '../../common/widgets/office_preview_view.dart';
import '../../common/widgets/pdf_native_preview.dart';
import '../../runtime_logger.dart';

/// Set whether this window stays on top of all other windows.
/// Delegates to the desktop_multi_window native plugin which calls
/// Win32 SetWindowPos with HWND_TOPMOST/HWND_NOTOPMOST on Windows.
/// Returns true only if the native call succeeded AND the OS reports
/// the expected topmost state (verified via isAlwaysOnTop).
Future<bool> _setWindowTopMost(int windowId, bool topmost) async {
 if (!Platform.isWindows) return false;
 final controller = WindowController.fromWindowId(windowId);
 try {
 // setAlwaysOnTop / isAlwaysOnTop are present in our custom fork
 // but may not exist in upstream window_manager, so call via
 // dynamic to stay compile-safe across versions.
 final dyn = controller as dynamic;
 await dyn.setAlwaysOnTop(topmost);
 final actual = await dyn.isAlwaysOnTop() as bool;
 RuntimeLogger.instance.info('PIN',
 'windowId=$windowId requested=$topmost actual=$actual ok=${actual == topmost}');
 if (actual != topmost) {
 await dyn.setAlwaysOnTop(topmost);
 final retried = await dyn.isAlwaysOnTop() as bool;
 RuntimeLogger.instance.info('PIN',
 'windowId=$windowId retry actual=$retried ok=${retried == topmost}');
 return retried == topmost;
 }
 return true;
 } catch (e) {
 RuntimeLogger.instance.info('PIN', 'windowId=$windowId error=$e');
 return false;
 }
}

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
	 bool _isPinned = false;
 bool _showThumbnailStrip = false;
 final List<Timer> _firstPaintTimers = <Timer>[];
 Rect? _windowFrame;

  WindowController get _windowController =>
      WindowController.fromWindowId(widget.windowId);

  /// Persistence key for window frame.
  static const _kPrefKey = 'file_preview_window_frame';

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
 WidgetsBinding.instance.addPostFrameCallback((_) {
 _restoreWindowState();
 _syncWindowState();
 _ensureFirstPaint();
 _restorePinState();
 });
  }

  /// LUODA FIX: on some machines the child Flutter engine composites its
  /// first frame partially (toolbar renders, the body stays as the raw
  /// window background). Re-asserting window visibility and forcing a
  /// rebuild shortly after mount makes the surface repaint and the image
  /// body appear.
  void _ensureFirstPaint() {
    _firstPaintTimers.add(Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _windowController.show();
      setState(() {});
      _firstPaintTimers.add(Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() {});
      }));
    }));
  }

 @override
 void dispose() {
   for (final t in _firstPaintTimers) {
     t.cancel();
   }
   _firstPaintTimers.clear();
   _imageTransformController.dispose();
   _saveWindowState();
   super.dispose();
 }

  /// Restore window frame from last session.
  Future<void> _restoreWindowState() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$_kPrefKey.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final left = (json['left'] as num?)?.toDouble();
        final top = (json['top'] as num?)?.toDouble();
        final width = (json['width'] as num?)?.toDouble();
        final height = (json['height'] as num?)?.toDouble();
        if (left != null && top != null && width != null && height != null) {
          final frame = Rect.fromLTWH(left, top, width, height);
          await _windowController.setFrame(frame);
          _windowFrame = frame;
        }
      }
    } catch (_) {}
  }

  /// Save window frame for next session.
  Future<void> _saveWindowState() async {
    try {
      final frame = _windowFrame;
      if (frame == null) return;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$_kPrefKey.json');
      await file.writeAsString(jsonEncode({
        'left': frame.left,
        'top': frame.top,
        'width': frame.width,
        'height': frame.height,
      }));
    } catch (_) {}
  }

Future<void> _syncWindowState() async {
		final fullScreen = await _windowController.isFullScreen();
		final maximized = await _windowController.isMaximized();
		final frame =
		!fullScreen && !maximized ? await _windowController.getFrame() : null;
		if (!mounted) return;
		if (frame != null) {
		setState(() => _windowFrame = frame);
		}
}

/// Read the OS-level topmost state and sync the UI toggle to match.
/// This handles cases where the window was pinned externally or the
/// state was lost across rebuilds.
Future<void> _restorePinState() async {
 try {
 final topmost = await (_windowController as dynamic).isAlwaysOnTop() as bool;
 if (!mounted) return;
 if (_isPinned != topmost) {
 setState(() => _isPinned = topmost);
 }
 RuntimeLogger.instance.info('PIN',
 'restorePinState windowId=${widget.windowId} topmost=$topmost');
 } catch (e) {
 RuntimeLogger.instance.info('PIN', 'restorePinState error=$e');
 }
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

 Future<void> _togglePin() async {
 final next = !_isPinned;
 final ok = await _setWindowTopMost(widget.windowId, next);
 if (!mounted) return;
 setState(() => _isPinned = ok ? next : false);
 if (!ok) {
 // Show a snackbar so the user knows the pin failed, rather than
 // the button appearing to do nothing.
 ScaffoldMessenger.maybeOf(context)?.showSnackBar(
 SnackBar(
 content: Text(translate('Unable to toggle pin')),
 duration: const Duration(seconds: 2),
 ),
 );
 }
 }

 void _toggleThumbnailStrip() {
 setState(() => _showThumbnailStrip = !_showThumbnailStrip);
 }

 Future<void> _editWithSystemApp() async {
 final path = _paths[_currentIndex];
 if (Platform.isWindows) {
 try {
 await Process.run('mspaint.exe', [path]);
 } catch (_) {
 await OpenFilex.open(path);
 }
 } else {
 await OpenFilex.open(path);
 }
 }

 Future<void> _saveAs() async {
	final srcPath = _paths[_currentIndex];
	final srcFile = File(srcPath);
	if (!await srcFile.exists()) return;
	final name = srcPath.split(Platform.pathSeparator).last;
	final saveName = await FilePicker.platform.saveFile(
 dialogTitle: translate('Save as'),
 fileName: name,
 );
 if (saveName == null || !mounted) return;
 try {
 await srcFile.copy(saveName);
 } catch (_) {}
 }

 void _showMoreMenu(BuildContext context) {
 final path = _paths[_currentIndex];
 final menuItems = <PopupMenuEntry<String>>[
 PopupMenuItem<String>(
 value: 'copy_path',
 child: Row(children: <Widget>[
 const Icon(Icons.copy_outlined, size: 18),
 const SizedBox(width: 8),
 Text(translate('Copy')),
 ]),
 ),
 PopupMenuItem<String>(
 value: 'open_folder',
 child: Row(children: <Widget>[
 const Icon(Icons.folder_open_outlined, size: 18),
 const SizedBox(width: 8),
 Text(translate('Open with system app')),
 ]),
 ),
 ];
 showMenu<String>(
 context: context,
 position: RelativeRect.fromLTRB(
 MediaQuery.of(context).size.width - 180,
 50,
 20,
 MediaQuery.of(context).size.height - 200,
 ),
 items: menuItems,
 ).then((value) {
 if (value == 'copy_path') {
 Clipboard.setData(ClipboardData(text: path));
 } else if (value == 'open_folder') {
 OpenFilex.open(path);
 }
 });
 }

  String get _currentName =>
      _paths[_currentIndex].split(Platform.pathSeparator).last;



  @override
  Widget build(BuildContext context) {
    final currentPath = _paths[_currentIndex];
    final fileName = _currentName;
    final hasMultiple = _paths.length > 1;
    final isImage = filePreviewKindForName(fileName) == FilePreviewKind.image;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Windows Photos style: white/light background for images,
    // dark for other file types.
    final bgColor = isImage
        ? const Color(0xFFF5F5F5) // light gray like Windows Photos
        : (dark ? const Color(0xFF1C1E23) : Colors.white);
    final toolbarBg = isImage
        ? const Color(0xFFF0F0F0)
        : (dark ? const Color(0xFF2A2D33) : const Color(0xFFF8F8F8));
    final iconColor = isImage
        ? const Color(0xFF333333)
        : (dark ? Colors.white70 : const Color(0xFF555555));

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: <Widget>[
 // ── Top toolbar (Windows Photos style) ──
 // The native OS title bar (kept via showTitleBar for FilePreview in
 // main.dart) already handles window drag, double-click maximize, and
 // the min/max/close buttons. Wrapping the toolbar in a drag region
 // here would intercept pointer events and make every toolbar button
 // unclickable, so the toolbar is a plain Container.
 Container(
 height: 44,
 decoration: BoxDecoration(
 color: toolbarBg,
 border: Border(
 bottom: BorderSide(
 color: isImage
 ? const Color(0xFFE0E0E0)
 : (dark ? const Color(0xFF3A3D43) : const Color(0xFFE8E8E8)),
 ),
 ),
 ),
 child: Row(
 children: <Widget>[
                  const SizedBox(width: 8),
 // ── Left section: navigation ──
 _ToolBtn(
 icon: _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
 tooltip: translate(_isPinned ? 'Unpin' : 'Pin'),
 color: iconColor,
 onPressed: _togglePin,
 ),
 const SizedBox(width: 2),
 if (hasMultiple) ...<Widget>[
 _ToolBtn(
 icon: Icons.chevron_left,
 tooltip: translate('Previous'),
 color: iconColor,
 enabled: _currentIndex > 0,
 onPressed: _goPrevious,
 ),
 _ToolBtn(
 icon: Icons.chevron_right,
 tooltip: translate('Next'),
 color: iconColor,
 enabled: _currentIndex < _paths.length - 1,
 onPressed: _goNext,
 ),
 ],
 const SizedBox(width: 2),
 if (hasMultiple)
 _ToolBtn(
 icon: Icons.grid_view_rounded,
 tooltip: translate('Thumbnail view'),
 color: iconColor,
 onPressed: _toggleThumbnailStrip,
 ),
                  const SizedBox(width: 2),
                  // ── Center section: zoom ──
                  if (isImage) ...<Widget>[
                    _ToolBtn(
                      icon: Icons.add_circle_outline,
                      tooltip: translate('Zoom in'),
                      color: iconColor,
                      enabled: _imageScale < 10,
                      onPressed: () => _zoomImage(1.25),
                    ),
                    _ToolBtn(
                      icon: Icons.remove_circle_outline,
                      tooltip: translate('Zoom out'),
                      color: iconColor,
                      enabled: _imageScale > 0.1,
                      onPressed: () => _zoomImage(0.8),
                    ),
                    _ToolBtn(
                      icon: Icons.crop_square_rounded,
                      tooltip: translate('Fit to window'),
                      color: iconColor,
                      onPressed: _resetImageTransform,
                    ),
                    const SizedBox(width: 2),
                  ],
                  // ── Right section: actions ──
                  if (isImage)
                    _ToolBtn(
                      icon: Icons.rotate_right_rounded,
                      tooltip: translate('Rotate right'),
                      color: iconColor,
                      onPressed: _rotateImage,
                    ),
if (isImage)
 _ToolBtn(
 icon: Icons.edit_outlined,
 tooltip: translate('Edit'),
 color: iconColor,
 onPressed: _editWithSystemApp,
 ),
 _ToolBtn(
 icon: Icons.download_rounded,
 tooltip: translate('Save as'),
 color: iconColor,
 onPressed: _saveAs,
 ),
 const SizedBox(width: 2),
 _ToolBtn(
 icon: Icons.more_horiz_rounded,
 tooltip: translate('More'),
 color: iconColor,
 onPressed: () => _showMoreMenu(context),
 ),
const Spacer(),
// Native OS title bar provides minimize / maximize / close — no
// duplicate buttons here.
const SizedBox(width: 8),
],
),
),
 // ── Body ──
 Expanded(
 child: Stack(
 children: <Widget>[
 Positioned.fill(
 child: _buildPreview(currentPath, fileName, dark)),
 if (_showThumbnailStrip && hasMultiple)
 Positioned(
 left: 0,
 right: 0,
 bottom: 0,
 child: _buildThumbnailStrip(dark),
 ),
 ],
 ),
 ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip(bool dark) {
 final bg = dark ? const Color(0xFF1C1E23) : const Color(0xFFF0F0F0);
 final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFD0D0D0);
 return Container(
 height: 96,
 decoration: BoxDecoration(
 color: bg.withOpacity(0.97),
 border: Border(top: BorderSide(color: border)),
 ),
 child: ListView.builder(
 scrollDirection: Axis.horizontal,
 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
 itemCount: _paths.length,
 itemBuilder: (context, index) {
 final p = _paths[index];
 final name = p.split(Platform.pathSeparator).last;
 final kind = filePreviewKindForName(name);
 final isSelected = index == _currentIndex;
 final isImg = kind == FilePreviewKind.image;
 return GestureDetector(
 onTap: () {
 _resetImageTransform(notify: false);
 setState(() {
 _rotationQuarterTurns = 0;
 _currentIndex = index;
 });
 },
 child: Container(
 width: 80,
 height: 80,
 margin: const EdgeInsets.only(right: 6),
 decoration: BoxDecoration(
 border: Border.all(
 color: isSelected
 ? Colors.blue
 : (dark ? Colors.white12 : Colors.black12),
 width: isSelected ? 2.5 : 1,
 ),
 borderRadius: BorderRadius.circular(4),
 color: dark ? Colors.black26 : Colors.white,
 ),
 clipBehavior: Clip.antiAlias,
 child: isImg
 ? Image.file(
 File(p),
 fit: BoxFit.cover,
 errorBuilder: (_, __, ___) => Container(
 color: Colors.grey[300],
 child: Icon(Icons.broken_image,
 size: 28, color: Colors.grey[500]),
 ),
 )
 : Center(
 child: Icon(
 filePreviewIcon(name),
 size: 28,
 color: filePreviewColor(name, 0.9),
 ),
 ),
 ),
 );
 },
 ),
 );
 }

 Widget _buildPreview(String path, String fileName, bool dark) {
    final file = File(path);
    if (!file.existsSync()) {
      // High-contrast "not found" state: this must look obviously broken,
      // never like an empty black/white void.
      final foreground = dark ? Colors.white70 : Colors.black54;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 64, color: foreground),
            const SizedBox(height: 12),
            Text(
              translate('File not found'),
              style: TextStyle(color: foreground, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 12),
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
                  Icon(Icons.broken_image_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    translate('Cannot preview this image'),
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
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

/// Minimal toolbar button matching Windows Photos style.
class _ToolBtn extends StatelessWidget {
 const _ToolBtn({
 required this.icon,
 required this.tooltip,
 required this.color,
 required this.onPressed,
 this.enabled = true,
 });

 final IconData icon;
 final String tooltip;
 final Color color;
 final VoidCallback? onPressed;
 final bool enabled;

 @override
 Widget build(BuildContext context) {
 final effectiveOnPressed = enabled ? onPressed : null;
	return Tooltip(
	message: tooltip,
	waitDuration: const Duration(milliseconds: 300),
	showDuration: const Duration(seconds: 2),
	child: InkWell(
 onTap: effectiveOnPressed,
 hoverColor: Colors.black.withOpacity(0.06),
 highlightColor: Colors.black.withOpacity(0.1),
 borderRadius: BorderRadius.circular(4),
 child: SizedBox(
 width: 36,
 height: 36,
 child: Icon(
 icon,
 size: 20,
 color: effectiveOnPressed != null
 ? color
 : color.withOpacity(0.35),
 ),
 ),
 ),
 );
 }
}
