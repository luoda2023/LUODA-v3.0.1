// Windows 顶层窗口扫描（截图"自动选择窗口"模式专用）。
//
// 用 Win32 API（dart:ffi + win32 包）枚举当前桌面上的可见顶层窗口，
// 供截图标注器在"自动选择窗口"模式下：鼠标悬停时高亮所在窗口、
// 单击选中整个窗口区域。所有坐标均为物理像素（与全屏截图一一对应）。

import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 一个可见的顶层窗口。
class ScreenshotWindow {
  const ScreenshotWindow({
    required this.hwnd,
    required this.rect,
    required this.title,
  });

  /// 窗口句柄。
  final int hwnd;

  /// 窗口在屏幕上的物理像素矩形。
  final Rect rect;

  /// 窗口标题（可能为空）。
  final String title;
}

/// 当前前台窗口句柄（截图标注器所在窗口，自动选窗口时需排除）。
int foregroundWindowHandle() => GetForegroundWindow();

/// 从当前前台窗口的 client 区域原点到屏幕左上角的物理像素偏移。
///
/// Flutter 的指针坐标是相对 client 区域的逻辑像素，乘以 devicePixelRatio
/// 再叠加这个偏移，就能得到屏幕物理坐标（与全屏截图同一坐标系）。
Rect clientOriginOnScreen() {
  final hwnd = GetForegroundWindow();
  final origin = _clientOrigin(hwnd);
  return origin;
}

Rect _clientOrigin(int hwnd) {
  if (hwnd == 0) return Rect.zero;
  final clientRect = calloc<RECT>();
  final pt = calloc<POINT>();
  try {
    GetClientRect(hwnd, clientRect);
    pt.ref
      ..x = 0
      ..y = 0;
    ClientToScreen(hwnd, pt);
    return Rect.fromLTWH(
      pt.ref.x.toDouble(),
      pt.ref.y.toDouble(),
      clientRect.ref.right.toDouble() - clientRect.ref.left.toDouble(),
      clientRect.ref.bottom.toDouble() - clientRect.ref.top.toDouble(),
    );
  } finally {
    calloc.free(clientRect);
    calloc.free(pt);
  }
}

/// 把 Flutter 指针的本地逻辑坐标换算为屏幕物理坐标。
Offset localToScreenPhysical(Offset localLogical, double devicePixelRatio) {
  final origin = clientOriginOnScreen();
  return Offset(
    origin.left + localLogical.dx * devicePixelRatio,
    origin.top + localLogical.dy * devicePixelRatio,
  );
}

/// 枚举所有可见的顶层应用窗口（跳过不可见、最小化、工具窗口、
/// 以及被其他窗口拥有的对话框/弹出层）。
///
/// 返回顺序为 z 序（最上层在前），与 [EnumWindows] 的枚举顺序一致。
List<ScreenshotWindow> scanVisibleWindows({int? excludeHwnd}) {
  final result = <ScreenshotWindow>[];
  final callback = Pointer.fromFunction<WNDENUMPROC>(_enumProc, 0);
  EnumWindows(callback, 0);
  final list = _collected;
  _collected = null;
  if (list == null) return result;
  for (final info in list) {
    if (excludeHwnd != null && info.hwnd == excludeHwnd) continue;
    result.add(info);
  }
  return result;
}

// EnumWindows 回调必须保持顶层（不能被 GC），用静态函数 + 静态收集列表。
List<ScreenshotWindow>? _collected;

int _enumProc(int hwnd, int lParam) {
  final list = _collected ??= <ScreenshotWindow>[];
  if (IsWindowVisible(hwnd) == 0) return 1;
  if (IsIconic(hwnd) != 0) return 1; // 最小化
  final exStyle = GetWindowLongPtr(hwnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
  if (exStyle & WINDOW_EX_STYLE.WS_EX_TOOLWINDOW != 0) return 1; // 工具窗口（托盘等）
  if (GetWindow(hwnd, GET_WINDOW_CMD.GW_OWNER) != 0) return 1; // 被拥有的对话框
  final rect = _windowRect(hwnd);
  if (rect == null || rect.width < 20 || rect.height < 20) return 1;
  list.add(ScreenshotWindow(
    hwnd: hwnd,
    rect: rect,
    title: _windowTitle(hwnd),
  ));
  return 1; // 继续枚举
}

Rect? _windowRect(int hwnd) {
  final rect = calloc<RECT>();
  try {
    if (GetWindowRect(hwnd, rect) == 0) return null;
    return Rect.fromLTRB(
      rect.ref.left.toDouble(),
      rect.ref.top.toDouble(),
      rect.ref.right.toDouble(),
      rect.ref.bottom.toDouble(),
    );
  } finally {
    calloc.free(rect);
  }
}

String _windowTitle(int hwnd) {
  final len = GetWindowTextLength(hwnd);
  if (len <= 0) return '';
  final buf = calloc<Uint16>(len + 1);
  try {
    GetWindowText(hwnd, buf.cast<Utf16>(), len + 1);
    return buf.cast<Utf16>().toDartString();
  } finally {
    calloc.free(buf);
  }
}

/// 返回包含 [screenPhysical] 点的最上层窗口；没有则返回 null。
ScreenshotWindow? windowAtPoint(
  Offset screenPhysical, {
  int? excludeHwnd,
}) {
  for (final w in scanVisibleWindows(excludeHwnd: excludeHwnd)) {
    if (w.rect.contains(screenPhysical)) return w;
  }
  return null;
}
