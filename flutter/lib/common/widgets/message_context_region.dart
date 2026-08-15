import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 消息上下文手势区域：
/// - 桌面端：鼠标右键（onSecondaryTap）
/// - 移动端：长按（onLongPress）
/// - 多选模式：普通点击 / Ctrl+点击 / Shift+点击（onTap）
/// 右键与长按触发消息操作菜单（撤回/销毁/转发/复制等）。
class MessageContextRegion extends StatelessWidget {
  const MessageContextRegion({
    super.key,
    required this.child,
    required this.onSecondaryTap,
    this.onLongPress,
    this.onTap,
  });

  final Widget child;
  final ValueChanged<Offset> onSecondaryTap;
  final ValueChanged<Offset>? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons & kSecondaryMouseButton != 0) {
          onSecondaryTap(event.position);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        onLongPressStart: onLongPress == null
            ? null
            : (details) => onLongPress!(details.globalPosition),
        child: child,
      ),
    );
  }
}
