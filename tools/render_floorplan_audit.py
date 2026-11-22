"""Gera planta-baixa 2D de auditoria (corte horizontal em Y=4.0 studs) a partir
de um dump JSON do Roblox Studio + data/interiors.json, na mesma orientação
do mapa oficial do IFSul (Setor 100 embaixo à esquerda, Saguão no centro,
Cantina em cima à direita) para validação visual instantânea de salas, paredes e portas.

Uso:
    python tools/render_floorplan_audit.py <slice_json_path> <output_png_path>
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SPM = 1.0 / 0.28


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: python tools/render_floorplan_audit.py <slice.json> <out.png>")
        sys.exit(1)

    slice_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    raw = slice_path.read_text(encoding="utf-8").strip()
    items = []
    if raw.startswith("["):
        items = json.loads(raw)
    else:
        for line in raw.splitlines():
            parts = line.strip().split(",")
            if len(parts) == 9:
                k = parts[0]
                nums = [float(x) for x in parts[1:]]
                items.append({
                    "k": k,
                    "pts": [(nums[0], nums[1]), (nums[2], nums[3]), (nums[4], nums[5]), (nums[6], nums[7])],
                })
    interiors = json.loads(Path("data/interiors.json").read_text(encoding="utf-8"))

    # Orientação igual ao mapa oficial:
    # +Z_world -> direita (+u), +X_world -> cima (-v), com rotação leve de -9.5° para alinhar eixos
    theta = math.radians(-9.5)
    ct, st = math.cos(theta), math.sin(theta)

    def to_map(wx: float, wz: float) -> tuple[float, float]:
        # Primeiro gira (wx, wz) para alinhar blocos com os eixos
        rx = wx * ct - wz * st
        rz = wx * st + wz * ct
        # u = direita (+rz), v = baixo (-rx, logo +rx vai para cima)
        return (rz, -rx)

    # Bounding box da região mostrada pelo usuário (Setor 100, Convivência, Saguão, 201..208, Cantina)
    u_min, u_max = -175.0, 145.0
    v_min, v_max = -155.0, 265.0
    scale = 5.0  # pixels por stud
    W = int((u_max - u_min) * scale)
    H = int((v_max - v_min) * scale)

    def px(wx: float, wz: float) -> tuple[float, float]:
        u, v = to_map(wx, wz)
        return ((u - u_min) * scale, (v - v_min) * scale)

    img = Image.new("RGB", (W, H), (246, 247, 245))
    draw = ImageDraw.Draw(img, "RGBA")

    # 1. Desenha retângulos das salas (data/interiors.json) com rótulos
    for rm in interiors["rooms"]:
        cx, cz = rm["center"][0] * SPM, rm["center"][1] * SPM
        hx, hz = rm["size"][0] * SPM * 0.5, rm["size"][1] * SPM * 0.5
        ang = math.radians(rm["rot_deg"])
        ca, sa = math.cos(ang), math.sin(ang)
        # Roblox CFrame.Angles(0, ang, 0): Right=(ca, -sa), Back=(sa, ca)
        corners = []
        for sx, sz in [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]:
            wx = cx + sx * ca + sz * sa
            wz = cz - sx * sa + sz * ca
            corners.append(px(wx, wz))
        u0, v0 = to_map(cx, cz)
        if u_min - 40 <= u0 <= u_max + 40 and v_min - 40 <= v0 <= v_max + 40:
            draw.polygon(corners, fill=(208, 228, 242, 130), outline=(140, 175, 200, 180))

    # 2. Desenha paredes/janelas/portas reais capturadas no Studio em Y=4.0
    layer_order = {"BldWall": 1, "IntWall": 2, "Window": 3, "IntDoor": 4, "BldDoor": 5}
    colors = {
        "BldWall": ((25, 28, 32, 240), (15, 18, 20, 255)),
        "IntWall": ((36, 128, 62, 235), (24, 92, 44, 255)),
        "Window": ((58, 126, 205, 220), (32, 86, 158, 255)),
        "IntDoor": ((230, 138, 20, 255), (180, 92, 0, 255)),
        "BldDoor": ((225, 32, 32, 255), (160, 0, 0, 255)),
    }
    items.sort(key=lambda it: layer_order.get(it["k"], 0))
    for it in items:
        poly = [px(pt[0], pt[1]) for pt in it["pts"]]
        fill, outline = colors.get(it["k"], ((120, 120, 120, 180), (80, 80, 80, 255)))
        draw.polygon(poly, fill=fill, outline=outline)
        if it["k"] in ("BldDoor", "IntDoor"):
            cx = sum(p[0] for p in poly) / 4
            cy = sum(p[1] for p in poly) / 4
            r_px = 6 if it["k"] == "BldDoor" else 4
            draw.ellipse((cx - r_px, cy - r_px, cx + r_px, cy + r_px), fill=fill)

    # 3. Rótulos das salas
    try:
        font = ImageFont.truetype("arialbd.ttf", 18)
        font_sm = ImageFont.truetype("arial.ttf", 13)
    except Exception:
        font = ImageFont.load_default()
        font_sm = font

    for rm in interiors["rooms"]:
        cx, cz = rm["center"][0] * SPM, rm["center"][1] * SPM
        u0, v0 = to_map(cx, cz)
        if u_min <= u0 <= u_max and v_min <= v0 <= v_max:
            x0, y0 = px(cx, cz)
            draw.text((x0 - 18, y0 - 10), rm["code"], fill=(15, 25, 45, 255), font=font)

    # Legenda no topo-esquerdo
    draw.rectangle((14, 14, 420, 146), fill=(255, 255, 255, 235), outline=(180, 185, 190, 255), width=2)
    legend = [
        ((25, 28, 32, 255), "Parede Buildings (Y=4.0)"),
        ((36, 128, 62, 255), "Parede Interiors / Enhanced (Y=4.0)"),
        ((58, 126, 205, 255), "Janela Buildings"),
        ((225, 32, 32, 255), "Porta Buildings (verificar se deveria existir!)"),
        ((230, 138, 20, 255), "Batente de Porta de Sala (Interiors)"),
    ]
    for i, (col, txt) in enumerate(legend):
        ly = 24 + i * 23
        draw.rectangle((26, ly + 2, 46, ly + 16), fill=col)
        draw.text((54, ly), txt, fill=(20, 24, 28, 255), font=font_sm)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(f"AUDIT_PNG_OK: {out_path} ({W}x{H}, items={len(items)})")


if __name__ == "__main__":
    main()
