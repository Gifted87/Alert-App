import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TimeframeSelector extends StatelessWidget {
  final String selectedTimeframe;
  final ValueChanged<String> onSelected;

  static const List<String> timeframes = [
    '1M',
    '5M',
    '15M',
    '30M',
    '1H',
    '4H',
    '1D',
  ];

  const TimeframeSelector({
    super.key,
    required this.selectedTimeframe,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: timeframes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tf = timeframes[index];
          final isSelected = tf == selectedTimeframe;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(tf),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  999,
                ), // pill shape per Stitch spec
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Center(
                child: Text(
                  tf,
                  style: AppTheme.mono(
                    context: context,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
