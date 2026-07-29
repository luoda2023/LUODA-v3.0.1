import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../consts.dart';

String _formatFileSize(int fileSize) {
  if (fileSize < 1024) return '$fileSize B';
  if (fileSize < 1024 * 1024) {
    return '${(fileSize / 1024).toStringAsFixed(1)} KB';
  }
  return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}

const Set<String> _kImageExts = <String>{
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg',
};
const Set<String> _kAudioExts = <String>{
  'mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a',
};
const Set<String> _kTextExts = <String>{
  'txt', 'md', 'log', 'json', 'xml', 'yaml', 'yml', 'toml', 'csv', 'ini',
};

String _ext(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';
}

bool _isImage(String fileName) => _kImageExts.contains(_ext(fileName));
bool _isAudio(String fileName) => _kAudioExts.contains(_ext(fileName));
bool _isText(String fileName) => _kTextExts.contains(_ext(fileName));

/// Standalone file preview window — supports images (zoom/pan), audio playback,
/// text display, and basic file info for other types.
/// Pass [siblingPaths] for prev/next navigation between files in the same
/// conversation or directory.
class FilePreviewPage extends StatefulWidget {
  final String filePath;
  final String fileName;
  final List<String>? siblingPaths;

  const FilePreviewPage({
    Key? key,
    required this.filePath,
    required this.fileName,
    this.siblingPaths,
  }) : super(key: key);

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage>
    with WindowListener {
  int _currentIndex = 0;
  List<String> get _paths =>
      widget.siblingPaths ?? [widget.filePath];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (widget.siblingPaths != null) {
      _currentIndex = widget.siblingPaths!.indexOf(widget.filePath);
      if (_currentIndex < 0) _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    windowManager.destroy();
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _goNext() {
    if (_currentIndex < _paths.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  String get _currentName =>
      _paths[_currentIndex].split(Platform.pathSeparator).last;

  @override
  Widget build(BuildContext context) {
    final currentPath = _paths[_currentIndex];
    final fileName = _currentName;
    final hasMultiple = _paths.length > 1;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = _isImage(fileName) ? Colors.black : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          fileName,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        leading: hasMultiple
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: translate('Previous'),
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _currentIndex > 0 ? _goPrevious : null,
                  ),
                  Text(
                    '${_currentIndex + 1} / ${_paths.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  IconButton(
                    tooltip: translate('Next'),
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed:
                        _currentIndex < _paths.length - 1 ? _goNext : null,
                  ),
                ],
              )
            : null,
        actions: [
          IconButton(
            tooltip: translate('Open with system app'),
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            onPressed: () => OpenFilex.open(currentPath),
          ),
          IconButton(
            tooltip: translate('Close'),
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
      body: _buildPreview(currentPath, fileName, dark),
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

    if (_isImage(fileName)) {
      return _buildImagePreview(path);
    }
    if (_isAudio(fileName)) {
      return _AudioPreview(path, fileName);
    }
    if (_isText(fileName)) {
      return _TextPreview(path, fileName, dark);
    }
    // Other file types: show info + open button
    return _buildOtherPreview(path, fileName, dark);
  }

  Widget _buildImagePreview(String path) {
    return InteractiveViewer(
      minScale: 0.1,
      maxScale: 10.0,
      child: Center(
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
            Icon(Icons.insert_drive_file_outlined,
                size: 64, color: Colors.white38),
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
              onChanged: (v) =>
                  _player.seek(Duration(milliseconds: v.toInt())),
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
