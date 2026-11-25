"""Testes unitarios offline do pipeline tools/city."""

from __future__ import annotations

import base64
import math

import pytest
from shapely.geometry import LineString, Polygon, box

from tools.city.buildings import build_buildings
from tools.city.codec import (
    CAT_BUILDINGS,
    CAT_ROADS,
    CAT_SIDEWALKS,
    FLAG_COLLIDE,
    FLAG_SHADOW,
    MAT_ASPHALT,
    MAT_CONCRETE,
    PART_BLOCK,
    PART_CYLINDER,
    PART_WEDGE,
    STUDS_PER_METER,
    TilePart,
    decode_tile_b64,
    encode_tile_b64,
)
from tools.city.project import calibrate_to_campus
from tools.city.roads import build_roads


def test_codec_roundtrip_and_zstd_fcs():
    ox, oz = 250.0 * STUDS_PER_METER, -250.0 * STUDS_PER_METER
    sample = [
        TilePart(PART_BLOCK, MAT_ASPHALT, CAT_ROADS, FLAG_COLLIDE | FLAG_SHADOW, 63, 65, 68, ox + 12.5, 0.08, oz - 30.0, 28.0, 0.06, 120.0, 1.23),
        TilePart(PART_CYLINDER, MAT_ASPHALT, CAT_ROADS, FLAG_COLLIDE, 63, 65, 68, ox - 40.0, 0.09, oz + 18.5, 32.0, 0.06, 32.0, 0.0),
        TilePart(PART_WEDGE, MAT_CONCRETE, CAT_BUILDINGS, 0, 168, 88, 62, ox + 5.0, 14.2, oz + 9.0, 20.0, 4.5, 10.0, 4.712),
    ]
    b64, _ = encode_tile_b64(0, -1, ox, oz, sample)
    raw_zst = base64.b64decode(b64)
    # Magic Zstd 0xFD2FB528 little-endian + FHD com Frame_Content_Size presente (bit 5=Single_Segment ou bits 6..7 > 0)
    assert raw_zst[:4] == b"\x28\xb5\x2f\xfd"
    fhd = raw_zst[4]
    assert (fhd & 0x20) != 0 or (fhd >> 6) > 0

    hdr, decoded = decode_tile_b64(b64)
    assert hdr[0] == 0 and hdr[1] == -1
    assert len(decoded) == 3
    for a, b in zip(sample, decoded):
        assert a.part_type == b.part_type
        assert a.material == b.material
        assert a.category == b.category
        assert a.flags == b.flags
        assert (a.r, a.g, a.b) == (b.r, b.g, b.b)
        assert abs(a.px_studs - b.px_studs) < 0.06
        assert abs(a.py_studs - b.py_studs) < 0.02
        assert abs(a.pz_studs - b.pz_studs) < 0.06
        assert abs(a.yaw_rad - b.yaw_rad) < 0.002


def test_calibration_recovers_synthetic_offset():
    campus_streets = [
        {"name": "Avenida Copacabana", "points": [[-80.0, -100.0], [-80.0, 100.0]], "width": 7.5},
        {"name": "Rua Palestina", "points": [[40.0, -120.0], [60.0, 120.0]], "width": 8.0},
        {"name": "Rua João Rodrigues", "points": [[-100.0, 140.0], [100.0, 120.0]], "width": 9.0},
    ]
    # Simula Overture deslocado por (+3.2m, -2.4m)
    dx_err, dz_err = 3.2, -2.4
    ov_roads = [
        {"name": "Avenida Copacabana", "geom": LineString([(-80.0 + dx_err, -100.0 + dz_err), (-80.0 + dx_err, 100.0 + dz_err)])},
        {"name": "Rua Palestina", "geom": LineString([(40.0 + dx_err, -120.0 + dz_err), (60.0 + dx_err, 120.0 + dz_err)])},
        {"name": "Rua Joao Rodrigues", "geom": LineString([(-100.0 + dx_err, 140.0 + dz_err), (100.0 + dx_err, 120.0 + dz_err)])},
    ]
    cal = calibrate_to_campus(ov_roads, campus_streets)
    assert abs(cal.dx_m - (-dx_err)) < 0.15
    assert abs(cal.dz_m - (-dz_err)) < 0.15
    assert cal.rms_residual_m < 0.1


def test_roads_conflation_and_sidewalks_no_campus_overlap():
    campus_data = {
        "perimeter": [[-40.0, -40.0], [40.0, -40.0], [40.0, 40.0], [-40.0, 40.0]],
        "streets": [
            {"name": "Avenida Copacabana", "width": 8.0, "points": [[-60.0, -100.0], [-60.0, 100.0]]},
        ],
        "driveways": [],
    }
    boundary = box(-300, -300, 300, 300)
    roads = [
        # Cruzamento em X fora do campus + trecho cruzando o campus + trecho duplicado na ancora
        {"id": "r1", "class": "primary", "name": "Avenida Copacabana", "is_tunnel": False, "width": None, "surface": "asphalt", "geom": LineString([(-60.0, -100.0), (-60.0, 100.0)])},
        {"id": "r2", "class": "residential", "name": "Rua Lateral", "is_tunnel": False, "width": None, "surface": "asphalt", "geom": LineString([(-180.0, 0.0), (-60.0, 0.0)])},
        {"id": "r3", "class": "secondary", "name": "Cruzamento Leste A", "is_tunnel": False, "width": None, "surface": "asphalt", "geom": LineString([(100.0, -80.0), (100.0, 80.0)])},
        {"id": "r4", "class": "secondary", "name": "Cruzamento Leste B", "is_tunnel": False, "width": None, "surface": "asphalt", "geom": LineString([(60.0, 0.0), (160.0, 0.0)])},
        {"id": "r5", "class": "residential", "name": "Rua Invasora", "is_tunnel": False, "width": None, "surface": "asphalt", "geom": LineString([(-20.0, 0.0), (20.0, 0.0)])},
    ]
    out = build_roads(roads, boundary, campus_data)
    assert out.stats["dropped_duplicate_anchor"] >= 1
    assert out.stats["segments"] >= 3

    campus_poly = Polygon(campus_data["perimeter"])
    for p in out.parts:
        pt_m = (p.px_studs / STUDS_PER_METER, p.pz_studs / STUDS_PER_METER)
        from shapely.geometry import Point
        assert not campus_poly.contains(Point(pt_m))

    # Calcadas nao devem ficar dentro do miolo do cruzamento (100, 0)
    sw_near_cross = [
        p for p in out.parts
        if p.category == CAT_SIDEWALKS
        and math.hypot(p.px_studs / STUDS_PER_METER - 100.0, p.pz_studs / STUDS_PER_METER - 0.0) < 3.5
    ]
    assert len(sw_near_cross) == 0


def test_buildings_obb_and_l_shape():
    boundary = box(-300, -300, 300, 300)
    campus_poly = box(-40, -40, 40, 40)
    road_clear = Polygon()

    rect_house = box(60, 60, 72, 68)  # 12x8 = 96 m2 -> 1 body + 2 roof wedges
    l_shape = Polygon([(100, 100), (130, 100), (130, 112), (112, 112), (112, 130), (100, 130)])  # 576 m2 L-shape
    tiny_shed = box(50, 50, 52, 52)  # 4 m2 -> descartado

    recs = [
        {"id": "b1", "class": "residential", "subtype": "residential", "height": None, "num_floors": None, "geom": rect_house},
        {"id": "b2", "class": "commercial", "subtype": "commercial", "height": 9.0, "num_floors": None, "geom": l_shape},
        {"id": "b3", "class": "outbuilding", "subtype": None, "height": None, "num_floors": None, "geom": tiny_shed},
    ]
    parts, polys, stats = build_buildings(recs, boundary, campus_poly, road_clear, {})
    assert stats["kept_buildings"] == 2
    assert stats["dropped_small"] == 1
    assert len(polys) >= 2
    assert len(parts) >= 5


def test_u_shaped_and_oblique_buildings_never_overlap_road_or_sidewalk():
    from shapely import affinity

    campus_data = {
        "perimeter": [[-20.0, -20.0], [20.0, -20.0], [20.0, 20.0], [-20.0, 20.0]],
        "streets": [],
        "driveways": [],
    }
    boundary = box(-300, -300, 300, 300)
    roads = [
        {
            "id": "r_culdesac",
            "class": "residential",
            "name": "Rua Sem Saida",
            "is_tunnel": False,
            "width": None,
            "surface": "asphalt",
            "geom": LineString([(60.0, 0.0), (110.0, 0.0)]),
        },
        {
            "id": "r_diag",
            "class": "tertiary",
            "name": "Rua Obliqua",
            "is_tunnel": False,
            "width": None,
            "surface": "asphalt",
            "geom": LineString([(-140.0, 120.0), (-80.0, 60.0)]),
        },
    ]
    rout = build_roads(roads, boundary, campus_data)

    # Edificio em U de ~160 m2 abracando a ponta da rua sem saida (110, 0)
    u_poly = Polygon([
        (95, -12), (122, -12), (122, 12), (95, 12),
        (95, 6), (116, 6), (116, -6), (95, -6),
    ])
    # Casa obliqua de ~190 m2 colada na rua diagonal
    oblique_poly = affinity.rotate(box(-118, 86, -100, 96), -45, origin=(-109, 91))

    recs = [
        {"id": "u_bld", "class": "residential", "subtype": "residential", "height": None, "num_floors": None, "geom": u_poly},
        {"id": "ob_bld", "class": "residential", "subtype": "residential", "height": None, "num_floors": None, "geom": oblique_poly},
    ]
    bparts, _, _ = build_buildings(
        recs,
        boundary,
        Polygon(campus_data["perimeter"]),
        rout.road_clearance_geoms,
        {},
        extra_road_parts=rout.parts,
        anchor_streets=campus_data["streets"],
    )

    def to_poly(p):
        if p.part_type == PART_CYLINDER:
            from shapely.geometry import Point
            return Point(p.px_studs, p.pz_studs).buffer(max(p.sx_studs, p.sz_studs) * 0.5)
        b = box(-p.sx_studs * 0.5, -p.sz_studs * 0.5, p.sx_studs * 0.5, p.sz_studs * 0.5)
        return affinity.translate(affinity.rotate(b, -math.degrees(p.yaw_rad), origin=(0, 0)), xoff=p.px_studs, yoff=p.pz_studs)

    road_polys = [to_poly(p) for p in rout.parts if p.category in (CAT_ROADS, CAT_SIDEWALKS) and p.flags != 0]
    for bp in bparts:
        bpoly = to_poly(bp)
        assert not any(rp.intersects(bpoly) for rp in road_polys)
