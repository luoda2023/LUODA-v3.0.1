import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 消息上下文手势区域：
/// - 桌面端：鼠标右键（onSecondaryTap）
/// - 移动端：长按（onLongPress）
/// 两者都触发消息操作菜单（撤回/销毁/转发/复制等）。
class MessageContextRegion extends StatelessWidget {
  const MessageContextRegion({
    super.key,
    required this.child,
    required this.onSecondaryTap,
    this.onLongPress,
  });

  final Widget child;
  final ValueChanged<Offset> onSecondaryTap;
  final ValueChanged<Offset>? onLongPress;

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
        onLongPressStart: onLongPress == null
            ? null
            : (details) => onLongPress!(details.globalPosition),
        child: child,
      ),
    );
  }
}
