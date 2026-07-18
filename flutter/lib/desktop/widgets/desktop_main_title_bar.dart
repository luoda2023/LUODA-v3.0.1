import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../common/wechat_ui_tokens.dart';

final ValueNotifier<bool> _mainWindowAlwaysOnTop = ValueNotifier<bool>(false);

class LDeskMainTitleBar extends StatelessWidget {
  static const double height = 40;
  static const String brandName = 'LDesk';

  final String title;
  final bool showPin;
  final bool showMinimize;
  final bool showMaximize;
  final bool showClose;
  final bool canMaximize;
  final VoidCallback? onBack;

  const LDeskMainTitleBar({
    super.key,
    required this.title,
    this.showPin = true,
    this.showMinimize = true,
    this.showMaximize = true,
    this.showClose = true,
    this.canMaximize = true,
    this.onBack,
  });

  Future<void> _toggleMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
      stateGlobal.setMaximized(false);
    } else {
      await windowManager.maximize();
      stateGlobal.setMaximized(true);
    }
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !await windowManager.isAlwaysOnTop();
    await windowManager.setAlwaysOnTop(next);
    _mainWindowAlwaysOnTop.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF202225) : kWeChatChromeColor;
    final secondaryText =
        dark ? const Color(0xFFA8AAAE) : const Color(0xFF666666);
    final hover = dark ? const Color(0xFF303236) : const Color(0xFFD6D6DB);
    final usesSystemTitleBar = kUseCompatibleUiMode;

    final dragArea = Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: !usesSystemTitleBar && canMaximize && showMaximize
            ? _toggleMaximized
            : null,
        onPanStart:
            usesSystemTitleBar ? null : (_) => windowManager.startDragging(),
        onPanCancel: !isMacOS
            ? null
            : () {
                windowManager.setMovable(false);
              },
        onPanEnd: !isMacOS
            ? null
            : (_) {
                windowManager.setMovable(false);
              },
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: '$brandName $title',
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Row(
        children: [
          if (isMacOS) const SizedBox(width: 78),
          if (onBack != null)
            _TitleBarButton(
              tooltip: translate('Back'),
              icon: Icons.arrow_back_rounded,
              foreground: secondaryText,
              hover: hover,
              onPressed: onBack,
            ),
          dragArea,
          if (showPin)
            ValueListenableBuilder<bool>(
              valueListenable: _mainWindowAlwaysOnTop,
              builder: (context, pinned, _) => _TitleBarButton(
                tooltip: translate(pinned ? 'Unpin' : 'Pin'),
                icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                foreground: pinned
                    ? Theme.of(context).colorScheme.primary
                    : secondaryText,
                hover: hover,
                onPressed: _toggleAlwaysOnTop,
              ),
            ),
          if (!usesSystemTitleBar && !isMacOS) ...[
            if (showMinimize)
              _TitleBarButton(
                tooltip: translate('Minimize'),
                icon: Icons.remove_rounded,
                foreground: secondaryText,
                hover: hover,
                onPressed: () => windowManager.minimize(),
              ),
            if (showMaximize)
              Obx(
                () => _TitleBarButton(
                  tooltip: stateGlobal.isMaximized.isTrue
                      ? translate('Restore')
                      : translate('Maximize'),
                  icon: stateGlobal.isMaximized.isTrue
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  foreground: canMaximize
                      ? secondaryText
                      : secondaryText.withOpacity(0.38),
                  hover: hover,
                  onPressed: canMaximize ? _toggleMaximized : null,
                ),
              ),
            if (showClose)
              _TitleBarButton(
                tooltip: translate('Close'),
                icon: Icons.close_rounded,
                foreground: secondaryText,
                hover: const Color(0xFFE81123),
                hoverForeground: Colors.white,
                onPressed: () => windowManager.close(),
              ),
          ],
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color foreground;
  final Color hover;
  final Color? hoverForeground;
  final VoidCallback? onPressed;

  const _TitleBarButton({
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.hover,
    required this.onPressed,
    this.hoverForeground,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      style: ButtonStyle(
        fixedSize: MaterialStateProperty.all(
          const Size(46, LDeskMainTitleBar.height - 1),
        ),
        minimumSize: MaterialStateProperty.all(Size.zero),
        padding: MaterialStateProperty.all(EdgeInsets.zero),
        shape: MaterialStateProperty.all(
          const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        backgroundColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.hovered)) return hover;
          if (states.contains(MaterialState.focused)) {
            return hover.withOpacity(0.6);
          }
          if (states.contains(MaterialState.pressed)) {
            return hover.withOpacity(0.75);
          }
          return Colors.transparent;
        }),
        foregroundColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.hovered) &&
              hoverForeground != null) {
            return hoverForeground;
          }
          return foreground;
        }),
      ),
    );
  }
}
