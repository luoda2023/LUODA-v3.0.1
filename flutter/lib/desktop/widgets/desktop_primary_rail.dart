import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    this.iconAssetPath,
    this.selectedIconAssetPath,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final int? badge;
  // When provided the rail renders this asset (SVG/PNG) instead of [icon].
  final String? iconAssetPath;
  final String? selectedIconAssetPath;
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
    this.pairPhoneBound = false,
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

  /// 手机是否已绑定。未绑定时在左下角手机图标上显示绿色“未绑定”气泡。
  final bool pairPhoneBound;

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
                  destination: DesktopRailDestination(
                    id: 'pair-phone',
                    label: translate('Pair phone'),
                    icon: Icons.phone_android_rounded,
                  ),
                  selected: false,
                  onTap: onPairPhone,
                  imageBackground: hasBackground,
                  // 未绑定时：绿色“未绑定”气泡（微信风格提示）。
                  badgeLabel: pairPhoneBound ? null : translate('Not bound'),
                  badgeColor: const Color(0xFF07C160),
                ),
              _RailButton(
                destination: DesktopRailDestination(
                  id: 'settings',
                  label: translate('Settings'),
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                ),
                selected: settingsSelected,
                onTap: onSettings,
                imageBackground: hasBackground,
              ),
              if (onMore != null)
                _RailButton(
                  destination: DesktopRailDestination(
                    id: 'more',
                    label: translate('More'),
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
    this.badgeLabel,
    this.badgeColor,
  });

  final DesktopRailDestination destination;
  final bool selected;
  final bool imageBackground;
  final VoidCallback? onTap;

  /// 文字气泡（如“未绑定”）。右对齐贴 rail 右缘，不超出左侧边框。
  final String? badgeLabel;
  final Color? badgeColor;

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
                _buildRailIcon(
                  destination: destination,
                  selected: selected,
                  foreground: foreground,
                ),
                if (badgeLabel != null)
                  // 文字气泡（如“未绑定”）：右对齐贴 rail 右缘，不超左边界。
                  Positioned(
                    right: 2,
                    top: 0,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badgeColor ?? const Color(0xFF07C160),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        badgeLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  )
                else if ((destination.badge ?? 0) > 0)
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


/// Renders the rail icon. Prefers an asset (SVG/PNG) when [DesktopRailDestination.iconAssetPath]
/// is supplied, otherwise falls back to the Material [IconData] so existing
/// destinations keep working.
Widget _buildRailIcon({
  required DesktopRailDestination destination,
  required bool selected,
  required Color foreground,
}) {
  final assetPath =
      selected ? (destination.selectedIconAssetPath ?? destination.iconAssetPath) : destination.iconAssetPath;
  if (assetPath != null && assetPath.isNotEmpty) {
    if (assetPath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        assetPath,
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
      );
    }
    return Image.asset(
      assetPath,
      width: 28,
      height: 28,
      color: foreground,
    );
  }
  return Icon(
    selected ? destination.selectedIcon ?? destination.icon : destination.icon,
    size: 28,
    color: foreground,
  );
}