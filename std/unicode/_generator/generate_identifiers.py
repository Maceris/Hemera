"""
Writes the compiler's identifier tables, apps/compiler/src/lexer/identifier_tables.h, from the Unicode Character
Database.

    python generate_identifiers.py <ucd folder>

The folder holds DerivedCoreProperties.txt, UnicodeData.txt and DerivedNormalizationProps.txt, from
https://www.unicode.org/Public/<version>/ucd/, of the version the rest of std/unicode is generated from.

Names are UAX #31's default identifiers (docs/formatting.md): a code point with XID_Start, then any with
XID_Continue. Default_Ignorable_Code_Point ones are left out of both, as they're invisible and so would make two names
that look the same. Each of those tables is the code points' runs, as first and last, ascending, which lookups find by
binary search.

A name must also be in NFKC already, which the compiler checks by normalizing it (UAX #15), with: each run of code
points with the same canonical combining class but 0; the full compatibility decomposition, decomposed again until
nothing in it decomposes, of each code point a name can have that has one, but Hangul syllables, which are worked out;
and each pair of code points that composes canonically, but those excluded from composition (Full_Composition_Exclusion).
"""

import os
import re
import sys

LAST = 0x10FFFF


def properties(path):
    """Each line's first and last code point and its property name, from DerivedCoreProperties.txt."""
    with open(path, encoding="utf-8") as file:
        for line in file:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            points, name = [part.strip() for part in line.split(";")[:2]]
            bounds = points.split("..")
            yield int(bounds[0], 16), int(bounds[-1], 16), name


def runs(points):
    """The runs of consecutive code points in a sorted list, as (first, last)."""
    result = []
    for point in points:
        if result and result[-1][1] == point - 1:
            result[-1] = (result[-1][0], point)
        else:
            result.append((point, point))
    return result


def table(name, comment, ranges):
    lines = [f"\t// {comment}", f"\tinline constexpr CodePointRange {name}[] = {{"]
    row = []
    for first, last in ranges:
        row.append(f"{{ 0x{first:05X}, 0x{last:05X} }}")
        if len(row) == 6:
            lines.append("\t\t" + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("\t\t" + ", ".join(row) + ",")
    lines.append("\t};")
    return "\n".join(lines)


def unicode_data(path):
    """Each code point's canonical combining class and decomposition, with whether it's canonical, from UnicodeData.txt."""
    classes = {}
    decompositions = {}
    with open(path, encoding="utf-8") as file:
        for line in file:
            fields = line.rstrip("\n").split(";")
            point = int(fields[0], 16)
            if fields[3] != "0":
                classes[point] = int(fields[3])
            if fields[5]:
                parts = fields[5].split()
                canonical = not parts[0].startswith("<")
                decompositions[point] = (canonical, [int(part, 16) for part in (parts if canonical else parts[1:])])
    return classes, decompositions


def full_decomposition(point, decompositions):
    """point's compatibility decomposition, decomposed again until nothing in it decomposes."""
    if point not in decompositions:
        return [point]
    result = []
    for part in decompositions[point][1]:
        result.extend(full_decomposition(part, decompositions))
    return result


def class_table(classes):
    lines = ["\t// Each run of code points with the same canonical combining class, but 0: first, last and the class",
             "\tinline constexpr CombiningClassRange COMBINING_CLASSES[] = {"]
    runs_of = []
    for point in sorted(classes):
        if runs_of and runs_of[-1][1] == point - 1 and runs_of[-1][2] == classes[point]:
            runs_of[-1] = (runs_of[-1][0], point, classes[point])
        else:
            runs_of.append((point, point, classes[point]))
    row = []
    for first, last, value in runs_of:
        row.append(f"{{ 0x{first:05X}, 0x{last:05X}, {value} }}")
        if len(row) == 5:
            lines.append("\t\t" + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("\t\t" + ", ".join(row) + ",")
    lines.append("\t};")
    return "\n".join(lines), len(runs_of)


def decomposition_tables(points, decompositions):
    entries = []
    pool = []
    for point in points:
        if point in decompositions:
            parts = full_decomposition(point, decompositions)
            entries.append((point, len(pool), len(parts)))
            pool.extend(parts)
    lines = ["\t// Each code point a name can have with a decomposition: it, where its full decomposition starts in",
             "\t// DECOMPOSED, and its length",
             "\tinline constexpr Decomposition DECOMPOSITIONS[] = {"]
    row = []
    for point, start, length in entries:
        row.append(f"{{ 0x{point:05X}, {start}, {length} }}")
        if len(row) == 6:
            lines.append("\t\t" + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("\t\t" + ", ".join(row) + ",")
    lines += ["\t};", "", "\t// The decompositions' code points, one after another",
              "\tinline constexpr uint32_t DECOMPOSED[] = {"]
    for i in range(0, len(pool), 10):
        lines.append("\t\t" + ", ".join(f"0x{point:05X}" for point in pool[i:i + 10]) + ",")
    lines.append("\t};")
    return "\n".join(lines), len(entries), len(pool)


def composition_table(decompositions, excluded):
    pairs = sorted((parts[0], parts[1], point) for point, (canonical, parts) in decompositions.items()
                   if canonical and len(parts) == 2 and point not in excluded)
    lines = ["\t// Each pair of code points that composes canonically, ascending, and what they compose into",
             "\tinline constexpr Composition COMPOSITIONS[] = {"]
    row = []
    for first, second, composed in pairs:
        row.append(f"{{ 0x{first:05X}, 0x{second:05X}, 0x{composed:05X} }}")
        if len(row) == 4:
            lines.append("\t\t" + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("\t\t" + ", ".join(row) + ",")
    lines.append("\t};")
    return "\n".join(lines), len(pairs)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = os.path.join(sys.argv[1], "DerivedCoreProperties.txt")
    with open(path, encoding="utf-8") as file:
        match = re.search(r"DerivedCoreProperties-(\d+\.\d+\.\d+)", file.readline())
    version = match.group(1) if match else "unknown"

    sets = {"XID_Start": set(), "XID_Continue": set(), "Default_Ignorable_Code_Point": set()}
    for first, last, name in properties(path):
        if name in sets:
            sets[name].update(range(first, last + 1))
    ignorable = sets["Default_Ignorable_Code_Point"]
    start = runs(sorted(sets["XID_Start"] - ignorable))
    rest = runs(sorted(sets["XID_Continue"] - ignorable))

    classes, decompositions = unicode_data(os.path.join(sys.argv[1], "UnicodeData.txt"))
    excluded = set()
    for first, last, name in properties(os.path.join(sys.argv[1], "DerivedNormalizationProps.txt")):
        if name == "Full_Composition_Exclusion":
            excluded.update(range(first, last + 1))
    combining, class_runs = class_table(classes)
    decomposed, decomposition_count, pool_size = decomposition_tables(
        sorted(sets["XID_Continue"] - ignorable), decompositions)
    composing, pair_count = composition_table(decompositions, excluded)

    here = os.path.dirname(os.path.abspath(__file__))
    output = os.path.join(here, "..", "..", "..", "apps", "compiler", "src", "lexer", "identifier_tables.h")
    text = "\n".join([
        "#pragma once",
        "",
        f"// Generated by std/unicode/_generator/generate_identifiers.py from the Unicode Character Database {version};",
        "// don't edit.",
        "",
        "#include <cstdint>",
        "",
        "namespace hemera::lexer {",
        "",
        "\t// A run of code points, first to last, both included",
        "\tstruct CodePointRange {",
        "\t\tuint32_t first;",
        "\t\tuint32_t last;",
        "\t};",
        "",
        "\tstruct CombiningClassRange {",
        "\t\tuint32_t first;",
        "\t\tuint32_t last;",
        "\t\tuint8_t combining_class;",
        "\t};",
        "",
        "\tstruct Decomposition {",
        "\t\tuint32_t code_point;",
        "\t\tuint16_t start;",
        "\t\tuint8_t length;",
        "\t};",
        "",
        "\tstruct Composition {",
        "\t\tuint32_t first;",
        "\t\tuint32_t second;",
        "\t\tuint32_t composed;",
        "\t};",
        "",
        f"\tinline constexpr const char* IDENTIFIER_UNICODE_VERSION = \"{version}\";",
        "",
        table("IDENTIFIER_START", "What a name can start with: XID_Start, but default ignorables", start),
        "",
        table("IDENTIFIER_CONTINUE", "What else a name can have: XID_Continue, but default ignorables", rest),
        "",
        combining,
        "",
        decomposed,
        "",
        composing,
        "}",
        "",
    ])
    with open(output, "w", encoding="utf-8", newline="\n") as file:
        file.write(text)
    print(f"{len(start)} start runs, {len(rest)} continue runs, {class_runs} combining class runs, "
          f"{decomposition_count} decompositions of {pool_size} code points, {pair_count} compositions, Unicode {version}")


if __name__ == "__main__":
    main()
