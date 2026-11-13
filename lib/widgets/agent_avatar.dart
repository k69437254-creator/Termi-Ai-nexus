import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/nexus_theme.dart';
import '../models/domain.dart';

/// Compact, non-human holographic portrait for each specialist agent.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({super.key, required this.agent, this.size = 48});

  final AgentProfile agent;
  final double size;

  Color get _color => switch (agent.role) {
        AgentRole.manager => NexusPalette.primary,
        AgentRole.architect => NexusPalette.purple,
        AgentRole.developer => NexusPalette.emerald,
        AgentRole.qa => NexusPalette.amber,
        AgentRole.security => NexusPalette.crimson,
      };

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: '${agent.name}: ${agent.description}',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _color.withValues(alpha: 0.26),
                const Color(0xFF111426),
                const Color(0xFF070A13),
              ],
              stops: const [0, 0.58, 1],
            ),
            border: Border.all(color: _color.withValues(alpha: 0.58), width: 1.1),
            boxShadow: [
              BoxShadow(color: _color.withValues(alpha: 0.22), blurRadius: size * 0.34),
            ],
          ),
          child: CustomPaint(painter: _AgentAvatarPainter(agent.role, _color)),
        ),
      );
}

class _AgentAvatarPainter extends CustomPainter {
  const _AgentAvatarPainter(this.role, this.color);

  final AgentRole role;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final u = math.min(size.width, size.height);
    final r = u * 0.30;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.11);
    canvas.drawCircle(c, r * 0.9, glow);

    final line = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, u * 0.026)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fine = Paint()
      ..color = color.withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, u * 0.014)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final core = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, color, color.withValues(alpha: 0.32)],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.72));

    switch (role) {
      case AgentRole.manager:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.55);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 3.0, height: r * 1.05), line);
        canvas.restore();
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(0.55);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 3.0, height: r * 1.05), fine);
        canvas.restore();
        canvas.drawCircle(c, r * 0.48, core);
        for (final a in [0.35, 2.45, 4.45]) {
          final p = c + Offset(math.cos(a) * r * 1.38, math.sin(a) * r * 0.72);
          canvas.drawCircle(p, u * 0.035, Paint()..color = Colors.white);
        }
        break;

      case AgentRole.architect:
        final top = c + Offset(0, -r * 1.12);
        final right = c + Offset(r * 1.0, -r * 0.42);
        final bottom = c + Offset(0, r * 0.22);
        final left = c + Offset(-r * 1.0, -r * 0.42);
        final prism = Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(right.dx, right.dy)
          ..lineTo(bottom.dx, bottom.dy)
          ..lineTo(left.dx, left.dy)
          ..close();
        canvas.drawPath(prism, line);
        canvas.drawLine(top, c + Offset(0, r * 1.05), line);
        canvas.drawLine(left, c + Offset(0, r * 1.05), fine);
        canvas.drawLine(right, c + Offset(0, r * 1.05), fine);
        canvas.drawLine(c + Offset(-r * 0.72, r * 0.12), c + Offset(r * 0.72, r * 0.12), fine);
        canvas.drawLine(c + Offset(-r * 0.82, r * 0.62), c + Offset(r * 0.82, r * 0.62), fine);
        break;

      case AgentRole.developer:
        final chip = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: r * 1.72, height: r * 1.72),
          Radius.circular(u * 0.07),
        );
        canvas.drawRRect(chip, line);
        final inner = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: r * 1.02, height: r * 1.02),
          Radius.circular(u * 0.04),
        );
        canvas.drawRRect(inner, fine);
        for (var i = -1; i <= 1; i++) {
          final d = i * u * 0.105;
          canvas.drawLine(Offset(c.dx + d, c.dy - r * 1.08), Offset(c.dx + d, c.dy - r * 1.42), line);
          canvas.drawLine(Offset(c.dx + d, c.dy + r * 1.08), Offset(c.dx + d, c.dy + r * 1.42), line);
          canvas.drawLine(Offset(c.dx - r * 1.08, c.dy + d), Offset(c.dx - r * 1.42, c.dy + d), line);
          canvas.drawLine(Offset(c.dx + r * 1.08, c.dy + d), Offset(c.dx + r * 1.42, c.dy + d), line);
        }
        canvas.drawLine(c + Offset(-r * 0.24, -r * 0.25), c + Offset(-r * 0.48, 0), line);
        canvas.drawLine(c + Offset(-r * 0.48, 0), c + Offset(-r * 0.24, r * 0.25), line);
        canvas.drawLine(c + Offset(r * 0.24, -r * 0.25), c + Offset(r * 0.48, 0), line);
        canvas.drawLine(c + Offset(r * 0.48, 0), c + Offset(r * 0.24, r * 0.25), line);
        break;

      case AgentRole.qa:
        canvas.drawCircle(c, r * 1.05, fine);
        canvas.drawCircle(c, r * 0.76, line);
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * 1.3), -2.5, 1.35, false, line);
        final check = Path()
          ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.10, c.dy + r * 0.34)
          ..lineTo(c.dx + r * 0.50, c.dy - r * 0.38);
        canvas.drawPath(check, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, u * 0.045)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
        break;

      case AgentRole.security:
        final shield = Path()
          ..moveTo(c.dx, c.dy - r * 1.22)
          ..lineTo(c.dx + r * 0.95, c.dy - r * 0.78)
          ..lineTo(c.dx + r * 0.78, c.dy + r * 0.30)
          ..quadraticBezierTo(c.dx + r * 0.52, c.dy + r * 0.92, c.dx, c.dy + r * 1.18)
          ..quadraticBezierTo(c.dx - r * 0.52, c.dy + r * 0.92, c.dx - r * 0.78, c.dy + r * 0.30)
          ..lineTo(c.dx - r * 0.95, c.dy - r * 0.78)
          ..close();
        canvas.drawPath(shield, line);
        final coreShield = Path()
          ..moveTo(c.dx, c.dy - r * 0.58)
          ..lineTo(c.dx + r * 0.45, c.dy - r * 0.34)
          ..lineTo(c.dx + r * 0.34, c.dy + r * 0.20)
          ..lineTo(c.dx, c.dy + r * 0.62)
          ..lineTo(c.dx - r * 0.34, c.dy + r * 0.20)
          ..lineTo(c.dx - r * 0.45, c.dy - r * 0.34)
          ..close();
        canvas.drawPath(coreShield, fine);
        canvas.drawCircle(c, u * 0.045, Paint()..color = Colors.white);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AgentAvatarPainter oldDelegate) =>
      oldDelegate.role != role || oldDelegate.color != color;
}
