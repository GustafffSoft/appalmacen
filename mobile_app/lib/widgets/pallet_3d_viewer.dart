import 'dart:math' as math;

import 'package:flutter/material.dart';

class Pallet3DViewer extends StatefulWidget {
  const Pallet3DViewer({
    super.key,
    required this.layout,
    required this.boxes,
    required this.pallet,
  });

  final List<Map<String, dynamic>> layout;
  final List<Map<String, dynamic>> boxes;
  final Map<String, dynamic> pallet;

  @override
  State<Pallet3DViewer> createState() => _Pallet3DViewerState();
}

class _Pallet3DViewerState extends State<Pallet3DViewer> {
  double _yaw = 0.65;
  double _pitch = 0.48;
  double _zoom = 1.0;

  @override
  Widget build(BuildContext context) {
    final cuboids = _buildCuboids(widget.layout, widget.boxes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.threed_rotation, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Vista 3D interactiva',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _yaw = 0.65;
                  _pitch = 0.48;
                  _zoom = 1.0;
                });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Arrastra para girar alrededor del pallet. Usa zoom para acercar/alejar y ver desde arriba.',
          style: TextStyle(fontSize: 12, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Container(
          height: 340,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _yaw += details.delta.dx * 0.01;
                _pitch = (_pitch - details.delta.dy * 0.01).clamp(-1.2, 1.2);
              });
            },
            child: CustomPaint(
              painter: _Pallet3DPainter(
                cuboids: cuboids,
                palletLength: _toDouble(widget.pallet['lengthCm'], 48),
                palletWidth: _toDouble(widget.pallet['widthCm'], 40),
                palletHeight: _toDouble(widget.pallet['maxHeightCm'], 84),
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Zoom', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _zoom,
                min: 0.6,
                max: 2.0,
                divisions: 28,
                label: _zoom.toStringAsFixed(2),
                onChanged: (value) => setState(() => _zoom = value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<_Cuboid> _buildCuboids(
    List<Map<String, dynamic>> layout,
    List<Map<String, dynamic>> boxes,
  ) {
    final boxMetaByBaseId = <String, _BoxMeta>{};
    for (final box in boxes) {
      final baseId = box['boxId']?.toString() ?? '';
      if (baseId.isEmpty) continue;
      boxMetaByBaseId[baseId] = _BoxMeta(
        name: box['name']?.toString() ?? baseId,
        l: _toDouble(box['lengthCm'], 16),
        w: _toDouble(box['widthCm'], 12),
        h: _toDouble(box['heightCm'], 12),
      );
    }

    final cuboids = <_Cuboid>[];
    for (final row in layout) {
      final boxId = row['boxId']?.toString() ?? '';
      final baseId = boxId.split('-').first;
      final meta = boxMetaByBaseId[baseId];
      if (meta == null) continue;

      final x = _toDouble(row['x'], 0);
      final y = _toDouble(row['y'], 0);
      final z = _toDouble(row['z'], 0);
      final placedL = _toDouble(row['lengthCm'], meta.l);
      final placedW = _toDouble(row['widthCm'], meta.w);
      final placedH = _toDouble(row['heightCm'], meta.h);
      final placedName = row['name']?.toString() ?? meta.name;

      cuboids.add(
        _Cuboid(
          name: placedName,
          min: _Vec3(x, y, z),
          max: _Vec3(x + placedL, y + placedW, z + placedH),
          color: _colorFromName(placedName),
        ),
      );
    }

    return cuboids;
  }

  static double _toDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static Color _colorFromName(String input) {
    final hash = input.codeUnits.fold<int>(
      0,
      (prev, c) => (prev * 31 + c) & 0x7fffffff,
    );
    final hue = (hash % 360).toDouble();
    final hsl = HSLColor.fromAHSL(1, hue, 0.25, 0.78);
    return hsl.toColor();
  }
}

class _Pallet3DPainter extends CustomPainter {
  _Pallet3DPainter({
    required this.cuboids,
    required this.palletLength,
    required this.palletWidth,
    required this.palletHeight,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  final List<_Cuboid> cuboids;
  final double palletLength;
  final double palletWidth;
  final double palletHeight;
  final double yaw;
  final double pitch;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFF8F8F8);
    canvas.drawRect(Offset.zero & size, bg);

    final centerX = size.width * 0.5;
    final centerY = size.height * 0.63;

    final maxDim = math.max(palletLength, math.max(palletWidth, palletHeight));
    final camDist = maxDim * 2.5;
    final focal = (size.shortestSide * 1.05) * zoom;

    _ProjectedPoint? project(_Vec3 p) {
      final cx = palletLength / 2;
      final cy = palletWidth / 2;
      final cz = palletHeight / 2;

      final px = p.x - cx;
      final py = p.y - cy;
      final pz = p.z - cz;

      final cYaw = math.cos(yaw);
      final sYaw = math.sin(yaw);
      final x1 = px * cYaw - py * sYaw;
      final y1 = px * sYaw + py * cYaw;
      final z1 = pz;

      final cPitch = math.cos(pitch);
      final sPitch = math.sin(pitch);
      final x2 = x1;
      final y2 = y1 * cPitch - z1 * sPitch;
      final z2 = y1 * sPitch + z1 * cPitch;

      final depth = y2 + camDist;
      if (depth <= 0.001) return null;

      final sx = centerX + (x2 * focal / depth);
      final sy = centerY - (z2 * focal / depth);
      return _ProjectedPoint(Offset(sx, sy), _Vec3(x2, y2, z2), depth);
    }

    final faces = <_FaceToDraw>[];
    for (final cuboid in cuboids) {
      final vertices = cuboid.vertices;
      final projected = <_ProjectedPoint?>[];
      for (final v in vertices) {
        projected.add(project(v));
      }

      for (final face in _Cuboid.faces) {
        final p0 = projected[face[0]];
        final p1 = projected[face[1]];
        final p2 = projected[face[2]];
        final p3 = projected[face[3]];
        if (p0 == null || p1 == null || p2 == null || p3 == null) continue;

        final path = Path()
          ..moveTo(p0.screen.dx, p0.screen.dy)
          ..lineTo(p1.screen.dx, p1.screen.dy)
          ..lineTo(p2.screen.dx, p2.screen.dy)
          ..lineTo(p3.screen.dx, p3.screen.dy)
          ..close();

        final a = p1.view - p0.view;
        final b = p2.view - p0.view;
        final normal = a.cross(b);

        // Camera looks towards +Y in view coordinates; faces pointing to camera have negative Y normal.
        if (normal.y >= -0.001) continue;

        final avgDepth = (p0.depth + p1.depth + p2.depth + p3.depth) / 4;
        final shade = _faceShade(normal);
        faces.add(
          _FaceToDraw(
            path: path,
            depth: avgDepth,
            fill: _shadeColor(cuboid.color, shade),
            stroke: Colors.black.withValues(alpha: 0.65),
          ),
        );
      }
    }

    // Draw far faces first.
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      canvas.drawPath(face.path, Paint()..color = face.fill);
      canvas.drawPath(
        face.path,
        Paint()
          ..color = face.stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Draw pallet outline box on top for reference.
    _drawPalletWireframe(canvas, project, size);

    final helpPainter = TextPainter(
      text: const TextSpan(
        text: 'Drag: rotar  |  Zoom: slider  |  Vista superior: sube pitch',
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: size.width - 16);
    helpPainter.paint(canvas, const Offset(8, 8));
  }

  double _faceShade(_Vec3 normal) {
    final n = normal.normalized();
    final light = _Vec3(-0.4, -0.7, 0.8).normalized();
    final dot = (n.dot(light)).clamp(-1.0, 1.0);
    return (0.68 + (dot * 0.24)).clamp(0.4, 0.92).toDouble();
  }

  Color _shadeColor(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness * factor).clamp(0.25, 0.92);
    return hsl.withLightness(lightness).toColor();
  }

  void _drawPalletWireframe(
    Canvas canvas,
    _ProjectedPoint? Function(_Vec3 point) project,
    Size size,
  ) {
    final corners = [
      _Vec3(0, 0, 0),
      _Vec3(palletLength, 0, 0),
      _Vec3(palletLength, palletWidth, 0),
      _Vec3(0, palletWidth, 0),
      _Vec3(0, 0, palletHeight),
      _Vec3(palletLength, 0, palletHeight),
      _Vec3(palletLength, palletWidth, palletHeight),
      _Vec3(0, palletWidth, palletHeight),
    ];

    final proj = corners.map(project).toList();
    if (proj.any((p) => p == null)) return;

    final p = proj.cast<_ProjectedPoint>();
    final wire = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    void line(int a, int b) {
      canvas.drawLine(p[a].screen, p[b].screen, wire);
    }

    line(0, 1);
    line(1, 2);
    line(2, 3);
    line(3, 0);
    line(4, 5);
    line(5, 6);
    line(6, 7);
    line(7, 4);
    line(0, 4);
    line(1, 5);
    line(2, 6);
    line(3, 7);

    final title = TextPainter(
      text: TextSpan(
        text:
            'Base ${palletLength.toStringAsFixed(0)}x${palletWidth.toStringAsFixed(0)} in  |  Max H ${palletHeight.toStringAsFixed(0)} in',
        style: const TextStyle(
          fontSize: 11,
          color: Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);
    title.paint(canvas, Offset(8, size.height - 18));
  }

  @override
  bool shouldRepaint(covariant _Pallet3DPainter oldDelegate) {
    return oldDelegate.cuboids != cuboids ||
        oldDelegate.palletLength != palletLength ||
        oldDelegate.palletWidth != palletWidth ||
        oldDelegate.palletHeight != palletHeight ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.zoom != zoom;
  }
}

class _ProjectedPoint {
  _ProjectedPoint(this.screen, this.view, this.depth);
  final Offset screen;
  final _Vec3 view;
  final double depth;
}

class _FaceToDraw {
  _FaceToDraw({
    required this.path,
    required this.depth,
    required this.fill,
    required this.stroke,
  });

  final Path path;
  final double depth;
  final Color fill;
  final Color stroke;
}

class _BoxMeta {
  _BoxMeta({
    required this.name,
    required this.l,
    required this.w,
    required this.h,
  });
  final String name;
  final double l;
  final double w;
  final double h;
}

class _Cuboid {
  _Cuboid({
    required this.name,
    required this.min,
    required this.max,
    required this.color,
  });

  final String name;
  final _Vec3 min;
  final _Vec3 max;
  final Color color;

  static const faces = <List<int>>[
    [0, 1, 2, 3], // bottom
    [4, 5, 6, 7], // top
    [0, 1, 5, 4], // front
    [1, 2, 6, 5], // right
    [2, 3, 7, 6], // back
    [3, 0, 4, 7], // left
  ];

  List<_Vec3> get vertices => [
    _Vec3(min.x, min.y, min.z),
    _Vec3(max.x, min.y, min.z),
    _Vec3(max.x, max.y, min.z),
    _Vec3(min.x, max.y, min.z),
    _Vec3(min.x, min.y, max.z),
    _Vec3(max.x, min.y, max.z),
    _Vec3(max.x, max.y, max.z),
    _Vec3(min.x, max.y, max.z),
  ];
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _Vec3 operator -(_Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);

  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;

  _Vec3 cross(_Vec3 o) =>
      _Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => math.sqrt(x * x + y * y + z * z);

  _Vec3 normalized() {
    final len = length;
    if (len <= 1e-9) return const _Vec3(0, 0, 0);
    return _Vec3(x / len, y / len, z / len);
  }
}
