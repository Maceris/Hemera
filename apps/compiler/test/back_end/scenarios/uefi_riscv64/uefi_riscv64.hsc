/*
 * A RISC-V UEFI application for freestanding_tests.py, which edk2 runs under QEMU: linked as an ELF and made into a
 * PE32+ image by the compiler. It writes to the firmware's console, checks that intrinsics.image_base is where the
 * image's headers were loaded, and turns the machine off through the runtime services, writing what it found first.
 */
package uefi_riscv64

import intrinsics from "base:intrinsics"
import io from "std:io"
import uefi from "std:os/uefi"

main :: fn() -> int {
    io.println("uefi started")
    // The image starts with its DOS header's "MZ"
    if intrinsics.volatile_load_u16(cast[ptr[u16]](intrinsics.image_base())) == 0x5a4d {
        io.println("image base found")
    }
    uefi.reset(.Shutdown)
}
