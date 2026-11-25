"""Orquestrador do pipeline de cidades: fetch -> project -> roads -> buildings -> tiles IFC2."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import time
from typing import Any

from PIL import Image, ImageDraw
from shapely.geometry import Polygon, box

from .buildings import build_buildings
from .codec import (
    CAT_BUILDINGS,
    CAT_GROUND,
    CAT_ROADS,
    FLAG_CAN_QUERY,
    FLAG_COLLIDE,
    MAT_CONCRETE,
    MAT_GRASS,
    PART_BLOCK,
    PART_WEDGE,
    STUDS_PER_METER,
    TilePart,
    encode_tile_b64,
)
from .fetch import fetch_city_data
from .project import calibrate_to_campus
from .roads import build_roads

REPO_ROOT = Path(__file__).resolve().parents[2]
CITIES_CFG_PATH = Path(__file__).resolve().parent / "cities.json"


def _tile_index(val_m: float, tile_size_m: float) -> int:
    return int(math.floor(val_m / tile_size_m))


def _make_tile_grass_parts(
    tx: int,
    tz: int,
    tile_size_m: float,
    campus_grass_box: Polygon,
    boundary_xz: Any,
) -> list[TilePart]:
    x0 = tx * tile_size_m
    z0 = tz * tile_size_m
    tile_poly = box(x0, z0, x0 + tile_size_m, z0 + tile_size_m)
    if not boundary_xz.intersects(tile_poly):
        return []
    free = tile_poly.difference(campus_grass_box)
    if free.is_empty:
        return []

    # Decompoe em sub-retangulos de grade 125m para manter dimensoes compactas e precisas
    sub = tile_size_m * 0.5
    parts: list[TilePart] = []
    for ix in range(2):
        for iz in range(2):
            sx0 = x0 + ix * sub
            sz0 = z0 + iz * sub
            cell = box(sx0, sz0, sx0 + sub, sz0 + sub).difference(campus_grass_box)
            if cell.is_empty:
                continue
            geoms = [cell] if cell.geom_type == "Polygon" else list(getattr(cell, "geoms", []))
            for g in geoms:
                if g.geom_type != "Polygon" or g.area < 4.0:
                    continue
                minx, minz, maxx, maxz = g.bounds
                w = maxx - minx
                d = maxz - minz
                if w < 1.0 or d < 1.0:
                    continue
                cx = (minx + maxx) * 0.5
                cz = (minz + maxz) * 0.5
                parts.append(
                    TilePart(
                        part_type=PART_BLOCK,
                        material=MAT_GRASS,
                        category=CAT_GROUND,
                        flags=FLAG_COLLIDE | FLAG_CAN_QUERY,
                        r=85,
                        g=140,
                        b=47,
                        px_studs=cx * STUDS_PER_METER,
                        py_studs=-2.0,
                        pz_studs=cz * STUDS_PER_METER,
                        sx_studs=w * STUDS_PER_METER,
                        sy_studs=4.0,
                        sz_studs=d * STUDS_PER_METER,
                        yaw_rad=0.0,
                    )
                )
    return parts


def _render_preview(
    out_png: Path,
    boundary_xz: Any,
    campus_data: dict[str, Any],
    road_lines: list[Any],
    building_polys: list[Polygon],
) -> None:
    minx, minz, maxx, maxz = boundary_xz.bounds
    span = max(maxx - minx, maxz - minz, 100.0)
    img_size = 1200
    pad = 40
    scale = (img_size - 2 * pad) / span
    cx = (minx + maxx) * 0.5
    cz = (minz + maxz) * 0.5

    def to_px(x: float, z: float) -> tuple[float, float]:
        return (img_size * 0.5 + (x - cx) * scale, img_size * 0.5 + (z - cz) * scale)

    img = Image.new("RGB", (img_size, img_size), (235, 240, 232))
    draw = ImageDraw.Draw(img)

    # Edificios
    for poly in building_polys:
        pts = [to_px(p[0], p[1]) for p in poly.exterior.coords]
        if len(pts) >= 3:
            draw.polygon(pts, fill=(214, 146, 108), outline=(168, 104, 72))

    # Ruas novas
    for ln in road_lines:
        pts = [to_px(p[0], p[1]) for p in ln.coords]
        if len(pts) >= 2:
            draw.line(pts, fill=(70, 74, 80), width=3)

    # Perimetro do campus
    c_pts = [to_px(p[0], p[1]) for p in campus_data["perimeter"]]
    if len(c_pts) >= 3:
        draw.polygon(c_pts, fill=(175, 220, 175), outline=(47, 158, 65), width=3)

    # 9 ruas-ancora em azul
    for st in campus_data.get("streets", []):
        pts = [to_px(p[0], p[1]) for p in st["points"]]
        if len(pts) >= 2:
            draw.line(pts, fill=(35, 110, 220), width=4)

    out_png.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_png)


def _enforce_tile_budget(t_parts: list[TilePart], max_parts: int = 6000) -> list[TilePart]:
    """Garante teto de parts por tile removendo faixas e simplificando telhados 2 aguas."""
    if len(t_parts) <= max_parts:
        return t_parts

    # 1) Remove faixas tracejadas (flags == 0 em CAT_ROADS)
    trimmed = [p for p in t_parts if not (p.category == CAT_ROADS and p.flags == 0)]
    if len(trimmed) <= max_parts:
        return trimmed

    # 2) Converte pares de telhados Wedge em laje unica se ainda exceder max_parts
    out: list[TilePart] = []
    skip_next_wedge = False
    for p in trimmed:
        if len(out) + (len(trimmed) - len(out)) <= max_parts:
            out.append(p)
            continue
        if p.category == CAT_BUILDINGS and p.part_type == PART_WEDGE:
            if skip_next_wedge:
                skip_next_wedge = False
                continue
            skip_next_wedge = True
            out.append(
                TilePart(
                    part_type=PART_BLOCK,
                    material=MAT_CONCRETE,
                    category=CAT_BUILDINGS,
                    flags=0,
                    r=p.r,
                    g=p.g,
                    b=p.b,
                    px_studs=p.px_studs,
                    py_studs=p.py_studs,
                    pz_studs=p.pz_studs,
                    sx_studs=p.sx_studs,
                    sy_studs=min(p.sy_studs, 1.0),
                    sz_studs=p.sz_studs,
                    yaw_rad=p.yaw_rad,
                )
            )
        else:
            out.append(p)
    return out


def run_build(city_id: str) -> dict[str, Any]:
    t0 = time.perf_counter()
    cfg = json.loads(CITIES_CFG_PATH.read_text(encoding="utf-8"))
    if city_id not in cfg["cities"]:
        raise SystemExit(f"Cidade '{city_id}' nao encontrada em cities.json")

    campus_data = json.loads((REPO_ROOT / "data" / "campus.json").read_text(encoding="utf-8"))
    origin_lat = float(cfg["origin"]["lat"])
    origin_lon = float(cfg["origin"]["lon"])
    tile_size_m = float(cfg["tile_size_m"])
    gx0, gz0, gx1, gz1 = [float(v) for v in cfg["campus_grass_box_m"]]
    campus_grass_box = box(gx0, gz0, gx1, gz1)

    boundary_xz, road_records, building_records = fetch_city_data(
        city_id=city_id,
        city_cfg=cfg["cities"][city_id],
        origin_lat=origin_lat,
        origin_lon=origin_lon,
        cache_root=REPO_ROOT / "data" / "cache",
    )

    calib = calibrate_to_campus(
        road_records,
        campus_data["streets"],
        fallback_calibration=cfg.get("calibrated_transform"),
    )
    if calib.matched_samples > 0:
        cfg["calibrated_transform"] = {
            "dx_m": round(calib.dx_m, 4),
            "dz_m": round(calib.dz_m, 4),
            "dtheta_deg": round(calib.dtheta_deg, 5),
            "rms_residual_m": round(calib.rms_residual_m, 4),
        }
        CITIES_CFG_PATH.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for rec in road_records:
        rec["geom"] = calib.apply(rec["geom"])
    for rec in building_records:
        rec["geom"] = calib.apply(rec["geom"])

    campus_poly = Polygon(campus_data["perimeter"])
    road_out = build_roads(road_records, boundary_xz, campus_data)
    bld_parts, bld_polys, bld_stats = build_buildings(
        building_records=building_records,
        boundary_xz=boundary_xz,
        campus_poly=campus_poly,
        road_clearance_poly=road_out.road_clearance_geoms,
        overrides=cfg.get("overrides") or {},
    )

    all_parts = [*road_out.parts, *bld_parts]

    # Agrupa por tile (tx, tz)
    buckets: dict[tuple[int, int], list[TilePart]] = {}
    for p in all_parts:
        px_m = p.px_studs / STUDS_PER_METER
        pz_m = p.pz_studs / STUDS_PER_METER
        key = (_tile_index(px_m, tile_size_m), _tile_index(pz_m, tile_size_m))
        buckets.setdefault(key, []).append(p)

    # Garante tiles de grama cobrindo todo o limite da cidade
    b_minx, b_minz, b_maxx, b_maxz = boundary_xz.bounds
    for tx in range(_tile_index(b_minx, tile_size_m), _tile_index(b_maxx, tile_size_m) + 1):
        for tz in range(_tile_index(b_minz, tile_size_m), _tile_index(b_maxz, tile_size_m) + 1):
            grass_parts = _make_tile_grass_parts(tx, tz, tile_size_m, campus_grass_box, boundary_xz)
            if grass_parts:
                buckets.setdefault((tx, tz), []).extend(grass_parts)

    out_dir = REPO_ROOT / "data" / "city" / city_id
    tiles_dir = out_dir / "tiles"
    tiles_dir.mkdir(parents=True, exist_ok=True)
    for old_file in tiles_dir.glob("*.b64"):
        old_file.unlink()

    tile_entries = []
    total_parts = 0
    total_b64_bytes = 0
    for (tx, tz) in sorted(buckets.keys()):
        t_parts = _enforce_tile_budget(buckets[(tx, tz)], max_parts=6000)
        if not t_parts:
            continue
        ox_m = (tx + 0.5) * tile_size_m
        oz_m = (tz + 0.5) * tile_size_m
        ox_s = ox_m * STUDS_PER_METER
        oz_s = oz_m * STUDS_PER_METER
        b64, _ = encode_tile_b64(tx, tz, ox_s, oz_s, t_parts)
        tkey = f"{tx}_{tz}"
        (tiles_dir / f"{tkey}.b64").write_text(b64, encoding="ascii")
        tile_entries.append(
            {
                "key": tkey,
                "tx": tx,
                "tz": tz,
                "center_x_studs": round(ox_s, 2),
                "center_z_studs": round(oz_s, 2),
                "parts": len(t_parts),
                "bytes_b64": len(b64),
            }
        )
        total_parts += len(t_parts)
        total_b64_bytes += len(b64)

    elapsed_s = time.perf_counter() - t0
    area_km2 = max(0.01, boundary_xz.area / 1_000_000.0)
    parts_per_km2 = int(round(total_parts / area_km2))
    sapucaia_est = int(round(parts_per_km2 * 58.6))  # Sapucaia do Sul ~58.6 km2 (area urbana ~28 km2)

    preview_path = REPO_ROOT / "docs" / "screenshots" / f"city_{city_id}_preview.png"
    _render_preview(preview_path, boundary_xz, campus_data, road_out.road_lines, bld_polys)

    index_obj = {
        "city": city_id,
        "tile_size_m": tile_size_m,
        "tile_size_studs": round(tile_size_m * STUDS_PER_METER, 4),
        "total_parts": total_parts,
        "total_tiles": len(tile_entries),
        "total_b64_bytes": total_b64_bytes,
        "calibration": {
            "dx_m": round(calib.dx_m, 3),
            "dz_m": round(calib.dz_m, 3),
            "dtheta_deg": round(calib.dtheta_deg, 4),
            "rms_residual_m": round(calib.rms_residual_m, 3),
            "matched_samples": calib.matched_samples,
            "matched_streets": calib.matched_streets,
        },
        "counts": {
            **road_out.stats,
            **bld_stats,
            "area_km2": round(area_km2, 3),
            "parts_per_km2": parts_per_km2,
            "sapucaia_extrapolated_max_parts": sapucaia_est,
        },
        "tiles": tile_entries,
    }
    (out_dir / "index.json").write_text(json.dumps(index_obj, indent=2, ensure_ascii=False), encoding="utf-8")

    return {
        "index": index_obj,
        "elapsed_s": round(elapsed_s, 2),
        "preview": str(preview_path),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Gera tiles IFC2 para uma cidade")
    parser.add_argument("--city", required=True, help="ID da cidade em cities.json")
    parser.add_argument("--summary", action="store_true", help="Imprime resumo curto (<=15 linhas)")
    args = parser.parse_args()

    res = run_build(args.city)
    idx = res["index"]
    cal = idx["calibration"]
    cnt = idx["counts"]
    print(f"city={idx['city']} time={res['elapsed_s']}s area={cnt['area_km2']}km2")
    print(f"calib: dx={cal['dx_m']}m dz={cal['dz_m']}m rot={cal['dtheta_deg']}deg rms={cal['rms_residual_m']}m samples={cal['matched_samples']} streets={len(cal['matched_streets'])}")
    print(f"roads: segs={cnt['segments']} junc={cnt['junction_nodes']} sidewalks={cnt['sidewalk_parts']} stripes={cnt['lane_stripes']} snaps={cnt['snapped_to_anchor']} dup_drop={cnt['dropped_duplicate_anchor']}")
    print(f"buildings: kept={cnt['kept_buildings']} parts={cnt['building_parts']} drop_small={cnt['dropped_small']} drop_road_campus={cnt['dropped_campus_or_road']}")
    print(f"output: tiles={idx['total_tiles']} total_parts={idx['total_parts']} b64_kb={idx['total_b64_bytes']//1024} parts/km2={cnt['parts_per_km2']} est_sapucaia_urban(25km2)={cnt['parts_per_km2']*25}")


if __name__ == "__main__":
    main()
