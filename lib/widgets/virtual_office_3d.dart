import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

class VirtualOffice3D extends StatefulWidget {
  const VirtualOffice3D({
    super.key,
    this.onAgentTap,
    this.autoOrbit = false,
    this.selectedAgentId,
  });

  final ValueChanged<String>? onAgentTap;
  final bool autoOrbit;
  final String? selectedAgentId;

  @override
  State<VirtualOffice3D> createState() => _VirtualOffice3DState();
}

class _VirtualOffice3DState extends State<VirtualOffice3D>
    with TickerProviderStateMixin {
  double _yaw = -0.68;
  double _pitch = 0.62;
  double _zoom = 1;
  double _startYaw = 0;
  double _startPitch = 0;
  double _startZoom = 1;
  Offset _gestureStart = Offset.zero;
  Offset _pan = Offset.zero;

  late final AnimationController _orbitController =
      AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  );

  double get _cameraYaw =>
      _yaw + (widget.autoOrbit
          ? _orbitController.value * math.pi * 2
          : 0);

  @override
  void initState() {
    super.initState();
    _syncOrbit();
  }

  @override
  void didUpdateWidget(covariant VirtualOffice3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoOrbit != widget.autoOrbit) {
      _syncOrbit(preservePhase: oldWidget.autoOrbit && !widget.autoOrbit);
    }
  }

  void _syncOrbit({bool preservePhase = false}) {
    if (preservePhase) {
      _yaw += _orbitController.value * math.pi * 2;
    }
    if (widget.autoOrbit) {
      if (!_orbitController.isAnimating) {
        _orbitController.repeat();
      }
    } else {
      _orbitController.stop();
      _orbitController.value = 0;
    }
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
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
                _yaw = _startYaw +
                    (details.focalPoint.dx - _gestureStart.dx) * 0.008;
                _pitch = (_startPitch -
                    (details.focalPoint.dy - _gestureStart.dy) * 0.004)
                    .clamp(0.25, 1.1);
              }
              _zoom = (_startZoom * details.scale).clamp(0.65, 1.7);
            });
          },
          onTapUp: (details) {
            final size = constraints.biggest;
            final unit = math.min(size.width / 17, size.height / 11) * _zoom;
            final center = Offset(size.width * 0.5, size.height * 0.55) + _pan;
            final agents = <List<dynamic>>[
              ['architect', -4.3, -1.2],
              ['manager', 0.0, -2.3],
              ['developer', 4.1, -1.2],
              ['qa', -3.0, 2.1],
              ['security', 3.0, 2.1],
            ];
            for (final agent in agents) {
              final x = agent[1] as double;
              final y = (agent[2] as double) - 0.65;
              final c = math.cos(_cameraYaw);
              final s = math.sin(_cameraYaw);
              final rx = x * c - y * s;
              final ry = x * s + y * c;
              final perspective = 1 - ry * 0.008;
              final point = Offset(
                center.dx + rx * unit * perspective,
                center.dy +
                    (ry * math.sin(_pitch) -
                        1.35 * math.cos(_pitch)) *
                        unit *
                        perspective,
              );
              if ((point - details.localPosition).distance <
                  math.max(22.0, unit * 0.48)) {
                widget.onAgentTap?.call(agent[0] as String);
                break;
              }
            }
          },
          child: AnimatedBuilder(
            animation: _orbitController,
            builder: (context, child) {
              return CustomPaint(
                painter: _OfficePainter(
                  yaw: _cameraYaw,
                  pitch: _pitch,
                  zoom: _zoom,
                  pan: _pan,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  selectedAgentId: widget.selectedAgentId,
                ),
                child: child,
              );
            },
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
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
  _OfficePainter({required this.yaw, required this.pitch, required this.zoom, required this.pan, required this.isDark, this.selectedAgentId});
  final double yaw, pitch, zoom;
  final Offset pan;
  final bool isDark;
  final String? selectedAgentId;
  late Size size;
  late double unit;
  late Offset center;
  final List<Color> _walls = const [Color(0xFF171526), Color(0xFF211B34), Color(0xFF2C2445)];

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
    final background = Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: isDark ? const [Color(0xFF090A10), Color(0xFF14111F)] : const [Color(0xFFE8EEF7), Color(0xFFD5E0EF)]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);
    _drawRoom(canvas);
    _drawGrid(canvas);
    final furniture = <_Furniture>[
      _Furniture(-4.3, -1.2, const Color(0xFF5B467E), 'architect', 'ARCHITECT'),
      _Furniture(0, -2.3, const Color(0xFF8B5CF6), 'manager', 'MANAGER'),
      _Furniture(4.1, -1.2, const Color(0xFF6D55A2), 'developer', 'DEVELOPER'),
      _Furniture(-3.0, 2.1, const Color(0xFF765F92), 'qa', 'QA'),
      _Furniture(3.0, 2.1, const Color(0xFF9A5E9F), 'security', 'SECURITY'),
    ]..sort((a, b) => (a.x * math.sin(yaw) + a.y * math.cos(yaw)).compareTo(b.x * math.sin(yaw) + b.y * math.cos(yaw)));
    for (final item in furniture) {
      _drawDesk(canvas, item.x, item.y, item.tint);
      _drawAgent(canvas, item.x, item.y - 0.65, item.tint, item.id, item.label, item.id == selectedAgentId);
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
    _polygon(canvas, const [_V3(-6.5, -4.5, 0), _V3(6.5, -4.5, 0), _V3(6.5, 4.5, 0), _V3(-6.5, 4.5, 0)], const Color(0xFF211C33), stroke: const Color(0xFF5A477D), strokeWidth: 2);
    _polygon(canvas, const [_V3(-6.5, 4.5, 0), _V3(6.5, 4.5, 0), _V3(6.5, 4.5, 3.1), _V3(-6.5, 4.5, 3.1)], _walls[1], stroke: const Color(0xFF513F70));
    _polygon(canvas, const [_V3(-6.5, -4.5, 0), _V3(-6.5, 4.5, 0), _V3(-6.5, 4.5, 3.1), _V3(-6.5, -4.5, 3.1)], _walls[0], stroke: const Color(0xFF513F70));
    _polygon(canvas, const [_V3(-6.5, 4.5, 3.1), _V3(6.5, 4.5, 3.1), _V3(6.5, 4.45, 3.02), _V3(-6.5, 4.45, 3.02)], const Color(0xFF8B5CF6));
  }

  void _drawGrid(Canvas canvas) {
    final paint = Paint()..color = const Color(0x338B5CF6)..strokeWidth = 0.7;
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
    _polygon(canvas, [at, bt, ct, et], Color.lerp(color, Colors.white, 0.13)!, stroke: const Color(0x668B5CF6), strokeWidth: 0.8);
  }

  void _drawDesk(Canvas canvas, double x, double y, Color tint) {
    for (final dx in [-0.65, 0.65]) {
      for (final dy in [-0.45, 0.45]) { _cube(canvas, x + dx, y + dy, 0, 0.12, 0.12, 0.72, const Color(0xFF667D96)); }
    }
    _cube(canvas, x, y, 0.74, 1.55, 1.12, 0.16, const Color(0xFF403650));
    _cube(canvas, x + 0.08, y - 0.12, 0.92, 0.56, 0.1, 0.62, const Color(0xFF211D32));
    _cube(canvas, x + 0.08, y - 0.12, 1.02, 0.49, 0.035, 0.42, tint.withValues(alpha: 0.95));
    _cube(canvas, x - 0.48, y + 0.18, 0.92, 0.28, 0.25, 0.045, const Color(0xFFD8D0E8));
  }

  void _drawAgent(
    Canvas canvas,
    double x,
    double y,
    Color tint,
    String id,
    String label,
    bool selected,
  ) {
    _cube(canvas, x, y, 0, 0.58, 0.52, 0.10,
        const Color(0xFF352C4C));

    final anchor = project(_V3(x, y, 0.78));
    final center = project(_V3(x, y, 1.38));
    final radius = unit * (selected ? 0.34 : 0.27);

    canvas.drawLine(
      anchor.offset,
      center.offset,
      Paint()
        ..color = tint.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
    );

    canvas.drawCircle(
      center.offset,
      radius * 1.8,
      Paint()
        ..color = tint.withValues(alpha: 0.2)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          radius * 0.7,
        ),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: center.offset,
        width: radius * 3.2,
        height: radius * 0.9,
      ),
      Paint()
        ..color = tint.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.8 : 1.1,
    );

    final diamond = Path()
      ..moveTo(center.x, center.y - radius)
      ..lineTo(center.x + radius * 0.65, center.y)
      ..lineTo(center.x, center.y + radius)
      ..lineTo(center.x - radius * 0.65, center.y)
      ..close();

    canvas.drawPath(
      diamond,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(tint, Colors.white, 0.6)!,
            tint,
            Color.lerp(tint, Colors.black, 0.2)!,
          ],
        ).createShader(
          Rect.fromCenter(
            center: center.offset,
            width: radius * 1.5,
            height: radius * 2,
          ),
        ),
    );

    canvas.drawCircle(
      center.offset,
      radius * 0.17,
      Paint()..color = Colors.white,
    );

    if (selected) {
      canvas.drawCircle(
        center.offset,
        radius * 2.1,
        Paint()
          ..color = tint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFE0D9F1),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelPoint = project(_V3(x, y - 0.1, 2.05));
    painter.paint(
      canvas,
      Offset(
        labelPoint.x - painter.width / 2,
        labelPoint.y - painter.height / 2,
      ),
    );
  }

  void _drawMeetingTable(Canvas canvas) {
    _cube(canvas, 0, 0.55, 0.72, 2.8, 1.5, 0.18, const Color(0xFF49375F));
    _cube(canvas, 0, 0.55, 0, 0.12, 0.12, 0.72, const Color(0xFF5B467C));
    for (final pos in [const _V3(-1.65, 0.6, 0), const _V3(1.65, 0.6, 0), const _V3(0, -0.5, 0), const _V3(0, 1.65, 0)]) {
      _cube(canvas, pos.x, pos.y, 0, 0.55, 0.5, 0.48, const Color(0xFF405A77));
    }
  }

  void _drawCenterHologram(Canvas canvas) {
    final p = project(const _V3(0, 0.55, 1.1));
    final r = unit * 0.42;
    canvas.drawCircle(p.offset, r, Paint()..color = const Color(0x338B5CF6)..style = PaintingStyle.fill);
    canvas.drawCircle(p.offset, r, Paint()..color = const Color(0xCCB69AFF)..style = PaintingStyle.stroke..strokeWidth = 1.3);
    canvas.drawLine(Offset(p.x - r * 0.7, p.y), Offset(p.x + r * 0.7, p.y), Paint()..color = const Color(0xCCB69AFF)..strokeWidth = 1);
    canvas.drawLine(Offset(p.x, p.y - r * 0.7), Offset(p.x, p.y + r * 0.7), Paint()..color = const Color(0xCCB69AFF)..strokeWidth = 1);
  }

  void _drawRoomLabels(Canvas canvas) {
    void label(String value, _V3 at) {
      final point = project(at);
      final tp = TextPainter(text: TextSpan(text: value, style: const TextStyle(color: Color(0xFFE0D9F1), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.4)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(point.x - tp.width / 2, point.y - tp.height / 2));
    }
    label('TEAM FLOOR', const _V3(0, 3.85, 2.3));
    label('MEETING HUB', const _V3(0, 0.55, 1.62));
  }

  @override
  bool shouldRepaint(covariant _OfficePainter oldDelegate) => oldDelegate.yaw != yaw || oldDelegate.pitch != pitch || oldDelegate.zoom != zoom || oldDelegate.pan != pan || oldDelegate.isDark != isDark || oldDelegate.selectedAgentId != selectedAgentId;
}

class _Furniture {
  const _Furniture(this.x, this.y, this.tint, this.id, this.label);
  final double x, y;
  final Color tint;
  final String id;
  final String label;
}
