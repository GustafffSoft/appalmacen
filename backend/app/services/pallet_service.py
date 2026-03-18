from __future__ import annotations

from dataclasses import dataclass
from itertools import permutations

from app.models.schemas import BoxPlan, DetectedItem, LayerSummary, LayoutItem, PackingSummary, PalletPlanView, PalletRequest, StatsResponse

EPS = 1e-6
PACKING_RULES = [
    'Ordenar cajas por peso y volumen descendente.',
    'Priorizar frente del pallet y sus esquinas antes que el resto del perimetro.',
    'Mantener cada caja tocando un lado visible del pallet para evitar cajas ocultas en el centro.',
    'Construir capas desde abajo hacia arriba con soporte completo y sin peso pesado sobre ligero.',
    'Penalizar distribuciones con desbalance de peso entre cuadrantes.',
]


@dataclass
class _UnitBox:
    box_id: str
    length: float
    width: float
    height: float
    weight: float


@dataclass
class _PlacedBox:
    box_id: str
    x: float
    y: float
    z: float
    length: float
    width: float
    height: float
    weight: float
    rotation: int
    layer: int


@dataclass
class _PalletState:
    pallet_no: int
    placed: list[_PlacedBox]
    running_weight: float


def _expand_units(items: list[DetectedItem]) -> list[_UnitBox]:
    units: list[_UnitBox] = []
    for item in items:
        for i in range(item.qty):
            units.append(
                _UnitBox(
                    box_id=f"{item.boxId}-{i + 1}",
                    length=item.lengthCm,
                    width=item.widthCm,
                    height=item.heightCm,
                    weight=item.weightKg,
                )
            )

    units.sort(key=lambda u: (u.weight, u.length * u.width * u.height), reverse=True)
    return units


def _orientations(unit: _UnitBox) -> list[tuple[float, float, float, int]]:
    unique: list[tuple[float, float, float, int]] = []
    seen: set[tuple[float, float, float]] = set()
    for idx, (l, w, h) in enumerate(permutations((unit.length, unit.width, unit.height), 3)):
        key = (round(l, 4), round(w, 4), round(h, 4))
        if key in seen:
            continue
        seen.add(key)
        unique.append((l, w, h, idx))
    return unique


def _overlap_1d(a0: float, a1: float, b0: float, b1: float) -> bool:
    return not (a1 <= b0 + EPS or b1 <= a0 + EPS)


def _overlap_3d(x: float, y: float, z: float, l: float, w: float, h: float, p: _PlacedBox) -> bool:
    return (
        _overlap_1d(x, x + l, p.x, p.x + p.length)
        and _overlap_1d(y, y + w, p.y, p.y + p.width)
        and _overlap_1d(z, z + h, p.z, p.z + p.height)
    )


def _union_area(rects: list[tuple[float, float, float, float]]) -> float:
    if not rects:
        return 0.0

    xs = sorted({x0 for x0, _, x1, _ in rects} | {x1 for _, _, x1, _ in rects})
    total = 0.0

    for i in range(len(xs) - 1):
        left = xs[i]
        right = xs[i + 1]
        if right <= left + EPS:
            continue

        ys: list[tuple[float, float]] = []
        for x0, y0, x1, y1 in rects:
            if x0 < right - EPS and x1 > left + EPS:
                ys.append((y0, y1))

        if not ys:
            continue

        ys.sort()
        merged: list[tuple[float, float]] = []
        cur_start, cur_end = ys[0]
        for y0, y1 in ys[1:]:
            if y0 <= cur_end + EPS:
                cur_end = max(cur_end, y1)
            else:
                merged.append((cur_start, cur_end))
                cur_start, cur_end = y0, y1
        merged.append((cur_start, cur_end))

        covered_y = sum(max(0.0, y1 - y0) for y0, y1 in merged)
        total += (right - left) * covered_y

    return total


def _support_info(x: float, y: float, z: float, l: float, w: float, weight: float, placed: list[_PlacedBox]) -> tuple[bool, float]:
    if z <= EPS:
        return True, 1.0

    support_boxes = [p for p in placed if abs((p.z + p.height) - z) <= 0.05]
    if not support_boxes:
        return False, 0.0

    overlap_rects: list[tuple[float, float, float, float]] = []
    min_support_weight = float('inf')
    for p in support_boxes:
        left = max(x, p.x)
        right = min(x + l, p.x + p.length)
        bottom = max(y, p.y)
        top = min(y + w, p.y + p.width)

        if right > left + EPS and top > bottom + EPS:
            overlap_rects.append((left, bottom, right, top))
            if p.weight < min_support_weight:
                min_support_weight = p.weight

    support_area = _union_area(overlap_rects)
    footprint = l * w
    ratio = support_area / footprint if footprint > EPS else 0.0

    if ratio < 0.999:
        return False, ratio
    if weight > min_support_weight + EPS:
        return False, ratio

    return True, ratio


def _extreme_points(placed: list[_PlacedBox]) -> list[tuple[float, float, float]]:
    points = {(0.0, 0.0, 0.0)}
    for p in placed:
        points.add((round(p.x + p.length, 2), round(p.y, 2), round(p.z, 2)))
        points.add((round(p.x, 2), round(p.y + p.width, 2), round(p.z, 2)))
        points.add((round(p.x, 2), round(p.y, 2), round(p.z + p.height, 2)))
    return sorted(points, key=lambda t: (t[2], t[0], t[1]))


def _corner_distance(x: float, y: float, l: float, w: float, pallet_l: float, pallet_w: float) -> float:
    d1 = x + y
    d2 = x + max(0.0, pallet_w - (y + w))
    d3 = max(0.0, pallet_l - (x + l)) + y
    d4 = max(0.0, pallet_l - (x + l)) + max(0.0, pallet_w - (y + w))
    return min(d1, d2, d3, d4)


def _edge_flags(x: float, y: float, l: float, w: float, pallet_l: float, pallet_w: float) -> tuple[bool, bool, bool, bool]:
    front = y <= EPS
    back = abs((y + w) - pallet_w) <= 0.05
    left = x <= EPS
    right = abs((x + l) - pallet_l) <= 0.05
    return front, back, left, right


def _perimeter_rank(x: float, y: float, l: float, w: float, pallet_l: float, pallet_w: float) -> tuple[int, float, float]:
    front, back, left, right = _edge_flags(x, y, l, w, pallet_l, pallet_w)
    touches_wall = front or back or left or right
    if not touches_wall:
        return (9, x + y, x + y)

    front_corner = front and (left or right)
    rear_corner = back and (left or right)
    front_edge = front
    side_edge = left or right
    rear_edge = back

    corner_dist = _corner_distance(x, y, l, w, pallet_l, pallet_w)
    front_bias = y

    if front_corner:
        return (0, front_bias, corner_dist)
    if front_edge:
        return (1, front_bias, x)
    if side_edge:
        return (2, front_bias, corner_dist)
    if rear_corner:
        return (3, front_bias, corner_dist)
    if rear_edge:
        return (4, front_bias, x)
    return (9, front_bias, corner_dist)


def _split_weight_by_quadrant(x: float, y: float, l: float, w: float, weight: float, pallet_l: float, pallet_w: float) -> list[float]:
    mid_x = pallet_l / 2
    mid_y = pallet_w / 2

    rects = [
        (0.0, 0.0, mid_x, mid_y),
        (mid_x, 0.0, pallet_l, mid_y),
        (0.0, mid_y, mid_x, pallet_w),
        (mid_x, mid_y, pallet_l, pallet_w),
    ]

    footprint = l * w
    if footprint <= EPS:
        return [0.0, 0.0, 0.0, 0.0]

    splits = [0.0, 0.0, 0.0, 0.0]
    for i, (qx0, qy0, qx1, qy1) in enumerate(rects):
        ox0 = max(x, qx0)
        oy0 = max(y, qy0)
        ox1 = min(x + l, qx1)
        oy1 = min(y + w, qy1)
        if ox1 > ox0 + EPS and oy1 > oy0 + EPS:
            area = (ox1 - ox0) * (oy1 - oy0)
            splits[i] = weight * (area / footprint)

    return splits


def _balance_weights_after(state: _PalletState, x: float, y: float, l: float, w: float, weight: float, pallet_l: float, pallet_w: float) -> float:
    weights = [0.0, 0.0, 0.0, 0.0]
    for p in state.placed:
        s = _split_weight_by_quadrant(p.x, p.y, p.length, p.width, p.weight, pallet_l, pallet_w)
        for i in range(4):
            weights[i] += s[i]

    cand = _split_weight_by_quadrant(x, y, l, w, weight, pallet_l, pallet_w)
    for i in range(4):
        weights[i] += cand[i]

    return max(weights) - min(weights)


def _candidate_score(
    x: float,
    y: float,
    z: float,
    l: float,
    w: float,
    pallet_l: float,
    pallet_w: float,
    support_ratio: float,
    balance_penalty: float,
) -> tuple:
    perimeter_rank, front_bias, corner_dist = _perimeter_rank(x, y, l, w, pallet_l, pallet_w)
    edge_gap = min(x, y, max(0.0, pallet_l - (x + l)), max(0.0, pallet_w - (y + w)))

    return (
        z,
        perimeter_rank,
        front_bias,
        corner_dist,
        balance_penalty,
        -support_ratio,
        edge_gap,
        x + y,
    )


def _try_place_unit(state: _PalletState, unit: _UnitBox, pallet_l: float, pallet_w: float, pallet_h: float) -> _PlacedBox | None:
    best: tuple[tuple, _PlacedBox] | None = None

    for x, y, z in _extreme_points(state.placed):
        for l, w, h, rotation in _orientations(unit):
            if x + l > pallet_l + EPS or y + w > pallet_w + EPS or z + h > pallet_h + EPS:
                continue

            if any(_overlap_3d(x, y, z, l, w, h, p) for p in state.placed):
                continue

            front, back, left, right = _edge_flags(x, y, l, w, pallet_l, pallet_w)
            touches_wall = front or back or left or right
            if not touches_wall:
                continue

            ok_support, support_ratio = _support_info(x, y, z, l, w, unit.weight, state.placed)
            if not ok_support:
                continue

            balance_penalty = _balance_weights_after(state, x, y, l, w, unit.weight, pallet_l, pallet_w)

            layer = 1 + sum(1 for p in state.placed if abs((p.z + p.height) - z) <= 0.05)
            placed = _PlacedBox(
                box_id=unit.box_id,
                x=round(x, 2),
                y=round(y, 2),
                z=round(z, 2),
                length=round(l, 2),
                width=round(w, 2),
                height=round(h, 2),
                weight=unit.weight,
                rotation=rotation,
                layer=layer,
            )

            score = _candidate_score(x, y, z, l, w, pallet_l, pallet_w, support_ratio, balance_penalty)
            if best is None or score < best[0]:
                best = (score, placed)

    return best[1] if best else None


def _commit(state: _PalletState, placed: _PlacedBox) -> None:
    state.placed.append(placed)
    state.running_weight += placed.weight


def _build_layer_summaries(state: _PalletState, items_by_box_id: dict[str, DetectedItem], pallet_l: float, pallet_w: float) -> list[LayerSummary]:
    by_z: dict[float, list[_PlacedBox]] = {}
    for p in state.placed:
        by_z.setdefault(round(p.z, 2), []).append(p)

    layer_summaries: list[LayerSummary] = []
    for index, z_start in enumerate(sorted(by_z), start=1):
        boxes = by_z[z_start]
        footprints = [(p.x, p.y, p.x + p.length, p.y + p.width) for p in boxes]
        base_area_used = round(_union_area(footprints), 2)
        base_capacity = pallet_l * pallet_w
        box_names: list[str] = []
        for p in boxes:
            base_id = p.box_id.rsplit('-', 1)[0]
            item = items_by_box_id.get(base_id)
            box_names.append(item.name if item else p.box_id)

        layer_summaries.append(
            LayerSummary(
                layer=index,
                zStart=round(z_start, 2),
                maxHeight=round(max(p.height for p in boxes), 2),
                boxCount=len(boxes),
                baseAreaUsed=base_area_used,
                baseCoveragePct=round((base_area_used / base_capacity) * 100 if base_capacity > EPS else 0.0, 2),
                totalWeightKg=round(sum(p.weight for p in boxes), 2),
                boxNames=box_names,
            )
        )

    return layer_summaries


def _build_packing_summary(state: _PalletState, items_by_box_id: dict[str, DetectedItem], pallet_l: float, pallet_w: float) -> PackingSummary:
    layers = _build_layer_summaries(state, items_by_box_id, pallet_l, pallet_w)
    notes = [
        'Se priorizan esquinas del frente, luego borde frontal, luego laterales y al final borde trasero.',
        'Cada caja debe tocar al menos un lado visible del pallet; no se permiten cajas aisladas en el centro.',
    ]
    if layers:
        first = layers[0]
        notes.append(f'Cobertura de la primera capa: {first.baseCoveragePct:.2f}% del area base.')
        if len(layers) > 1:
            second = layers[1]
            notes.append(f'Cobertura de la segunda capa: {second.baseCoveragePct:.2f}% del area base.')
    return PackingSummary(rules=PACKING_RULES, layers=layers, notes=notes)


def run_palletizing(
    items: list[DetectedItem],
    pallet: PalletRequest,
    allow_overhang_cm: float,
) -> tuple[list[BoxPlan], list[PalletPlanView], StatsResponse, list[str]]:
    del allow_overhang_cm

    pallet_l = pallet.lengthCm
    pallet_w = pallet.widthCm
    pallet_h = pallet.maxHeightCm

    units = _expand_units(items)
    pallets: list[_PalletState] = []
    unpacked_count = 0
    packing_log: list[str] = []

    for unit in units:
        placed = None

        for state in pallets:
            if state.running_weight + unit.weight > pallet.maxWeightKg + EPS:
                continue
            placed = _try_place_unit(state, unit, pallet_l, pallet_w, pallet_h)
            if placed:
                _commit(state, placed)
                packing_log.append(
                    f'Caja {unit.box_id} asignada a pallet {state.pallet_no} en z={placed.z}, pos=({placed.x}, {placed.y}), dims={placed.length}x{placed.width}x{placed.height}.'
                )
                break

        if placed:
            continue

        new_state = _PalletState(pallet_no=len(pallets) + 1, placed=[], running_weight=0.0)
        if unit.weight <= pallet.maxWeightKg + EPS:
            placed = _try_place_unit(new_state, unit, pallet_l, pallet_w, pallet_h)
            if placed:
                _commit(new_state, placed)
                pallets.append(new_state)
                packing_log.append(
                    f'Se abrio pallet {new_state.pallet_no} para {unit.box_id} porque no habia posicion valida visible/perimetral en pallets anteriores.'
                )
                continue

        unpacked_count += 1
        packing_log.append(f'Caja {unit.box_id} quedo sin empacar: no encontro posicion valida.')

    boxes = [
        BoxPlan(
            boxId=item.boxId,
            sku=item.sku,
            name=item.name,
            lengthCm=item.lengthCm,
            widthCm=item.widthCm,
            heightCm=item.heightCm,
            weightKg=item.weightKg,
            qty=item.qty,
        )
        for item in items
    ]

    items_by_box_id = {item.boxId: item for item in items}

    pallet_volume = pallet_l * pallet_w * pallet_h
    pallet_views: list[PalletPlanView] = []

    for state in pallets:
        state.placed.sort(key=lambda p: (p.z, p.x, p.y))
        layout = []
        for p in state.placed:
            base_id = p.box_id.rsplit('-', 1)[0]
            item = items_by_box_id.get(base_id)
            layout.append(
                LayoutItem(
                    boxId=p.box_id,
                    x=p.x,
                    y=p.y,
                    z=p.z,
                    rotation=p.rotation,
                    layer=p.layer,
                    lengthCm=p.length,
                    widthCm=p.width,
                    heightCm=p.height,
                    weightKg=round(p.weight, 2),
                    sku=item.sku if item else None,
                    name=item.name if item else None,
                )
            )

        used_volume = round(sum(p.length * p.width * p.height for p in state.placed), 2)
        utilization = round((used_volume / pallet_volume) * 100 if pallet_volume > EPS else 0.0, 2)

        pallet_views.append(
            PalletPlanView(
                palletNo=state.pallet_no,
                layout=layout,
                stats=StatsResponse(
                    totalWeightKg=round(state.running_weight, 2),
                    usedVolumeCm3=used_volume,
                    utilizationPct=utilization,
                    unpackedCount=0,
                ),
                packingSummary=_build_packing_summary(state, items_by_box_id, pallet_l, pallet_w),
            )
        )

    overall_volume = round(sum(v.stats.usedVolumeCm3 for v in pallet_views), 2)
    overall_capacity = pallet_volume * len(pallet_views)
    overall_util = round((overall_volume / overall_capacity) * 100 if overall_capacity > EPS else 0.0, 2)

    overall_stats = StatsResponse(
        totalWeightKg=round(sum(v.stats.totalWeightKg for v in pallet_views), 2),
        usedVolumeCm3=overall_volume,
        utilizationPct=overall_util,
        unpackedCount=unpacked_count,
    )

    return boxes, pallet_views, overall_stats, packing_log
