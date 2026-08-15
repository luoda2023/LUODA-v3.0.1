// Screenshot annotation tool (PC chat "screenshot" flow).
//
// Mirrors the workflow of mainstream screenshot tools (Snipaste / WeChat
// screenshots): capture the full screen, drag a selection box over it, then
// annotate the selected region with a freehand pen, rectangles, arrows or
// text labels, undo mistakes, and finally save (and send) the composed PNG.
//
// Everything is rasterized at native image resolution so the exported file
// keeps the full detail of the captured screen.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/desktop/widgets/win_window_scanner.dart';
import 'package:path_provider/path_provider.dart';

/// Shows the annotation overlay and returns the path of the composed PNG,
/// or null when the user cancels.
///
/// [preselected] = true 表示 [imageBytes] 已经是框选好的区域图，annotator
/// 直接进入标注阶段（工具条立即可用），不再需要拖拽框选。
Future<String?> showScreenshotAnnotator(
  BuildContext context, {
  required Uint8List imageBytes,
  bool preselected = false,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: translate('Screenshot annotator'),
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return ScreenshotAnnotatorOverlay(
        imageBytes: imageBytes,
        preselected: preselected,
      );
    },
  );
}

enum _ShotTool { pen, rect, ellipse, arrow, text, mosaic, highlight }

/// 截图选取模式：框选区域 / 自动选择窗口。
enum _ShotMode { region, window }

/// A finished annotation element, stored in full-image pixel coordinates.
sealed class _ShotMark {
  const _ShotMark(this.color, this.width);
  final Color color;
  final double width;
}

class _ShotStroke extends _ShotMark {
  _ShotStroke(this.points, super.color, super.width);
  final List<Offset> points;
}

class _ShotRect extends _ShotMark {
  _ShotRect(this.rect, super.color, super.width);
  final Rect rect;
}

class _ShotEllipse extends _ShotMark {
  _ShotEllipse(this.rect, super.color, super.width);
  final Rect rect;
}

/// 马赛克（像素化）：记录笔画经过的路径点，绘制时把经过的格子
/// 替换为原图像素采样色块，遮住下方的敏感内容。
class _ShotMosaic extends _ShotMark {
  _ShotMosaic(this.points, this.cellSize, super.color, super.width);
  final List<Offset> points;
  final double cellSize;
}

/// 高亮（荧光笔）：半透明粗笔，突出标记区域。
class _ShotHighlight extends _ShotMark {
  _ShotHighlight(this.points, super.color, super.width);
  final List<Offset> points;
}

class _ShotArrow extends _ShotMark {
  _ShotArrow(this.start, this.end, super.color, super.width);
  final Offset start;
  final Offset end;
}

class _ShotText extends _ShotMark {
  _ShotText(this.position, this.text, this.fontSize, super.color, super.width);
  final Offset position;
  final String text;
  final double fontSize;
}

class ScreenshotAnnotatorOverlay extends StatefulWidget {
  const ScreenshotAnnotatorOverlay({
    super.key,
    required this.imageBytes,
    this.preselected = false,
  });

  final Uint8List imageBytes;

  /// 传入的图片已是框选好的区域图：直接进入标注阶段。
  final bool preselected;

  @override
  State<ScreenshotAnnotatorOverlay> createState() =>
      _ScreenshotAnnotatorOverlayState();
}

class _ScreenshotAnnotatorOverlayState extends State<ScreenshotAnnotatorOverlay> {
  ui.Image? _image;
  bool _decodeFailed = false;

  /// RGBA 像素缓存（rawRgba），供马赛克工具采样原图颜色。
  Uint8List? _pixels;

  /// Image size in native pixels.
  Size _imageSize = Size.zero;

  /// Where the (possibly scaled) image is drawn inside the overlay.
  Rect _fitRect = Rect.zero;
  double _scale = 1.0;

  /// Selected region in image pixels (null until the user drags).
  Rect? _selection;

  /// In-progress selection drag (image pixels).
  Rect? _selectDrag;

  final List<_ShotMark> _marks = <_ShotMark>[];
  List<Offset> _activeStroke = <Offset>[];
  bool _drawing = false;

  _ShotTool _tool = _ShotTool.pen;
  Color _color = const Color(0xFFE53935);
  double _width = 4;
  Offset? _shapeStart;
  Offset? _shapeEnd;

  /// 文字工具：点击图板后在此位置直接输入（微信式，无对话框）。
  Offset? _pendingTextPos;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  bool _compositing = false;

  /// 当前截图模式（微信风格：右上角向下箭头切换）。
  _ShotMode _mode = _ShotMode.region;

  /// 按住 Ctrl 时临时进入“自动选择窗口”：悬停高亮、单击选中。
  bool _ctrlDown = false;

  /// 自动选择窗口模式下，鼠标当前悬停的窗口（用于高亮）。
  ScreenshotWindow? _hoverWindow;

  /// 标注器所在窗口句柄（自动选窗口时要排除自己）。
  int _selfHwnd = 0;

  DateTime _lastHoverScan = DateTime.fromMillisecondsSinceEpoch(0);

  static const List<Color> _palette = <Color>[
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF212121),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    // 记录标注器所在窗口，自动选窗口模式时排除自身。
    if (Platform.isWindows) {
      _selfHwnd = foregroundWindowHandle();
    }
    ui.decodeImageFromList(widget.imageBytes, (image) {
      if (!mounted) return;
      setState(() {
        if (image.width <= 0 || image.height <= 0) {
          _decodeFailed = true;
        } else {
          _image = image;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          // 区域图直接进入标注阶段：整图为选中区域。
          if (widget.preselected) {
            _selection = Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );
          }
        }
      });
      // 马赛克工具需要逐像素采样，异步提取一次 RGBA 缓存。
      unawaited(_extractPixels(image));
    });
  }

  Future<void> _extractPixels(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null || !mounted) return;
    setState(() => _pixels = data.buffer.asUint8List());
  }

  @override
  void dispose() {
    _image?.dispose();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /// Maps a pointer position in the overlay to image pixel coordinates.
  Offset _toImage(Offset local) {
    final dx = (local.dx - _fitRect.left) / _scale;
    final dy = (local.dy - _fitRect.top) / _scale;
    return Offset(dx.clamp(0, _imageSize.width),
        dy.clamp(0, _imageSize.height));
  }

  void _layoutImage(Size box) {
    if (_imageSize.isEmpty) return;
    const inset = 0.0;
    final availW = box.width - inset * 2;
    final availH = box.height - inset * 2;
    var scale = (availW / _imageSize.width)
        .clamp(0.0, availH / _imageSize.height)
        .toDouble();
    // Never upscale a small capture; keep it at native size, centered.
    scale = scale.clamp(0.0, 1.0).toDouble();
    final w = _imageSize.width * scale;
    final h = _imageSize.height * scale;
    _scale = scale;
    _fitRect = Rect.fromLTWH(
      (box.width - w) / 2,
      (box.height - h) / 2,
      w,
      h,
    );
  }

  // 用原始指针事件（Listener）而非 GestureDetector 手势：桌面端鼠标拖拽
  // 与触摸都能即时响应，不依赖手势竞技场判定，框选/标注更可靠。
  int? _activePointer;

  void _onPointerDown(PointerDownEvent event) {
    if (_image == null || _compositing) return;
    if (event.buttons != kPrimaryButton) return;
    _activePointer = event.pointer;
    final pos = _toImage(event.localPosition);
    // 自动选择窗口模式（或按住 Ctrl）：单击即选中鼠标下的窗口。
    if ((_mode == _ShotMode.window || _ctrlDown) && _selection == null) {
      final win = _windowAtPointer(event.localPosition);
      if (win != null) {
        setState(() {
          final rect = Rect.fromLTRB(
            win.rect.left.clamp(0, _imageSize.width),
            win.rect.top.clamp(0, _imageSize.height),
            win.rect.right.clamp(0, _imageSize.width),
            win.rect.bottom.clamp(0, _imageSize.height),
          );
          _selection = rect;
          _hoverWindow = null;
          _selectDrag = null;
        });
      }
      return;
    }
    if (_selection == null) {
      _selectDrag = Rect.fromPoints(pos, pos);
      return;
    }
    _drawing = true;
    _activeStroke = <Offset>[pos];
    _shapeStart = pos;
    _shapeEnd = pos;
  }

  /// 自动选择窗口模式（或按住 Ctrl）：鼠标悬停时高亮所在窗口。
  void _onPointerHover(PointerHoverEvent event) {
    if (_image == null || _compositing) return;
    if (_selection != null || (_mode != _ShotMode.window && !_ctrlDown)) return;
    final now = DateTime.now();
    if (now.difference(_lastHoverScan).inMilliseconds < 50) return;
    _lastHoverScan = now;
    final win = _windowAtPointer(event.localPosition);
    if (win?.hwnd != _hoverWindow?.hwnd) {
      setState(() => _hoverWindow = win);
    }
  }

  /// 把指针位置换算为屏幕物理坐标，查询该点所在的顶层窗口。
  ScreenshotWindow? _windowAtPointer(Offset local) {
    final dpr = _devicePixelRatio;
    final screen =
        localToScreenPhysical(local, dpr);
    return windowAtPoint(screen, excludeHwnd: _selfHwnd);
  }

  double get _devicePixelRatio {
    final view = View.of(context);
    return view.devicePixelRatio;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_image == null || _compositing) return;
    if (event.pointer != _activePointer) return;
    if (event.buttons != kPrimaryButton) return;
    final pos = _toImage(event.localPosition);
    if (_selection == null) {
      if (_selectDrag != null) {
        setState(() {
          _selectDrag = Rect.fromPoints(_selectDrag!.topLeft, pos);
        });
      }
      return;
    }
    if (!_drawing) return;
    setState(() {
      // 画笔/高亮/马赛克是自由笔迹，其余是两点确定的形状。
      if (_tool == _ShotTool.pen ||
          _tool == _ShotTool.highlight ||
          _tool == _ShotTool.mosaic) {
        _activeStroke.add(pos);
      } else {
        _shapeEnd = pos;
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    if (_hoverWindow != null && mounted) {
      setState(() => _hoverWindow = null);
    }
    if (_image == null || _compositing) return;
    if (_selection == null) {
      final drag = _selectDrag;
      if (drag == null) return;
      setState(() {
        if (drag.width < 4 || drag.height < 4) {
          // Tiny drag = select nothing yet; keep selecting.
          _selectDrag = null;
        } else {
          final selection = Rect.fromPoints(
            Offset(drag.left.clamp(0, _imageSize.width),
                drag.top.clamp(0, _imageSize.height)),
            Offset(drag.right.clamp(0, _imageSize.width),
                drag.bottom.clamp(0, _imageSize.height)),
          );
          _selection = selection;
          _selectDrag = null;
        }
      });
      return;
    }
    if (!_drawing) return;
    _drawing = false;
    setState(() {
      switch (_tool) {
        case _ShotTool.pen:
          if (_activeStroke.length >= 2) {
            _marks.add(_ShotStroke(List<Offset>.of(_activeStroke), _color, _width));
          }
          break;
        case _ShotTool.highlight:
          if (_activeStroke.length >= 2) {
            _marks.add(_ShotHighlight(
              List<Offset>.of(_activeStroke),
              _color,
              _width,
            ));
          }
          break;
        case _ShotTool.mosaic:
          if (_activeStroke.length >= 2) {
            _marks.add(_ShotMosaic(
              List<Offset>.of(_activeStroke),
              _mosaicCellSize,
              _color,
              _width,
            ));
          }
          break;
        case _ShotTool.rect:
          final rect = _shapeStart == null || _shapeEnd == null
              ? null
              : Rect.fromPoints(_shapeStart!, _shapeEnd!);
          if (rect != null && rect.width > 1 && rect.height > 1) {
            _marks.add(_ShotRect(rect, _color, _width));
          }
          break;
        case _ShotTool.ellipse:
          final rect = _shapeStart == null || _shapeEnd == null
              ? null
              : Rect.fromPoints(_shapeStart!, _shapeEnd!);
          if (rect != null && rect.width > 1 && rect.height > 1) {
            _marks.add(_ShotEllipse(rect, _color, _width));
          }
          break;
        case _ShotTool.arrow:
          if (_shapeStart != null &&
              _shapeEnd != null &&
              (_shapeEnd! - _shapeStart!).distance > 4) {
            _marks.add(_ShotArrow(_shapeStart!, _shapeEnd!, _color, _width));
          }
          break;
        case _ShotTool.text:
          // 不在图板上弹对话框：记录点击位置，随后在图板上直接输入。
          if (_shapeStart != null) {
            _pendingTextPos = _shapeStart;
            _textController.clear();
          }
          break;
      }
      _activeStroke = <Offset>[];
      _shapeStart = null;
      _shapeEnd = null;
    });
  }

  void _commitPendingText() {
    final text = _textController.text.trim();
    final pos = _pendingTextPos;
    if (!mounted) return;
    if (text.isNotEmpty && pos != null) {
      setState(() {
        _marks.add(_ShotText(
          pos,
          text,
          (10 * _width).clamp(20.0, 72.0),
          _color,
          _width,
        ));
        _pendingTextPos = null;
      });
    } else {
      setState(() => _pendingTextPos = null);
    }
    _textFocus.unfocus();
  }

  void _resetSelection() {
    setState(() {
      _selection = null;
      _marks.clear();
    });
  }

  Future<String?> _compose() async {
    final image = _image;
    if (image == null) return null;
    setState(() => _compositing = true);
    try {
      final selection = _selection ??
          Rect.fromLTWH(0, 0, _imageSize.width, _imageSize.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(-selection.left, -selection.top);
      canvas.drawImage(image, Offset.zero, Paint());
      _paintMarks(canvas);
      final picture = recorder.endRecording();
      final composed = await picture.toImage(
        selection.width.round(),
        selection.height.round(),
      );
      final byteData =
          await composed.toByteData(format: ui.ImageByteFormat.png);
      composed.dispose();
      if (byteData == null) return null;

      final supportDir = await getApplicationSupportDirectory();
      final imageDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}screenshots',
      );
      await imageDir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final target =
          '${imageDir.path}${Platform.pathSeparator}screenshot_$stamp.png';
      await File(target).writeAsBytes(
        byteData.buffer.asUint8List(),
        flush: true,
      );
      return target;
    } finally {
      if (mounted) setState(() => _compositing = false);
    }
  }

  /// 马赛克格子大小：随笔刷宽度变化，但限制在合理范围内。
  double get _mosaicCellSize => (_width * 4).clamp(14.0, 36.0);

  /// 高亮笔刷宽度：比普通笔画粗得多，营造荧光笔效果。
  double get _highlightWidth => _width * 5;

  /// 从原图 RGBA 缓存采样 (x, y) 处像素颜色。
  Color _samplePixel(int x, int y) {
    final px = _pixels;
    if (px == null) return _color;
    final w = _imageSize.width.round();
    final h = _imageSize.height.round();
    final cx = x.clamp(0, w - 1);
    final cy = y.clamp(0, h - 1);
    final i = (cy * w + cx) * 4;
    return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
  }

  /// 画一个马赛克格子：填充采样色 + 1px 描边，保证“虚化”效果清晰可见
  /// （纯色平滑区域也能看出打码格子）。
  void _paintMosaicCell(
      Canvas canvas, double left, double top, double cellSize) {
    final cell = Rect.fromLTWH(left, top, cellSize, cellSize);
    canvas.drawRect(cell, Paint()..color = _samplePixel(left.round() + 1, top.round() + 1));
    canvas.drawRect(
      cell,
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// 画一条连续的马赛克笔刷：沿路径采样，把经过的每个格子
  /// 用原图像素色块覆盖，实现像素化（打码）效果。
  void _paintMosaicStroke(Canvas canvas, List<Offset> points, double cellSize) {
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final step = cellSize / 2;
    final half = cellSize / 2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += step) {
        final pos = metric.getTangentForOffset(d)!.position;
        final left = (pos.dx - half).floorToDouble();
        final top = (pos.dy - half).floorToDouble();
        _paintMosaicCell(canvas, left, top, cellSize);
      }
    }
  }

  /// 画一条高亮笔刷：半透明粗线。
  void _paintHighlightStroke(Canvas canvas, List<Offset> points) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = _color.withOpacity(0.35)
      ..strokeWidth = _highlightWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _paintMarks(Canvas canvas) {
    for (final mark in _marks) {
      switch (mark) {
        case _ShotStroke():
          final paint = Paint()
            ..color = mark.color
            ..strokeWidth = mark.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          if (mark.points.length == 1) {
            canvas.drawPoints(ui.PointMode.points, mark.points, paint);
          } else {
            final path = Path()..moveTo(mark.points.first.dx, mark.points.first.dy);
            for (final point in mark.points.skip(1)) {
              path.lineTo(point.dx, point.dy);
            }
            canvas.drawPath(path, paint);
          }
        case _ShotHighlight():
          _paintHighlightStroke(canvas, mark.points);
        case _ShotMosaic():
          _paintMosaicStroke(canvas, mark.points, mark.cellSize);
        case _ShotRect():
          canvas.drawRect(
            mark.rect,
            Paint()
              ..color = mark.color
              ..strokeWidth = mark.width
              ..style = PaintingStyle.stroke,
          );
        case _ShotEllipse():
          canvas.drawOval(
            mark.rect,
            Paint()
              ..color = mark.color
              ..strokeWidth = mark.width
              ..style = PaintingStyle.stroke,
          );
        case _ShotArrow():
          _drawArrow(canvas, mark.start, mark.end, mark.color, mark.width);
        case _ShotText():
          final tp = TextPainter(
            text: TextSpan(
              text: mark.text,
              style: TextStyle(
                color: mark.color,
                fontSize: mark.fontSize,
                fontWeight: FontWeight.w600,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 2),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, mark.position);
      }
    }
    // In-progress marks.
    if (_activeStroke.length >= 2) {
      switch (_tool) {
        case _ShotTool.pen:
          final paint = Paint()
            ..color = _color
            ..strokeWidth = _width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          final path = Path()..moveTo(_activeStroke.first.dx, _activeStroke.first.dy);
          for (final point in _activeStroke.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
          canvas.drawPath(path, paint);
        case _ShotTool.highlight:
          _paintHighlightStroke(canvas, _activeStroke);
        case _ShotTool.mosaic:
          _paintMosaicStroke(canvas, _activeStroke, _mosaicCellSize);
        case _ShotTool.text:
        case _ShotTool.rect:
        case _ShotTool.ellipse:
        case _ShotTool.arrow:
          break;
      }
    }
    if (_shapeStart != null && _shapeEnd != null) {
      switch (_tool) {
        case _ShotTool.rect:
          canvas.drawRect(
            Rect.fromPoints(_shapeStart!, _shapeEnd!),
            Paint()
              ..color = _color
              ..strokeWidth = _width
              ..style = PaintingStyle.stroke,
          );
        case _ShotTool.ellipse:
          canvas.drawOval(
            Rect.fromPoints(_shapeStart!, _shapeEnd!),
            Paint()
              ..color = _color
              ..strokeWidth = _width
              ..style = PaintingStyle.stroke,
          );
        case _ShotTool.arrow:
          _drawArrow(canvas, _shapeStart!, _shapeEnd!, _color, _width);
        case _ShotTool.pen:
        case _ShotTool.highlight:
        case _ShotTool.mosaic:
        case _ShotTool.text:
          break;
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
    final angle = (end - start).direction;
    final headLength = (width * 5).clamp(12.0, 26.0);
    final left = end - Offset.fromDirection(angle + 0.45, headLength);
    final right = end - Offset.fromDirection(angle - 0.45, headLength);
    final head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      autofocus: true,
      // 按住 Ctrl：临时进入“自动选择窗口”模式（悬停高亮、单击选中）。
      onKeyEvent: (node, event) {
        final key = event.logicalKey;
        final isCtrl = key == LogicalKeyboardKey.controlLeft ||
            key == LogicalKeyboardKey.controlRight;
        if (isCtrl) {
          final down = event is KeyDownEvent || event is KeyRepeatEvent;
          if (down != _ctrlDown && mounted) {
            setState(() => _ctrlDown = down);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _decodeFailed
              ? _buildFailure(theme)
              : _image == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _layoutImage(constraints.biggest);
                        return Stack(
                          children: <Widget>[
                            // 顶部提示条：拖拽框选，按住 Ctrl 自动选窗口。
                            if (_selection == null)
                              Positioned(
                                top: 10,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white24,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Icon(
                                          _ctrlDown
                                              ? Icons.ads_click_rounded
                                              : Icons.keyboard_control_key_rounded,
                                          size: 15,
                                          color: Colors.white70,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          _ctrlDown
                                              ? translate('Click a window to select it')
                                              : translate(
                                                  'Drag to select area, hold Ctrl to pick a window'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            Positioned.fill(
                            // Listener 只包图片层：拖动/框选在图片上生效，
                            // 底部工具栏与右上按钮不在其子树中，点击不受影响。
                            child: MouseRegion(
                              // 框选阶段显示十字准星光标（微信截图风格），
                              // 选中后恢复默认箭头，方便操作工具条。
                              cursor: _selection == null
                                  ? SystemMouseCursors.precise
                                  : SystemMouseCursors.basic,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: _onPointerDown,
                                onPointerMove: _onPointerMove,
                                onPointerUp: _onPointerUp,
                                onPointerHover: _onPointerHover,
                                onPointerCancel: (event) {
                                  if (event.pointer == _activePointer) {
                                    _activePointer = null;
                                    _drawing = false;
                                    _selectDrag = null;
                                  }
                                },
                                child: CustomPaint(
                                painter: _ScreenshotPainter(
                                  image: _image!,
                                  fitRect: _fitRect,
                                  scale: _scale,
                                  selection: _selection,
                                  selectDrag: _selectDrag,
                                  marks: _marks,
                                  activeStroke: _activeStroke,
                                  shapeStart: _shapeStart,
                                  shapeEnd: _shapeEnd,
                                  tool: _tool,
                                  color: _color,
                                  width: _width,
                                  pixels: _pixels,
                                  imagePixelWidth: _imageSize.width.round(),
                                  imagePixelHeight:
                                      _imageSize.height.round(),
                                  hoverWindow: _hoverWindow,
                                ),
                              ),
                            ),
                            ),
                          ),
                            // Always-visible top-right controls: capture-mode
                            // picker, region size, cancel.
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (_selection != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8),
                                      child: Text(
                                        '${_selection!.width.round()} × '
                                        '${_selection!.height.round()}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  // 模式选择（向下箭头）：矩形框选 / 自动选择窗口。
                                  PopupMenuButton<_ShotMode>(
                                    tooltip: translate('Capture mode'),
                                    // 菜单向上展开，避免超出窗口底部被裁剪。
                                    position: PopupMenuPosition.over,
                                    initialValue: _mode,
                                    onSelected: (mode) => setState(() {
                                      _mode = mode;
                                      _hoverWindow = null;
                                    }),
                                    itemBuilder: (menuContext) =>
                                        <PopupMenuEntry<_ShotMode>>[
                                      PopupMenuItem<_ShotMode>(
                                        value: _ShotMode.region,
                                        child: Row(
                                          children: <Widget>[
                                            const Icon(
                                              Icons.crop_free_rounded,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(translate('Rect region')),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<_ShotMode>(
                                        value: _ShotMode.window,
                                        child: Row(
                                          children: <Widget>[
                                            const Icon(
                                              Icons.web_asset_rounded,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              translate('Select window'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 26,
                                      color: Colors.white,
                                    ),
                                    iconSize: 26,
                                  ),
                                  Material(
                                    color: Colors.black54,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: translate('Cancel'),
                                      onPressed: _compositing
                                          ? null
                                          : () =>
                                              Navigator.of(context).pop(),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 22,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 自动选择窗口模式的悬停提示。
                            if (_mode == _ShotMode.window &&
                                _selection == null)
                              Positioned(
                                top: 60,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    translate(
                                        'Hover to highlight a window, click to select'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            // 文字工具：在图板上直接输入（微信式，无对话框）。
                            if (_pendingTextPos != null)
                              Positioned(
                                top: 12,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Material(
                                    color: Colors.white,
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 340,
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 2, 4, 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Expanded(
                                            child: TextField(
                                              key: const ValueKey<String>(
                                                  'shot-text-field'),
                                              controller: _textController,
                                              focusNode: _textFocus,
                                              autofocus: true,
                                              maxLength: 120,
                                              style: const TextStyle(
                                                  fontSize: 15),
                                              decoration:
                                                  const InputDecoration(
                                                hintText: 'Enter text…',
                                                counterText: '',
                                                border: InputBorder.none,
                                              ),
                                              onSubmitted: (_) =>
                                                  _commitPendingText(),
                                              onTapOutside: (_) =>
                                                  _commitPendingText(),
                                            ),
                                          ),
                                          IconButton(
                                            key: const ValueKey<String>(
                                                'shot-text-done'),
                                            tooltip: translate('Done'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              Icons.check_rounded,
                                              color: Color(0xFF07C160),
                                            ),
                                            onPressed: _commitPendingText,
                                          ),
                                          IconButton(
                                            tooltip: translate('Cancel'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                            onPressed: () => setState(() {
                                              _pendingTextPos = null;
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_selection != null)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: _buildToolbar(theme),
                              ),
                            if (_compositing)
                              Container(
                                color: Colors.black45,
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
        ),
    );
  }

  Widget _buildFailure(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.broken_image_outlined,
              size: 56, color: Colors.white54),
          const SizedBox(height: 14),
          Text(
            translate('Failed to decode the captured screen.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    Widget toolButton(_ShotTool tool, IconData icon, String label) {
      final selected = _tool == tool;
      return InkWell(
        onTap: () => setState(() => _tool = tool),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF07C160) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 21,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2F38) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black38, blurRadius: 14),
        ],
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          // 微信截图风格：撤销/重做固定在工具条最左侧，
          // 紧挨工具图标（微信截图工具条布局一致）。
          IconButton(
            tooltip: translate('Undo'),
            visualDensity: VisualDensity.compact,
            onPressed: _marks.isEmpty
                ? null
                : () => setState(() => _marks.removeLast()),
            icon: const Icon(Icons.undo_rounded, size: 22),
          ),
          IconButton(
            tooltip: translate('Redo selection'),
            visualDensity: VisualDensity.compact,
            onPressed: _resetSelection,
            icon: const Icon(Icons.crop_free_rounded, size: 22),
          ),
          Container(
            width: 1,
            height: 26,
            color: Colors.black12,
          ),
          toolButton(_ShotTool.rect, Icons.crop_square_rounded,
              translate('Rectangle')),
          toolButton(_ShotTool.ellipse, Icons.circle_outlined,
              translate('Ellipse')),
          toolButton(_ShotTool.arrow, Icons.north_east_rounded,
              translate('Arrow')),
          toolButton(_ShotTool.pen, Icons.edit_rounded, translate('Pen')),
          toolButton(_ShotTool.text, Icons.text_fields_rounded,
              translate('Text')),
          toolButton(_ShotTool.mosaic, Icons.grid_view_rounded,
              translate('Mosaic')),
          toolButton(_ShotTool.highlight, Icons.border_color_rounded,
              translate('Highlight')),
          Container(
            width: 1,
            height: 26,
            color: Colors.black12,
          ),
          for (final color in _palette)
            InkWell(
              onTap: () => setState(() => _color = color),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == color
                        ? const Color(0xFF07C160)
                        : Colors.black26,
                    width: _color == color ? 3 : 1,
                  ),
                ),
              ),
            ),
          Container(
            width: 1,
            height: 26,
            color: Colors.black12,
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _compositing
                ? null
                : () async {
                    final path = await _compose();
                    if (path != null && mounted) {
                      Navigator.of(context).pop(path);
                    }
                  },
            icon: const Icon(Icons.check_rounded, size: 18),
            // 工具条确认按钮：完成标注后把图片放入消息输入框（待发送），
            // 用户在输入框点“发送”才真正发出（微信截图流程一致）。
            label: Text(translate('Send')),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF07C160),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotPainter extends CustomPainter {
  _ScreenshotPainter({
    required this.image,
    required this.fitRect,
    required this.scale,
    required this.selection,
    required this.selectDrag,
    required this.marks,
    required this.activeStroke,
    required this.shapeStart,
    required this.shapeEnd,
    required this.tool,
    required this.color,
    required this.width,
    required this.pixels,
    required this.imagePixelWidth,
    required this.imagePixelHeight,
    required this.hoverWindow,
  });

  final ui.Image image;
  final Rect fitRect;
  final double scale;
  final Rect? selection;
  final Rect? selectDrag;
  final List<_ShotMark> marks;
  final List<Offset> activeStroke;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final _ShotTool tool;
  final Color color;
  final double width;
  final Uint8List? pixels;
  final int imagePixelWidth;
  final int imagePixelHeight;
  final ScreenshotWindow? hoverWindow;

  double get _mosaicCellSize => (width * 4).clamp(14.0, 36.0);
  double get _highlightWidth => width * 5;

  Color _samplePixel(int x, int y) {
    final px = pixels;
    if (px == null) return color;
    final cx = x.clamp(0, imagePixelWidth - 1);
    final cy = y.clamp(0, imagePixelHeight - 1);
    final i = (cy * imagePixelWidth + cx) * 4;
    return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
  }

  void _paintMosaicCell(
      Canvas canvas, double left, double top, double cellSize) {
    final cell = Rect.fromLTWH(left, top, cellSize, cellSize);
    canvas.drawRect(
      cell,
      Paint()
        ..color = _samplePixel(left.round() + 1, top.round() + 1),
    );
    canvas.drawRect(
      cell,
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintMosaicStroke(
      Canvas canvas, List<Offset> points, double cellSize) {
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final step = cellSize / 2;
    final half = cellSize / 2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += step) {
        final pos = metric.getTangentForOffset(d)!.position;
        _paintMosaicCell(
          canvas,
          (pos.dx - half).floorToDouble(),
          (pos.dy - half).floorToDouble(),
          cellSize,
        );
      }
    }
  }

  void _paintHighlightStroke(Canvas canvas, List<Offset> points) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = _highlightWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Dim the whole overlay first.
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black54);

    canvas.save();
    canvas.translate(fitRect.left, fitRect.top);
    canvas.scale(scale);

    if (selection == null) {
      // Selecting phase: full image visible, outside-selection dimmed.
      canvas.drawImage(image, Offset.zero, Paint());
      final drag = selectDrag;
      if (drag != null) {
        final dragRect = Rect.fromPoints(
          Offset(drag.left.clamp(0, image.width.toDouble()),
              drag.top.clamp(0, image.height.toDouble())),
          Offset(drag.right.clamp(0, image.width.toDouble()),
              drag.bottom.clamp(0, image.height.toDouble())),
        );
        // 拖拽框选过程中实时生效：选框内亮、选框外变暗（微信式“浮现”）。
        final dimOutside = Path()
          ..addRect(Rect.fromLTWH(
              0, 0, image.width.toDouble(), image.height.toDouble()))
          ..addRect(dragRect)
          ..fillType = PathFillType.evenOdd;
        canvas.drawPath(dimOutside, Paint()..color = Colors.black45);
        canvas.drawRect(
          dragRect,
          Paint()
            ..color = const Color(0x3307C160)
            ..style = PaintingStyle.fill,
        );
        _dashedRect(
          canvas,
          dragRect,
          const Color(0xFF07C160),
          2 / scale,
        );
        _drawSizeLabel(canvas, dragRect);
      } else {
        // 自动选择窗口模式：高亮鼠标所在的窗口。
        final win = hoverWindow;
        if (win != null) {
          final rect = Rect.fromLTWH(
            win.rect.left.clamp(0, image.width.toDouble()),
            win.rect.top.clamp(0, image.height.toDouble()),
            (win.rect.right - win.rect.left)
                .clamp(0, image.width.toDouble() - win.rect.left),
            (win.rect.bottom - win.rect.top)
                .clamp(0, image.height.toDouble() - win.rect.top),
          );
          canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0x2207C160)
              ..style = PaintingStyle.fill,
          );
          _dashedRect(canvas, rect, const Color(0xFF07C160), 2 / scale);
          final label = win.title.isEmpty ? translate('Window') : win.title;
          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final anchor = Offset(rect.left + 4, rect.top + 4);
          canvas.drawRect(
            Rect.fromLTWH(
                anchor.dx, anchor.dy, tp.width + 10, tp.height + 6),
            Paint()..color = const Color(0xCC000000),
          );
          tp.paint(canvas, anchor + const Offset(5, 3));
        }
      }
      canvas.restore();
      return;
    }

    // Annotating phase: show only the selected region, dim the rest.
    canvas.clipRect(selection!);
    canvas.drawImageRect(image, selection!, Offset.zero & selection!.size, Paint());
    canvas.translate(-selection!.left, -selection!.top);
    _paintMarks(canvas);
    canvas.restore();

    // Re-draw the dim overlay for everything outside the selection and the
    // selection border on top (in widget space).
    final selWidget = Rect.fromLTWH(
      fitRect.left + selection!.left * scale,
      fitRect.top + selection!.top * scale,
      selection!.width * scale,
      selection!.height * scale,
    );
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(selWidget)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black45);
    _dashedRect(canvas, selWidget, const Color(0xFF07C160), 2);
  }

  void _paintMarks(Canvas canvas) {
    for (final mark in marks) {
      switch (mark) {
        case _ShotStroke():
          final paint = Paint()
            ..color = mark.color
            ..strokeWidth = mark.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          if (mark.points.length == 1) {
            canvas.drawPoints(ui.PointMode.points, mark.points, paint);
          } else {
            final path = Path()
              ..moveTo(mark.points.first.dx, mark.points.first.dy);
            for (final point in mark.points.skip(1)) {
              path.lineTo(point.dx, point.dy);
            }
            canvas.drawPath(path, paint);
          }
        case _ShotHighlight():
          _paintHighlightStroke(canvas, mark.points);
        case _ShotMosaic():
          _paintMosaicStroke(canvas, mark.points, mark.cellSize);
        case _ShotRect():
          canvas.drawRect(
            mark.rect,
            Paint()
              ..color = mark.color
              ..strokeWidth = mark.width
              ..style = PaintingStyle.stroke,
          );
        case _ShotEllipse():
          canvas.drawOval(
            mark.rect,
            Paint()
              ..color = mark.color
              ..strokeWidth = mark.width
              ..style = PaintingStyle.stroke,
          );
        case _ShotArrow():
          _drawArrow(canvas, mark.start, mark.end, mark.color, mark.width);
        case _ShotText():
          final tp = TextPainter(
            text: TextSpan(
              text: mark.text,
              style: TextStyle(
                color: mark.color,
                fontSize: mark.fontSize,
                fontWeight: FontWeight.w600,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 2),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, mark.position);
      }
    }
    if (activeStroke.length >= 2) {
      switch (tool) {
        case _ShotTool.pen:
          final paint = Paint()
            ..color = color
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          final path = Path()
            ..moveTo(activeStroke.first.dx, activeStroke.first.dy);
          for (final point in activeStroke.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
          canvas.drawPath(path, paint);
        case _ShotTool.highlight:
          _paintHighlightStroke(canvas, activeStroke);
        case _ShotTool.mosaic:
          _paintMosaicStroke(canvas, activeStroke, _mosaicCellSize);
        case _ShotTool.text:
        case _ShotTool.rect:
        case _ShotTool.ellipse:
        case _ShotTool.arrow:
          break;
      }
    }
    if (shapeStart != null && shapeEnd != null) {
      switch (tool) {
        case _ShotTool.rect:
          canvas.drawRect(
            Rect.fromPoints(shapeStart!, shapeEnd!),
            Paint()
              ..color = color
              ..strokeWidth = width
              ..style = PaintingStyle.stroke,
          );
        case _ShotTool.ellipse:
          canvas.drawOval(
            Rect.fromPoints(shapeStart!, shapeEnd!),
            Paint()
              ..color = color
              ..strokeWidth = width
              ..style = PaintingStyle.stroke,
          );
        case _ShotTool.arrow:
          _drawArrow(canvas, shapeStart!, shapeEnd!, color, width);
        case _ShotTool.pen:
        case _ShotTool.highlight:
        case _ShotTool.mosaic:
        case _ShotTool.text:
          break;
      }
    }
  }

  void _drawArrow(
      Canvas canvas, Offset start, Offset end, Color arrowColor, double w) {
    final paint = Paint()
      ..color = arrowColor
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
    final angle = (end - start).direction;
    final headLength = (w * 5).clamp(12.0, 26.0);
    final left = end - Offset.fromDirection(angle + 0.45, headLength);
    final right = end - Offset.fromDirection(angle - 0.45, headLength);
    final head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = arrowColor
        ..style = PaintingStyle.fill,
    );
  }

  void _dashedRect(Canvas canvas, Rect rect, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    const dash = 6.0;
    const gap = 4.0;
    void dashedLine(Offset a, Offset b) {
      final total = (b - a).distance;
      if (total <= 0) return;
      final direction = (b - a) / total;
      var traveled = 0.0;
      while (traveled < total) {
        final end = (traveled + dash).clamp(0.0, total);
        canvas.drawLine(a + direction * traveled, a + direction * end, paint);
        traveled = end + gap;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  void _drawSizeLabel(Canvas canvas, Rect rect) {
    final label = '${rect.width.round()} × ${rect.height.round()}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final anchor = rect.bottomRight + const Offset(8, 8);
    canvas.drawRect(
      Rect.fromLTWH(anchor.dx, anchor.dy, tp.width + 10, tp.height + 6),
      Paint()..color = const Color(0xCC000000),
    );
    tp.paint(canvas, anchor + const Offset(5, 3));
  }

  @override
  bool shouldRepaint(_ScreenshotPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.fitRect != fitRect ||
      oldDelegate.scale != scale ||
      oldDelegate.selection != selection ||
      oldDelegate.selectDrag != selectDrag ||
      oldDelegate.marks.length != marks.length ||
      oldDelegate.activeStroke.length != activeStroke.length ||
      oldDelegate.shapeStart != shapeStart ||
      oldDelegate.shapeEnd != shapeEnd ||
      oldDelegate.tool != tool ||
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.pixels != pixels ||
      oldDelegate.hoverWindow?.hwnd != hoverWindow?.hwnd;
}
