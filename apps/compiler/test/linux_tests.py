"""
Cross-compiles hosted test programs for Linux with the compiler built here, copies them to a Linux
machine over SSH and runs them there, checking each one's exit code: 42 if everything it checks
worked, or the number of the first check that failed. A scenario with output.txt or error.txt is
also checked for writing exactly that to standard output or error. Exits 0 if every test passed.

    HEMERA_LINUX_HOST=user@address python apps/compiler/test/linux_tests.py

HEMERA_LINUX_KEY is the SSH key to log in with (default ~/.ssh/hemera_linux_vm), HEMERA the
compiler (default the Debug build), and HEMERA_LINUX_SYSROOT a folder with the Linux machine's
libc.so (a copy of libc.so.6), libm.so and ld-linux-x86-64.so.2, for the tests that link C. The
programs go in ~/hemera-tests on the Linux machine.
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
    ("threads", ["--stack-check=morestack"], 42),
    ("heap", [], 42),
    ("containers", [], 42),
    ("maps", [], 42),
    ("format", [], 42),
    ("using_fields", [], 42),
    ("mut_arguments", [], 42),
    ("output", [], 42),
    ("library", [], 42),
    ("arrays", [], 42),
    # Every function in base and std, used or not
    ("everything", ["--generate-all"], 42),
    ("files", [], 42),
    ("system", [], 42),
    ("constraints", [], 42),
    # runtime.ASSERTION_EXIT_CODE
    ("assertion", [], 134),
    # The same with debug info, its frames named and symbolized from its DWARF
    ("assertion_debug", ["--debug"], 134),
    # Links C, against HEMERA_LINUX_SYSROOT
    ("libc", ["--stack-check=morestack", "SYSROOT"], 42),
]

# How a test is run, in its folder on the Linux machine, where it isn't just the program: its
# environment and arguments (see each scenario)
RUN_WITH = {
    "files": ("HEMERA_FILES_TEST='h\u00e9llo'", "alpha 'two words' ''"),
}

# A test that builds another's scenario, with different arguments
SCENARIO_OF = {
    "assertion_debug": "assertion",
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


def main() -> int:
    host = os.environ.get("HEMERA_LINUX_HOST")
    if not host:
        print("HEMERA_LINUX_HOST isn't set: user@address of a Linux machine to run the tests on")
        return 2
    key = os.environ.get("HEMERA_LINUX_KEY", str(Path.home() / ".ssh" / "hemera_linux_vm"))
    compiler = os.environ.get("HEMERA", str(COMPILER_DIR / "bin" / "Debug" / "hemera.exe"))
    sysroot = os.environ.get("HEMERA_LINUX_SYSROOT", "D:/Programs/System Tools/linux-sysroot")
    ssh = ["ssh", "-i", key, "-o", "BatchMode=yes", host]
    if run(ssh + ["mkdir -p ~/hemera-tests"]).returncode != 0:
        print(f"can't reach {host}")
        return 2
    failures = 0
    with tempfile.TemporaryDirectory(prefix="hemera-linux-tests-") as temporary:
        for name, arguments, exit_code in TESTS:
            output = Path(temporary) / name
            arguments = [f"--sysroot={sysroot}" if argument == "SYSROOT" else argument for argument in arguments]
            scenario = SCENARIOS / SCENARIO_OF.get(name, name)
            built = run([compiler, "--os=linux", f"--output={output}", *arguments, str(scenario)])
            if built.returncode != 0 or not output.exists():
                print(f"FAILED: {name} doesn't build\n{built.stdout}{built.stderr}")
                failures += 1
                continue
            copied = run(["scp", "-q", "-i", key, str(output), f"{host}:hemera-tests/{name}"])
            if copied.returncode != 0:
                print(f"FAILED: {name} couldn't be copied\n{copied.stderr}")
                failures += 1
                continue
            environment, program_arguments = RUN_WITH.get(name, ("", ""))
            ran = run(ssh + [f"chmod +x ~/hemera-tests/{name} && cd ~/hemera-tests && "
                             f"{environment} timeout 120 ./{name} {program_arguments}"])
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
            if not problems:
                print(f"passed: {name}")
            else:
                print(f"FAILED: {name} {', '.join(problems)}\n{ran.stdout}{ran.stderr}")
                failures += 1
    print(f"{len(TESTS) - failures} of {len(TESTS)} passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
