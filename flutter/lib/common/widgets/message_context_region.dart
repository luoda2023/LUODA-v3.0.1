import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class MessageContextRegion extends StatelessWidget {
  const MessageContextRegion({
    super.key,
    required this.child,
    required this.onSecondaryTap,
  });

  final Widget child;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons & kSecondaryMouseButton != 0) {
          onSecondaryTap(event.position);
        }
      },
      child: child,
    );
  }
}
