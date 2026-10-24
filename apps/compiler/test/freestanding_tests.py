"""
Builds freestanding test programs with the compiler built here and boots them in QEMU, checking each
one's exit code: 42 if everything it checks worked, or the number of the first check that failed. They end
QEMU through semihosting, and write what they've reached to the serial port, which is checked too. Exits 0
if every test passed.

    python apps/compiler/test/freestanding_tests.py

HEMERA is the compiler (default the Release build if there is one, otherwise Debug), and
QEMU_AARCH64 qemu-system-aarch64 (default C:/Program Files/qemu/qemu-system-aarch64.exe).

The AArch64 program runs on QEMU's virt machine, which starts it at EL1 with the MMU off: QEMU loads its
ELF, and its generic loader starts the CPU at the image's first instructions, which the linker script
writes, since the compiler makes the linker start at kernel_entry instead. Every function in base and std
is also generated for the same target, so what can't be generated for it shows up before anything uses it.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

COMPILER_DIR = Path(__file__).resolve().parent.parent
SCENARIOS = COMPILER_DIR / "test" / "back_end" / "scenarios"

# A kernel's target: no startup code, stack checks that trap, no floating point or SIMD (which trap until
# CPACR_EL1 enables them), and aligned accesses, since memory is Device memory until the MMU is on
AARCH64_KERNEL = ["--arch=aarch64", "--os=unknown", "--no-startup-code", "--entry=kernel_entry", "--stack-check=trap",
                  "--cpu-features=-fp-armv8,-neon,+strict-align"]

# What freestanding_aarch64 writes on the way
AARCH64_OUTPUT = ["booted", "mmu on", "breakpoint", "user mode", "done"]


def run(command: list[str], timeout: int | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def main() -> int:
    release = COMPILER_DIR / "bin" / "Release" / "hemera.exe"
    compiler = os.environ.get("HEMERA", str(release if release.exists() else COMPILER_DIR / "bin" / "Debug" / "hemera.exe"))
    qemu = os.environ.get("QEMU_AARCH64", "C:/Program Files/qemu/qemu-system-aarch64.exe")
    scenario = SCENARIOS / "freestanding_aarch64"
    linker_script = f"--linker-script={scenario / 'linker.ld'}"
    failures = 0
    with tempfile.TemporaryDirectory(prefix="hemera-freestanding-tests-") as temporary:
        # Everything generates
        everything = Path(temporary) / "everything.elf"
        built = run([compiler, *AARCH64_KERNEL, linker_script, "--generate-all", f"--output={everything}", str(scenario)])
        if built.returncode != 0:
            print(f"FAILED: everything_aarch64 doesn't build\n{built.stdout}{built.stderr}")
            failures += 1
        else:
            print("passed: everything_aarch64")

        kernel = Path(temporary) / "kernel.elf"
        built = run([compiler, *AARCH64_KERNEL, linker_script, f"--output={kernel}", str(scenario)])
        if built.returncode != 0 or not kernel.exists():
            print(f"FAILED: freestanding_aarch64 doesn't build\n{built.stdout}{built.stderr}")
            return 1
        try:
            ran = run([qemu, "-M", "virt", "-cpu", "max", "-m", "128M", "-nographic", "-semihosting",
                       "-device", f"loader,file={kernel}", "-device", "loader,addr=0x40200000,cpu-num=0"], timeout=60)
        except subprocess.TimeoutExpired:
            print("FAILED: freestanding_aarch64 didn't finish in 60 seconds")
            return 1
        written = [line.strip() for line in ran.stdout.splitlines() if line.strip()]
        problems = []
        if ran.returncode != 42:
            problems.append(f"exited with {ran.returncode}")
        if written != AARCH64_OUTPUT:
            problems.append(f"wrote {written}")
        if problems:
            print(f"FAILED: freestanding_aarch64 {', '.join(problems)}\n{ran.stdout}{ran.stderr}")
            failures += 1
        else:
            print("passed: freestanding_aarch64")
    print(f"{2 - failures} of 2 passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
