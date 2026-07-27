import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../consts.dart';

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

  @override
  Widget build(BuildContext context) {
    final currentPath = _paths[_currentIndex];
    final currentName = currentPath.split(Platform.pathSeparator).last;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          currentName,
          style: const TextStyle(fontSize: 14),
        ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.1,
            maxScale: 10.0,
            child: Center(
              child: Image.file(
                File(currentPath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined,
                          size: 64, color: Colors.white38),
                      const SizedBox(height: 12),
                      Text(
                        translate('Cannot preview this file'),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_paths.length > 1) ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _currentIndex > 0
                  ? _NavButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: _goPrevious,
                    )
                  : const SizedBox(width: 48),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _currentIndex < _paths.length - 1
                  ? _NavButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: _goNext,
                    )
                  : const SizedBox(width: 48),
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${_paths.length}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white70, size: 32),
        ),
      ),
    );
  }
}
