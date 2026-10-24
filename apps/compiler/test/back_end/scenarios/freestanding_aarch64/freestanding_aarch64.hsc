/*
 * A freestanding AArch64 program for freestanding_tests.py: a kernel that QEMU's virt machine starts at
 * EL1, with no startup code. kernel_entry sets up a carrier block and a context itself, turns the MMU on,
 * installs its exception vectors and runs its checks, writing to the PL011 UART along the way, then ends
 * QEMU through semihosting with 42 if everything worked, or the number of the first check that failed.
 *
 * It takes real exceptions: a breakpoint at EL1, which the entry function returns from; then three system
 * calls from user code at EL0, returned from by eret after the entry function returns, then through
 * return_to_user; and last a stack check that traps, built with stack checks that trap.
 *
 * Hemera has no mutable globals, so the page tables and stacks are at fixed places in RAM past the image,
 * and the entry function finds the test's state through TPIDR_EL1.
 */
package freestanding_aarch64

import intrinsics from "base"
import runtime from "base"
import aarch64 from "base/intrinsics"

// QEMU virt's PL011 UART: data, and flags, whose bit 5 says the transmit FIFO is full
UART : u64 : 0x0900_0000
UART_FLAGS : u64 : 0x0900_0018

// Where the image is (the linker script's), and the RAM past it this uses
IMAGE : u64 : 0x4020_0000
USER_STACK : u64 : 0x4100_0000
KERNEL_STACK_TOP : u64 : 0x4140_0000
LEVEL1_TABLE : u64 : 0x4160_0000
RAM_TABLE : u64 : 0x4160_1000
USER_TABLE : u64 : 0x4160_2000

// Where EL0 sees the image again, read-only and executable for it, and its stack, both 2 MiB
USER_IMAGE : u64 : 0x8000_0000
USER_STACK_ALIAS : u64 : 0x8020_0000
BLOCK_SIZE : u64 : 0x20_0000

// Translation table entries' bits
TABLE : u64 : 0b11
BLOCK : u64 : 0b01
ACCESSED : u64 : 1 << 10
INNER_SHAREABLE : u64 : 3 << 8
// AP[2:1]: EL0 can reach it (bit 6), it's read-only (bit 7)
EL0_ACCESS : u64 : 1 << 6
READ_ONLY : u64 : 1 << 7
PRIVILEGED_EXECUTE_NEVER : u64 : 1 << 53
USER_EXECUTE_NEVER : u64 : 1 << 54
// MAIR_EL1's attributes: 0 Device-nGnRnE, 1 Normal write-back
DEVICE : u64 : 0 << 2
NORMAL : u64 : 1 << 2

SEMIHOSTING_EXIT : u64 : 0x18
APPLICATION_EXIT : u64 : 0x20026

// What the entry function needs, found through TPIDR_EL1.
TestState :: struct {
    // The kernel's carrier block, as an address, since it's on kernel_entry's stack
    carrier : u64,
    breakpoints : u64,
    // The system calls from EL0 so far
    calls : u64,
}

write_byte :: fn(byte: u8) {
    // Wait until the transmit FIFO has room
    loop {
    }
    while (intrinsics.volatile_load_u32(cast[ptr[u32]](UART_FLAGS)) & 0x20) != 0
    intrinsics.volatile_store_u32(cast[ptr[mut u32]](UART), cast[u32](byte))
}

write :: fn(text: string) {
    for character in text {
        write_byte(cast[u8](character))
    }
}

exit_qemu #never_returns :: fn(code: u64) {
    block : u64[2] = u64.[APPLICATION_EXIT, code]
    aarch64.semihosting(SEMIHOSTING_EXIT, cast[rawptr](&block))
    loop {
        aarch64.wfi()
    }
}

table_entry :: fn(table: u64, index: u64) -> ptr[mut u64] {
    return cast[ptr[mut u64]](table + index * 8)
}

/*
 * An identity map of the first 2 GiB, devices in the first and RAM in 2 MiB blocks in the second, for EL1
 * only; then the image again at USER_IMAGE, read-only and executable at EL0 only, and a stack for EL0 after it.
 */
map_memory :: fn() {
    for i in 0..<512 {
        table_entry(LEVEL1_TABLE, cast[u64](i))^ = 0
        table_entry(USER_TABLE, cast[u64](i))^ = 0
        ram :: 0x4000_0000 + cast[u64](i) * BLOCK_SIZE
        table_entry(RAM_TABLE, cast[u64](i))^ = ram | BLOCK | ACCESSED | INNER_SHAREABLE | NORMAL | USER_EXECUTE_NEVER
    }
    table_entry(LEVEL1_TABLE, 0)^ = BLOCK | ACCESSED | DEVICE | USER_EXECUTE_NEVER | PRIVILEGED_EXECUTE_NEVER
    table_entry(LEVEL1_TABLE, 1)^ = RAM_TABLE | TABLE
    table_entry(LEVEL1_TABLE, 2)^ = USER_TABLE | TABLE
    table_entry(USER_TABLE, 0)^ = IMAGE | BLOCK | ACCESSED | INNER_SHAREABLE | NORMAL | EL0_ACCESS | READ_ONLY
        | PRIVILEGED_EXECUTE_NEVER
    table_entry(USER_TABLE, 1)^ = USER_STACK | BLOCK | ACCESSED | INNER_SHAREABLE | NORMAL | EL0_ACCESS
        | USER_EXECUTE_NEVER | PRIVILEGED_EXECUTE_NEVER

    aarch64.write_system_register(.MAIR_EL1, 0xff00)
    // 39-bit addresses from TTBR0 (T0SZ 25), 4 KiB pages, walks cached and inner shareable, no TTBR1 walks
    // (EPD1), and the physical address size the CPU has
    physical_size :: aarch64.read_system_register(.ID_AA64MMFR0_EL1) & 7
    aarch64.write_system_register(.TCR_EL1, 25 | 1 << 8 | 1 << 10 | 3 << 12 | 1 << 23 | physical_size << 32)
    aarch64.write_system_register(.TTBR0_EL1, LEVEL1_TABLE)
    aarch64.isb()
    aarch64.tlbi_vmalle1()
    aarch64.dsb(.ISH)
    aarch64.isb()
    // The MMU, data and instruction caches on, and alignment checks off
    control :: aarch64.read_system_register(.SCTLR_EL1)
    aarch64.write_system_register(.SCTLR_EL1, (control | 1 | 1 << 2 | 1 << 12) & ~cast[u64](1 << 1))
    aarch64.isb()
}

/*
 * The test's exceptions: the breakpoint at EL1, which it returns from past the brk; the system calls from
 * EL0; and the stack check's trap, which ends the test.
 */
exception #calling_convention(.entry) :: fn(frame: ptr[mut aarch64.RegisterFrame]) {
    state :: cast[ptr[mut TestState]](aarch64.read_system_register(.TPIDR_EL1))
    carrier :: cast[ptr[mut runtime.CarrierBlock]](state.carrier)
    intrinsics.set_carrier(carrier)
    push_context taken from runtime.MINIMAL_CONTEXT {
        class :: (frame.esr >> 26) & 0x3f
        handled := false
        if frame.vector == aarch64.VECTOR_CURRENT_SPX && class == aarch64.ESR_CLASS_BRK {
            immediate :: frame.esr & 0xffff
            if immediate == 7 {
                state.breakpoints += 1
                frame.elr += 4
                handled = true
            }
            else if immediate == 1 {
                // From overflows' prologue, before its body ran: no limit now, so write's own check passes
                carrier.stack_limit = null
                write("done\n")
                exit_qemu(if state.calls == 3 && state.breakpoints == 1 { 42 } else { 13 })
            }
        }
        if frame.vector == aarch64.VECTOR_LOWER_AARCH64 && class == aarch64.ESR_CLASS_SVC {
            handled = system_call(state, frame)
        }
        if !handled {
            write("unexpected exception\n")
            exit_qemu(20 + frame.vector)
        }
    }
}

/*
 * user_main's three calls, in x8: 1 is answered by the entry function returning, 2 through return_to_user,
 * and 3 ends user mode, with the last check.
 */
system_call :: fn(state: ptr[mut TestState], frame: ptr[mut aarch64.RegisterFrame]) -> bool {
    number :: frame.x[8]
    state.calls += 1
    if number != state.calls {
        exit_qemu(16)
    }
    if number == 1 {
        if frame.x[0] != 6 {
            exit_qemu(17)
        }
        frame.x[0] = 100
        write("user mode\n")
        return true
    }
    if number == 2 {
        if frame.x[0] != 100 {
            exit_qemu(18)
        }
        frame.x[0] = 200
        aarch64.return_to_user(frame, cast[rawptr](KERNEL_STACK_TOP))
    }
    if frame.x[0] != 200 {
        exit_qemu(19)
    }
    // The last check: with stack_limit above the stack, overflows' prologue traps
    cast[ptr[mut runtime.CarrierBlock]](state.carrier).stack_limit = cast[rawptr](0xffff_ffff_ffff_ffff)
    overflows()
    exit_qemu(11)
}

// Never runs: its prologue traps first. It calls write, since small leaf functions don't check.
overflows :: fn() {
    write("the stack check didn't trap\n")
    exit_qemu(10)
}

/*
 * EL0's code, run from USER_IMAGE: three system calls, each with the last one's answer plus one. It
 * reaches nothing in the kernel, since only its own code and stack are mapped for it.
 */
user_main #calling_convention(.c) #no_context :: fn(value: u64) #never_returns {
    first :: aarch64.syscall(1, value + 1)
    second :: aarch64.syscall(2, first)
    aarch64.syscall(3, second)
    loop {
    }
}

checks :: fn(carrier: ptr[mut runtime.CarrierBlock]) {
    if cast[rawptr](intrinsics.carrier()) != cast[rawptr](carrier) {
        exit_qemu(2)
    }
    // Atomics, which LSE makes single instructions, on memory the MMU made normal
    counter : u64 = 5
    old, swapped := intrinsics.interlocked_compare_exchange_u64(&counter, 9, 5)
    if old != 5 || !swapped || intrinsics.interlocked_exchange_add_u64(&counter, 3) != 9 || counter != 12 {
        exit_qemu(3)
    }
    intrinsics.fence_sequentially_consistent()
    aarch64.dmb(.ISHST)
    // The MMU translates: a read of the image at EL1 gives its own address, and EL0 can't reach it
    aarch64.at_s1e1r(cast[rawptr](IMAGE))
    translated :: aarch64.read_system_register(.PAR_EL1)
    if translated & 1 != 0 || translated & 0xffff_ffff_f000 != IMAGE {
        exit_qemu(4)
    }
    aarch64.at_s1e0r(cast[rawptr](IMAGE))
    if aarch64.read_system_register(.PAR_EL1) & 1 != 1 {
        exit_qemu(5)
    }
    // The generic timer counts
    before :: aarch64.read_system_register(.CNTVCT_EL0)
    if aarch64.read_system_register(.CNTFRQ_EL0) == 0 || aarch64.read_system_register(.CNTVCT_EL0) < before {
        exit_qemu(6)
    }
    // The random number generator, where the CPU has it
    if (aarch64.read_system_register(.ID_AA64ISAR0_EL1) >> 60) & 0xf != 0 {
        aarch64.rndr()
    }
    // An encoded register reads the same as its name: MIDR_EL1
    if aarch64.read_system_register_encoded(3, 0, 0, 0, 0) != aarch64.read_system_register(.MIDR_EL1) {
        exit_qemu(7)
    }
    // Never true: makes the fiber switches part of the kernel, so they're assembled and linked
    if before == 0xffff_ffff_ffff_ffff {
        switch_fibers(cast[ptr[mut runtime.Fiber]](cast[rawptr](carrier)))
    }
}

// Never runs (see checks): starts, resumes and suspends a fiber.
switch_fibers :: fn(fiber: ptr[mut runtime.Fiber]) {
    if intrinsics.fiber_start(fiber) == .Yielded {
        intrinsics.fiber_resume(fiber)
    }
    intrinsics.fiber_suspend(fiber)
}

kernel_entry #calling_convention(.c) #no_context :: fn() #never_returns {
    // A carrier block for this stack before anything else, then a context
    carrier : runtime.CarrierBlock
    intrinsics.set_carrier(&carrier)
    push_context boot from runtime.MINIMAL_CONTEXT {
        write("booted\n")
        if aarch64.read_system_register(.CurrentEL) != 1 << 2 {
            exit_qemu(1)
        }
        map_memory()
        write("mmu on\n")
        checks(&carrier)
        state := TestState.{carrier = cast[u64](&carrier)}
        aarch64.write_system_register(.TPIDR_EL1, cast[u64](&state))
        aarch64.write_system_register(.VBAR_EL1, cast[u64](aarch64.vector_table(exception)))
        aarch64.isb()
        aarch64.brk(7)
        if state.breakpoints != 1 {
            exit_qemu(12)
        }
        write("breakpoint\n")
        // user_main's code is written: cleaned to the point of unification and invalidated for fetching
        aarch64.dc_cvau(cast[rawptr](user_main))
        aarch64.dsb(.ISH)
        aarch64.ic_ivau(cast[rawptr](user_main))
        aarch64.dsb(.ISH)
        aarch64.isb()
        // Into user mode: EL0 with interrupts unmasked (SPSR 0), at user_main as EL0 sees it
        user : aarch64.RegisterFrame
        user.elr = cast[u64](user_main) - IMAGE + USER_IMAGE
        user.sp_el0 = USER_STACK_ALIAS + BLOCK_SIZE
        user.x[0] = 5
        aarch64.return_to_user(&user, cast[rawptr](KERNEL_STACK_TOP))
    }
}
