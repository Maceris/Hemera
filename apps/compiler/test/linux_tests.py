"""
Cross-compiles hosted test programs for Linux with the compiler built here, copies them to a Linux
machine over SSH and runs them there, checking each one's exit code: 42 if everything it checks
worked, or the number of the first check that failed. A scenario with output.txt or error.txt is
also checked for writing exactly that to standard output or error. Exits 0 if every test passed.

    HEMERA_LINUX_HOST=user@address python apps/compiler/test/linux_tests.py

HEMERA_LINUX_KEY is the SSH key to log in with (default ~/.ssh/hemera_linux_vm), HEMERA the
compiler (default the Release build if there is one, otherwise Debug), and HEMERA_LINUX_SYSROOT a folder with the Linux machine's
libc.so (a copy of libc.so.6), libm.so and ld-linux-x86-64.so.2, for the tests that link C. The
programs go in ~/hemera-tests on the Linux machine.

HEMERA_LINUX_ARCH=aarch64 builds them for AArch64 instead, run on an x86-64 Linux machine through
user-mode QEMU (qemu-user-static and binfmt), with the C library from QEMU_LD_PREFIX
(/usr/aarch64-linux-gnu, libc6-arm64-cross) and HEMERA_LINUX_SYSROOT_AARCH64 for linking it. They go in
~/hemera-tests-aarch64, and the Valgrind tests are left out. HEMERA_LINUX_TESTS, names separated by
commas, runs only those.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

COMPILER_DIR = Path(__file__).resolve().parent.parent
SCENARIOS = COMPILER_DIR / "test" / "back_end" / "scenarios"

# Scenario folder, the compiler's extra arguments, and the exit code expected
TESTS = [
    ("hosted", [], 42),
    ("threads", ["--test", "--stack-check=morestack"], 0),
    ("heap", ["--test"], 0),
    ("containers", ["--test"], 0),
    ("maps", ["--test"], 0),
    ("code_values", ["--test"], 0),
    ("inserted_code", ["--test"], 0),
    ("macros", ["--test"], 0),
    ("expression_forms", ["--test"], 0),
    ("inserted_member_names", ["--test"], 0),
    ("mutability", ["--test"], 0),
    ("inserted_declarations", ["--test"], 0),
    ("generated_functions", ["--test"], 0),
    ("format", ["--test"], 0),
    ("using_fields", ["--test"], 0),
    ("mut_arguments", ["--test"], 0),
    ("owned", ["--test"], 0),
    ("shared", ["--test"], 0),
    ("arena", ["--test"], 0),
    ("new_defaults", ["--test"], 0),
    ("optional_functions", ["--test"], 0),
    ("large_values", ["--test", "--stack-check=morestack"], 0),
    ("integer_ranges", ["--test"], 0),
    ("vectors", ["--test"], 0),
    ("memory_functions", ["--test"], 0),
    ("reverse_loops", ["--test"], 0),
    ("secrets", ["--test"], 0),
    ("hashes", ["--test"], 0),
    ("aead", ["--test"], 0),
    ("ml_kem", ["--test"], 0),
    ("curves", ["--test"], 0),
    ("argon2", ["--test"], 0),
    ("wycheproof", ["--test"], 0),
    ("wycheproof_tls", ["--test"], 0),
    ("x509", ["--test"], 0),
    # Under Valgrind's Memcheck, which reports anything that depends on a secret (docs/memory.md)
    ("ctgrind", ["--valgrind-secrets"], 42),
    # And a secret leaked past the compiler, which it must report: --error-exitcode
    ("ctgrind_leak", ["--valgrind-secrets"], 99),
    ("processes", [], 42),
    ("output", [], 42),
    ("library", [], 42),
    ("arrays", ["--test"], 0),
    # Every function in base and std, used or not
    ("everything", ["--generate-all"], 42),
    ("files", [], 42),
    ("system", ["--test"], 0),
    ("constraints", ["--test"], 0),
    # Floats in parts, f16 among them, which AArch64 computes natively
    ("composites", ["--test"], 0),
    # runtime.ASSERTION_EXIT_CODE
    ("assertion", [], 134),
    # The same with debug info, its frames named and symbolized from its DWARF
    ("assertion_debug", ["--debug"], 134),
    # Compute blocks, what a function gives back pointers from, ?.member, secrets in optionals and results, generic
    # types inserting code and declared in functions, #union constants, and C strings within a limit
    ("compute_blocks", ["--test"], 0),
    ("returns_from_heap", ["--test"], 0),
    ("unwrap_member", ["--test"], 0),
    ("secret_holders", ["--test"], 0),
    ("generic_type_insertions", ["--test"], 0),
    ("local_generic_types", ["--test"], 0),
    ("union_constants", ["--test"], 0),
    ("c_strings", ["--test"], 0),
    ("schemas", ["--test"], 0),
    ("in_image", ["--test"], 0),
    # The float functions, by instructions on both architectures
    ("float_intrinsics", ["--test"], 0),
    # std/math against its references, the same bits on every architecture
    ("float_math", ["--test"], 0),
    # Arrays as vectors, element by element on each architecture's own instructions
    ("array_arithmetic", ["--test"], 0),
    ("matrices", ["--test"], 0),
    ("linear_algebra", ["--test"], 0),
    # The network protocol's policies, plain code on every OS
    ("network_policy", ["--test"], 0),
    ("tls", ["--test"], 0),
    ("ntp", ["--test"], 0),
    ("ssh", ["--test"], 0),
    # Instances of a generic whose parameter is an optional of a generic alias, each with its own
    ("generic_alias_arguments", ["--test"], 0),
    # #test(CASES), each case a test of its own
    ("test_cases", [], 42),
    # #tags and property tests, shrinking included
    ("property_tests", [], 42),
    # Fuzz targets run as property tests, then fuzzed with coverage from a fixed seed, which finds the magic bytes
    ("fuzz_targets", [], 42),
    ("fuzz_magic", ["--fuzz=finds_the_magic", "--fuzz-seed=1", "--fuzz-runs=2000000", "--fuzz-folder=fuzz_magic_inputs"], 1),
    # Links C, against HEMERA_LINUX_SYSROOT
    ("libc", ["--test", "--stack-check=morestack", "SYSROOT"], 0),
]

# How a test is run, in its folder on the Linux machine, where it isn't just the program: its
# environment and arguments (see each scenario)
RUN_WITH = {
    "files": ("HEMERA_FILES_TEST='h\u00e9llo'", "alpha 'two words' ''"),
}

# Tests run under Valgrind's Memcheck, when the Linux machine has it, failing on any error it reports
UNDER_VALGRIND = {"ctgrind", "ctgrind_leak"}
VALGRIND = "valgrind -q --error-exitcode=99 --track-origins=yes"

# A test that builds another's scenario, with different arguments
SCENARIO_OF = {
    "assertion_debug": "assertion",
    "fuzz_magic": "fuzz_targets",
}

# What hemera --symbolize says about assertion_debug's first frame: assert inlined into check, into main
SYMBOLIZED = [
    "runtime.assert at <base>/runtime/assertion.hsc:",
    "assertion.check at ",
    "assertion.hsc:10:",
    "assertion.main at ",
]

# What a failed assertion's report starts with, on standard error
ASSERTION_REPORT = "assertion failed: count must be positive\n    at "


def run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True)


def openssh_interop(compiler: str, aarch64: bool, temporary: Path, ssh: list[str], key: str, host: str, folder: str) -> str:
    """
    std/ssh against OpenSSH's ssh, sshd and ssh-keygen on the Linux machine, which needs them and sshpass: the
    ssh_openssh scenario's program, run by its interop.sh as a server for ssh and a client of sshd -i, under each
    exchange and cipher, with keys each side wrote. What went wrong, or "" if nothing did.
    """
    scenario = SCENARIOS / "ssh_openssh"
    program = temporary / "ssh_openssh"
    architecture = ["--arch=aarch64"] if aarch64 else []
    built = run([compiler, "--os=linux", *architecture, f"--output={program}", str(scenario)])
    if built.returncode != 0 or not program.exists():
        return f"doesn't build\n{built.stdout}{built.stderr}"
    for file in (program, scenario / "interop.sh"):
        if run(["scp", "-q", "-i", key, str(file), f"{host}:{folder}/{file.name}"]).returncode != 0:
            return f"couldn't copy {file.name}"
    prefix = "QEMU_LD_PREFIX=/usr/aarch64-linux-gnu " if aarch64 else ""
    ran = run(ssh + [f"cd ~/{folder} && chmod +x ssh_openssh interop.sh && {prefix}timeout 600 ./interop.sh"])
    if ran.returncode != 42:
        return f"exited with {ran.returncode}\n{ran.stdout}{ran.stderr}"
    return ""


def typed_libraries(compiler: str, aarch64: bool, temporary: Path, ssh: list[str], key: str, host: str, folder: str) -> str:
    """
    docs/compilation.md, Typed Libraries: a library and a program calling it, built by a build package, which loads it
    with base's own ELF loader and calls through it; then the library built again with add's type changed, which the
    program refuses, naming add. What went wrong, or "" if nothing did.
    """
    scenario = SCENARIOS / "typed_libraries"
    library = temporary / "maths"
    program = temporary / "typed_program"
    architecture = ["--arch=aarch64"] if aarch64 else []
    built = run([compiler, "--os=linux", *architecture, f"--setting=library={library.as_posix()},program={program.as_posix()}",
                 str(scenario / "build")])
    if built.returncode != 0 or not library.exists() or not program.exists():
        return f"doesn't build\n{built.stdout}{built.stderr}"
    prefix = "QEMU_LD_PREFIX=/usr/aarch64-linux-gnu " if aarch64 else ""
    for file in (library, program):
        if run(["scp", "-q", "-i", key, str(file), f"{host}:{folder}/{file.name}"]).returncode != 0:
            return f"couldn't copy {file.name}"
    ran = run(ssh + [f"chmod +x ~/{folder}/typed_program && cd ~/{folder} && {prefix}timeout 120 ./typed_program"])
    if ran.returncode != 42:
        return f"exited with {ran.returncode}\n{ran.stdout}{ran.stderr}"
    changed = run([compiler, "--os=linux", *architecture, f"--setting=library={library.as_posix()}", str(scenario / "build_changed")])
    if changed.returncode != 0:
        return f"the changed library doesn't build\n{changed.stdout}{changed.stderr}"
    if run(["scp", "-q", "-i", key, str(library), f"{host}:{folder}/maths"]).returncode != 0:
        return "couldn't copy the changed library"
    refused = run(ssh + [f"cd ~/{folder} && {prefix}timeout 120 ./typed_program"])
    if refused.returncode != 1 or "can't bind add from the library maths: it exports it with another type" not in refused.stderr:
        return f"took the changed library: exited with {refused.returncode}\n{refused.stdout}{refused.stderr}"
    return ""


def main() -> int:
    host = os.environ.get("HEMERA_LINUX_HOST")
    if not host:
        print("HEMERA_LINUX_HOST isn't set: user@address of a Linux machine to run the tests on")
        return 2
    key = os.environ.get("HEMERA_LINUX_KEY", str(Path.home() / ".ssh" / "hemera_linux_vm"))
    release = COMPILER_DIR / "bin" / "Release" / "hemera.exe"
    compiler = os.environ.get("HEMERA", str(release if release.exists() else COMPILER_DIR / "bin" / "Debug" / "hemera.exe"))
    architecture = os.environ.get("HEMERA_LINUX_ARCH", "x86_64")
    aarch64 = architecture == "aarch64"
    if aarch64:
        sysroot = os.environ.get("HEMERA_LINUX_SYSROOT_AARCH64", "D:/Programs/System Tools/linux-sysroot-aarch64")
    else:
        sysroot = os.environ.get("HEMERA_LINUX_SYSROOT", "D:/Programs/System Tools/linux-sysroot")
    folder = "hemera-tests-aarch64" if aarch64 else "hemera-tests"
    only = [name for name in os.environ.get("HEMERA_LINUX_TESTS", "").split(",") if name]
    tests = [test for test in TESTS if (not only or test[0] in only) and not (aarch64 and test[0] in UNDER_VALGRIND)]
    ssh = ["ssh", "-i", key, "-o", "BatchMode=yes", host]
    if run(ssh + [f"mkdir -p ~/{folder}"]).returncode != 0:
        print(f"can't reach {host}")
        return 2
    failures = 0
    with tempfile.TemporaryDirectory(prefix="hemera-linux-tests-") as temporary:
        for name, arguments, exit_code in tests:
            output = Path(temporary) / name
            arguments = [f"--sysroot={sysroot}" if argument == "SYSROOT" else argument for argument in arguments]
            if aarch64:
                arguments = ["--arch=aarch64", *arguments]
            scenario = SCENARIOS / SCENARIO_OF.get(name, name)
            built = run([compiler, "--os=linux", f"--output={output}", *arguments, str(scenario)])
            if built.returncode != 0 or not output.exists():
                print(f"FAILED: {name} doesn't build\n{built.stdout}{built.stderr}")
                failures += 1
                continue
            copied = run(["scp", "-q", "-i", key, str(output), f"{host}:{folder}/{name}"])
            if copied.returncode != 0:
                print(f"FAILED: {name} couldn't be copied\n{copied.stderr}")
                failures += 1
                continue
            environment, program_arguments = RUN_WITH.get(name, ("", ""))
            if aarch64:
                environment = f"QEMU_LD_PREFIX=/usr/aarch64-linux-gnu {environment}"
            launch = f"timeout 120 ./{name}"
            if name in UNDER_VALGRIND:
                launch = (f"if command -v valgrind > /dev/null; then timeout 1200 {VALGRIND} ./{name}; "
                          f"else echo 'valgrind not installed' >&2; exit {exit_code}; fi")
            ran = run(ssh + [f"chmod +x ~/{folder}/{name} && cd ~/{folder} && "
                             f"{environment} {launch} {program_arguments}"])
            problems = []
            if ran.returncode != exit_code:
                problems.append(f"exited with {ran.returncode}")
            for stream, written in (("output.txt", ran.stdout), ("error.txt", ran.stderr)):
                expected = scenario / stream
                if expected.exists() and written != expected.read_text(encoding="utf-8"):
                    problems.append(f"wrote {written!r} rather than {stream}")
            if name.startswith("assertion") and not ran.stderr.startswith(ASSERTION_REPORT):
                problems.append(f"reported {ran.stderr!r}")
            if name == "assertion_debug":
                offsets = [line.split()[0] for line in ran.stderr.splitlines() if line.startswith("    0x")]
                if "  assertion.main+0x" not in ran.stderr or not offsets:
                    problems.append("didn't name its frames")
                else:
                    symbolized = run([compiler, f"--symbolize={output}", *offsets])
                    missing = [part for part in SYMBOLIZED if part not in symbolized.stdout]
                    if missing:
                        problems.append(f"symbolized without {missing}:\n{symbolized.stdout}")
            if not problems and "valgrind not installed" in ran.stderr:
                print(f"passed: {name}, but not under Valgrind, which isn't installed")
            elif not problems:
                print(f"passed: {name}")
            else:
                print(f"FAILED: {name} {', '.join(problems)}\n{ran.stdout}{ran.stderr}")
                failures += 1
        count = len(tests)
        if not only or "openssh_interop" in only:
            count += 1
            problem = openssh_interop(compiler, aarch64, Path(temporary), ssh, key, host, folder)
            if problem:
                print(f"FAILED: openssh_interop {problem}")
                failures += 1
            else:
                print("passed: openssh_interop")
        if not only or "typed_libraries" in only:
            count += 1
            problem = typed_libraries(compiler, aarch64, Path(temporary), ssh, key, host, folder)
            if problem:
                print(f"FAILED: typed_libraries {problem}")
                failures += 1
            else:
                print("passed: typed_libraries")
    print(f"{count - failures} of {count} passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
