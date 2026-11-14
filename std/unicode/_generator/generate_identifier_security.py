"""
Writes the compiler's tables for UTS #39's checks of names, apps/compiler/src/lexer/identifier_security_tables.h,
from the Unicode Character Database and its security data.

    python generate_identifier_security.py <ucd folder>

The folder holds, from https://www.unicode.org/Public/<version>/ucd/: DerivedCoreProperties.txt, UnicodeData.txt,
Scripts.txt, ScriptExtensions.txt and PropertyValueAliases.txt, of the version the rest of std/unicode is generated
from; and from https://www.unicode.org/Public/security/<version>/: confusables.txt and IdentifierStatus.txt, of that
version or, where there's none, the next.

Only code points a name can have (XID_Continue, not default ignorable), and those their decompositions hold, are in the
tables (docs/formatting.md, Identifiers):

- every script, as its code and its name, by index;
- each run of code points with the same scripts (Script_Extensions, or Script where it has none) and where those start
  among SCRIPT_SETS; Common and Inherited code points, which go with any script, have none;
- each run of code points UTS #39 allows in identifiers (Identifier_Status Allowed);
- each code point's prototype, which it's confusable with (confusables.txt), as where it starts among PROTOTYPES.
"""

import os
import re
import sys


def lines_of(path):
    """Each line's fields, split at ';', without its comment; blank lines left out."""
    with open(path, encoding="utf-8") as file:
        for line in file:
            line = line.split("#", 1)[0].strip()
            if line:
                yield [field.strip() for field in line.split(";")]


def points_of(field):
    bounds = field.split("..")
    return range(int(bounds[0], 16), int(bounds[-1], 16) + 1)


def version_of(path, name):
    with open(path, encoding="utf-8") as file:
        match = re.search(name + r"-(\d+\.\d+\.\d+)", file.readline())
    return match.group(1) if match else "unknown"


def rows(entries, per_row):
    lines = []
    for i in range(0, len(entries), per_row):
        lines.append("\t\t" + ", ".join(entries[i:i + per_row]) + ",")
    return lines


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ucd = sys.argv[1]

    # The code points a name can have, and what their decompositions hold
    sets = {"XID_Continue": set(), "Default_Ignorable_Code_Point": set()}
    for fields in lines_of(os.path.join(ucd, "DerivedCoreProperties.txt")):
        if fields[1] in sets:
            sets[fields[1]].update(points_of(fields[0]))
    names = sets["XID_Continue"] - sets["Default_Ignorable_Code_Point"]
    decompositions = {}
    for fields in lines_of(os.path.join(ucd, "UnicodeData.txt")):
        if fields[5]:
            parts = fields[5].split()
            decompositions[int(fields[0], 16)] = [int(part, 16) for part in parts if not part.startswith("<")]

    def decomposed(point):
        if point not in decompositions:
            return [point]
        return [part for inner in decompositions[point] for part in decomposed(inner)]

    covered = set(names)
    for point in names:
        covered.update(decomposed(point))

    # Scripts, by index: every one PropertyValueAliases.txt names
    codes = []
    long_names = {}
    for fields in lines_of(os.path.join(ucd, "PropertyValueAliases.txt")):
        if fields[0] == "sc":
            codes.append(fields[1])
            long_names[fields[1]] = fields[2]
    index_of_code = {code: i for i, code in enumerate(codes)}
    index_of_name = {long_names[code]: index_of_code[code] for code in codes}
    for code in ("Zyyy", "Zinh", "Latn", "Hani", "Hira", "Kana", "Bopo", "Hang"):
        assert code in index_of_code, code
    any_script = {index_of_code["Zyyy"], index_of_code["Zinh"]}

    scripts = {}
    for fields in lines_of(os.path.join(ucd, "Scripts.txt")):
        for point in points_of(fields[0]):
            scripts[point] = (index_of_name[fields[1]],)
    for fields in lines_of(os.path.join(ucd, "ScriptExtensions.txt")):
        for point in points_of(fields[0]):
            scripts[point] = tuple(index_of_code[code] for code in fields[1].split())

    def scripts_of(point):
        found = scripts.get(point, (index_of_code["Zzzz"],))
        return () if set(found) <= any_script else found

    pool = []
    set_start = {}
    script_runs = []
    for point in sorted(covered):
        found = scripts_of(point)
        if found not in set_start:
            set_start[found] = len(pool)
            pool.extend(found)
        if script_runs and script_runs[-1][1] == point - 1 and script_runs[-1][2] == found:
            script_runs[-1] = (script_runs[-1][0], point, found)
        else:
            script_runs.append((point, point, found))

    allowed = set()
    for fields in lines_of(os.path.join(ucd, "IdentifierStatus.txt")):
        if fields[1] == "Allowed":
            allowed.update(points_of(fields[0]))
    allowed_runs = []
    for point in sorted(allowed & covered):
        if allowed_runs and allowed_runs[-1][1] == point - 1:
            allowed_runs[-1] = (allowed_runs[-1][0], point)
        else:
            allowed_runs.append((point, point))

    prototypes = []
    prototype_pool = []
    for fields in lines_of(os.path.join(ucd, "confusables.txt")):
        source = int(fields[0], 16)
        if source in covered:
            target = [int(part, 16) for part in fields[1].split()]
            prototypes.append((source, len(prototype_pool), len(target)))
            prototype_pool.extend(target)
    prototypes.sort()

    version = version_of(os.path.join(ucd, "Scripts.txt"), "Scripts")
    security_version = version_of(os.path.join(ucd, "confusables.txt"), "confusables")
    with open(os.path.join(ucd, "confusables.txt"), encoding="utf-8") as file:
        for line in file:
            match = re.match(r"# Version: (\d+\.\d+\.\d+)", line)
            if match:
                security_version = match.group(1)
                break

    lines = [
        "#pragma once",
        "",
        "// Generated by std/unicode/_generator/generate_identifier_security.py from the Unicode Character Database "
        f"{version}",
        f"// and its security data {security_version}; don't edit.",
        "",
        "#include <cstdint>",
        "",
        "namespace hemera::lexer {",
        "",
        "\tstruct ScriptRun {",
        "\t\tuint32_t first;",
        "\t\tuint32_t last;",
        "\t\t// Where its scripts start among SCRIPT_SETS, and how many; none for Common and Inherited",
        "\t\tuint16_t start;",
        "\t\tuint8_t count;",
        "\t};",
        "",
        "\tstruct AllowedRun {",
        "\t\tuint32_t first;",
        "\t\tuint32_t last;",
        "\t};",
        "",
        "\tstruct Prototype {",
        "\t\tuint32_t code_point;",
        "\t\tuint16_t start;",
        "\t\tuint8_t length;",
        "\t};",
        "",
        f"\tinline constexpr const char* SECURITY_DATA_VERSION = \"{security_version}\";",
        "",
        "\t// Each script's ISO 15924 code, by index",
        "\tinline constexpr const char* SCRIPT_CODES[] = {",
        *rows([f'"{code}"' for code in codes], 12),
        "\t};",
        "",
        "\t// Each script's name, by index",
        "\tinline constexpr const char* SCRIPT_NAMES[] = {",
        *rows([f'"{long_names[code].replace("_", " ")}"' for code in codes], 6),
        "\t};",
        "",
        "\t// The scripts of each run, one after another, by index",
        "\tinline constexpr uint8_t SCRIPT_SETS[] = {",
        *rows([str(index) for index in pool], 20),
        "\t};",
        "",
        "\t// Each run of code points a name can have with the same scripts, ascending",
        "\tinline constexpr ScriptRun SCRIPT_RUNS[] = {",
        *rows([f"{{ 0x{first:05X}, 0x{last:05X}, {set_start[found]}, {len(found)} }}"
               for first, last, found in script_runs], 5),
        "\t};",
        "",
        "\t// Each run of code points UTS #39 allows in identifiers (Identifier_Status Allowed), ascending",
        "\tinline constexpr AllowedRun ALLOWED_RUNS[] = {",
        *rows([f"{{ 0x{first:05X}, 0x{last:05X} }}" for first, last in allowed_runs], 6),
        "\t};",
        "",
        "\t// Each code point's prototype, which it can be mistaken for: where it starts among PROTOTYPE_POINTS, and its length",
        "\tinline constexpr Prototype PROTOTYPES[] = {",
        *rows([f"{{ 0x{source:05X}, {start}, {length} }}" for source, start, length in prototypes], 6),
        "\t};",
        "",
        "\t// The prototypes' code points, one after another",
        "\tinline constexpr uint32_t PROTOTYPE_POINTS[] = {",
        *rows([f"0x{point:05X}" for point in prototype_pool], 10),
        "\t};",
        "}",
        "",
    ]
    here = os.path.dirname(os.path.abspath(__file__))
    output = os.path.join(here, "..", "..", "..", "apps", "compiler", "src", "lexer", "identifier_security_tables.h")
    with open(output, "w", encoding="utf-8", newline="\n") as file:
        file.write("\n".join(lines))
    print(f"{len(codes)} scripts, {len(script_runs)} script runs, {len(pool)} in script sets, {len(allowed_runs)} allowed "
          f"runs, {len(prototypes)} prototypes of {len(prototype_pool)} code points; Unicode {version}, security "
          f"{security_version}")


if __name__ == "__main__":
    main()
