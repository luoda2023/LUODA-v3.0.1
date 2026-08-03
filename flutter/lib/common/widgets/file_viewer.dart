import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../consts.dart';
import 'file_preview_types.dart';

String formatFileSize(int fileSize) {
  if (fileSize < 1024) return '$fileSize B';
  if (fileSize < 1024 * 1024) {
    return '${(fileSize / 1024).toStringAsFixed(1)} KB';
  }
  return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Best-effort resolution of an incoming file's on-disk path by matching the
/// file name (and optionally size) inside well-known download/storage folders.
Future<String?> resolveReceivedFilePath(String fileName, int fileSize) async {
  if (fileName.isEmpty) return null;
  final dirs = <Directory>[];
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

  if (!resolved) {
    // File not found locally — show info dialog in-app.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FileViewerPage(
          fileName: fileName,
          fileSize: fileSize,
          path: null,
        ),
      ),
    );
    return;
  }

  // Mobile: use in-app viewer for all types.
  // Web falls through to desktop path (DesktopMultiWindow or system app).
  if (isMobile) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FileViewerPage(
          fileName: fileName,
          fileSize: fileSize,
          path: path,
        ),
      ),
    );
    return;
  }

  // Desktop: open in a separate OS window.
  try {
    final windowController = await DesktopMultiWindow.createWindow(
      jsonEncode({
        'type': kAppTypeDesktopFilePreview,
        'file_path': path,
        'file_name': fileName,
        if (siblingPaths != null) 'sibling_paths': siblingPaths,
      }),
    );
    await windowController.setTitle(fileName);
    if (filePreviewKindForName(fileName) == FilePreviewKind.image) {
      await windowController.setFullscreen(true);
    } else {
      await windowController.setFrame(
        const Offset(0, 0) & const Size(960, 720),
      );
      await windowController.center();
    }
    await windowController.show();
  } catch (_) {
    // Last resort: open with system app
    await OpenFilex.open(path);
  }
}

class _FileViewerPage extends StatelessWidget {
  const _FileViewerPage({
    required this.fileName,
    required this.fileSize,
    this.path,
  });

  final String fileName;
  final int fileSize;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final kind = filePreviewKindForName(fileName);
    if (path != null && kind == FilePreviewKind.image) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildPreview(context),
            Positioned(
              left: 12,
              top: 0,
              right: 8,
              child: SafeArea(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: translate('Close'),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          if (canOpen)
            IconButton(
              tooltip: translate('Open with system app'),
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => OpenFilex.open(path!),
            ),
          IconButton(
            tooltip: translate('Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: path == null ? _buildMissingState(context) : _buildPreview(context),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final kind = filePreviewKindForName(fileName);
    if (kind == FilePreviewKind.image) {
      return InteractiveViewer(
        minScale: 0.1,
        maxScale: 10.0,
        boundaryMargin: const EdgeInsets.all(80),
        child: Center(
          child: Image.file(
            File(path!),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.broken_image_outlined,
                    size: 64,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white38
                        : Colors.black26),
                const SizedBox(height: 12),
                Text(
                  translate('Cannot preview this image'),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white54
                        : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (kind == FilePreviewKind.audio) return _AudioPreview(path!, fileName);
    if (kind == FilePreviewKind.text || kind == FilePreviewKind.code) {
      return _TextPreview(path!, fileName);
    }
    return _OtherPreview(path!, fileName, fileSize);
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
            Icon(filePreviewIcon(fileName), size: 56, color: foreground),
            const SizedBox(height: 16),
            Text(
              translate('File not found on this device'),
              style: TextStyle(fontSize: 16, color: foreground),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${translate('Name')}: $fileName\n'
              '${translate('Size')}: ${formatFileSize(fileSize)}',
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
