"""Geracao simplificada de fachadas de edificios a partir dos footprints do Overture Maps."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import math
from typing import Any

import shapely
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box as shp_box
from shapely.geometry.base import BaseGeometry
from shapely.ops import unary_union
from shapely.strtree import STRtree

from .codec import (
    CAT_BUILDINGS,
    CAT_ROADS,
    CAT_SIDEWALKS,
    FLAG_CAN_QUERY,
    FLAG_COLLIDE,
    FLAG_DETAIL,
    FLAG_SHADOW,
    MAT_CONCRETE,
    MAT_METAL,
    MAT_SLATE,
    MAT_SMOOTH_PLASTIC,
    PART_BLOCK,
    PART_CYLINDER,
    PART_WEDGE,
    STUDS_PER_METER,
    TilePart,
)

# Paleta sobria realista do Rio Grande do Sul (fachadas)
WALL_PALETTE_RESIDENTIAL = [
    (234, 228, 216),  # creme claro
    (242, 240, 234),  # branco sujo
    (220, 206, 186),  # areia
    (214, 186, 162),  # pessego/terracota suave
    (208, 214, 218),  # cinza azulado claro
    (226, 214, 180),  # ocre claro
    (198, 174, 154),  # reboco terroso
    (240, 222, 150),  # amarelo suave
    (196, 218, 190),  # verde menta
    (232, 196, 180),  # salmao
    (176, 200, 222),  # azul claro
    (222, 170, 150),  # tijolo claro
]

WALL_PALETTE_COMMERCIAL = [
    (228, 230, 232),
    (205, 210, 215),
    (222, 216, 204),
    (184, 192, 200),
]

WALL_PALETTE_INDUSTRIAL = [
    (195, 198, 202),
    (176, 182, 188),
    (212, 208, 200),
]

ROOF_PALETTE_TILE = [
    (168, 88, 62),   # telha barro
    (144, 76, 56),   # telha escura
    (118, 120, 122), # fibrocimento
]


@dataclass(slots=True)
class OrientedBox:
    cx: float
    cz: float
    width_u: float   # dimensao ao longo de u (eixo maior)
    depth_v: float   # dimensao ao longo de v (eixo menor)
    yaw_u: float     # angulo de u para colocar +X ao longo de u e +Z ao longo de v


def _stable_hash(bid: str) -> int:
    return int.from_bytes(hashlib.blake2b(bid.encode("utf-8"), digest_size=8).digest(), "little")


def _obb_params(poly: Polygon) -> OrientedBox:
    rect = poly.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)[:4]
    edges = []
    for i in range(4):
        p0, p1 = coords[i], coords[(i + 1) % 4]
        dx = p1[0] - p0[0]
        dz = p1[1] - p0[1]
        edges.append((math.hypot(dx, dz), dx, dz))
    # Pega duas arestas adjacentes (0 e 1)
    l0, dx0, dz0 = edges[0]
    l1, dx1, dz1 = edges[1]
    if l0 >= l1:
        u_len, ux, uz = l0, dx0, dz0
        v_len = l1
    else:
        u_len, ux, uz = l1, dx1, dz1
        v_len = l0

    cx = float(rect.centroid.x)
    cz = float(rect.centroid.y)
    # Em Roblox, CFrame.Angles(0, yaw, 0) leva +X=(1,0,0) para (cos(yaw), 0, -sin(yaw))
    # Logo cos(yaw) = ux/u_len, -sin(yaw) = uz/u_len -> yaw = atan2(-uz, ux)
    yaw = math.atan2(-uz, ux) if u_len > 1e-6 else 0.0
    return OrientedBox(cx=cx, cz=cz, width_u=u_len, depth_v=v_len, yaw_u=yaw)


def obb_world_polygon(box: OrientedBox, margin_m: float = 0.0) -> Polygon:
    """Retorna o poligono 2D exato (em metros) da OBB no sistema do Roblox (+Z=Sul)."""
    hx = max(0.5, box.width_u * 0.5 + margin_m)
    hz = max(0.5, box.depth_v * 0.5 + margin_m)
    p = shp_box(-hx, -hz, hx, hz)
    p = affinity.rotate(p, -math.degrees(box.yaw_u), origin=(0.0, 0.0))
    return affinity.translate(p, xoff=box.cx, yoff=box.cz)


def _tile_part_footprint_m(part: TilePart, extra_margin_m: float = 0.0) -> Polygon:
    px = part.px_studs / STUDS_PER_METER
    pz = part.pz_studs / STUDS_PER_METER
    if part.part_type == PART_CYLINDER:
        r = max(part.sx_studs, part.sz_studs) * 0.5 / STUDS_PER_METER + extra_margin_m
        return Point(px, pz).buffer(max(0.2, r), resolution=8)
    hx = max(0.2, part.sx_studs * 0.5 / STUDS_PER_METER + extra_margin_m)
    hz = max(0.2, part.sz_studs * 0.5 / STUDS_PER_METER + extra_margin_m)
    p = shp_box(-hx, -hz, hx, hz)
    p = affinity.rotate(p, -math.degrees(part.yaw_rad), origin=(0.0, 0.0))
    return affinity.translate(p, xoff=px, yoff=pz)


def _decompose_footprint(poly: Polygon, min_area_m2: float = 14.0, depth: int = 0) -> list[OrientedBox]:
    obb_geom = poly.minimum_rotated_rectangle
    if obb_geom.area <= 0.1:
        return []
    fill_ratio = poly.area / obb_geom.area
    if fill_ratio >= 0.84 or depth >= 3:
        box = _obb_params(poly)
        if box.width_u >= 2.2 and box.depth_v >= 2.2:
            return [box]
        return []

    # Divide pelo centro ao longo do eixo menor (cortando o eixo maior ao meio); se nao dividir, tenta o outro eixo
    box = _obb_params(poly)
    ux = math.cos(box.yaw_u)
    uz = -math.sin(box.yaw_u)
    vx = -uz
    vz = ux
    span = max(box.width_u, box.depth_v) + 2.0

    pieces: list[Polygon] = []
    for axis_x, axis_z in ((vx, vz), (ux, uz)):
        cut_line = LineString([
            (box.cx - axis_x * span, box.cz - axis_z * span),
            (box.cx + axis_x * span, box.cz + axis_z * span),
        ])
        rem = poly.difference(cut_line.buffer(0.05))
        cand = [rem] if rem.geom_type == "Polygon" else [g for g in getattr(rem, "geoms", []) if g.geom_type == "Polygon"]
        cand = [g for g in cand if g.area >= min_area_m2]
        if len(cand) >= 2:
            pieces = cand
            break

    if not pieces:
        if fill_ratio >= 0.65 and box.width_u >= 2.2 and box.depth_v >= 2.2:
            return [box]
        return []

    out: list[OrientedBox] = []
    for p in pieces:
        out.extend(_decompose_footprint(p, min_area_m2=min_area_m2, depth=depth + 1))
    return out[:4]


def _estimate_height_and_kind(
    rec: dict[str, Any],
    area_m2: float,
    h_seed: int,
    height_override: float | None,
) -> tuple[float, str]:
    bclass = (rec.get("class") or "").lower()
    if height_override is not None:
        h = max(2.8, min(60.0, float(height_override)))
    elif rec.get("height") is not None and 2.5 <= rec["height"] <= 65.0:
        h = float(rec["height"])
    elif rec.get("num_floors") is not None and 1 <= rec["num_floors"] <= 20:
        h = float(rec["num_floors"]) * 3.05
    else:
        r = (h_seed % 1000) / 1000.0
        if bclass in {"industrial", "warehouse", "manufacture"} or area_m2 >= 500.0:
            h = 6.5 + r * 2.5
        elif area_m2 < 130.0:
            h = 6.0 if r > 0.80 else (3.1 + r * 0.7)
        elif area_m2 < 320.0:
            if r < 0.45:
                h = 3.4 + (r * 0.6)
            elif r < 0.85:
                h = 6.2 + (r * 0.8)
            else:
                h = 9.0 + r * 1.2
        else:
            h = 6.8 + r * 6.0

    if bclass in {"industrial", "warehouse", "manufacture"} or (area_m2 >= 450.0 and h <= 10.5):
        kind = "warehouse"
    elif bclass in {"commercial", "retail", "supermarket", "office"} or h > 7.8 or area_m2 >= 280.0:
        kind = "commercial_or_midrise"
    else:
        kind = "house"
    return h, kind


def build_buildings(
    building_records: list[dict[str, Any]],
    boundary_xz: BaseGeometry,
    campus_poly: BaseGeometry,
    road_clearance_poly: BaseGeometry | list[BaseGeometry],
    overrides: dict[str, Any],
    extra_road_parts: list[TilePart] | None = None,
    anchor_streets: list[dict[str, Any]] | None = None,
) -> tuple[list[TilePart], list[Polygon], dict[str, int]]:
    """Converte footprints em fachadas simplificadas garantindo zero sobreposicao com ruas/calcadas."""
    exclude_ids = set(overrides.get("exclude_ids") or [])
    height_overrides = overrides.get("heights_m") or {}

    parts: list[TilePart] = []
    preview_polys: list[Polygon] = []
    stats = {
        "raw_buildings": len(building_records),
        "dropped_small": 0,
        "dropped_campus_or_road": 0,
        "post_filter_dropped": 0,
        "kept_buildings": 0,
        "building_parts": 0,
    }

    campus_guard = campus_poly.buffer(2.5)
    shapely.prepare(boundary_xz)
    shapely.prepare(campus_guard)

    if isinstance(road_clearance_poly, list):
        clearance_list = [g for g in road_clearance_poly if not g.is_empty]
    elif road_clearance_poly is not None and not road_clearance_poly.is_empty:
        clearance_list = [road_clearance_poly.buffer(0.25)]
    else:
        clearance_list = []
    road_tree = STRtree(clearance_list) if clearance_list else None

    exact_road_polys: list[BaseGeometry] = []
    if extra_road_parts:
        for rp in extra_road_parts:
            if rp.category in (CAT_ROADS, CAT_SIDEWALKS) and rp.flags != 0:
                exact_road_polys.append(_tile_part_footprint_m(rp, extra_margin_m=0.08))
    if anchor_streets:
        for st in anchor_streets:
            pts = st.get("points") or []
            if len(pts) >= 2:
                exact_road_polys.append(
                    LineString(pts).buffer(float(st.get("width", 7.5)) * 0.5 + 2.2, cap_style="flat")
                )
    exact_road_tree = STRtree(exact_road_polys) if exact_road_polys else None

    def _box_conflicts(b: OrientedBox) -> bool:
        b_poly = obb_world_polygon(b, margin_m=0.35)
        if campus_guard.intersects(b_poly):
            return True
        if road_tree is not None and any(clearance_list[idx].intersects(b_poly) for idx in road_tree.query(b_poly)):
            return True
        if exact_road_tree is not None and any(exact_road_polys[idx].intersects(b_poly) for idx in exact_road_tree.query(b_poly)):
            return True
        return False

    for rec in building_records:
        bid = rec["id"]
        if bid in exclude_ids:
            continue
        geom = rec["geom"]
        if geom.geom_type == "MultiPolygon":
            geom = max(geom.geoms, key=lambda g: g.area, default=Polygon())
        if geom.geom_type != "Polygon" or not geom.is_valid:
            geom = geom.buffer(0)
            if geom.geom_type != "Polygon":
                continue

        if geom.area < 15.0:
            stats["dropped_small"] += 1
            continue
        if not boundary_xz.intersects(geom.centroid):
            continue
        if campus_guard.intersects(geom):
            stats["dropped_campus_or_road"] += 1
            continue

        # Se o footprint bruto encosta em rua/calcada, recorta apenas a porcao livre
        work_geoms: list[Polygon]
        if road_tree is not None:
            hit_idxs = road_tree.query(geom)
            hits = [clearance_list[idx] for idx in hit_idxs if clearance_list[idx].intersects(geom)]
            if hits:
                diff = geom.difference(unary_union(hits))
                cands = [diff] if diff.geom_type == "Polygon" else [g for g in getattr(diff, "geoms", []) if g.geom_type == "Polygon"]
                work_geoms = [g for g in cands if g.area >= 15.0 and not campus_guard.intersects(g)]
                if not work_geoms:
                    stats["dropped_campus_or_road"] += 1
                    continue
            else:
                work_geoms = [geom]
        else:
            work_geoms = [geom]

        raw_boxes: list[OrientedBox] = []
        for wg in work_geoms:
            raw_boxes.extend(_decompose_footprint(wg))

        valid_boxes: list[OrientedBox] = []
        for b in raw_boxes:
            if not _box_conflicts(b):
                valid_boxes.append(b)
            else:
                # Tenta recuar ate 15% mantendo dimensao minima >= 3.0 m
                shrunk = OrientedBox(
                    cx=b.cx,
                    cz=b.cz,
                    width_u=b.width_u * 0.85,
                    depth_v=b.depth_v * 0.85,
                    yaw_u=b.yaw_u,
                )
                if shrunk.width_u >= 3.0 and shrunk.depth_v >= 3.0 and not _box_conflicts(shrunk):
                    valid_boxes.append(shrunk)
                else:
                    stats["post_filter_dropped"] += 1

        if not valid_boxes:
            if not raw_boxes:
                stats["dropped_small"] += 1
            continue

        seed = _stable_hash(bid)
        h_ov = height_overrides.get(bid)
        height_m, kind = _estimate_height_and_kind(rec, geom.area, seed, h_ov)

        if kind == "warehouse":
            w_rgb = WALL_PALETTE_INDUSTRIAL[seed % len(WALL_PALETTE_INDUSTRIAL)]
            w_mat = MAT_CONCRETE
        elif kind == "commercial_or_midrise":
            w_rgb = WALL_PALETTE_COMMERCIAL[seed % len(WALL_PALETTE_COMMERCIAL)]
            w_mat = MAT_SMOOTH_PLASTIC
        else:
            w_rgb = WALL_PALETTE_RESIDENTIAL[seed % len(WALL_PALETTE_RESIDENTIAL)]
            w_mat = MAT_CONCRETE

        roof_rgb = ROOF_PALETTE_TILE[(seed >> 8) % len(ROOF_PALETTE_TILE)]

        # Variacao sutil de tom por edificio (determinstica) para quebrar a repeticao da paleta
        jitter = ((seed >> 16) % 15) - 7
        w_rgb = tuple(max(0, min(255, c + jitter)) for c in w_rgb)
        trim_rgb = tuple(max(0, c - 55) for c in w_rgb)
        win_rgb = (52, 78, 104)

        kept_any_box = False
        for box in valid_boxes:
            sx = box.width_u * STUDS_PER_METER
            sz = box.depth_v * STUDS_PER_METER
            sy = height_m * STUDS_PER_METER
            cx_s = box.cx * STUDS_PER_METER
            cz_s = box.cz * STUDS_PER_METER

            group_parts: list[TilePart] = [
                TilePart(
                    part_type=PART_BLOCK,
                    material=w_mat,
                    category=CAT_BUILDINGS,
                    flags=FLAG_COLLIDE | FLAG_SHADOW | FLAG_CAN_QUERY,
                    r=w_rgb[0],
                    g=w_rgb[1],
                    b=w_rgb[2],
                    px_studs=cx_s,
                    py_studs=sy * 0.5,
                    pz_studs=cz_s,
                    sx_studs=sx,
                    sy_studs=sy,
                    sz_studs=sz,
                    yaw_rad=box.yaw_u,
                )
            ]

            # Detalhes baratos: rodape escuro + fita de janelas por andar (1 Part cada, envolvendo a fachada)
            def _detail(center_y_m: float, h_m: float, grow_m: float, rgb: tuple[int, int, int]) -> TilePart:
                return TilePart(
                    part_type=PART_BLOCK,
                    material=MAT_SMOOTH_PLASTIC,
                    category=CAT_BUILDINGS,
                    flags=FLAG_DETAIL,
                    r=rgb[0],
                    g=rgb[1],
                    b=rgb[2],
                    px_studs=cx_s,
                    py_studs=center_y_m * STUDS_PER_METER,
                    pz_studs=cz_s,
                    sx_studs=sx + grow_m * 2.0 * STUDS_PER_METER,
                    sy_studs=h_m * STUDS_PER_METER,
                    sz_studs=sz + grow_m * 2.0 * STUDS_PER_METER,
                    yaw_rad=box.yaw_u,
                )

            group_parts.append(_detail(0.3, 0.6, 0.07, trim_rgb))
            if kind != "warehouse" and min(box.width_u, box.depth_v) >= 3.5:
                n_floors = max(1, min(8, int(round(height_m / 3.1))))
                floor_h = height_m / n_floors
                win_h = min(1.2, floor_h * 0.36)
                for f in range(n_floors):
                    group_parts.append(_detail(f * floor_h + floor_h * 0.58, win_h, 0.04, win_rgb))

            # Cobertura por tipologia
            if kind == "house":
                roof_h_m = min(1.5, max(0.7, box.depth_v * 0.22))
                roof_sy = roof_h_m * STUDS_PER_METER
                half_v_m = box.depth_v * 0.25 + 0.12
                vx = math.sin(box.yaw_u)
                vz = math.cos(box.yaw_u)
                for side in (-1.0, 1.0):
                    w_yaw = box.yaw_u if side < 0 else (box.yaw_u + math.pi)
                    wx_s = (box.cx + vx * half_v_m * side) * STUDS_PER_METER
                    wz_s = (box.cz + vz * half_v_m * side) * STUDS_PER_METER
                    group_parts.append(
                        TilePart(
                            part_type=PART_WEDGE,
                            material=MAT_SLATE,
                            category=CAT_BUILDINGS,
                            flags=0,
                            r=roof_rgb[0],
                            g=roof_rgb[1],
                            b=roof_rgb[2],
                            px_studs=wx_s,
                            py_studs=sy + roof_sy * 0.5,
                            pz_studs=wz_s,
                            sx_studs=sx + 0.8,
                            sy_studs=roof_sy,
                            sz_studs=(box.depth_v * 0.5 + 0.28) * STUDS_PER_METER,
                            yaw_rad=w_yaw,
                        )
                    )
            elif kind == "warehouse":
                cap_sy = 0.35 * STUDS_PER_METER
                group_parts.append(
                    TilePart(
                        part_type=PART_BLOCK,
                        material=MAT_METAL,
                        category=CAT_BUILDINGS,
                        flags=0,
                        r=148,
                        g=154,
                        b=160,
                        px_studs=cx_s,
                        py_studs=sy + cap_sy * 0.5,
                        pz_studs=cz_s,
                        sx_studs=sx + 1.0,
                        sy_studs=cap_sy,
                        sz_studs=sz + 1.0,
                        yaw_rad=box.yaw_u,
                    )
                )
            else:
                cap_sy = 0.28 * STUDS_PER_METER
                group_parts.append(
                    TilePart(
                        part_type=PART_BLOCK,
                        material=MAT_CONCRETE,
                        category=CAT_BUILDINGS,
                        flags=0,
                        r=84,
                        g=88,
                        b=94,
                        px_studs=cx_s,
                        py_studs=sy + cap_sy * 0.5,
                        pz_studs=cz_s,
                        sx_studs=sx + 0.4,
                        sy_studs=cap_sy,
                        sz_studs=sz + 0.4,
                        yaw_rad=box.yaw_u,
                    )
                )

            # Gate final: nenhuma part deste grupo (inclusive beirais) pode invadir pista/calcada
            if exact_road_tree is not None:
                conflict = False
                for gp in group_parts:
                    gpoly = _tile_part_footprint_m(gp, extra_margin_m=0.02)
                    if any(exact_road_polys[idx].intersects(gpoly) for idx in exact_road_tree.query(gpoly)):
                        conflict = True
                        break
                if conflict:
                    stats["post_filter_dropped"] += 1
                    continue

            parts.extend(group_parts)
            stats["building_parts"] += len(group_parts)
            preview_polys.append(obb_world_polygon(box))
            kept_any_box = True

        if kept_any_box:
            stats["kept_buildings"] += 1

    return parts, preview_polys, stats
