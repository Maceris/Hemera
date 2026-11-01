"""
Checks the generated structs against vulkan_core.h: every struct's size, alignment and field offsets, as C lays them
out and as Hemera does.

    python check_layouts.py [path/to/hemera] [path/to/clang]

It writes a C program and a Hemera program that print the same layouts, builds and runs both, and compares what
they print. Needs the Vulkan SDK (VULKAN_SDK, or C:/VulkanSDK/*) for the header, and clang.
"""

import glob
import os
import shutil
import subprocess
import sys
import tempfile

from generate import Declaration, Generator, field_name, find_registry, for_vulkan

HERE = os.path.dirname(os.path.abspath(__file__))
REPOSITORY = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def structs(generator):
    """Each struct and union the bindings have, with its fields' C names and Hemera names, bitfields left out."""
    for name in sorted(generator.required_types):
        t = generator.types.get(name)
        if not generator.wanted(name) or generator.category(name) not in ("struct", "union") or t.get("alias"):
            continue
        members = [Declaration(m) for m in t.findall("member") if for_vulkan(m)]
        yield name, [(m.name, field_name(m.name)) for m in members if m.bits is None]


def c_program(generator):
    lines = ["#include <stdio.h>", "#include <stddef.h>", "#include <vulkan/vulkan_core.h>", "", "int main(void) {"]
    for name, members in structs(generator):
        lines.append(f'    printf("%s %zu %zu\\n", "{name}", sizeof({name}), _Alignof({name}));')
        for c_name, _ in members:
            lines.append(f'    printf("  %s %zu\\n", "{c_name}", offsetof({name}, {c_name}));')
    lines += ["    return 0;", "}"]
    return "\n".join(lines) + "\n"


def hemera_program(generator):
    lines = [
        "package layouts",
        "",
        "import compiler from \"base\"",
        "import io",
        "import vulkan as vk from \"vendor\"",
        "",
        "layout :: fn(info: ptr[compiler.TypeInfo], fields: string[]) {",
        "    s :: cast[ptr[compiler.TypeInfoStruct]](info)",
        "    printf(\"% % %\\n\", s.name, s.size, s.alignment)",
        "    for field in fields {",
        "        for member in s.members {",
        "            if member.name == field {",
        "                printf(\"  % %\\n\", field, member.offset)",
        "            }",
        "        }",
        "    }",
        "}",
        "",
        "main :: fn() {",
    ]
    for name, members in structs(generator):
        fields = ", ".join(f'"{hemera_name}"' for _, hemera_name in members)
        lines.append(f"    layout(type_info_of(vk.{name}), string.[{fields}])")
    lines.append("}")
    return "\n".join(lines) + "\n"


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        sys.exit(f"{' '.join(command)} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    hemera = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPOSITORY, "apps", "compiler", "bin", "Release", "hemera.exe")
    clang = sys.argv[2] if len(sys.argv) > 2 else shutil.which("clang") or "clang"
    registry = find_registry()
    sdk = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(registry))))
    generator = Generator(registry)
    generator.gather()

    folder = tempfile.mkdtemp(prefix="vulkan_layouts_")
    with open(os.path.join(folder, "layouts.c"), "w") as f:
        f.write(c_program(generator))
    hemera_folder = os.path.join(folder, "layouts")
    os.makedirs(hemera_folder)
    with open(os.path.join(hemera_folder, "layouts.hsc"), "w", newline="\n") as f:
        f.write(hemera_program(generator))

    c_exe = os.path.join(folder, "layouts_c.exe")
    run([clang, "-I", os.path.join(sdk, "Include"), "-I", os.path.join(sdk, "include"), os.path.join(folder, "layouts.c"), "-o", c_exe])
    run([hemera, "--output=" + os.path.join(folder, "layouts_hemera"), hemera_folder])
    expected = run([c_exe]).splitlines()
    actual = run([os.path.join(folder, "layouts_hemera.exe")]).splitlines()

    differences = 0
    struct = None
    for want, got in zip(expected, actual):
        if not want.startswith(" "):
            struct = want.split()[0]
        if want.split() != [got.split()[0].rstrip("_")] + got.split()[1:] if got else True:
            differences += 1
            if differences <= 40:
                print(f"{struct}: C has '{want.strip()}', Hemera '{got.strip()}'")
    if len(expected) != len(actual):
        print(f"C printed {len(expected)} lines, Hemera {len(actual)}")
        differences += 1
    count = sum(1 for _ in structs(generator))
    print(f"{count} structs and unions: {'all match' if differences == 0 else f'{differences} differences'} ({folder})")
    sys.exit(1 if differences else 0)


if __name__ == "__main__":
    main()
