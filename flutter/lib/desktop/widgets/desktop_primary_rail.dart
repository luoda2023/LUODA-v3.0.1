import 'package:flutter/material.dart';

import '../../common.dart';

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
    this.onMore,
  });

  static const double width = 76;

  final List<DesktopRailDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onSettings;
  final bool settingsSelected;
  final Widget? avatar;
  final VoidCallback? onAvatarPressed;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF24262B) : null,
        gradient: dark
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFF0D1D2),
                  Color(0xFFE7E6EA),
                  Color(0xFFD9D9E1),
                ],
              ),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 14),
          Tooltip(
            message: translate('Account'),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAvatarPressed,
              child: SizedBox(
                width: 44,
                height: 44,
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
          const SizedBox(height: 14),
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
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          _RailButton(
            destination: const DesktopRailDestination(
              id: 'settings',
              label: 'Settings',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
            ),
            selected: settingsSelected,
            onTap: onSettings,
          ),
          _RailButton(
            destination: const DesktopRailDestination(
              id: 'more',
              label: 'More',
              icon: Icons.menu_rounded,
            ),
            selected: false,
            onTap: onMore,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DesktopRailDestination destination;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
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
          child: SizedBox(
            width: 48,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(
                  selected
                      ? destination.selectedIcon ?? destination.icon
                      : destination.icon,
                  size: 24,
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
