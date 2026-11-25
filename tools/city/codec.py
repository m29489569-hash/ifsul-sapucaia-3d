"""Codec binario IFC2 (SoA + Zstd + Base64) para tiles de cidade no Roblox Studio."""

from __future__ import annotations

import base64
from compression import zstd
from dataclasses import dataclass
import math
import struct
from typing import Iterable

STUDS_PER_METER = 1.0 / 0.28

MAGIC = b"IFC2"
HEADER_FMT = "<4shhffI"
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # 20 bytes

# Tipos de BasePart (alinhados ao CampusBuilder.luau)
PART_BLOCK = 1
PART_CYLINDER = 2
PART_WEDGE = 5

# Materiais (alinhados ao CampusBuilder.luau)
MAT_SMOOTH_PLASTIC = 1
MAT_CONCRETE = 2
MAT_GRASS = 3
MAT_ASPHALT = 4
MAT_SLATE = 5
MAT_METAL = 6
MAT_GLASS = 7
MAT_WOOD = 8
MAT_NEON = 9

# Categorias de pasta dentro do Model do tile
CAT_GROUND = 1
CAT_ROADS = 2
CAT_SIDEWALKS = 3
CAT_BUILDINGS = 4

FLAG_COLLIDE = 1 << 0
FLAG_SHADOW = 1 << 1
FLAG_CAN_QUERY = 1 << 2


@dataclass(slots=True)
class TilePart:
    part_type: int
    material: int
    category: int
    flags: int
    r: int
    g: int
    b: int
    px_studs: float
    py_studs: float
    pz_studs: float
    sx_studs: float
    sy_studs: float
    sz_studs: float
    yaw_rad: float = 0.0


def _clamp_i16(v: float) -> int:
    iv = int(round(v))
    if iv < -32768:
        return -32768
    if iv > 32767:
        return 32767
    return iv


def _clamp_u16(v: float, lo: int = 1) -> int:
    iv = int(round(v))
    if iv < lo:
        return lo
    if iv > 65535:
        return 65535
    return iv


def _clamp_u8(v: int) -> int:
    if v < 0:
        return 0
    if v > 255:
        return 255
    return int(v)


def encode_tile_b64(
    tx: int,
    tz: int,
    origin_x_studs: float,
    origin_z_studs: float,
    parts: Iterable[TilePart],
    zstd_level: int = 19,
) -> tuple[str, int]:
    """Serializa uma lista de TilePart em formato IFC2 + Zstd + Base64."""
    items = list(parts)
    n = len(items)

    buf = bytearray()
    buf.extend(struct.pack(HEADER_FMT, MAGIC, tx, tz, origin_x_studs, origin_z_studs, n))

    if n > 0:
        t_arr = bytearray(n)
        m_arr = bytearray(n)
        c_arr = bytearray(n)
        f_arr = bytearray(n)
        r_arr = bytearray(n)
        g_arr = bytearray(n)
        b_arr = bytearray(n)

        px_arr = [0] * n
        py_arr = [0] * n
        pz_arr = [0] * n
        sx_arr = [0] * n
        sy_arr = [0] * n
        sz_arr = [0] * n
        yaw_arr = [0] * n

        two_pi = math.tau
        for i, p in enumerate(items):
            t_arr[i] = p.part_type & 0xFF
            m_arr[i] = p.material & 0xFF
            c_arr[i] = p.category & 0xFF
            f_arr[i] = p.flags & 0xFF
            r_arr[i] = _clamp_u8(p.r)
            g_arr[i] = _clamp_u8(p.g)
            b_arr[i] = _clamp_u8(p.b)

            px_arr[i] = _clamp_i16((p.px_studs - origin_x_studs) * 20.0)
            py_arr[i] = _clamp_i16(p.py_studs * 100.0)
            pz_arr[i] = _clamp_i16((p.pz_studs - origin_z_studs) * 20.0)

            sx_arr[i] = _clamp_u16(p.sx_studs * 20.0, 1)
            sy_arr[i] = _clamp_u16(p.sy_studs * 100.0, 1)
            sz_arr[i] = _clamp_u16(p.sz_studs * 20.0, 1)

            yaw_norm = (p.yaw_rad % two_pi) / two_pi
            yaw_arr[i] = int(round(yaw_norm * 65536.0)) & 0xFFFF

        buf.extend(t_arr)
        buf.extend(m_arr)
        buf.extend(c_arr)
        buf.extend(f_arr)
        buf.extend(r_arr)
        buf.extend(g_arr)
        buf.extend(b_arr)

        buf.extend(struct.pack(f"<{n}h", *px_arr))
        buf.extend(struct.pack(f"<{n}h", *py_arr))
        buf.extend(struct.pack(f"<{n}h", *pz_arr))
        buf.extend(struct.pack(f"<{n}H", *sx_arr))
        buf.extend(struct.pack(f"<{n}H", *sy_arr))
        buf.extend(struct.pack(f"<{n}H", *sz_arr))
        buf.extend(struct.pack(f"<{n}H", *yaw_arr))

    raw = bytes(buf)
    compressed = zstd.compress(raw, level=zstd_level)
    b64 = base64.b64encode(compressed).decode("ascii")
    return b64, len(raw)


def decode_tile_b64(b64_payload: str) -> tuple[tuple[int, int, float, float], list[TilePart]]:
    """Decodifica um blob Base64+Zstd IFC2 (espelho do decoder Luau para testes)."""
    comp = base64.b64decode(b64_payload)
    raw = zstd.decompress(comp)
    magic, tx, tz, ox, oz, n = struct.unpack_from(HEADER_FMT, raw, 0)
    if magic != MAGIC:
        raise ValueError(f"Magic invalido: {magic!r}")

    off = HEADER_SIZE
    t_arr = raw[off : off + n]; off += n
    m_arr = raw[off : off + n]; off += n
    c_arr = raw[off : off + n]; off += n
    f_arr = raw[off : off + n]; off += n
    r_arr = raw[off : off + n]; off += n
    g_arr = raw[off : off + n]; off += n
    b_arr = raw[off : off + n]; off += n

    px_arr = struct.unpack_from(f"<{n}h", raw, off); off += 2 * n
    py_arr = struct.unpack_from(f"<{n}h", raw, off); off += 2 * n
    pz_arr = struct.unpack_from(f"<{n}h", raw, off); off += 2 * n
    sx_arr = struct.unpack_from(f"<{n}H", raw, off); off += 2 * n
    sy_arr = struct.unpack_from(f"<{n}H", raw, off); off += 2 * n
    sz_arr = struct.unpack_from(f"<{n}H", raw, off); off += 2 * n
    yaw_arr = struct.unpack_from(f"<{n}H", raw, off); off += 2 * n

    parts: list[TilePart] = []
    for i in range(n):
        parts.append(
            TilePart(
                part_type=t_arr[i],
                material=m_arr[i],
                category=c_arr[i],
                flags=f_arr[i],
                r=r_arr[i],
                g=g_arr[i],
                b=b_arr[i],
                px_studs=ox + px_arr[i] / 20.0,
                py_studs=py_arr[i] / 100.0,
                pz_studs=oz + pz_arr[i] / 20.0,
                sx_studs=sx_arr[i] / 20.0,
                sy_studs=sy_arr[i] / 100.0,
                sz_studs=sz_arr[i] / 20.0,
                yaw_rad=(yaw_arr[i] / 65536.0) * math.tau,
            )
        )
    return (tx, tz, ox, oz), parts
