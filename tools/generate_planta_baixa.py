import json
import math
import os
import urllib.request
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join("assets", "ref", "plantas_e_mapas")
os.makedirs(OUT_DIR, exist_ok=True)

with open(os.path.join("data", "campus.json"), "r", encoding="utf-8") as f:
    CAMPUS = json.load(f)

INTERIORS = {}
interiors_path = os.path.join("data", "interiors.json")
if os.path.exists(interiors_path):
    with open(interiors_path, "r", encoding="utf-8") as f:
        INTERIORS = json.load(f)

ORIGIN_LAT = CAMPUS["meta"]["origin_lat"]
ORIGIN_LON = CAMPUS["meta"]["origin_lon"]
LAT_M = 111132.0
LON_M = 96486.0


def fetch_file(url: str, path: str) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "IFSulCampusReference/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            with open(path, "wb") as out:
                out.write(resp.read())
        return os.path.getsize(path) > 1000
    except Exception as e:
        print(f"WARN fetch {url}: {e}")
        return False


def tile2lonlat(tx: float, ty: float, z: int):
    n = 2.0 ** z
    lon = tx / n * 360.0 - 180.0
    lat_r = math.atan(math.sinh(math.pi * (1.0 - 2.0 * ty / n)))
    return lon, math.degrees(lat_r)


def download_maps():
    # Compute Zoom-19 Esri World Imagery bounds around campus
    z19 = 19
    n19 = 2 ** z19
    xc = int((ORIGIN_LON + 180.0) / 360.0 * n19)
    lat_r = math.radians(ORIGIN_LAT)
    yc = int((1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n19)
    tx0, tx1 = xc - 2, xc + 3
    ty0, ty1 = yc - 3, yc + 4
    lon_min, lat_max = tile2lonlat(tx0, ty0, z19)
    lon_max, lat_min = tile2lonlat(tx1, ty1, z19)

    sat_path = os.path.join(OUT_DIR, "ortofoto_campus_alta_res.jpg")
    if not (os.path.exists(sat_path) and os.path.getsize(sat_path) > 10000):
        sat_w, sat_h = (tx1 - tx0) * 256, (ty1 - ty0) * 256
        sat_img = Image.new("RGB", (sat_w, sat_h))
        for dy, ty in enumerate(range(ty0, ty1)):
            for dx, tx in enumerate(range(tx0, tx1)):
                tmp = os.path.join(OUT_DIR, f"_esri_{tx}_{ty}.jpg")
                if fetch_file(f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z19}/{ty}/{tx}", tmp):
                    sat_img.paste(Image.open(tmp).convert("RGB"), (dx * 256, dy * 256))
                if os.path.exists(tmp):
                    os.remove(tmp)
        sat_img.save(sat_path, quality=95)

    osm_path = os.path.join(OUT_DIR, "mapa_osm_zoom18.png")
    if not (os.path.exists(osm_path) and os.path.getsize(osm_path) > 10000):
        z = 18
        n = 2 ** z
        xt = int((ORIGIN_LON + 180.0) / 360.0 * n)
        yt = int((1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n)
        osm_img = Image.new("RGB", (256 * 3, 256 * 4))
        for dy, ty in enumerate(range(yt - 1, yt + 3)):
            for dx, tx in enumerate(range(xt - 1, xt + 2)):
                tmp = os.path.join(OUT_DIR, f"_osm_{tx}_{ty}.png")
                if fetch_file(f"https://tile.openstreetmap.org/{z}/{tx}/{ty}.png", tmp):
                    tile = Image.open(tmp).convert("RGB")
                    osm_img.paste(tile, (dx * 256, dy * 256))
                if os.path.exists(tmp):
                    os.remove(tmp)
        osm_img.save(osm_path)

    return sat_path, (lon_min, lat_min, lon_max, lat_max)


def poly_bbox(poly):
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    return min(xs), min(zs), max(xs), max(zs)


def poly_area(poly):
    a = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        a += x1 * y2 - x2 * y1
    return abs(a) * 0.5


def poly_centroid(poly):
    return sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly)


def hex_to_rgba(h: str, alpha: int = 120):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def draw_blueprint(sat_path: str, sat_bounds):
    W, H = 1800, 2400
    X0, X1 = -115.0, 110.0
    Z0, Z1 = -175.0, 175.0
    PAD_TOP = 130
    PAD_BOT = 120
    PAD_X = 90
    DRAW_W = W - 2 * PAD_X
    DRAW_H = H - PAD_TOP - PAD_BOT
    scale = min(DRAW_W / (X1 - X0), DRAW_H / (Z1 - Z0))
    OX = (W - (X1 - X0) * scale) * 0.5
    OY = PAD_TOP + (DRAW_H - (Z1 - Z0) * scale) * 0.5

    def w2p(x, z):
        return (OX + (x - X0) * scale, OY + (z - Z0) * scale)

    def _font(sz: int):
        for fp in ["C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
            if os.path.exists(fp):
                return ImageFont.truetype(fp, sz)
        return ImageFont.load_default(size=sz)

    font_lg = _font(28)
    font_md = _font(18)
    font_sm = _font(14)
    font_xs = _font(12)

    img = Image.new("RGB", (W, H), "#F6F8F6")
    d = ImageDraw.Draw(img)

    # 10m metric grid
    for gx in range(-110, 115, 10):
        p0 = w2p(gx, Z0)
        p1 = w2p(gx, Z1)
        col = "#D7E0D8" if gx % 50 != 0 else "#B8C7BA"
        d.line([p0, p1], fill=col, width=1)
        if gx % 20 == 0:
            d.text((p0[0] - 12, p0[1] - 18), f"{gx}m", fill="#4D6150", font=font_xs)
    for gz in range(-170, 175, 10):
        p0 = w2p(X0, gz)
        p1 = w2p(X1, gz)
        col = "#D7E0D8" if gz % 50 != 0 else "#B8C7BA"
        d.line([p0, p1], fill=col, width=1)
        if gz % 20 == 0:
            d.text((p0[0] - 42, p0[1] - 6), f"{gz}m", fill="#4D6150", font=font_xs)

    # Streets
    for st in CAMPUS.get("streets", []):
        pts = [w2p(p[0], p[1]) for p in st["points"]]
        w_px = max(4, int(st.get("width", 8.0) * scale))
        if len(pts) >= 2:
            d.line(pts, fill="#9BA2A8", width=w_px)
            d.line(pts, fill="#FFFFFF", width=1)
            mx, my = pts[len(pts) // 2]
            d.text((mx - 40, my - 8), st["name"], fill="#2B3137", font=font_xs)

    # Campus perimeter
    perim = [w2p(p[0], p[1]) for p in CAMPUS.get("perimeter", [])]
    if len(perim) >= 3:
        d.polygon(perim, fill="#E4EFE3", outline="#1B6E2B", width=4)

    # Parking lots & walkways
    for pk in CAMPUS.get("parking_lots", []):
        pts = [w2p(p[0], p[1]) for p in pk["polygon"]]
        d.polygon(pts, fill="#C5C9CE", outline="#5A626A", width=2)
        cx, cy = poly_centroid(pk["polygon"])
        px, py = w2p(cx, cy)
        d.text((px - 50, py - 8), pk["name"], fill="#1F2429", font=font_xs)

    for fw in CAMPUS.get("footways", []):
        pts = [w2p(p[0], p[1]) for p in fw["points"]]
        if len(pts) >= 2:
            d.line(pts, fill="#D8D2C5", width=max(3, int(fw.get("width", 2.5) * scale)))

    # Horta landmark
    horta = CAMPUS.get("landmarks", {}).get("horta", {})
    if horta and horta.get("polygon"):
        hpts = [w2p(p[0], p[1]) for p in horta["polygon"]]
        d.polygon(hpts, fill="#A5D6A7", outline="#2E7D32", width=2)
        hcx, hcy = poly_centroid(horta["polygon"])
        hpx, hpy = w2p(hcx, hcy)
        d.text((hpx - 28, hpy - 8), "Horta", fill="#1B5E20", font=font_sm)

    # Entrance Covered Walkway (Passarela Coberta da Portaria)
    walkway = CAMPUS.get("landmarks", {}).get("passarela_entrada", {})
    if walkway and walkway.get("polygon"):
        wpts = [w2p(p[0], p[1]) for p in walkway["polygon"]]
        d.polygon(wpts, fill="#EBE3A8", outline="#2E6E36", width=2)
        wpx, wpy = w2p(-46.5, -5.8)
        d.text((wpx - 44, wpy - 6), "Passarela Coberta", fill="#1B4D22", font=font_xs)

    # Courts
    for c in CAMPUS.get("courts", []):
        pts = [w2p(p[0], p[1]) for p in c["polygon"]]
        sp = c.get("sport", "")
        fill = "#89B4D8" if sp == "multi" else ("#B0BEC5" if sp == "outdoor_multi" else "#E3C9A3")
        d.polygon(pts, fill=fill, outline="#1F3B52", width=3)
        cx, cy = poly_centroid(c["polygon"])
        px, py = w2p(cx, cy)
        sz = c["size"]
        d.text((px - 55, py - 14), f"{c['name']}\n{sz[0]:.1f}m × {sz[1]:.1f}m", fill="#102536", font=font_xs)

    # Buildings colored by official Mapa das Salas sector palette
    svg_elems = []
    if walkway and walkway.get("polygon"):
        w_svg_pts = " ".join(f"{w2p(p[0], p[1])[0]:.1f},{w2p(p[0], p[1])[1]:.1f}" for p in walkway["polygon"])
        svg_elems.append(f'<polygon points="{w_svg_pts}" fill="#EBE3A8" stroke="#2E6E36" stroke-width="2"/>')
    for idx, b in enumerate(CAMPUS.get("buildings", []), start=1):
        poly = b["polygon"]
        pts = [w2p(p[0], p[1]) for p in poly]
        area = poly_area(poly)
        x0, z0, x1, z1 = poly_bbox(poly)
        bw, bd = x1 - x0, z1 - z0
        fill = b.get("map_color", "#FFFFFF")
        outline = "#1B3A24" if b.get("type") != "auditorium" else "#8A6D0B"
        d.polygon(pts, fill=fill, outline=outline, width=3)
        if b.get("courtyard_inset"):
            cx0, cz0 = poly_centroid(poly)
            inset_pts = [w2p(p[0] + (cx0 - p[0]) * 0.48, p[1] + (cz0 - p[1]) * 0.48) for p in poly]
            d.polygon(inset_pts, fill="#CFE3CE", outline="#1E5E2C", width=2)
        cx, cy = poly_centroid(poly)
        px, py = w2p(cx, cy)
        short = b["name"].split("—")[0].strip()[:26]
        label = f"B{idx}: {short}\n{bw:.1f}×{bd:.1f}m ({area:.0f}m²)\n{b['floors']} pav. | h={b['height_m']}m"
        d.text((px - 55, py - 18), label, fill="#111913", font=font_xs)
        svg_pts = " ".join(f"{p[0]:.1f},{p[1]:.1f}" for p in pts)
        svg_elems.append(f'<polygon points="{svg_pts}" fill="{fill}" stroke="{outline}" stroke-width="2.5"/>')
        svg_elems.append(f'<text x="{px:.1f}" y="{py:.1f}" font-size="11" font-family="Arial" text-anchor="middle" fill="#111">B{idx}: {short} ({area:.0f}m², {b["floors"]}p)</text>')

    # Water tower + 8 POIs
    wt = CAMPUS.get("landmarks", {}).get("water_tower", {})
    if wt:
        wx, wy = w2p(wt["position"][0], wt["position"][2])
        rr = wt["radius"] * scale
        d.ellipse([wx - rr, wy - rr, wx + rr, wy + rr], fill="#64748B", outline="#0F172A", width=2)
        d.text((wx + rr + 4, wy - 6), "Caixa d'Água", fill="#0F172A", font=font_xs)

    pois = CAMPUS.get("pois", [])
    for i, poi in enumerate(pois, start=1):
        px, py = w2p(poi["position"][0], poi["position"][2])
        d.ellipse([px - 8, py - 8, px + 8, py + 8], fill="#F5C43D", outline="#111111", width=2)
        d.text((px - 4, py - 7), str(i), fill="#000000", font=font_xs)

    # Header & Legend & North Rose & Scale Bar
    d.rectangle([0, 0, W, 102], fill="#143D1E")
    d.text((36, 20), "PLANTA-BAIXA DE IMPLANTAÇÃO COTADA — IFSul CÂMPUS SAPUCAIA DO SUL", fill="#FFFFFF", font=font_lg)
    room_cnt = len(INTERIORS.get("rooms", []))
    d.text((36, 58), f"{CAMPUS['meta']['address']} | Área: ~38.600 m² | 16 Blocos | {room_cnt} Salas/Ambientes | {len(pois)} POIs (Mapa das Salas + OSM + Esri)", fill="#C8E6CE", font=font_md)

    # Scale bar (50m) + North arrow
    sb_x, sb_y = W - 420, H - 72
    sb_len = 50.0 * scale
    d.rectangle([sb_x, sb_y, sb_x + sb_len, sb_y + 12], fill="#143D1E", outline="#143D1E")
    d.rectangle([sb_x, sb_y, sb_x + sb_len * 0.5, sb_y + 12], fill="#FFFFFF", outline="#143D1E")
    d.text((sb_x, sb_y - 20), "0m                 25m                 50m (Escala métrica)", fill="#143D1E", font=font_sm)
    nx, ny = W - 80, 175
    d.polygon([(nx, ny - 34), (nx - 14, ny + 12), (nx, ny + 2), (nx + 14, ny + 12)], fill="#CD191E", outline="#111")
    d.text((nx - 6, ny - 54), "N", fill="#CD191E", font=font_md)
    d.text((36, H - 78), f"Legenda: Cores = Setores oficiais (100 Azul, 200/230 Verde, 300/400 Laranja, 500 Amarelo, 800 Verde-claro, Biblioteca Turquesa) | Amarelo 1..{len(pois)} = POIs", fill="#1B3321", font=font_sm)

    out_png = os.path.join(OUT_DIR, "planta_baixa_tecnica_cotada.png")
    img.save(out_png)

    # Save SVG vector blueprint too
    perim_svg = " ".join(f"{p[0]:.1f},{p[1]:.1f}" for p in perim)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
        f'<rect width="100%" height="100%" fill="#f6f8f6"/>'
        f'<polygon points="{perim_svg}" fill="#e4efe3" stroke="#1b6e2b" stroke-width="4"/>'
        + "\n".join(svg_elems)
        + "</svg>"
    )
    with open(os.path.join(OUT_DIR, "planta_baixa_tecnica_cotada.svg"), "w", encoding="utf-8") as sf:
        sf.write(svg)

    # Hybrid architectural overlay on Esri high-res Zoom-19 orthoimage
    if os.path.exists(sat_path) and os.path.getsize(sat_path) > 5000:
        sat = Image.open(sat_path).convert("RGBA")
        sw, sh = sat.size
        ov = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        lon_min, lat_min, lon_max, lat_max = sat_bounds

        def s2p(x, z):
            lon = ORIGIN_LON + x / LON_M
            lat = ORIGIN_LAT - z / LAT_M
            px = (lon - lon_min) / (lon_max - lon_min) * sw
            py = (lat_max - lat) / (lat_max - lat_min) * sh
            return (px, py)

        p_sat = [s2p(p[0], p[1]) for p in CAMPUS.get("perimeter", [])]
        od.polygon(p_sat, outline=(47, 255, 95, 220), width=4)
        if horta and horta.get("polygon"):
            hp_sat = [s2p(p[0], p[1]) for p in horta["polygon"]]
            od.polygon(hp_sat, fill=(102, 187, 106, 75), outline=(129, 230, 134, 235), width=2)
        if walkway and walkway.get("polygon"):
            wp_sat = [s2p(p[0], p[1]) for p in walkway["polygon"]]
            od.polygon(wp_sat, fill=(235, 227, 168, 125), outline=(46, 110, 54, 240), width=2)
        for idx, b in enumerate(CAMPUS.get("buildings", []), start=1):
            bp = [s2p(p[0], p[1]) for p in b["polygon"]]
            col_rgba = hex_to_rgba(b.get("map_color", "#FFFFFF"), 80)
            od.polygon(bp, fill=col_rgba, outline=(255, 230, 80, 235), width=2)
            cx, cy = poly_centroid(b["polygon"])
            sx, sy = s2p(cx, cy)
            short = b["name"].split("—")[0].strip()[:20]
            od.text((sx - 34, sy - 6), f"B{idx}: {short}", fill=(255, 255, 255, 255), font=font_xs)
        for c in CAMPUS.get("courts", []):
            cp = [s2p(p[0], p[1]) for p in c["polygon"]]
            od.polygon(cp, outline=(56, 189, 248, 240), width=3)
        for i, poi in enumerate(pois, start=1):
            sx, sy = s2p(poi["position"][0], poi["position"][2])
            od.ellipse([sx - 9, sy - 9, sx + 9, sy + 9], fill=(245, 196, 61, 255), outline=(0, 0, 0, 255), width=2)
            od.text((sx - 4, sy - 7), str(i), fill=(0, 0, 0, 255), font=font_xs)
        hybrid = Image.alpha_composite(sat, ov).convert("RGB")
        hybrid.save(os.path.join(OUT_DIR, "planta_baixa_sobre_satelite.png"))


if __name__ == "__main__":
    sat, bounds = download_maps()
    draw_blueprint(sat, bounds)
    print("PLANTA_BAIXA_OK")
