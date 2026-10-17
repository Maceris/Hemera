"""
Cross-compiles hosted test programs for Linux with the compiler built here, copies them to a Linux
machine over SSH and runs them there, checking each one's exit code: 42 if everything it checks
worked, or the number of the first check that failed. Exits 0 if every test passed.

    HEMERA_LINUX_HOST=user@address python apps/compiler/test/linux_tests.py

HEMERA_LINUX_KEY is the SSH key to log in with (default ~/.ssh/hemera_linux_vm), and HEMERA the
compiler (default the Debug build). The programs go in ~/hemera-tests on the Linux machine.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

COMPILER_DIR = Path(__file__).resolve().parent.parent
SCENARIOS = COMPILER_DIR / "test" / "back_end" / "scenarios"

# Scenario folder, and the compiler's extra arguments
TESTS = [
    ("hosted", []),
    ("threads", ["--stack-check=morestack"]),
    ("heap", []),
]


def run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True)


def main() -> int:
    host = os.environ.get("HEMERA_LINUX_HOST")
    if not host:
        print("HEMERA_LINUX_HOST isn't set: user@address of a Linux machine to run the tests on")
        return 2
    key = os.environ.get("HEMERA_LINUX_KEY", str(Path.home() / ".ssh" / "hemera_linux_vm"))
    compiler = os.environ.get("HEMERA", str(COMPILER_DIR / "bin" / "Debug" / "hemera.exe"))
    ssh = ["ssh", "-i", key, "-o", "BatchMode=yes", host]
    if run(ssh + ["mkdir -p ~/hemera-tests"]).returncode != 0:
        print(f"can't reach {host}")
        return 2
    failures = 0
    with tempfile.TemporaryDirectory(prefix="hemera-linux-tests-") as temporary:
        for name, arguments in TESTS:
            output = Path(temporary) / name
            built = run([compiler, "--os=linux", f"--output={output}", *arguments, str(SCENARIOS / name)])
            if built.returncode != 0 or not output.exists():
                print(f"FAILED: {name} doesn't build\n{built.stdout}{built.stderr}")
                failures += 1
                continue
            copied = run(["scp", "-q", "-i", key, str(output), f"{host}:hemera-tests/{name}"])
            if copied.returncode != 0:
                print(f"FAILED: {name} couldn't be copied\n{copied.stderr}")
                failures += 1
                continue
            ran = run(ssh + [f"chmod +x ~/hemera-tests/{name} && timeout 120 ~/hemera-tests/{name}"])
            if ran.returncode == 42:
                print(f"passed: {name}")
            else:
                print(f"FAILED: {name} exited with {ran.returncode}\n{ran.stdout}{ran.stderr}")
                failures += 1
    print(f"{len(TESTS) - failures} of {len(TESTS)} passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
