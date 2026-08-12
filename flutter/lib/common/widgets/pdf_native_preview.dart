import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../common.dart';

/// PDF 原生渲染预览：使用 PDFium 逐页栅格化，版式与原文完全一致。
/// 支持缩放、翻页、页码指示、以系统应用打开。
class PdfNativePreview extends StatefulWidget {
  const PdfNativePreview({
    super.key,
    required this.path,
    required this.fileName,
    this.fileSize = 0,
  });

  final String path;
  final String fileName;
  final int fileSize;

  @override
  State<PdfNativePreview> createState() => _PdfNativePreviewState();
}

class _PdfNativePreviewState extends State<PdfNativePreview> {
  final PdfViewerController _controller = PdfViewerController();
  bool _failed = false;
  int _pageCount = 0;
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final canvas = dark ? const Color(0xFF101418) : const Color(0xFFE8EBF0);
    final foreground = dark ? Colors.white70 : Colors.black87;

    if (_failed) {
      return _buildFallback(context, canvas, foreground);
    }

    return ColoredBox(
      color: canvas,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: PdfViewer.file(
              widget.path,
              controller: _controller,
              params: PdfViewerParams(
                backgroundColor: canvas,
                margin: 12,
                onDocumentChanged: (doc) {
                  final count = doc?.pages.length ?? 0;
                  if (count != _pageCount) {
                    setState(() {
                      _pageCount = count;
                      _currentPage = 1;
                    });
                  }
                },
                onPageChanged: (pageNumber) {
                  final page = pageNumber ?? 1;
                  if (page != _currentPage) {
                    setState(() => _currentPage = page);
                  }
                },
                errorBannerBuilder: (context, error, stack, ref) {
                  return _buildFallback(context, canvas, foreground);
                },
              ),
            ),
          ),
          // 顶部工具栏：文件名 + 页码 + 用系统应用打开。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    canvas.withOpacity(0.95),
                    canvas.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_pageCount > 0) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$_currentPage / $_pageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    tooltip: translate('Open with system app'),
                    icon: Icon(Icons.open_in_new_rounded,
                        color: foreground, size: 18),
                    onPressed: () => OpenFilex.open(widget.path),
                  ),
                ],
              ),
            ),
          ),
          // 底部缩放控制。
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _circleButton(
                  Icons.remove_rounded,
                  translate('Zoom out'),
                  () => _controller.zoomDown(),
                ),
                const SizedBox(width: 8),
                _circleButton(
                  Icons.zoom_in_rounded,
                  translate('Zoom in'),
                  () => _controller.zoomUp(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  /// PDF 打不开时的兜底：文件信息 + 用系统应用打开。
  Widget _buildFallback(BuildContext context, Color canvas, Color foreground) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.picture_as_pdf_outlined,
                size: 56, color: foreground.withOpacity(0.5)),
            const SizedBox(height: 14),
            Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              translate('This PDF cannot be rendered in-app'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: foreground.withOpacity(0.6)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => OpenFilex.open(widget.path),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(translate('Open with system app')),
            ),
          ],
        ),
      ),
    );
  }
}
