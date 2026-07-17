import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:window_manager/window_manager.dart';

class LDeskMainTitleBar extends StatelessWidget {
  static const double height = 44;

  final String title;
  final bool showThemeToggle;
  final bool showMinimize;
  final bool showMaximize;
  final bool showClose;
  final bool canMaximize;
  final VoidCallback? onBack;

  const LDeskMainTitleBar({
    super.key,
    required this.title,
    this.showThemeToggle = true,
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF202225) : const Color(0xFFF7F7F7);
    final divider = dark ? const Color(0xFF34373C) : const Color(0xFFE5E5E7);
    final primaryText =
        dark ? const Color(0xFFF2F2F2) : const Color(0xFF191919);
    final secondaryText =
        dark ? const Color(0xFFA8AAAE) : const Color(0xFF666666);
    final hover = dark ? const Color(0xFF303236) : const Color(0xFFECECED);
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
            SizedBox(width: onBack == null ? 14 : 4),
            loadIcon(22),
            const SizedBox(width: 8),
            Text(
              'LDesk',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: primaryText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: divider,
            ),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: divider, width: 1)),
      ),
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
          if (showThemeToggle)
            _TitleBarButton(
              tooltip: MyTheme.currentThemeMode() == ThemeMode.dark
                  ? translate('Switch to Light')
                  : translate('Switch to Dark'),
              icon: MyTheme.currentThemeMode() == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              foreground: secondaryText,
              hover: hover,
              onPressed: () {
                final isDark = MyTheme.currentThemeMode() == ThemeMode.dark;
                MyTheme.changeDarkMode(
                  isDark ? ThemeMode.light : ThemeMode.dark,
                );
              },
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
