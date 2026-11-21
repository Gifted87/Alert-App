import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RateDisplay extends StatelessWidget {
  final double rate;
  final int digits;
  final double fontSize;
  final Color? color;
  final bool isBold;

  const RateDisplay({
    super.key,
    required this.rate,
    this.digits = 5,
    this.fontSize = 28,
    this.color,
    this.isBold = true,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = rate.toStringAsFixed(digits);
    if (formatted.length <= 1 || !formatted.contains('.')) {
      return Text(
        formatted,
        style: AppTheme.mono(
          context: context,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      );
    }

    // Split the stem and the last pipette digit
    final stem = formatted.substring(0, formatted.length - 1);
    final pipette = formatted.substring(formatted.length - 1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stem,
          style: AppTheme.mono(
            context: context,
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
        Transform.translate(
          offset: Offset(1, -fontSize * 0.22),
          child: Text(
            pipette,
            style: AppTheme.mono(
              context: context,
              fontSize: fontSize * 0.55,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
