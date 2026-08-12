import 'package:flutter/material.dart';

class PeerTabStrip extends StatelessWidget {
  const PeerTabStrip({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
    this.visibleIndexes,
    this.showLabels = false,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;
  final List<int>? visibleIndexes;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final indexes = visibleIndexes ?? List.generate(icons.length, (i) => i);
    final tabTheme = Theme.of(context).tabBarTheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: indexes.map((index) {
          final selected = selectedIndex == index;
          final indicatorColor = Theme.of(context).colorScheme.primary;
          final unselectedColor =
              (tabTheme.unselectedLabelColor ?? Colors.grey).withOpacity(0.72);
          return Semantics(
            button: true,
            selected: selected,
            label: labels[index],
            child: Tooltip(
              message: labels[index],
              preferBelow: false,
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: showLabels ? 68 : 42,
                  height: showLabels ? 48 : 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: selected ? 2 : 0,
                        color: selected ? indicatorColor : Colors.transparent,
                      ),
                    ),
                  ),
                  child: showLabels
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              icons[index],
                              size: 19,
                              color:
                                  selected ? indicatorColor : unselectedColor,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color:
                                    selected ? indicatorColor : unselectedColor,
                              ),
                            ),
                          ],
                        )
                      : Icon(
                          icons[index],
                          size: 20,
                          color: selected ? indicatorColor : unselectedColor,
                        ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
