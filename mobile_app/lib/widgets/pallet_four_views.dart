import 'dart:math' as math;

import 'package:flutter/material.dart';

class PalletFourViews extends StatelessWidget {
  const PalletFourViews({
    super.key,
    required this.layout,
    required this.boxes,
    required this.pallet,
  });

  final List<Map<String, dynamic>> layout;
  final List<Map<String, dynamic>> boxes;
  final Map<String, dynamic> pallet;

  @override
  Widget build(BuildContext context) {
    final length = _toDouble(pallet['lengthCm'], 48);
    final width = _toDouble(pallet['widthCm'], 40);
    final height = _toDouble(pallet['maxHeightCm'], 84);

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

    final views = [
      _ViewSpec(label: 'Frente', type: _ViewType.front, sideIn: length),
      _ViewSpec(label: 'Derecha', type: _ViewType.right, sideIn: width),
      _ViewSpec(label: 'Atras', type: _ViewType.back, sideIn: length),
      _ViewSpec(label: 'Izquierda', type: _ViewType.left, sideIn: width),
    ];

    return DefaultTabController(
      length: views.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            isScrollable: true,
            tabs: views.map((v) => Tab(text: v.label)).toList(growable: false),
          ),
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SizedBox(
                height: 320,
                child: TabBarView(
                  children: views
                      .map(
                        (view) => _PalletCanvas(
                          sideLabel: view.label,
                          sideIn: view.sideIn,
                          maxHeightIn: height,
                          placements: _projectPlacements(
                            layout,
                            boxMetaByBaseId,
                            view.type,
                            length,
                            width,
                            height,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _toDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<_Placement2D> _projectPlacements(
    List<Map<String, dynamic>> layout,
    Map<String, _BoxMeta> boxMetaByBaseId,
    _ViewType type,
    double palletLength,
    double palletWidth,
    double palletHeight,
  ) {
    final projected = <_Placement2D>[];

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
      final dimLabel = placedL.toStringAsFixed(0) + 'x' + placedW.toStringAsFixed(0) + 'x' + placedH.toStringAsFixed(0) + ' in';

      switch (type) {
        case _ViewType.front:
          projected.add(
            _Placement2D(
              x: x,
              y: z,
              w: placedL,
              h: placedH,
              maxW: palletLength,
              maxH: palletHeight,
              label: placedName,
              dimLabel: dimLabel,
              depth: y,
            ),
          );
          break;
        case _ViewType.right:
          projected.add(
            _Placement2D(
              x: y,
              y: z,
              w: placedW,
              h: placedH,
              maxW: palletWidth,
              maxH: palletHeight,
              label: placedName,
              dimLabel: dimLabel,
              depth: palletLength - (x + placedL),
            ),
          );
          break;
        case _ViewType.back:
          final mirroredX = palletLength - x - placedL;
          projected.add(
            _Placement2D(
              x: mirroredX,
              y: z,
              w: placedL,
              h: placedH,
              maxW: palletLength,
              maxH: palletHeight,
              label: placedName,
              dimLabel: dimLabel,
              depth: palletWidth - (y + placedW),
            ),
          );
          break;
        case _ViewType.left:
          final mirroredY = palletWidth - y - placedW;
          projected.add(
            _Placement2D(
              x: mirroredY,
              y: z,
              w: placedW,
              h: placedH,
              maxW: palletWidth,
              maxH: palletHeight,
              label: placedName,
              dimLabel: dimLabel,
              depth: x,
            ),
          );
          break;
      }
    }

    return projected;
  }
}

class _ViewSpec {
  _ViewSpec({required this.label, required this.type, required this.sideIn});
  final String label;
  final _ViewType type;
  final double sideIn;
}

enum _ViewType { front, right, back, left }

class _BoxMeta {
  _BoxMeta({required this.name, required this.l, required this.w, required this.h});
  final String name;
  final double l;
  final double w;
  final double h;
}

class _Placement2D {
  _Placement2D({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.maxW,
    required this.maxH,
    required this.label,
    required this.dimLabel,
    required this.depth,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final double maxW;
  final double maxH;
  final String label;
  final String dimLabel;
  final double depth;
}

class _DrawEntry {
  _DrawEntry({
    required this.placement,
    required this.rect,
    required this.visibleRatio,
  });

  final _Placement2D placement;
  final Rect rect;
  final double visibleRatio;
}

class _PalletCanvas extends StatelessWidget {
  const _PalletCanvas({
    required this.placements,
    required this.sideLabel,
    required this.sideIn,
    required this.maxHeightIn,
  });

  final List<_Placement2D> placements;
  final String sideLabel;
  final double sideIn;
  final double maxHeightIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(
        painter: _PalletPainter(placements, sideLabel, sideIn, maxHeightIn),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PalletPainter extends CustomPainter {
  _PalletPainter(this.placements, this.sideLabel, this.sideIn, this.maxHeightIn);
  final List<_Placement2D> placements;
  final String sideLabel;
  final double sideIn;
  final double maxHeightIn;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 12.0;
    const baseThickness = 10.0;
    const rightDimWidth = 44.0;

    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    final frame = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final leftBound = padding;
    final rightBound = size.width - padding - rightDimWidth;
    final topBound = padding + 8;
    final baseTop = size.height - padding - baseThickness - 16;
    final baseBottom = size.height - padding - 16;

    final contentRect = Rect.fromLTWH(
      leftBound,
      topBound,
      rightBound - leftBound,
      baseTop - topBound,
    );

    canvas.drawRect(contentRect, frame);

    final baseFill = Paint()..color = const Color(0xFFE4E4E4);
    final baseRect = Rect.fromLTWH(leftBound, baseTop, rightBound - leftBound, baseThickness);
    canvas.drawRect(baseRect, baseFill);
    canvas.drawRect(baseRect, frame);

    final fill = Paint()..color = const Color(0xFFC9C9C9);
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final usableWidth = (rightBound - leftBound - 2).clamp(1, double.infinity).toDouble();
    final usableHeight = (baseTop - topBound - 2).clamp(1, double.infinity).toDouble();

    final projectedEntries = <_DrawEntry>[];
    for (final p in placements) {
      final scaleX = usableWidth / (p.maxW <= 0 ? 1 : p.maxW);
      final scaleY = usableHeight / (p.maxH <= 0 ? 1 : p.maxH);

      final rawRect = Rect.fromLTWH(
        leftBound + 1 + (p.x * scaleX),
        baseTop - ((p.y + p.h) * scaleY),
        (p.w * scaleX).clamp(8, usableWidth).toDouble(),
        (p.h * scaleY).clamp(8, usableHeight).toDouble(),
      );

      final clipped = rawRect.intersect(contentRect);
      if (clipped.width <= 1 || clipped.height <= 1) {
        continue;
      }

      projectedEntries.add(
        _DrawEntry(
          placement: p,
          rect: clipped,
          visibleRatio: 1,
        ),
      );
    }

    // Occlusion by side: keep only faces that are still visible from this side.
    final nearToFar = [...projectedEntries]
      ..sort((a, b) {
        final byDepth = a.placement.depth.compareTo(b.placement.depth);
        if (byDepth != 0) return byDepth;
        final byBottom = a.placement.y.compareTo(b.placement.y);
        if (byBottom != 0) return byBottom;
        return a.placement.x.compareTo(b.placement.x);
      });

    final occluders = <Rect>[];
    final visible = <_DrawEntry>[];
    for (final e in nearToFar) {
      final area = e.rect.width * e.rect.height;
      if (area <= 1) continue;

      final overlap = _unionOverlapArea(e.rect, occluders);
      final ratio = ((area - overlap) / area).clamp(0, 1).toDouble();

      // Only draw if at least a meaningful visible face remains.
      if (ratio >= 0.12) {
        visible.add(_DrawEntry(placement: e.placement, rect: e.rect, visibleRatio: ratio));
      }

      occluders.add(e.rect);
    }

    final drawBackToFront = [...visible]
      ..sort((a, b) {
        final byDepth = b.placement.depth.compareTo(a.placement.depth);
        if (byDepth != 0) return byDepth;
        final byBottom = a.placement.y.compareTo(b.placement.y);
        if (byBottom != 0) return byBottom;
        return a.placement.x.compareTo(b.placement.x);
      });

    canvas.save();
    canvas.clipRect(contentRect);

    for (final e in drawBackToFront) {
      canvas.drawRect(e.rect, fill);
      canvas.drawRect(e.rect, stroke);

      if (e.rect.width >= 56 && e.rect.height >= 16 && e.visibleRatio >= 0.35) {
        final titleSpan = TextSpan(
          text: e.placement.label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        );

        final titlePainter = TextPainter(
          text: titleSpan,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '...',
        )..layout(maxWidth: e.rect.width - 6);

        titlePainter.paint(canvas, Offset(e.rect.left + 3, e.rect.top + 2));

        if (e.rect.width >= 78 && e.rect.height >= 26) {
          final dimSpan = TextSpan(
            text: e.placement.dimLabel,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          );

          final dimPainter = TextPainter(
            text: dimSpan,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '...',
          )..layout(maxWidth: e.rect.width - 6);

          dimPainter.paint(canvas, Offset(e.rect.left + 3, e.rect.top + 14));
        }
      }
    }

    canvas.restore();

    _drawHorizontalDimension(canvas, leftBound, rightBound, baseBottom + 10, '$sideLabel: ${sideIn.toStringAsFixed(0)} in');
    _drawVerticalDimension(canvas, rightBound + 20, baseTop, topBound, 'Max H\n${maxHeightIn.toStringAsFixed(0)} in\n(83-86 in)');
  }

  double _unionOverlapArea(Rect target, List<Rect> occluders) {
    final clipped = <Rect>[];
    for (final occluder in occluders) {
      final inter = target.intersect(occluder);
      if (inter.width > 0.01 && inter.height > 0.01) {
        clipped.add(inter);
      }
    }
    if (clipped.isEmpty) return 0;

    final xs = <double>{};
    for (final r in clipped) {
      xs.add(r.left);
      xs.add(r.right);
    }
    final sortedXs = xs.toList()..sort();

    var total = 0.0;
    for (var i = 0; i < sortedXs.length - 1; i++) {
      final x0 = sortedXs[i];
      final x1 = sortedXs[i + 1];
      if (x1 <= x0 + 0.001) continue;

      final segments = <_Seg>[];
      for (final r in clipped) {
        if (r.left < x1 - 0.001 && r.right > x0 + 0.001) {
          segments.add(_Seg(r.top, r.bottom));
        }
      }
      if (segments.isEmpty) continue;
      segments.sort((a, b) => a.a.compareTo(b.a));

      var coveredY = 0.0;
      var curA = segments.first.a;
      var curB = segments.first.b;
      for (final s in segments.skip(1)) {
        if (s.a <= curB + 0.001) {
          curB = math.max(curB, s.b);
        } else {
          coveredY += math.max(0, curB - curA);
          curA = s.a;
          curB = s.b;
        }
      }
      coveredY += math.max(0, curB - curA);

      total += (x1 - x0) * coveredY;
    }

    final targetArea = target.width * target.height;
    return total.clamp(0, targetArea).toDouble();
  }

  void _drawHorizontalDimension(Canvas canvas, double left, double right, double y, String label) {
    final line = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    canvas.drawLine(Offset(left, y), Offset(right, y), line);
    _drawArrowHead(canvas, Offset(left, y), const Offset(1, 0));
    _drawArrowHead(canvas, Offset(right, y), const Offset(-1, 0));

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: (right - left) - 8);

    tp.paint(canvas, Offset(left + ((right - left - tp.width) / 2), y + 2));
  }

  void _drawVerticalDimension(Canvas canvas, double x, double bottomY, double topY, String label) {
    final line = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    canvas.drawLine(Offset(x, bottomY), Offset(x, topY), line);
    _drawArrowHead(canvas, Offset(x, topY), const Offset(0, 1));
    _drawArrowHead(canvas, Offset(x, bottomY), const Offset(0, -1));

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 40);

    tp.paint(canvas, Offset(x - (tp.width / 2), (topY + bottomY - tp.height) / 2));
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset dir) {
    final paint = Paint()..color = Colors.black;
    final norm = dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
    final perp = Offset(-norm.dy, norm.dx);

    final p1 = tip;
    final p2 = tip + (norm * 6) + (perp * 3);
    final p3 = tip + (norm * 6) - (perp * 3);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PalletPainter oldDelegate) {
    return oldDelegate.placements != placements ||
        oldDelegate.sideLabel != sideLabel ||
        oldDelegate.sideIn != sideIn ||
        oldDelegate.maxHeightIn != maxHeightIn;
  }
}

class _Seg {
  _Seg(this.a, this.b);
  final double a;
  final double b;
}




