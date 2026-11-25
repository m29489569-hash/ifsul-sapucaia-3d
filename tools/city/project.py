"""Projecao cartografica local e calibracao rigida com as ruas-ancora do campus."""

from __future__ import annotations

from dataclasses import dataclass
import math
import re
import unicodedata
from typing import Any, Iterable

import numpy as np
from pyproj import Transformer
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon
from shapely.geometry.base import BaseGeometry


def normalize_street_name(name: str | None) -> str:
    if not name:
        return ""
    s = unicodedata.normalize("NFKD", name)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = s.lower().strip()
    s = re.sub(r"\([^)]*\)", " ", s)
    s = re.sub(r"\b(avenida|av|rua|r|travessa|tv|estrada|est|rodovia|br|rs)\b\.?", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


@dataclass(slots=True)
class LocalProjection:
    origin_lat: float
    origin_lon: float
    _transformer: Transformer

    @classmethod
    def from_origin(cls, lat: float, lon: float) -> "LocalProjection":
        proj_str = (
            f"+proj=tmerc +lat_0={lat:.8f} +lon_0={lon:.8f} "
            "+k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
        )
        transformer = Transformer.from_crs("EPSG:4326", proj_str, always_xy=True)
        return cls(origin_lat=lat, origin_lon=lon, _transformer=transformer)

    def lonlat_to_xz(self, lon: float, lat: float) -> tuple[float, float]:
        east, north = self._transformer.transform(lon, lat)
        return float(east), float(-north)

    def geom_to_xz(self, geom: BaseGeometry) -> BaseGeometry:
        if geom.is_empty:
            return geom
        gtype = geom.geom_type
        if gtype == "Point":
            x, z = self.lonlat_to_xz(geom.x, geom.y)
            return Point(x, z)
        if gtype == "LineString":
            coords = [self.lonlat_to_xz(c[0], c[1]) for c in geom.coords]
            return LineString(coords)
        if gtype == "Polygon":
            ext = [self.lonlat_to_xz(c[0], c[1]) for c in geom.exterior.coords]
            holes = [
                [self.lonlat_to_xz(c[0], c[1]) for c in ring.coords]
                for ring in geom.interiors
            ]
            return Polygon(ext, holes)
        if hasattr(geom, "geoms"):
            parts = [self.geom_to_xz(g) for g in geom.geoms]
            return type(geom)([g for g in parts if not g.is_empty])
        raise TypeError(f"Geometria nao suportada para projecao: {gtype}")


@dataclass(slots=True)
class CalibrationResult:
    dx_m: float
    dz_m: float
    dtheta_deg: float
    rms_residual_m: float
    matched_samples: int
    matched_streets: list[str]

    def apply(self, geom: BaseGeometry) -> BaseGeometry:
        if geom.is_empty:
            return geom
        out = geom
        if abs(self.dtheta_deg) > 1e-7:
            out = affinity.rotate(out, self.dtheta_deg, origin=(0.0, 0.0), use_radians=False)
        if abs(self.dx_m) > 1e-7 or abs(self.dz_m) > 1e-7:
            out = affinity.translate(out, xoff=self.dx_m, yoff=self.dz_m)
        return out


def _sample_line_points(line: LineString, step_m: float = 12.0) -> list[tuple[float, float]]:
    length = line.length
    if length <= 0.1:
        return []
    count = max(2, int(math.ceil(length / step_m)) + 1)
    pts: list[tuple[float, float]] = []
    for i in range(count):
        frac = i / (count - 1)
        p = line.interpolate(frac, normalized=True)
        pts.append((float(p.x), float(p.y)))
    return pts


def _closest_point_and_tangent(line: LineString, pt: Point) -> tuple[float, float, float, float, float]:
    d = line.project(pt)
    q = line.interpolate(d)
    eps = 0.5
    d0 = max(0.0, d - eps)
    d1 = min(line.length, d + eps)
    p0 = line.interpolate(d0)
    p1 = line.interpolate(d1)
    tx, tz = p1.x - p0.x, p1.y - p0.y
    norm = math.hypot(tx, tz) or 1.0
    tx /= norm
    tz /= norm
    # normal unitaria a esquerda
    nx, nz = -tz, tx
    dist = pt.distance(q)
    return dist, float(q.x), float(q.y), nx, nz


def calibrate_to_campus(
    road_records: Iterable[dict[str, Any]],
    campus_streets: list[dict[str, Any]],
    max_initial_dist_m: float = 35.0,
    max_rms_m: float = 3.0,
) -> CalibrationResult:
    """Estima transformacao rigida (dx, dz, rotacao) alinhando Overture as 9 ruas-ancora."""
    anchors_by_name: dict[str, list[LineString]] = {}
    for st in campus_streets:
        key = normalize_street_name(st.get("name"))
        pts = st.get("points") or []
        if key and len(pts) >= 2:
            anchors_by_name.setdefault(key, []).append(LineString(pts))

    # Coleta pares (ponto_overture, linha_ancora)
    pairs: list[tuple[float, float, LineString, str]] = []
    matched_names: set[str] = set()
    for rec in road_records:
        key = normalize_street_name(rec.get("name"))
        if not key or key not in anchors_by_name:
            continue
        geom = rec.get("geom")
        if geom is None or geom.geom_type != "LineString" or geom.length < 5.0:
            continue
        candidates = anchors_by_name[key]
        for px, pz in _sample_line_points(geom, step_m=10.0):
            pt = Point(px, pz)
            best_line = min(candidates, key=lambda ln: ln.distance(pt))
            if best_line.distance(pt) <= max_initial_dist_m:
                pairs.append((px, pz, best_line, key))
                matched_names.add(key)

    if len(pairs) < 6:
        raise RuntimeError(
            f"Poucas amostras casadas com as ruas do campus ({len(pairs)}); "
            "verifique nomes ou bbox."
        )

    # Iteracoes de ponto-a-linha (linearizado) com rejeicao de outliers (trimmed 15%)
    dx = 0.0
    dz = 0.0
    theta = 0.0
    active = list(pairs)

    for it in range(6):
        c = math.cos(theta)
        s = math.sin(theta)
        rows = []
        rhs = []
        dists = []

        for px, pz, line, _ in active:
            rx = c * px - s * pz + dx
            rz = s * px + c * pz + dz
            dist, qx, qz, nx, nz = _closest_point_and_tangent(line, Point(rx, rz))
            dists.append(dist)
            # Residual ao longo da normal: n . (r + [ddx, ddz] + dtheta*[-rz0, rx0] - q) = 0
            # onde rz0 = s*px + c*pz, rx0 = c*px - s*pz
            rx0 = rx - dx
            rz0 = rz - dz
            a_dx = nx
            a_dz = nz
            a_th = nx * (-rz0) + nz * rx0
            err = nx * (qx - rx) + nz * (qz - rz)
            rows.append([a_dx, a_dz, a_th])
            rhs.append(err)

        if it == 2 and len(active) > 14:
            cutoff = float(np.percentile(dists, 85))
            active = [p for p, d in zip(active, dists) if d <= max(cutoff, 2.0)]
            continue

        A = np.asarray(rows, dtype=np.float64)
        b = np.asarray(rhs, dtype=np.float64)
        # Regularizacao minima em rotacao caso todas as ruas casadas sejam paralelas
        reg = np.diag([1e-6, 1e-6, 1e2])
        sol = np.linalg.solve(A.T @ A + reg, A.T @ b)
        dx += float(sol[0])
        dz += float(sol[1])
        theta += float(sol[2])
        if max(abs(sol[0]), abs(sol[1]), abs(sol[2]) * 100.0) < 1e-4:
            break

    # Mede RMS final nas amostras ativas
    c = math.cos(theta)
    s = math.sin(theta)
    final_dists = []
    for px, pz, line, _ in active:
        rx = c * px - s * pz + dx
        rz = s * px + c * pz + dz
        final_dists.append(line.distance(Point(rx, rz)))

    rms = float(math.sqrt(np.mean(np.square(final_dists)))) if final_dists else 999.0
    dtheta_deg = math.degrees(theta)
    if rms > max_rms_m:
        raise RuntimeError(
            f"Residuo de calibracao acima do limite: rms={rms:.2f}m > {max_rms_m:.2f}m "
            f"(dx={dx:.2f}, dz={dz:.2f}, rot={dtheta_deg:.3f}deg)"
        )

    return CalibrationResult(
        dx_m=dx,
        dz_m=dz,
        dtheta_deg=dtheta_deg,
        rms_residual_m=rms,
        matched_samples=len(active),
        matched_streets=sorted(matched_names),
    )
