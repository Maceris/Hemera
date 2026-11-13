"""
Reference metrics for the fonts scenario, read from the Noto fonts by a reader of its own, apart from std/fonts:
head's units per em, hhea's ascender, descender and line gap, cmap's glyphs for some characters, hmtx's advances,
and each glyph's bounding box from glyf. Writes references.hsc beside this file.

    python -I references.py
"""

import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
FONTS = HERE.parent.parent / "fonts"
CHARACTERS = "AVWagé0 .€"


def tables(data: bytes) -> dict:
    count = struct.unpack_from(">H", data, 4)[0]
    found = {}
    for i in range(count):
        tag, _, offset, length = struct.unpack_from(">4sIII", data, 12 + 16 * i)
        found[tag.decode("latin-1")] = (offset, length)
    return found


def glyph_of(data: bytes, cmap: int, point: int) -> int:
    # Format 4 only: what Noto Sans's Basic Multilingual Plane needs
    count = struct.unpack_from(">H", data, cmap + 2)[0]
    for i in range(count):
        platform, encoding, offset = struct.unpack_from(">HHI", data, cmap + 4 + 8 * i)
        sub = cmap + offset
        if struct.unpack_from(">H", data, sub)[0] != 4 or (platform, encoding) not in ((3, 1), (0, 3)):
            continue
        segments = struct.unpack_from(">H", data, sub + 6)[0] // 2
        ends = [struct.unpack_from(">H", data, sub + 14 + 2 * s)[0] for s in range(segments)]
        starts_at = sub + 16 + 2 * segments
        for s in range(segments):
            if ends[s] >= point:
                start = struct.unpack_from(">H", data, starts_at + 2 * s)[0]
                if start > point:
                    return 0
                delta = struct.unpack_from(">h", data, starts_at + 2 * segments + 2 * s)[0]
                ranges = starts_at + 4 * segments + 2 * s
                range_offset = struct.unpack_from(">H", data, ranges)[0]
                if range_offset == 0:
                    return (point + delta) & 0xFFFF
                glyph = struct.unpack_from(">H", data, ranges + range_offset + 2 * (point - start))[0]
                return 0 if glyph == 0 else (glyph + delta) & 0xFFFF
        return 0
    raise SystemExit("no format 4 cmap")


def main() -> None:
    lines = ["// Made by references.py from the Noto fonts, by a reader of its own, apart from std/fonts", "package fonts_test", ""]
    for name in ("NotoSans-Regular", "NotoSansMono-Regular"):
        data = (FONTS / f"{name}.ttf").read_bytes()
        found = tables(data)
        head, hhea, hmtx, cmap, loca, glyf = (found[t][0] for t in ("head", "hhea", "hmtx", "cmap", "loca", "glyf"))
        units = struct.unpack_from(">H", data, head + 18)[0]
        long_loca = struct.unpack_from(">h", data, head + 50)[0] != 0
        ascender, descender, gap = struct.unpack_from(">hhh", data, hhea + 4)
        metrics = struct.unpack_from(">H", data, hhea + 34)[0]
        ident = name.replace("-", "_").upper()
        lines.append(f"{ident}_UNITS :: {units}")
        lines.append(f"{ident}_ASCENDER :: {ascender}")
        lines.append(f"{ident}_DESCENDER :: {descender}")
        lines.append(f"{ident}_LINE_GAP :: {gap}")
        lines.append(f"/** Each of {CHARACTERS!r}: its code point, glyph, advance and bounding box (x min, y min, x max, y max). */")
        lines.append(f"{ident}_GLYPHS :: Expected.[")
        for character in CHARACTERS:
            point = ord(character)
            glyph = glyph_of(data, cmap, point)
            index = min(glyph, metrics - 1)
            advance = struct.unpack_from(">H", data, hmtx + 4 * index)[0]
            if long_loca:
                start, end = struct.unpack_from(">II", data, loca + 4 * glyph)
            else:
                start, end = (2 * v for v in struct.unpack_from(">HH", data, loca + 2 * glyph))
            box = struct.unpack_from(">hhhh", data, glyf + start + 2) if end > start else (0, 0, 0, 0)
            lines.append(f"    Expected.{{point = {point}, glyph = {glyph}, advance = {advance}, x_min = {box[0]}, y_min = {box[1]}, "
                         f"x_max = {box[2]}, y_max = {box[3]}}},")
        lines.append("]")
        lines.append("")
    (HERE / "references.hsc").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print("ok")


main()
