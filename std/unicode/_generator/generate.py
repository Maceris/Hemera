"""
Writes std/unicode/tables.hsc from the Unicode Character Database.

    python generate.py <ucd folder>

The folder holds, from https://www.unicode.org/Public/<version>/ucd/: EastAsianWidth.txt,
DerivedCoreProperties.txt, extracted/DerivedGeneralCategory.txt, auxiliary/GraphemeBreakProperty.txt
and emoji/emoji-data.txt, all at the top. GraphemeBreakTest.txt (auxiliary/), for the tests, is copied
beside the tables as test/grapheme_break_test.txt.

Every code point gets one u16 of properties, and the table holds each run of code points with the same
value as its first code point and that value, which lookups find by binary search.
"""

import os
import re
import shutil
import sys

LAST = 0x10FFFF

# Grapheme_Cluster_Break values, in bits 0 to 3 (std/unicode's GraphemeBreak)
BREAKS = ["Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator", "Prepend", "SpacingMark",
          "L", "V", "T", "LV", "LVT"]
EXTENDED_PICTOGRAPHIC = 1 << 4
# Indic_Conjunct_Break, in bits 5 and 6
CONJUNCT = {"None": 0, "Linker": 1, "Consonant": 2, "Extend": 3}
CONJUNCT_SHIFT = 5
# Columns a code point takes, in bits 7 and 8
WIDTH_SHIFT = 7
DEFAULT_IGNORABLE = 1 << 9


def ranges(path, field=1):
    """Each line's first and last code point and its property, from a UCD file's 'a..b ; value' lines."""
    with open(path, encoding="utf-8") as file:
        for line in file:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = [part.strip() for part in line.split(";")]
            points = parts[0].split("..")
            first = int(points[0], 16)
            last = int(points[-1], 16)
            yield first, last, parts[field:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ucd = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    package = os.path.dirname(here)
    version = None
    with open(os.path.join(ucd, "EastAsianWidth.txt"), encoding="utf-8") as file:
        match = re.search(r"EastAsianWidth-(\d+\.\d+\.\d+)", file.readline())
        version = match.group(1) if match else "unknown"

    values = [0] * (LAST + 1)
    breaks = {name: i for i, name in enumerate(BREAKS)}
    for first, last, (value, *_) in ranges(os.path.join(ucd, "GraphemeBreakProperty.txt")):
        for point in range(first, last + 1):
            values[point] |= breaks[value]
    for first, last, (value, *_) in ranges(os.path.join(ucd, "emoji-data.txt")):
        if value == "Extended_Pictographic":
            for point in range(first, last + 1):
                values[point] |= EXTENDED_PICTOGRAPHIC
    for first, last, fields in ranges(os.path.join(ucd, "DerivedCoreProperties.txt")):
        if fields[0] == "InCB":
            for point in range(first, last + 1):
                values[point] |= CONJUNCT[fields[1]] << CONJUNCT_SHIFT
        elif fields[0] == "Default_Ignorable_Code_Point":
            for point in range(first, last + 1):
                values[point] |= DEFAULT_IGNORABLE

    # Widths: 1 unless wide, or zero-width below
    widths = [1] * (LAST + 1)
    listed = [False] * (LAST + 1)
    for first, last, (value, *_) in ranges(os.path.join(ucd, "EastAsianWidth.txt")):
        for point in range(first, last + 1):
            listed[point] = True
        if value in ("W", "F"):
            for point in range(first, last + 1):
                widths[point] = 2
    # Unassigned code points in the wide blocks EastAsianWidth.txt's @missing lines name are wide too
    with open(os.path.join(ucd, "EastAsianWidth.txt"), encoding="utf-8") as file:
        for line in file:
            match = re.match(r"# @missing: ([0-9A-F]+)\.\.([0-9A-F]+); W", line)
            if match:
                for point in range(int(match.group(1), 16), int(match.group(2), 16) + 1):
                    if not listed[point]:
                        widths[point] = 2
    categories = {}
    for first, last, (value, *_) in ranges(os.path.join(ucd, "DerivedGeneralCategory.txt")):
        for point in range(first, last + 1):
            categories[point] = value
    for point in range(LAST + 1):
        category = categories.get(point, "Cn")
        # Marks that combine, formats, controls, default ignorables and Hangul's medial vowels and final consonants
        # take no columns of their own
        if category in ("Mn", "Me", "Cf", "Cc") or values[point] & DEFAULT_IGNORABLE \
                or 0x1160 <= point <= 0x11FF or 0xD7B0 <= point <= 0xD7FF:
            widths[point] = 0
        values[point] |= widths[point] << WIDTH_SHIFT

    starts = []
    runs = []
    for point in range(LAST + 1):
        if point == 0 or values[point] != values[point - 1]:
            starts.append(point)
            runs.append(values[point])

    def rows(items, per_line, digits):
        lines = []
        for i in range(0, len(items), per_line):
            lines.append("    " + ", ".join(f"0x{item:0{digits}x}" for item in items[i:i + per_line]) + ",")
        return "\n".join(lines)

    text = f"""package unicode

// Generated by _generator/generate.py from the Unicode Character Database {version}; don't edit.

// The Unicode version the tables are from.
VERSION :: "{version}"

// The first code point of each run of code points with the same properties, ascending, from 0.
RUN_STARTS :: u32.[
{rows(starts, 10, 6)}
]

// Each run's properties: the grapheme break in bits 0 to 3, Extended_Pictographic in bit 4, the Indic conjunct break in
// bits 5 and 6, the width in bits 7 and 8, and Default_Ignorable_Code_Point in bit 9.
RUN_PROPERTIES :: u16.[
{rows(runs, 12, 4)}
]
"""
    with open(os.path.join(package, "tables.hsc"), "w", encoding="utf-8", newline="\n") as file:
        file.write(text)
    test_folder = os.path.join(package, "test")
    os.makedirs(test_folder, exist_ok=True)
    shutil.copyfile(os.path.join(ucd, "GraphemeBreakTest.txt"), os.path.join(test_folder, "grapheme_break_test.txt"))
    print(f"{len(starts)} runs from Unicode {version}")


if __name__ == "__main__":
    main()
