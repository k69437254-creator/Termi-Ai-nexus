import 'dart:math' as math;
import 'package:flutter/material.dart';

class VirtualOffice3D extends StatefulWidget {
  const VirtualOffice3D({super.key, this.onAgentTap});
  final ValueChanged<String>? onAgentTap;
  @override
  State<VirtualOffice3D> createState() => _VirtualOffice3DState();
}

class _VirtualOffice3DState extends State<VirtualOffice3D> {
  double _yaw = -0.68;
  double _pitch = 0.62;
  double _zoom = 1;
  double _startYaw = 0;
  double _startPitch = 0;
  double _startZoom = 1;
  Offset _gestureStart = Offset.zero;
  Offset _pan = Offset.zero;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onScaleStart: (details) {
      _startYaw = _yaw;
      _startPitch = _pitch;
      _startZoom = _zoom;
      _gestureStart = details.focalPoint;
    },
    onScaleUpdate: (details) {
      setState(() {
        if (details.pointerCount > 1) {
          _pan += details.focalPointDelta;
        } else {
          _yaw = _startYaw + (details.focalPoint.dx - _gestureStart.dx) * 0.008;
          _pitch = (_startPitch - (details.focalPoint.dy - _gestureStart.dy) * 0.004).clamp(0.25, 1.1);
        }
        _zoom = (_startZoom * details.scale).clamp(0.65, 1.7);
      });
    },
    child: CustomPaint(
      painter: _OfficePainter(yaw: _yaw, pitch: _pitch, zoom: _zoom, pan: _pan, isDark: Theme.of(context).brightness == Brightness.dark),
      child: const SizedBox.expand(),
    ),
  );
}

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
}

class _P2 {
  const _P2(this.x, this.y);
  final double x, y;
  Offset get offset => Offset(x, y);
}

class _OfficePainter extends CustomPainter {
  _OfficePainter({required this.yaw, required this.pitch, required this.zoom, required this.pan, required this.isDark});
  final double yaw, pitch, zoom;
  final Offset pan;
  final bool isDark;
  late Size size;
  late double unit;
  late Offset center;
  final List<Color> _walls = const [Color(0xFF17243C), Color(0xFF1D3150), Color(0xFF243D5B)];

  _P2 project(_V3 point) {
    final c = math.cos(yaw), s = math.sin(yaw);
    final x = point.x * c - point.y * s;
    final y = point.x * s + point.y * c;
    final elevation = math.sin(pitch);
    final vertical = math.cos(pitch);
    final perspective = 1 - y * 0.008;
    return _P2(center.dx + x * unit * perspective, center.dy + (y * elevation - point.z * vertical) * unit * perspective);
  }

  @override
  void paint(Canvas canvas, Size canvasSize) {
    size = canvasSize;
    center = Offset(size.width * 0.5, size.height * 0.55) + pan;
    unit = math.min(size.width / 17, size.height / 11) * zoom;
    final background = Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: isDark ? const [Color(0xFF0B1220), Color(0xFF111D30)] : const [Color(0xFFE8EEF7), Color(0xFFD5E0EF)]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);
    _drawRoom(canvas);
    _drawGrid(canvas);
    final furniture = <_Furniture>[
      _Furniture(-4.3, -1.2, const Color(0xFF316A89), 'ARCHITECT'),
      _Furniture(0, -2.3, const Color(0xFF7656A8), 'MANAGER'),
      _Furniture(4.1, -1.2, const Color(0xFF267B77), 'DEVELOPER'),
      _Furniture(-3.0, 2.1, const Color(0xFF9B7041), 'QA'),
      _Furniture(3.0, 2.1, const Color(0xFF9B4D5D), 'SECURITY'),
    ]..sort((a, b) => (a.x * math.sin(yaw) + a.y * math.cos(yaw)).compareTo(b.x * math.sin(yaw) + b.y * math.cos(yaw)));
    for (final item in furniture) {
      _drawDesk(canvas, item.x, item.y, item.tint);
      _drawAgent(canvas, item.x, item.y - 0.65, item.tint, item.label);
    }
    _drawMeetingTable(canvas);
    _drawCenterHologram(canvas);
    _drawRoomLabels(canvas);
  }

  void _polygon(Canvas canvas, List<_V3> vertices, Color color, {Color? stroke, double strokeWidth = 1}) {
    final points = vertices.map(project).toList();
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) { path.lineTo(point.x, point.y); }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    if (stroke != null) canvas.drawPath(path, Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = strokeWidth);
  }

  void _drawRoom(Canvas canvas) {
    _polygon(canvas, const [_V3(-6.5, -4.5, 0), _V3(6.5, -4.5, 0), _V3(6.5, 4.5, 0), _V3(-6.5, 4.5, 0)], const Color(0xFF243650), stroke: const Color(0xFF5D7696), strokeWidth: 2);
    _polygon(canvas, const [_V3(-6.5, 4.5, 0), _V3(6.5, 4.5, 0), _V3(6.5, 4.5, 3.1), _V3(-6.5, 4.5, 3.1)], _walls[1], stroke: const Color(0xFF46607E));
    _polygon(canvas, const [_V3(-6.5, -4.5, 0), _V3(-6.5, 4.5, 0), _V3(-6.5, 4.5, 3.1), _V3(-6.5, -4.5, 3.1)], _walls[0], stroke: const Color(0xFF46607E));
    _polygon(canvas, const [_V3(-6.5, 4.5, 3.1), _V3(6.5, 4.5, 3.1), _V3(6.5, 4.45, 3.02), _V3(-6.5, 4.45, 3.02)], const Color(0xFF5BA9D5));
  }

  void _drawGrid(Canvas canvas) {
    final paint = Paint()..color = const Color(0x225C88B4)..strokeWidth = 0.7;
    for (var x = -6; x <= 6; x++) {
      final a = project(_V3(x.toDouble(), -4.4, 0.01)).offset;
      final b = project(_V3(x.toDouble(), 4.4, 0.01)).offset;
      canvas.drawLine(a, b, paint);
    }
    for (var y = -4; y <= 4; y++) {
      final a = project(_V3(-6.4, y.toDouble(), 0.01)).offset;
      final b = project(_V3(6.4, y.toDouble(), 0.01)).offset;
      canvas.drawLine(a, b, paint);
    }
  }

  void _cube(Canvas canvas, double x, double y, double z, double w, double d, double h, Color color) {
    final a = _V3(x - w / 2, y - d / 2, z), b = _V3(x + w / 2, y - d / 2, z), c = _V3(x + w / 2, y + d / 2, z), e = _V3(x - w / 2, y + d / 2, z);
    final at = _V3(a.x, a.y, z + h), bt = _V3(b.x, b.y, z + h), ct = _V3(c.x, c.y, z + h), et = _V3(e.x, e.y, z + h);
    _polygon(canvas, [e, c, ct, et], Color.lerp(color, Colors.black, 0.22)!);
    _polygon(canvas, [b, c, ct, bt], Color.lerp(color, Colors.black, 0.12)!);
    _polygon(canvas, [at, bt, ct, et], Color.lerp(color, Colors.white, 0.13)!, stroke: const Color(0x553D668F), strokeWidth: 0.8);
  }

  void _drawDesk(Canvas canvas, double x, double y, Color tint) {
    for (final dx in [-0.65, 0.65]) {
      for (final dy in [-0.45, 0.45]) { _cube(canvas, x + dx, y + dy, 0, 0.12, 0.12, 0.72, const Color(0xFF667D96)); }
    }
    _cube(canvas, x, y, 0.74, 1.55, 1.12, 0.16, const Color(0xFF536C88));
    _cube(canvas, x + 0.08, y - 0.12, 0.92, 0.56, 0.1, 0.62, const Color(0xFF263C55));
    _cube(canvas, x + 0.08, y - 0.12, 1.02, 0.49, 0.035, 0.42, tint.withValues(alpha: 0.95));
    _cube(canvas, x - 0.48, y + 0.18, 0.92, 0.28, 0.25, 0.045, const Color(0xFFD5DFE9));
  }

  void _drawAgent(Canvas canvas, double x, double y, Color tint, String label) {
    _cube(canvas, x, y, 0, 0.5, 0.48, 0.12, const Color(0xFF354A62));
    _cube(canvas, x, y, 0.16, 0.34, 0.27, 0.65, tint);
    final head = project(_V3(x, y, 1.03));
    canvas.drawCircle(head.offset, math.max(4, unit * 0.17), Paint()..shader = RadialGradient(colors: [Color.lerp(tint, Colors.white, 0.55)!, tint]).createShader(Rect.fromCircle(center: head.offset, radius: unit * 0.18)));
    final labelPainter = TextPainter(text: TextSpan(text: label, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 0.9)), textDirection: TextDirection.ltr)..layout();
    final p = project(_V3(x, y - 0.1, 1.35));
    labelPainter.paint(canvas, Offset(p.x - labelPainter.width / 2, p.y - labelPainter.height / 2));
  }

  void _drawMeetingTable(Canvas canvas) {
    _cube(canvas, 0, 0.55, 0.72, 2.8, 1.5, 0.18, const Color(0xFF3D5B7D));
    _cube(canvas, 0, 0.55, 0, 0.12, 0.12, 0.72, const Color(0xFF607B9B));
    for (final pos in [const _V3(-1.65, 0.6, 0), const _V3(1.65, 0.6, 0), const _V3(0, -0.5, 0), const _V3(0, 1.65, 0)]) {
      _cube(canvas, pos.x, pos.y, 0, 0.55, 0.5, 0.48, const Color(0xFF405A77));
    }
  }

  void _drawCenterHologram(Canvas canvas) {
    final p = project(const _V3(0, 0.55, 1.1));
    final r = unit * 0.42;
    canvas.drawCircle(p.offset, r, Paint()..color = const Color(0x2249C8E8)..style = PaintingStyle.fill);
    canvas.drawCircle(p.offset, r, Paint()..color = const Color(0xAA57D7F0)..style = PaintingStyle.stroke..strokeWidth = 1.3);
    canvas.drawLine(Offset(p.x - r * 0.7, p.y), Offset(p.x + r * 0.7, p.y), Paint()..color = const Color(0xAA57D7F0)..strokeWidth = 1);
    canvas.drawLine(Offset(p.x, p.y - r * 0.7), Offset(p.x, p.y + r * 0.7), Paint()..color = const Color(0xAA57D7F0)..strokeWidth = 1);
  }

  void _drawRoomLabels(Canvas canvas) {
    void label(String value, _V3 at) {
      final point = project(at);
      final tp = TextPainter(text: TextSpan(text: value, style: const TextStyle(color: Color(0xFFB8CBE0), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.4)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(point.x - tp.width / 2, point.y - tp.height / 2));
    }
    label('TEAM FLOOR', const _V3(0, 3.85, 2.3));
    label('MEETING HUB', const _V3(0, 0.55, 1.62));
  }

  @override
  bool shouldRepaint(covariant _OfficePainter oldDelegate) => oldDelegate.yaw != yaw || oldDelegate.pitch != pitch || oldDelegate.zoom != zoom || oldDelegate.pan != pan || oldDelegate.isDark != isDark;
}

class _Furniture {
  const _Furniture(this.x, this.y, this.tint, this.label);
  final double x, y;
  final Color tint;
  final String label;
}
