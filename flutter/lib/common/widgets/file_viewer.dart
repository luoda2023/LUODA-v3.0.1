import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';

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
    if (ext is List) {
      for (final e in ext) {
        if (e is String) dirs.add(Directory(e));
      }
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

/// Opens a full-screen preview for a chat file. [localPath] is the sender's
/// local path (reliable for outgoing files); when it is missing or invalid we
/// attempt to locate a received copy on disk.
Future<void> showFileViewer(
  BuildContext context, {
  required String fileName,
  required int fileSize,
  String? localPath,
}) async {
  String? path = localPath?.isNotEmpty == true ? localPath : null;
  if (path == null || !(await File(path).exists())) {
    path = await resolveReceivedFilePath(fileName, fileSize);
  }
  final resolved = path != null && await File(path).exists();

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _FileViewerPage(
        fileName: fileName,
        fileSize: fileSize,
        path: resolved ? path : null,
      ),
    ),
  );
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
    final canOpen = path != null && !_isImage(fileName);
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
              tooltip: 'Open with system app',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => OpenFilex.open(path!),
            ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: path == null
          ? _buildMissingState(context)
          : _buildPreview(context),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (_isImage(fileName)) {
      return InteractiveViewer(
        child: Center(child: Image.file(File(path!))),
      );
    }
    if (_isAudio(fileName)) return _AudioPreview(path!, fileName);
    if (_isText(fileName)) return _TextPreview(path!, fileName);
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
            Icon(Icons.folder_open_outlined,
                size: 56, color: foreground),
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
              translate('Receive the file via File Transfer to preview it here.'),
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
            Icon(Icons.audiotrack_rounded,
                size: 72, color: dark ? Colors.white70 : Colors.black45),
            const SizedBox(height: 18),
            Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 18),
            Slider(
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
              children: <Widget>[
                Text(_clock(_position)),
                IconButton(
                  icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 44,
                  onPressed: () {
                    if (_playing) {
                      _player.pause();
                    } else {
                      _player.seek(_position);
                      _player.resume();
                    }
                  },
                ),
                Text(_clock(_duration)),
              ],
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
        return Container(
          color: dark ? const Color(0xFF15171B) : Colors.white,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              snapshot.data!,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontFamily: 'monospace',
                color: dark ? Colors.white70 : Colors.black87,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.insert_drive_file_outlined,
                size: 72, color: dark ? Colors.white70 : Colors.black45),
            const SizedBox(height: 18),
            Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
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
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(translate('Open with system app')),
              onPressed: () => OpenFilex.open(path),
            ),
          ],
        ),
      ),
    );
  }
}
