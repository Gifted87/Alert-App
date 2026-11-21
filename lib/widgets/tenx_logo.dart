import 'package:flutter/material.dart';

/// Abstract, modern vector-painted TenX app logo.
/// Features dual glowing precision geometric chevrons intersecting to form an abstract 'X'.
class TenXLogo extends StatelessWidget {
  final double size;
  final bool showGlow;

  const TenXLogo({super.key, this.size = 48, this.showGlow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF131B2E), Color(0xFF0A0E18)],
        ),
        border: Border.all(color: const Color(0xFF2B3A5A), width: 1.2),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                  blurRadius: size * 0.35,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.62, size * 0.62),
          painter: _TenXAbstractPainter(),
        ),
      ),
    );
  }
}

class _TenXAbstractPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Stroke width proportional to size
    final strokeWidth = w * 0.18;

    // First diagonal blade: Top-Left to Bottom-Right (Electric Blue -> Cyan)
    final paint1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF00E5FF), Color(0xFF0066FF)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Path 1: dynamic chevron slash
    final path1 = Path();
    path1.moveTo(w * 0.12, h * 0.12);
    path1.lineTo(w * 0.88, h * 0.88);
    canvas.drawPath(path1, paint1);

    // Second diagonal blade: Top-Right to Bottom-Left (Purple -> Fuchsia)
    final paint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFC084FC), Color(0xFF7C3AED)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Path 2: intersecting chevron slash
    final path2 = Path();
    path2.moveTo(w * 0.88, h * 0.12);
    path2.lineTo(w * 0.12, h * 0.88);
    canvas.drawPath(path2, paint2);

    // Glowing core pip in the geometric intersection center
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w / 2, h / 2), strokeWidth * 0.45, corePaint);

    final glowPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(w / 2, h / 2), strokeWidth * 0.75, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
