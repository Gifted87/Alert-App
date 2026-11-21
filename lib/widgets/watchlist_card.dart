import 'package:flutter/material.dart';

import '../models/market_models.dart';
import '../theme/app_theme.dart';

class WatchlistCard extends StatefulWidget {
  final BiquoteTick tick;
  final bool isSelected;
  final VoidCallback onTap;

  const WatchlistCard({
    super.key,
    required this.tick,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<WatchlistCard> createState() => _WatchlistCardState();
}

class _WatchlistCardState extends State<WatchlistCard> {
  Color? _flashColor;

  @override
  void didUpdateWidget(WatchlistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick.mid != oldWidget.tick.mid) {
      final isUp = widget.tick.mid > oldWidget.tick.mid;
      setState(() {
        _flashColor = (isUp ? AppTheme.darkBullish : AppTheme.darkBearish)
            .withValues(alpha: 0.25);
      });
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          setState(() {
            _flashColor = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tick = widget.tick;
    final isBullish = tick.dayDiffPercent >= 0;
    final trendColor = isBullish
        ? (isDark ? AppTheme.darkBullish : AppTheme.lightBullish)
        : (isDark ? AppTheme.darkBearish : AppTheme.lightBearish);

    final displayPair = _formatPair(tick.symbol);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 180,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              _flashColor ??
              (widget.isSelected
                  ? (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2)
                  : (isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected
                ? theme.colorScheme.primary
                : theme.dividerColor,
            width: widget.isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top: Symbol and % Change
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    displayPair,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${isBullish ? '+' : ''}${tick.dayDiffPercent.toStringAsFixed(2)}%',
                    style: AppTheme.mono(
                      context: context,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: trendColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Center: Mini Sparkline
            SizedBox(
              height: 22,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(
                  isBullish: isBullish,
                  color: trendColor,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Bottom: Mid & Spread Stack
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    tick.mid > 0
                        ? tick.mid.toStringAsFixed(tick.precision)
                        : '--',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      context: context,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  tick.mid > 0
                      ? '${(tick.spread * (tick.precision == 3 ? 100 : (tick.precision == 5 ? 10000 : 1))).toStringAsFixed(1)}p'
                      : '--',
                  style: AppTheme.mono(
                    context: context,
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPair(String s) {
    if (s.length == 6) {
      return '${s.substring(0, 3)}/${s.substring(3)}';
    }
    return s;
  }
}

class _SparklinePainter extends CustomPainter {
  final bool isBullish;
  final Color color;

  _SparklinePainter({required this.isBullish, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final points = isBullish
        ? [
            Offset(0, size.height * 0.8),
            Offset(size.width * 0.2, size.height * 0.65),
            Offset(size.width * 0.4, size.height * 0.75),
            Offset(size.width * 0.6, size.height * 0.35),
            Offset(size.width * 0.8, size.height * 0.45),
            Offset(size.width, size.height * 0.15),
          ]
        : [
            Offset(0, size.height * 0.2),
            Offset(size.width * 0.2, size.height * 0.35),
            Offset(size.width * 0.4, size.height * 0.25),
            Offset(size.width * 0.6, size.height * 0.65),
            Offset(size.width * 0.8, size.height * 0.55),
            Offset(size.width, size.height * 0.85),
          ];

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.isBullish != isBullish || oldDelegate.color != color;
  }
}
