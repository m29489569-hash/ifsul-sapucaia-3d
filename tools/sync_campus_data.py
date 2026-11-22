"""
Gera src/shared/CampusData.luau a partir de data/campus.json e data/interiors.json.
Execute sempre que editar qualquer arquivo em data/ para manter o código Luau sincronizado:

    python tools/sync_campus_data.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAMPUS_JSON = ROOT / "data" / "campus.json"
INTERIORS_JSON = ROOT / "data" / "interiors.json"
OUT_LUAU = ROOT / "src" / "shared" / "CampusData.luau"

STUDS_PER_METER = 1.0 / 0.28


def lua_str(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    if len(h) != 6:
        return (200, 200, 200)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def main() -> None:
    campus = json.loads(CAMPUS_JSON.read_text(encoding="utf-8"))
    interiors = json.loads(INTERIORS_JSON.read_text(encoding="utf-8"))

    lines: list[str] = [
        "--!strict",
        "-- GERADO AUTOMATICAMENTE por tools/sync_campus_data.py",
        "-- NÃO edite manualmente: altere data/campus.json ou data/interiors.json e rode o script.",
        "",
        "export type POIData = {",
        "\tid: string,",
        "\ttitle: string,",
        "\tsubtitle: string,",
        "\tdescription: string,",
        "\tposition: Vector3,",
        "}",
        "",
        "export type SectorData = {",
        "\tid: string,",
        "\tname: string,",
        "\tcolor: Color3,",
        "}",
        "",
        "export type RoomData = {",
        "\tid: string,",
        "\tcode: string,",
        "\tname: string,",
        "\tsector: string,",
        "\taliases: { string },",
        "\tcenter: Vector3,",
        "\tsize: Vector2,",
        "\trotDeg: number,",
        "}",
        "",
        "local CampusData = {}",
        "",
    ]

    # Sectors
    lines.append("CampusData.Sectors = {")
    for sid, sinfo in interiors.get("sectors", {}).items():
        r, g, b = hex_to_rgb(sinfo.get("color", "#888888"))
        lines.append(
            f"\t[{lua_str(sid)}] = {{ id = {lua_str(sid)}, name = {lua_str(sinfo.get('name', sid))}, "
            f"color = Color3.fromRGB({r}, {g}, {b}) }},"
        )
    lines.append("}")
    lines.append("")

    # POIs
    lines.append("CampusData.POIs = {")
    for poi in campus.get("pois", []):
        p = poi.get("position", [0, 0, 0])
        sx = round(p[0] * STUDS_PER_METER, 2)
        sy = round(max(1.2, p[1]) * STUDS_PER_METER, 2)
        sz = round(p[2] * STUDS_PER_METER, 2)
        lines.append("\t{")
        lines.append(f"\t\tid = {lua_str(poi['id'])},")
        lines.append(f"\t\ttitle = {lua_str(poi['title'])},")
        lines.append(f"\t\tsubtitle = {lua_str(poi.get('subtitle', ''))},")
        lines.append(f"\t\tdescription = {lua_str(poi.get('description', ''))},")
        lines.append(f"\t\tposition = Vector3.new({sx}, {sy}, {sz}),")
        lines.append("\t},")
    lines.append("}")
    lines.append("")

    # Rooms
    lines.append("CampusData.Rooms = {")
    for rm in interiors.get("rooms", []):
        c = rm.get("center", [0, 0])
        sz = rm.get("size", [4, 4])
        cx = round(c[0] * STUDS_PER_METER, 2)
        cz = round(c[1] * STUDS_PER_METER, 2)
        sw = round(sz[0] * STUDS_PER_METER, 2)
        sd = round(sz[1] * STUDS_PER_METER, 2)
        aliases = ", ".join(lua_str(a) for a in rm.get("aliases", []))
        lines.append(
            f"\t{{ id = {lua_str(rm['id'])}, code = {lua_str(str(rm.get('code', '')))}, "
            f"name = {lua_str(rm.get('name', ''))}, sector = {lua_str(str(rm.get('sector', '')))}, "
            f"aliases = {{ {aliases} }}, center = Vector3.new({cx}, 4.5, {cz}), "
            f"size = Vector2.new({sw}, {sd}), rotDeg = {round(float(rm.get('rot_deg', 0.0)), 2)} }},"
        )
    lines.append("}")
    lines.append("")
    lines.append("return CampusData")
    lines.append("")

    OUT_LUAU.parent.mkdir(parents=True, exist_ok=True)
    OUT_LUAU.write_text("\n".join(lines), encoding="utf-8")
    print(
        f"SYNC_OK: {OUT_LUAU.relative_to(ROOT)} "
        f"(sectors={len(interiors.get('sectors', {}))}, "
        f"pois={len(campus.get('pois', []))}, "
        f"rooms={len(interiors.get('rooms', []))})"
    )


if __name__ == "__main__":
    main()
