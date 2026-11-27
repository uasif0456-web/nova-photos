/// The NOVA mark as a widget — the same geometric nova burst as the
/// launcher icon, drawn with Flutter primitives (no image asset needed
/// for in-app use).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Eight-point nova star with three aurora arcs, on a rounded indigo tile.
class NovaLogo extends StatelessWidget {
  const NovaLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _NovaLogoPainter()),
    );
  }
}

class _NovaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final unit = size.width;
    final tileRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(unit * 0.22),
    );

    // Tile.
    canvas.drawRRect(tileRect, Paint()..color = NovaColors.indigoDeep);

    canvas.save();
    canvas.clipRRect(tileRect);

    // Aurora arcs (violet -> teal -> rose).
    final arcColors = [
      NovaColors.violet,
      NovaColors.auroraTeal,
      NovaColors.auroraRose,
    ];
    for (var i = 0; i < 3; i++) {
      final radius = unit * (0.30 + i * 0.075);
      final paint = Paint()
        ..color = arcColors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.022;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        3.4, // ~195 deg
        2.6, // ~150 deg sweep
        false,
        paint,
      );
    }

    // Glow behind the star.
    final glowPaint = Paint()
      ..color = NovaColors.violet.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.06);
    canvas.drawCircle(center, unit * 0.16, glowPaint);

    // Eight-point star, white with a violet core.
    canvas.drawPath(
      Path()..addPolygon(_starPoints(center, unit * 0.155, unit * 0.052), true),
      Paint()..color = Colors.white,
    );
    canvas.drawPath(
      Path()..addPolygon(_starPoints(center, unit * 0.085, unit * 0.030), true),
      Paint()..color = NovaColors.violetLight,
    );
    canvas.restore();
  }

  List<Offset> _starPoints(Offset center, double outer, double inner) {
    final points = <Offset>[];
    for (var i = 0; i < 16; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 8;
      points.add(Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      ));
    }
    return points;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
