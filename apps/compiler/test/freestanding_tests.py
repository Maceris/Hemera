"""
Builds freestanding test programs with the compiler built here and boots them in QEMU, checking each
one's exit code: 42 if everything it checks worked, or the number of the first check that failed. They end
QEMU through semihosting, and write what they've reached to the serial port, which is checked too. Exits 0
if every test passed.

    python apps/compiler/test/freestanding_tests.py

HEMERA is the compiler (default the Release build if there is one, otherwise Debug), and QEMU the folder
with qemu-system-aarch64, qemu-system-riscv64 and edk2's firmware in share (default C:/Program Files/qemu).

The AArch64 program runs on QEMU's virt machine, which starts it at EL1 with the MMU off: QEMU loads its
ELF, and its generic loader starts the CPU at the image's first instructions, which the linker script
writes, since the compiler makes the linker start at kernel_entry instead. The RISC-V one runs on virt too,
which OpenSBI starts in supervisor mode at the ELF's entry, the linker script's first instructions again.
For each, every function in base and std is also generated for the same target, so what can't be
generated for it shows up before anything uses it.

The RISC-V UEFI application is made into a PE image by the compiler, and edk2 runs it from a FAT drive, as
EFI/BOOT/BOOTRISCV64.EFI; it writes to the firmware's console and turns the machine off.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

COMPILER_DIR = Path(__file__).resolve().parent.parent
# Where the windows preset (CMakePresets.json) puts the compiler, in a folder per configuration
BUILT = COMPILER_DIR.parent.parent / "build" / "windows" / "bin"
SCENARIOS = COMPILER_DIR / "test" / "back_end" / "scenarios"

# A kernel's target: no startup code, stack checks that trap, no floating point or SIMD (which trap until
# CPACR_EL1 enables them), and aligned accesses, since memory is Device memory until the MMU is on
AARCH64_KERNEL = ["--arch=aarch64", "--os=unknown", "--no-startup-code", "--entry=kernel_entry", "--stack-check=trap",
                  "--cpu-features=-fp-armv8,-neon,+strict-align"]

# The same for RISC-V: no floating point or vectors (which trap until sstatus enables them), and code that
# reaches what it addresses relative to itself, since it runs at 0x80200000, out of reach of absolute addresses
RISCV64_KERNEL = ["--arch=riscv64", "--os=unknown", "--no-startup-code", "--entry=kernel_entry", "--stack-check=trap",
                  "--relocation-model=static", "--code-model=medium", "--cpu-features=-f,-d,-zve32x,-zvl32b"]

# What each kernel writes on the way, after the firmware's own output
AARCH64_OUTPUT = ["booted", "mmu on", "breakpoint", "user mode", "done"]
RISCV64_OUTPUT = ["booted", "paging on", "breakpoint", "user mode", "done"]

# What the UEFI application writes, among the firmware's own messages
UEFI_RISCV64_OUTPUT = ["uefi started", "image base found"]


def run(command: list[str], timeout: int | None = None, cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout, cwd=cwd, errors="replace")


def written_from(output: str, first: str) -> list[str]:
    """The lines written from the first that is first on, leaving out the firmware's before it."""
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return lines[lines.index(first):] if first in lines else lines


def kernel_test(name: str, compiler: str, target: list[str], machine: list[str], expected: list[str],
                temporary: Path) -> int:
    """Builds the scenario named name for target, everything first, then boots it with machine; the failures."""
    scenario = SCENARIOS / f"freestanding_{name}"
    linker_script = f"--linker-script={scenario / 'linker.ld'}"
    failures = 0
    everything = temporary / f"everything_{name}.elf"
    built = run([compiler, *target, linker_script, "--generate-all", f"--output={everything}", str(scenario)])
    if built.returncode != 0:
        print(f"FAILED: everything_{name} doesn't build\n{built.stdout}{built.stderr}")
        failures += 1
    else:
        print(f"passed: everything_{name}")

    kernel = temporary / f"kernel_{name}.elf"
    built = run([compiler, *target, linker_script, f"--output={kernel}", str(scenario)])
    if built.returncode != 0 or not kernel.exists():
        print(f"FAILED: freestanding_{name} doesn't build\n{built.stdout}{built.stderr}")
        return failures + 1
    try:
        ran = run([part.replace("KERNEL", str(kernel)) for part in machine], timeout=60)
    except subprocess.TimeoutExpired:
        print(f"FAILED: freestanding_{name} didn't finish in 60 seconds")
        return failures + 1
    written = written_from(ran.stdout, expected[0])
    problems = []
    if ran.returncode != 42:
        problems.append(f"exited with {ran.returncode}")
    if written != expected:
        problems.append(f"wrote {written}")
    if problems:
        print(f"FAILED: freestanding_{name} {', '.join(problems)}\n{ran.stdout}{ran.stderr}")
        return failures + 1
    print(f"passed: freestanding_{name}")
    return failures


def uefi_riscv64_test(compiler: str, qemu: Path, temporary: Path) -> int:
    """Builds the RISC-V UEFI application and runs it under edk2; the failures."""
    esp = temporary / "esp"
    (esp / "EFI" / "BOOT").mkdir(parents=True)
    image = esp / "EFI" / "BOOT" / "BOOTRISCV64.EFI"
    built = run([compiler, "--arch=riscv64", "--os=uefi", f"--output={image}", str(SCENARIOS / "uefi_riscv64")])
    if built.returncode != 0 or not image.exists():
        print(f"FAILED: uefi_riscv64 doesn't build\n{built.stdout}{built.stderr}")
        return 1
    # The firmware's variables are written to, so each run has its own copy
    shutil.copyfile(qemu / "share" / "edk2-riscv-vars.fd", temporary / "vars.fd")
    code = (qemu / "share" / "edk2-riscv-code.fd").as_posix()
    try:
        ran = run([str(qemu / "qemu-system-riscv64.exe"), "-M", "virt,pflash0=code,pflash1=vars", "-cpu", "rva23s64",
                   "-m", "512M", "-nographic",
                   "-blockdev", f"node-name=code,driver=file,filename={code},read-only=on",
                   "-blockdev", "node-name=vars,driver=file,filename=vars.fd",
                   "-drive", "file=fat:esp,format=raw,if=none,id=esp,readonly=on",
                   "-device", "virtio-blk-device,drive=esp"], timeout=180, cwd=str(temporary))
    except subprocess.TimeoutExpired:
        print("FAILED: uefi_riscv64 didn't turn the machine off in 180 seconds")
        return 1
    lines = [line.strip() for line in ran.stdout.splitlines()]
    written = [line for line in lines if line in UEFI_RISCV64_OUTPUT]
    if ran.returncode != 0 or written != UEFI_RISCV64_OUTPUT:
        print(f"FAILED: uefi_riscv64 exited with {ran.returncode} and wrote {written}\n{ran.stdout[-4000:]}{ran.stderr}")
        return 1
    print("passed: uefi_riscv64")
    return 0


def main() -> int:
    release = BUILT / "Release" / "hemera.exe"
    compiler = os.environ.get("HEMERA", str(release if release.exists() else BUILT / "Debug" / "hemera-debug.exe"))
    qemu = Path(os.environ.get("QEMU", "C:/Program Files/qemu"))
    failures = 0
    with tempfile.TemporaryDirectory(prefix="hemera-freestanding-tests-") as folder:
        temporary = Path(folder)
        failures += kernel_test("aarch64", compiler, AARCH64_KERNEL,
                                [str(qemu / "qemu-system-aarch64.exe"), "-M", "virt", "-cpu", "max", "-m", "128M",
                                 "-nographic", "-semihosting", "-device", "loader,file=KERNEL",
                                 "-device", "loader,addr=0x40200000,cpu-num=0"], AARCH64_OUTPUT, temporary)
        failures += kernel_test("riscv64", compiler, RISCV64_KERNEL,
                                [str(qemu / "qemu-system-riscv64.exe"), "-M", "virt", "-cpu", "rva23s64", "-m", "128M",
                                 "-nographic", "-semihosting", "-bios", "default", "-kernel", "KERNEL"],
                                RISCV64_OUTPUT, temporary)
        failures += uefi_riscv64_test(compiler, qemu, temporary)
    print(f"{5 - failures} of 5 passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
