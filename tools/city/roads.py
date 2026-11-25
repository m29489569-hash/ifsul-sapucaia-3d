"""Conflacao de ruas do Overture Maps com as 9 ruas-ancora e geracao de geometria viaria."""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Any

import shapely
from shapely.geometry import LineString, MultiLineString, Point, Polygon
from shapely.geometry.base import BaseGeometry
from shapely.ops import nearest_points, unary_union
from shapely.strtree import STRtree

from .codec import (
    CAT_ROADS,
    CAT_SIDEWALKS,
    FLAG_CAN_QUERY,
    FLAG_COLLIDE,
    FLAG_SHADOW,
    MAT_ASPHALT,
    MAT_CONCRETE,
    MAT_SLATE,
    MAT_SMOOTH_PLASTIC,
    PART_BLOCK,
    PART_CYLINDER,
    STUDS_PER_METER,
    TilePart,
)
from .project import normalize_street_name

EXCLUDED_ROAD_CLASSES = {
    "footway",
    "path",
    "steps",
    "cycleway",
    "bridleway",
    "pedestrian",
    "corridor",
    "via_ferrata",
}

DEFAULT_WIDTHS_M: dict[str, float] = {
    "motorway": 11.0,
    "trunk": 10.5,
    "primary": 9.0,
    "secondary": 8.0,
    "tertiary": 7.5,
    "residential": 7.0,
    "living_street": 6.5,
    "unclassified": 7.0,
    "service": 4.5,
    "track": 5.0,
}

UNPAVED_SURFACES = {"unpaved", "dirt", "gravel", "earth", "sand", "ground", "grass", "mud"}
CENTERLINE_CLASSES = {"motorway", "trunk", "primary", "secondary", "tertiary"}
NO_SIDEWALK_CLASSES = {"service", "track", "motorway", "trunk"}


@dataclass(slots=True)
class RoadSegment:
    p0: tuple[float, float]
    p1: tuple[float, float]
    width_m: float
    rclass: str
    is_unpaved: bool
    has_sidewalk: bool
    has_centerline: bool


@dataclass(slots=True)
class RoadNetworkOutput:
    parts: list[TilePart]
    road_clearance_geoms: list[BaseGeometry]
    road_lines: list[LineString]
    stats: dict[str, int]


def _extract_linestrings(geom: BaseGeometry) -> list[LineString]:
    if geom.is_empty:
        return []
    if geom.geom_type == "LineString":
        return [geom] if geom.length > 0.4 else []
    if geom.geom_type in {"MultiLineString", "GeometryCollection"}:
        out: list[LineString] = []
        for g in geom.geoms:
            out.extend(_extract_linestrings(g))
        return out
    return []


def _angle_diff_deg(dx1: float, dz1: float, dx2: float, dz2: float) -> float:
    n1 = math.hypot(dx1, dz1)
    n2 = math.hypot(dx2, dz2)
    if n1 < 1e-6 or n2 < 1e-6:
        return 90.0
    dot = abs((dx1 * dx2 + dz1 * dz2) / (n1 * n2))
    dot = max(-1.0, min(1.0, dot))
    return math.degrees(math.acos(dot))


def _is_parallel_duplicate(line: LineString, anchors: list[tuple[LineString, float, str]]) -> bool:
    """Detecta trechos Overture que duplicam paralelamente uma rua-ancora existente."""
    if line.length < 1.0:
        return True
    sample_count = max(3, min(15, int(line.length / 8.0) + 1))
    inside = 0
    parallel = 0
    for i in range(sample_count):
        frac = i / (sample_count - 1)
        pt = line.interpolate(frac, normalized=True)
        d0 = max(0.0, frac * line.length - 1.0)
        d1 = min(line.length, frac * line.length + 1.0)
        q0 = line.interpolate(d0)
        q1 = line.interpolate(d1)
        ldx, ldz = q1.x - q0.x, q1.y - q0.y

        for anc, w, _ in anchors:
            if anc.distance(pt) <= (w * 0.5 + 5.0):
                inside += 1
                ad = anc.project(pt)
                a0 = anc.interpolate(max(0.0, ad - 1.0))
                a1 = anc.interpolate(min(anc.length, ad + 1.0))
                if _angle_diff_deg(ldx, ldz, a1.x - a0.x, a1.y - a0.y) < 25.0:
                    parallel += 1
                break
    return (inside / sample_count) >= 0.60 and (parallel / sample_count) >= 0.50


def _split_long_segment(p0: tuple[float, float], p1: tuple[float, float], max_len_m: float = 110.0) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    dx = p1[0] - p0[0]
    dz = p1[1] - p0[1]
    length = math.hypot(dx, dz)
    if length <= max_len_m:
        return [(p0, p1)]
    n = int(math.ceil(length / max_len_m))
    pts = [(p0[0] + dx * (i / n), p0[1] + dz * (i / n)) for i in range(n + 1)]
    return [(pts[i], pts[i + 1]) for i in range(n)]


def _segment_center_yaw(p0: tuple[float, float], p1: tuple[float, float]) -> tuple[float, float, float, float]:
    """Retorna (cx, cz, length, yaw_rad) com +Z local ao longo de (p0->p1)."""
    dx = p1[0] - p0[0]
    dz = p1[1] - p0[1]
    length = math.hypot(dx, dz)
    cx = (p0[0] + p1[0]) * 0.5
    cz = (p0[1] + p1[1]) * 0.5
    # Em Roblox, CFrame.Angles(0, yaw, 0) leva +Z local (0,0,1) para (sin(yaw), 0, cos(yaw))
    yaw = math.atan2(dx, dz)
    return cx, cz, length, yaw


def _snap_key(pt: tuple[float, float], cell_m: float = 0.6) -> tuple[int, int]:
    return (int(round(pt[0] / cell_m)), int(round(pt[1] / cell_m)))


def build_roads(
    road_records: list[dict[str, Any]],
    boundary_xz: BaseGeometry,
    campus_data: dict[str, Any],
) -> RoadNetworkOutput:
    """Conflaciona ruas calibradas com o campus e gera Parts de asfalto, calcada e faixas."""
    campus_poly = Polygon(campus_data["perimeter"]).buffer(1.2, join_style="mitre")

    anchors: list[tuple[LineString, float, str]] = []
    anchor_carriages = []
    anchor_corridors = []
    for st in campus_data.get("streets", []):
        pts = st.get("points") or []
        if len(pts) < 2:
            continue
        ln = LineString(pts)
        w = float(st.get("width", 7.5))
        key = normalize_street_name(st.get("name"))
        anchors.append((ln, w, key))
        anchor_carriages.append(ln.buffer(w * 0.5 + 0.6, cap_style="flat", join_style="round"))
        anchor_corridors.append(ln.buffer(w * 0.5 + 2.8, cap_style="flat", join_style="round"))

    anchor_carriage_union = unary_union(anchor_carriages) if anchor_carriages else Polygon()
    anchor_corridor_union = unary_union(anchor_corridors) if anchor_corridors else Polygon()

    # Tambem protege a faixa de entrada/driveway do campus
    driveway_geoms = [
        LineString(d["points"]).buffer(float(d.get("width", 6.0)) * 0.5 + 0.5, cap_style="flat")
        for d in campus_data.get("driveways", [])
        if len(d.get("points", [])) >= 2
    ]
    protected_campus = unary_union([campus_poly, *driveway_geoms]) if driveway_geoms else campus_poly

    kept_edges: list[RoadSegment] = []
    kept_lines: list[LineString] = []
    carriage_polys: list[BaseGeometry] = []
    sidewalk_polys: list[BaseGeometry] = []

    stats = {
        "raw_roads": 0,
        "dropped_tunnel_or_foot": 0,
        "dropped_duplicate_anchor": 0,
        "snapped_to_anchor": 0,
        "segments": 0,
        "junction_nodes": 0,
        "sidewalk_parts": 0,
        "lane_stripes": 0,
    }

    # Passo 1: filtrar, recortar pelo limite/campus e conflacionar com ancoras
    raw_lines_meta: list[tuple[LineString, float, str, bool, bool, bool]] = []
    for rec in road_records:
        stats["raw_roads"] += 1
        rclass = rec.get("class", "unclassified")
        if rec.get("is_tunnel") or rclass in EXCLUDED_ROAD_CLASSES:
            stats["dropped_tunnel_or_foot"] += 1
            continue

        geom = rec["geom"]
        clipped = geom.intersection(boundary_xz)
        if clipped.is_empty:
            continue
        clipped = clipped.difference(protected_campus)
        if clipped.is_empty:
            continue

        w = rec.get("width")
        if w is None or w < 3.5 or w > 22.0:
            w = DEFAULT_WIDTHS_M.get(rclass, 7.0)
        else:
            w = float(w)

        surface = (rec.get("surface") or "").lower()
        is_unpaved = rclass == "track" or surface in UNPAVED_SURFACES
        has_sidewalk = (not is_unpaved) and (rclass not in NO_SIDEWALK_CLASSES)
        has_centerline = (not is_unpaved) and (rclass in CENTERLINE_CLASSES)

        for ln in _extract_linestrings(clipped):
            if _is_parallel_duplicate(ln, anchors):
                stats["dropped_duplicate_anchor"] += 1
                continue
            rem = ln.difference(anchor_carriage_union)
            for sub in _extract_linestrings(rem):
                coords = list(sub.coords)
                if len(coords) < 2:
                    continue
                # Solda pontas proximas a uma rua-ancora por baixo da pista existente (py=0.08 vs 0.085)
                for end_idx in (0, -1):
                    end_pt = Point(coords[end_idx])
                    best_anc = min(anchors, key=lambda a: a[0].distance(end_pt), default=None)
                    if best_anc is not None:
                        anc_ln, _, _ = best_anc
                        dist = anc_ln.distance(end_pt)
                        if 0.05 < dist <= 13.5:
                            target = nearest_points(end_pt, anc_ln)[1]
                            if not protected_campus.buffer(-0.2).contains(target):
                                coords[end_idx] = (float(target.x), float(target.y))
                                stats["snapped_to_anchor"] += 1
                clean_ln = LineString(coords).simplify(0.30, preserve_topology=True)
                if clean_ln.length >= 1.2:
                    raw_lines_meta.append((clean_ln, w, rclass, is_unpaved, has_sidewalk, has_centerline))
                    kept_lines.append(clean_ln)

    # Passo 2: inserir nos de intersecao entre vias via STRtree e fazer snap
    if raw_lines_meta:
        geoms_list = [item[0] for item in raw_lines_meta]
        tree = STRtree(geoms_list)
        noded_meta = []
        for idx, (ln, w, rclass, is_unpaved, has_sidewalk, has_centerline) in enumerate(raw_lines_meta):
            split_pts: list[tuple[float, float]] = list(ln.coords)
            for j in tree.query(ln):
                if j == idx:
                    continue
                inter = ln.intersection(geoms_list[j])
                if inter.is_empty:
                    continue
                pts_found = []
                if inter.geom_type == "Point":
                    pts_found.append((float(inter.x), float(inter.y)))
                elif inter.geom_type == "MultiPoint":
                    pts_found.extend((float(g.x), float(g.y)) for g in inter.geoms)
                for px, pz in pts_found:
                    split_pts.append((px, pz))
            # Ordena todos os pontos ao longo da linha preservando ordem topologica
            uniq_d: list[tuple[float, tuple[float, float]]] = []
            for p in split_pts:
                d = ln.project(Point(p))
                if not any(abs(d - existing_d) < 0.4 for existing_d, _ in uniq_d):
                    uniq_d.append((d, (float(p[0]), float(p[1]))))
            uniq_d.sort(key=lambda x: x[0])
            if len(uniq_d) >= 2:
                noded_meta.append((LineString([p for _, p in uniq_d]), w, rclass, is_unpaved, has_sidewalk, has_centerline))
        raw_lines_meta = noded_meta

    node_accum: dict[tuple[int, int], list[tuple[float, float]]] = {}
    for ln, *_ in raw_lines_meta:
        for pt in ln.coords:
            k = _snap_key((pt[0], pt[1]))
            node_accum.setdefault(k, []).append((float(pt[0]), float(pt[1])))
    snapped_pos: dict[tuple[int, int], tuple[float, float]] = {
        k: (
            sum(p[0] for p in pts) / len(pts),
            sum(p[1] for p in pts) / len(pts),
        )
        for k, pts in node_accum.items()
    }

    node_widths: dict[tuple[int, int], list[tuple[float, bool]]] = {}
    for ln, w, rclass, is_unpaved, has_sidewalk, has_centerline in raw_lines_meta:
        coords = [snapped_pos[_snap_key((c[0], c[1]))] for c in ln.coords]
        for i in range(len(coords) - 1):
            p0, p1 = coords[i], coords[i + 1]
            if math.hypot(p1[0] - p0[0], p1[1] - p0[1]) < 0.8:
                continue
            node_widths.setdefault(_snap_key(p0), []).append((w, is_unpaved))
            node_widths.setdefault(_snap_key(p1), []).append((w, is_unpaved))
            for seg_a, seg_b in _split_long_segment(p0, p1, max_len_m=110.0):
                kept_edges.append(
                    RoadSegment(
                        p0=seg_a,
                        p1=seg_b,
                        width_m=w,
                        rclass=rclass,
                        is_unpaved=is_unpaved,
                        has_sidewalk=has_sidewalk,
                        has_centerline=has_centerline,
                    )
                )

        carriage_polys.append(LineString(coords).buffer(w * 0.5, cap_style="round", join_style="round"))
        if has_sidewalk:
            sidewalk_polys.append(LineString(coords).buffer(w * 0.5 + 2.0, cap_style="flat", join_style="round"))

    all_carriage_items = [*carriage_polys, *anchor_carriages, protected_campus]
    carriage_tree = STRtree(all_carriage_items) if all_carriage_items else None
    all_clearance_geoms = [
        g.buffer(0.25)
        for g in [*all_carriage_items, *sidewalk_polys, *anchor_corridors]
        if not g.is_empty
    ]

    parts: list[TilePart] = []

    # Passo 3: emitir Parts de pista
    for seg in kept_edges:
        stats["segments"] += 1
        cx, cz, length, yaw = _segment_center_yaw(seg.p0, seg.p1)
        mat = MAT_SLATE if seg.is_unpaved else MAT_ASPHALT
        rgb = (138, 112, 84) if seg.is_unpaved else (63, 65, 68)
        py_studs = 0.075 if seg.is_unpaved else 0.08
        parts.append(
            TilePart(
                part_type=PART_BLOCK,
                material=mat,
                category=CAT_ROADS,
                flags=FLAG_COLLIDE | FLAG_SHADOW | FLAG_CAN_QUERY,
                r=rgb[0],
                g=rgb[1],
                b=rgb[2],
                px_studs=cx * STUDS_PER_METER,
                py_studs=py_studs,
                pz_studs=cz * STUDS_PER_METER,
                sx_studs=seg.width_m * STUDS_PER_METER,
                sy_studs=0.06,
                sz_studs=length * STUDS_PER_METER,
                yaw_rad=yaw,
            )
        )

        # Faixa tracejada central (padrao CONTRAN: 3m traco a cada 9m)
        if seg.has_centerline and length >= 10.0:
            dx = (seg.p1[0] - seg.p0[0]) / length
            dz = (seg.p1[1] - seg.p0[1]) / length
            dash_len = 3.0
            step = 9.0
            s = 3.0
            while s + dash_len <= length - 3.0:
                dcx = seg.p0[0] + dx * (s + dash_len * 0.5)
                dcz = seg.p0[1] + dz * (s + dash_len * 0.5)
                parts.append(
                    TilePart(
                        part_type=PART_BLOCK,
                        material=MAT_SMOOTH_PLASTIC,
                        category=CAT_ROADS,
                        flags=0,
                        r=245,
                        g=245,
                        b=240,
                        px_studs=dcx * STUDS_PER_METER,
                        py_studs=0.13,
                        pz_studs=dcz * STUDS_PER_METER,
                        sx_studs=0.55,
                        sy_studs=0.05,
                        sz_studs=dash_len * STUDS_PER_METER,
                        yaw_rad=yaw,
                    )
                )
                stats["lane_stripes"] += 1
                s += step

        # Calcadas laterais recortadas contra pistas e campus
        if seg.has_sidewalk and length >= 2.5:
            dx = (seg.p1[0] - seg.p0[0]) / length
            dz = (seg.p1[1] - seg.p0[1]) / length
            nx, nz = -dz, dx
            sw_width = 2.0
            offset = seg.width_m * 0.5 + sw_width * 0.5
            for side in (-1.0, 1.0):
                sp0 = (seg.p0[0] + nx * offset * side, seg.p0[1] + nz * offset * side)
                sp1 = (seg.p1[0] + nx * offset * side, seg.p1[1] + nz * offset * side)
                sw_line = LineString([sp0, sp1])
                # Subtrai apenas pistas proximas via STRtree (rapido mesmo em cidades grandes)
                if carriage_tree is not None:
                    nearby = [all_carriage_items[idx] for idx in carriage_tree.query(sw_line.buffer(1.1))]
                    if nearby:
                        sw_free = sw_line.difference(unary_union(nearby).buffer(0.95))
                    else:
                        sw_free = sw_line
                else:
                    sw_free = sw_line
                for sub_sw in _extract_linestrings(sw_free):
                    if sub_sw.length < 1.5:
                        continue
                    sc0 = (float(sub_sw.coords[0][0]), float(sub_sw.coords[0][1]))
                    sc1 = (float(sub_sw.coords[-1][0]), float(sub_sw.coords[-1][1]))
                    scx, scz, slen, syaw = _segment_center_yaw(sc0, sc1)
                    parts.append(
                        TilePart(
                            part_type=PART_BLOCK,
                            material=MAT_CONCRETE,
                            category=CAT_SIDEWALKS,
                            flags=FLAG_COLLIDE | FLAG_SHADOW | FLAG_CAN_QUERY,
                            r=155,
                            g=149,
                            b=140,
                            px_studs=scx * STUDS_PER_METER,
                            py_studs=0.11,
                            pz_studs=scz * STUDS_PER_METER,
                            sx_studs=sw_width * STUDS_PER_METER,
                            sy_studs=0.22,
                            sz_studs=slen * STUDS_PER_METER,
                            yaw_rad=syaw,
                        )
                    )
                    stats["sidewalk_parts"] += 1

    # Passo 4: discos de juncao nos cruzamentos, dobras e divisas municipais (py=0.09 evita z-fighting)
    boundary_guard = boundary_xz.boundary.buffer(1.2)
    shapely.prepare(boundary_guard)
    for key, incident in node_widths.items():
        nx, nz = snapped_pos[key]
        pt_node = Point(nx, nz)
        if len(incident) < 2 and not (len(incident) == 1 and boundary_guard.intersects(pt_node)):
            continue
        if protected_campus.contains(pt_node):
            continue
        max_w = max(w for w, _ in incident)
        all_unpaved = all(u for _, u in incident)
        stats["junction_nodes"] += 1
        parts.append(
            TilePart(
                part_type=PART_CYLINDER,
                material=MAT_SLATE if all_unpaved else MAT_ASPHALT,
                category=CAT_ROADS,
                flags=FLAG_COLLIDE | FLAG_SHADOW | FLAG_CAN_QUERY,
                r=138 if all_unpaved else 63,
                g=112 if all_unpaved else 65,
                b=84 if all_unpaved else 68,
                px_studs=nx * STUDS_PER_METER,
                py_studs=0.08 if all_unpaved else 0.09,
                pz_studs=nz * STUDS_PER_METER,
                sx_studs=max_w * 1.02 * STUDS_PER_METER,
                sy_studs=0.06,
                sz_studs=max_w * 1.02 * STUDS_PER_METER,
                yaw_rad=0.0,
            )
        )

    return RoadNetworkOutput(
        parts=parts,
        road_clearance_geoms=all_clearance_geoms,
        road_lines=kept_lines,
        stats=stats,
    )
