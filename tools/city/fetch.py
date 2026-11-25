"""Download com cache local de segmentos e edificios do Overture Maps + limites IBGE."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import overturemaps
import pyarrow.parquet as pq
import requests
from shapely import wkb as shapely_wkb
from shapely.geometry import Point, shape
from shapely.geometry.base import BaseGeometry
from shapely.ops import unary_union

from .project import LocalProjection


def _circle_boundary_geom(center_lat: float, center_lon: float, radius_m: float, proj: LocalProjection) -> BaseGeometry:
    cx, cz = proj.lonlat_to_xz(center_lon, center_lat)
    return Point(cx, cz).buffer(radius_m, resolution=32)


def _ibge_boundary_geom(ibge_code: str, cache_dir: Path, proj: LocalProjection) -> BaseGeometry:
    cache_file = cache_dir / "boundary.geojson"
    if not cache_file.exists():
        url = (
            f"https://servicodados.ibge.gov.br/api/v3/malhas/municipios/{ibge_code}"
            "?formato=application/vnd.geo+json&qualidade=maxima"
        )
        resp = requests.get(url, timeout=30)
        resp.raise_for_status()
        cache_file.write_bytes(resp.content)

    gj = json.loads(cache_file.read_text(encoding="utf-8"))
    geoms = []
    if gj.get("type") == "FeatureCollection":
        for feat in gj.get("features", []):
            geoms.append(proj.geom_to_xz(shape(feat["geometry"])))
    elif gj.get("type") == "Feature":
        geoms.append(proj.geom_to_xz(shape(gj["geometry"])))
    else:
        geoms.append(proj.geom_to_xz(shape(gj)))
    return unary_union(geoms)


def _wgs84_bbox_from_local(bounds_xz: tuple[float, float, float, float], origin_lat: float, origin_lon: float, margin_m: float = 150.0) -> tuple[float, float, float, float]:
    minx, minz, maxx, maxz = bounds_xz
    minx -= margin_m
    minz -= margin_m
    maxx += margin_m
    maxz += margin_m
    # Aproximacao segura em torno de -29.8 deg (1 deg lat ~ 110850 m, 1 deg lon ~ 96650 m)
    m_per_lat = 110850.0
    m_per_lon = 111320.0 * math.cos(math.radians(origin_lat))
    # Lembrete: +z = Sul = -north
    min_lon = origin_lon + minx / m_per_lon
    max_lon = origin_lon + maxx / m_per_lon
    min_lat = origin_lat - maxz / m_per_lat
    max_lat = origin_lat - minz / m_per_lat
    return (min_lon, min_lat, max_lon, max_lat)


def _download_overture_parquet(overture_type: str, bbox: tuple[float, float, float, float], out_path: Path) -> None:
    if out_path.exists():
        return
    out_path.parent.mkdir(parents=True, exist_ok=True)
    reader = overturemaps.record_batch_reader(overture_type, bbox=bbox)
    if reader is None:
        raise RuntimeError(f"overturemaps.record_batch_reader retornou None para {overture_type}")
    table = reader.read_all()
    pq.write_table(table, out_path)


def _extract_primary_name(names_val: Any) -> str | None:
    if isinstance(names_val, dict):
        primary = names_val.get("primary")
        if primary:
            return str(primary)
    return None


def _extract_rule_value(rules_val: Any) -> Any:
    if isinstance(rules_val, list):
        for item in rules_val:
            if isinstance(item, dict) and item.get("value") is not None:
                return item["value"]
    return None


def fetch_city_data(
    city_id: str,
    city_cfg: dict[str, Any],
    origin_lat: float,
    origin_lon: float,
    cache_root: Path,
) -> tuple[BaseGeometry, list[dict[str, Any]], list[dict[str, Any]]]:
    """Retorna (boundary_xz, road_records_xz, building_records_xz) em metros locais."""
    proj = LocalProjection.from_origin(origin_lat, origin_lon)
    cache_dir = cache_root / city_id
    cache_dir.mkdir(parents=True, exist_ok=True)

    if "radius_m" in city_cfg:
        lat, lon = city_cfg["center"]
        boundary_xz = _circle_boundary_geom(lat, lon, float(city_cfg["radius_m"]), proj)
    elif "ibge_code" in city_cfg:
        boundary_xz = _ibge_boundary_geom(str(city_cfg["ibge_code"]), cache_dir, proj)
    else:
        raise ValueError(f"Configuracao de cidade invalida para {city_id}: {city_cfg}")

    bbox = _wgs84_bbox_from_local(boundary_xz.bounds, origin_lat, origin_lon, margin_m=180.0)
    seg_path = cache_dir / "segments.parquet"
    bld_path = cache_dir / "buildings.parquet"
    _download_overture_parquet("segment", bbox, seg_path)
    _download_overture_parquet("building", bbox, bld_path)

    seg_table = pq.read_table(
        seg_path,
        columns=[
            "id",
            "subtype",
            "class",
            "names",
            "road_flags",
            "width_rules",
            "road_surface",
            "level_rules",
            "geometry",
        ],
    ).to_pylist()

    road_records: list[dict[str, Any]] = []
    for row in seg_table:
        if row.get("subtype") != "road":
            continue
        geom_ll = shapely_wkb.loads(row["geometry"])
        geom_xz = proj.geom_to_xz(geom_ll)
        if geom_xz.is_empty:
            continue
        is_tunnel = False
        road_flags = row.get("road_flags")
        if isinstance(road_flags, list):
            for rf in road_flags:
                vals = rf.get("values") if isinstance(rf, dict) else None
                if vals and "is_tunnel" in vals:
                    is_tunnel = True
                    break
        level_rules = row.get("level_rules")
        if isinstance(level_rules, list):
            for lr in level_rules:
                if isinstance(lr, dict) and isinstance(lr.get("value"), (int, float)) and lr["value"] < 0:
                    is_tunnel = True
                    break
        width_val = _extract_rule_value(row.get("width_rules"))
        surface_val = _extract_rule_value(row.get("road_surface"))
        road_records.append(
            {
                "id": str(row["id"]),
                "class": str(row.get("class") or "unclassified"),
                "name": _extract_primary_name(row.get("names")),
                "is_tunnel": is_tunnel,
                "width": float(width_val) if isinstance(width_val, (int, float)) else None,
                "surface": str(surface_val) if surface_val is not None else None,
                "geom": geom_xz,
            }
        )

    bld_table = pq.read_table(
        bld_path,
        columns=["id", "class", "subtype", "height", "num_floors", "is_underground", "geometry"],
    ).to_pylist()

    building_records: list[dict[str, Any]] = []
    for row in bld_table:
        if row.get("is_underground") is True:
            continue
        geom_ll = shapely_wkb.loads(row["geometry"])
        geom_xz = proj.geom_to_xz(geom_ll)
        if geom_xz.is_empty:
            continue
        height = row.get("height")
        num_floors = row.get("num_floors")
        bclass = row.get("class")
        bsubtype = row.get("subtype")
        building_records.append(
            {
                "id": str(row["id"]),
                "class": str(bclass) if bclass else None,
                "subtype": str(bsubtype) if bsubtype else None,
                "height": float(height) if height is not None else None,
                "num_floors": int(num_floors) if num_floors is not None else None,
                "geom": geom_xz,
            }
        )

    return boundary_xz, road_records, building_records
