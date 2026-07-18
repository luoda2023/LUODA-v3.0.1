import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/wechat_ui_tokens.dart';
import '../../models/platform_model.dart';

const String kDesktopRailBackgroundOption = 'desktop-rail-background-image-v1';
const Color kDesktopRailSelectedForeground = Color(0xFF057A3A);
final ValueNotifier<int> desktopRailBackgroundRevision = ValueNotifier<int>(0);

Uint8List? decodeDesktopRailBackground(String value) {
  final separator = value.indexOf(',');
  final payload = separator < 0 ? value : value.substring(separator + 1);
  if (payload.isEmpty) return null;
  try {
    return base64Decode(payload);
  } on FormatException {
    return null;
  }
}

Uint8List? desktopRailBackgroundBytes() => decodeDesktopRailBackground(
      bind.mainGetLocalOption(key: kDesktopRailBackgroundOption),
    );

BoxDecoration desktopRailBackgroundDecoration(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final backgroundBytes = desktopRailBackgroundBytes();
  return BoxDecoration(
    color: backgroundBytes != null
        ? const Color(0xFF24262B)
        : dark
            ? const Color(0xFF24262B)
            : kWeChatChromeColor,
    image: backgroundBytes == null
        ? null
        : DecorationImage(
            image: MemoryImage(backgroundBytes),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            colorFilter: const ColorFilter.mode(
              Color(0x80000000),
              BlendMode.darken,
            ),
          ),
  );
}

class DesktopRailDestination {
  const DesktopRailDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badge,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final int? badge;
}

class DesktopPrimaryRail extends StatelessWidget {
  const DesktopPrimaryRail({
    super.key,
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
    required this.onSettings,
    this.settingsSelected = false,
    this.avatar,
    this.onAvatarPressed,
    this.onPairPhone,
    this.onMore,
  });

  static const double width = kWeChatDesktopRailWidth;

  final List<DesktopRailDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onSettings;
  final bool settingsSelected;
  final Widget? avatar;
  final VoidCallback? onAvatarPressed;
  final VoidCallback? onPairPhone;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: desktopRailBackgroundRevision,
      builder: (context, _, __) {
        final hasBackground = desktopRailBackgroundBytes() != null;
        return Container(
          width: width,
          decoration: desktopRailBackgroundDecoration(context),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Tooltip(
                message: translate('Account'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onAvatarPressed,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: avatar ??
                          Image.asset(
                            'assets/avatar.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: Theme.of(context).colorScheme.primary,
                              child: const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: destinations
                        .map(
                          (destination) => _RailButton(
                            destination: destination,
                            selected: destination.id == selectedId,
                            onTap: () => onSelected(destination.id),
                            imageBackground: hasBackground,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              if (onPairPhone != null)
                _RailButton(
                  destination: const DesktopRailDestination(
                    id: 'pair-phone',
                    label: '绑定手机',
                    icon: Icons.phone_android_rounded,
                  ),
                  selected: false,
                  onTap: onPairPhone,
                  imageBackground: hasBackground,
                ),
              _RailButton(
                destination: const DesktopRailDestination(
                  id: 'settings',
                  label: '设置',
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                ),
                selected: settingsSelected,
                onTap: onSettings,
                imageBackground: hasBackground,
              ),
              _RailButton(
                destination: const DesktopRailDestination(
                  id: 'more',
                  label: '更多',
                  icon: Icons.menu_rounded,
                ),
                selected: false,
                onTap: onMore,
                imageBackground: hasBackground,
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.destination,
    required this.selected,
    required this.imageBackground,
    required this.onTap,
  });

  final DesktopRailDestination destination;
  final bool selected;
  final bool imageBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = imageBackground
        ? selected
            ? kDesktopRailSelectedForeground
            : Colors.white.withOpacity(0.88)
        : selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withOpacity(0.58);
    return Tooltip(
      message: translate(destination.label),
      waitDuration: const Duration(milliseconds: 350),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutQuart,
            width: kWeChatDesktopRailButtonSize,
            height: 42,
            decoration: BoxDecoration(
              color: imageBackground && selected
                  ? Colors.white.withOpacity(0.94)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(
                  selected
                      ? destination.selectedIcon ?? destination.icon
                      : destination.icon,
                  size: 22,
                  color: foreground,
                ),
                if ((destination.badge ?? 0) > 0)
                  Positioned(
                    right: 5,
                    top: 3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFA5151),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        destination.badge! > 99
                            ? '99+'
                            : destination.badge.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
