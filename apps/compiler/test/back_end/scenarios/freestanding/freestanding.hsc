/*
 * A freestanding program for the back end's test: a kernel that Limine boots, with no startup
 * code. kernel_entry sets up a carrier block and a context itself, runs its checks, and exits QEMU
 * through the isa-debug-exit device at port 0xf4 with 42 if everything worked, or the number of
 * the first check that failed. Along the way it writes to the serial port. It's built with
 * stack checks that trap, and the last check is that one does.
 */
package freestanding

import intrinsics from "base"
import runtime from "base"
import x86_64 from "base/intrinsics"

// Limine's request markers and base revision tag (base revision 6)
REQUESTS_START #externally_initialized #section(".limine_requests_start") : u64[4] : u64.[0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9]
BASE_REVISION #externally_initialized #section(".limine_requests") : u64[3] : u64.[0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 6]
REQUESTS_END #externally_initialized #section(".limine_requests_end") : u64[2] : u64.[0xadc0e0531bb10d03, 0x9572709f31764c62]

COM1 :: 0x3f8
DEBUG_EXIT : u16 : 0xf4
// Limine's 64-bit code segment
KERNEL_CODE : u16 : 0x28

IdtEntry :: struct {
    offset_low : u16,
    selector : u16,
    ist : u8,
    attributes : u8,
    offset_middle : u16,
    offset_high : u32,
    reserved : u32,
}

#assert size_of(IdtEntry) == 16

write_byte :: fn(byte: u8) {
    // Wait until the transmitter can take another byte
    loop {
    }
    while (x86_64.in_u8(COM1 + 5) & 0x20) == 0
    x86_64.out_u8(COM1, byte)
}

write :: fn(text: string) {
    for character in text {
        write_byte(cast[u8](character))
    }
}

exit_qemu #never_returns :: fn(code: u32) {
    x86_64.out_u32(DEBUG_EXIT, code)
    loop {
        x86_64.cli()
        x86_64.hlt()
    }
}

gate :: fn(handler: u64) -> IdtEntry {
    return IdtEntry.{
        offset_low = cast[u16](handler & 0xffff),
        selector = KERNEL_CODE,
        attributes = 0x8e,
        offset_middle = cast[u16]((handler >> 16) & 0xffff),
        offset_high = cast[u32](handler >> 32),
    }
}

// The last check: a stack check that fails traps, with an invalid opcode, which ends up here
invalid_opcode #calling_convention(.interrupt) :: fn(frame: ptr[x86_64.InterruptFrame]) {
    push_context fault from runtime.MINIMAL_CONTEXT {
        if frame.rip < 0xffffffff80000000 {
            exit_qemu(9)
        }
        // From overflows' prologue, before its body ran
        write("done\n")
        exit_qemu(42)
    }
}

checks :: fn(carrier: ptr[mut runtime.CarrierBlock]) {
    if cast[rawptr](intrinsics.carrier()) != cast[rawptr](carrier) {
        exit_qemu(1)
    }
    counter : u64 = 5
    if intrinsics.atomic_load_u64(&counter) != 5 {
        exit_qemu(2)
    }
    intrinsics.atomic_store_u64_release(&counter, 7)
    old, swapped := intrinsics.interlocked_compare_exchange_u64(&counter, 9, 7)
    if old != 7 || !swapped || counter != 9 {
        exit_qemu(3)
    }
    if intrinsics.interlocked_exchange_add_u64(&counter, 3) != 9 || counter != 12 {
        exit_qemu(4)
    }
    intrinsics.fence_sequentially_consistent()
    intrinsics.compiler_fence_acquire_release()
    flag : u32 = 0
    intrinsics.volatile_store_u32(&flag, 0xabcd)
    if intrinsics.volatile_load_u32(&flag) != 0xabcd {
        exit_qemu(5)
    }
    // "GenuineIntel" or "AuthenticAMD": either way, leaf 0 gives the highest leaf in eax
    vendor := x86_64.cpuid(0)
    if vendor.eax == 0 {
        exit_qemu(6)
    }
    if x86_64.rdtsc() == 0 {
        exit_qemu(7)
    }
    // Paging is on, and long mode is enabled in EFER
    if (x86_64.read_cr0() >> 31) & 1 != 1 || (x86_64.rdmsr(0xc0000080) >> 8) & 1 != 1 {
        exit_qemu(8)
    }
}

// Never runs: with stack_limit above the stack, its prologue traps first. It calls write, since
// small leaf functions don't check (docs/calling_convention.md, Prologue Stack Check).
overflows :: fn() {
    write("the stack check didn't trap\n")
    exit_qemu(10)
}

kernel_entry #calling_convention(.c) #no_context :: fn() #never_returns {
    // A carrier block for this stack before anything else, then a context
    carrier : runtime.CarrierBlock
    intrinsics.set_carrier(&carrier)
    idt : IdtEntry[256]
    push_context boot from runtime.MINIMAL_CONTEXT {
        write("booted\n")
        checks(&carrier)
        idt[6] = gate(cast[u64](invalid_opcode))
        table := x86_64.DescriptorTablePointer.{cast[u16](size_of(IdtEntry) * 256 - 1), cast[u64](&idt)}
        x86_64.lidt(&table)
        carrier.stack_limit = cast[rawptr](0xffff_ffff_ffff_ffff)
        overflows()
    }
    // Only reached if the stack check didn't trap
    x86_64.out_u32(DEBUG_EXIT, 11)
    intrinsics.trap()
}
