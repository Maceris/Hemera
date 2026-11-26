/*
 * A freestanding RISC-V program for freestanding_tests.py: a kernel that OpenSBI starts in supervisor mode on QEMU's
 * virt machine, with no startup code. kernel_entry sets up a carrier block and a context itself, turns on Sv39
 * translation, points stvec at its entry function and runs its checks, writing to the 16550 UART along the way, then
 * ends QEMU through semihosting with 42 if everything worked, or the number of the first check that failed.
 *
 * It takes real traps: a breakpoint in supervisor mode, which the entry function returns from; then three system calls
 * from user code, returned from by sret after the entry function returns, then through return_to_user; and last a
 * stack check that traps, built with stack checks that trap.
 *
 * Hemera has no mutable globals, so the page tables and stacks are at fixed places in RAM past the image, and the
 * entry function finds the test's state through tp, where the TrapScratch at its start puts it.
 */
package freestanding_riscv64

import intrinsics from "base:intrinsics"
import runtime from "base:runtime"
import riscv64 from "base:intrinsics/riscv64"

// QEMU virt's 16550 UART: data, and the line status, whose bit 5 says the transmitter can take a byte
UART : u64 : 0x1000_0000
UART_LINE_STATUS : u64 : 0x1000_0005

// Where the image is (the linker script's), and the RAM past it this uses
IMAGE : u64 : 0x8020_0000
USER_STACK : u64 : 0x8100_0000
KERNEL_STACK_TOP : u64 : 0x8140_0000
ROOT_TABLE : u64 : 0x8160_0000
USER_TABLE : u64 : 0x8160_1000

// Where user mode sees the image again, readable and executable for it, and its stack, both 2 MiB
USER_IMAGE : u64 : 0x1_0000_0000
USER_STACK_ALIAS : u64 : 0x1_0020_0000
MEGAPAGE_SIZE : u64 : 0x20_0000

// Sv39's page table entries' bits
VALID : u64 : 1 << 0
READ : u64 : 1 << 1
WRITE : u64 : 1 << 2
EXECUTE : u64 : 1 << 3
USER : u64 : 1 << 4
ACCESSED : u64 : 1 << 6
DIRTY : u64 : 1 << 7
SV39 : u64 : 8 << 60

SEMIHOSTING_EXIT : u64 : 0x18
APPLICATION_EXIT : u64 : 0x20026

// What the entry function needs, found through tp: the TrapScratch first, since a trap from user mode leaves tp there.
TestState :: struct {
    scratch : riscv64.TrapScratch,
    // The kernel's carrier block, as an address, since it's on kernel_entry's stack
    carrier : u64,
    breakpoints : u64,
    // The system calls from user mode so far
    calls : u64,
}

write_byte :: fn(byte: u8) {
    // Wait until the transmitter can take it
    loop {
    }
    while (intrinsics.volatile_load_u8(cast[ptr[u8]](UART_LINE_STATUS)) & 0x20) == 0
    intrinsics.volatile_store_u8(cast[ptr[mut u8]](UART), byte)
}

write :: fn(text: string) {
    for character in text {
        write_byte(cast[u8](character))
    }
}

exit_qemu #never_returns :: fn(code: u64) {
    block : u64[2] = u64.[APPLICATION_EXIT, code]
    riscv64.semihosting(SEMIHOSTING_EXIT, cast[rawptr](&block))
    loop {
        riscv64.wfi()
    }
}

table_entry :: fn(table: u64, index: u64) -> ptr[mut u64] {
    return cast[ptr[mut u64]](table + index * 8)
}

leaf :: fn(physical: u64, bits: u64) -> u64 {
    return physical >> 12 << 10 | bits | VALID | ACCESSED
}

/*
 * The first 1 GiB, devices, and RAM's 1 GiB, mapped as they are for the supervisor only; then the image again at
 * USER_IMAGE, readable and executable in user mode only, and a stack for user mode after it.
 */
map_memory :: fn() {
    for i in 0..<512 {
        table_entry(ROOT_TABLE, cast[u64](i))^ = 0
        table_entry(USER_TABLE, cast[u64](i))^ = 0
    }
    table_entry(ROOT_TABLE, 0)^ = leaf(0, READ | WRITE | DIRTY)
    table_entry(ROOT_TABLE, 2)^ = leaf(0x8000_0000, READ | WRITE | EXECUTE | DIRTY)
    table_entry(ROOT_TABLE, USER_IMAGE >> 30)^ = USER_TABLE >> 12 << 10 | VALID
    table_entry(USER_TABLE, 0)^ = leaf(IMAGE, READ | EXECUTE | USER)
    table_entry(USER_TABLE, 1)^ = leaf(USER_STACK, READ | WRITE | USER | DIRTY)
    riscv64.fence(riscv64.FENCE_WRITE, riscv64.FENCE_READ | riscv64.FENCE_WRITE)
    riscv64.csrw(.SATP, SV39 | ROOT_TABLE >> 12)
    riscv64.sfence_vma_all()
}

/*
 * The test's traps: the breakpoint in supervisor mode, which it returns from past the ebreak; the system calls from
 * user mode; and the stack check's trap, which ends the test.
 */
trap #calling_convention(.entry) :: fn(frame: ptr[mut riscv64.RegisterFrame]) {
    state :: cast[ptr[mut TestState]](riscv64.read_tp())
    carrier :: cast[ptr[mut runtime.CarrierBlock]](state.carrier)
    intrinsics.set_carrier(carrier)
    push_context taken from runtime.MINIMAL_CONTEXT {
        from_supervisor :: frame.sstatus & riscv64.SSTATUS_SPP != 0
        handled := false
        if from_supervisor && frame.scause == riscv64.CAUSE_BREAKPOINT {
            if state.calls == 3 {
                // From overflows' prologue, before its body ran: no limit now, so write's own check passes
                carrier.stack_limit = null
                write("done\n")
                exit_qemu(if state.breakpoints == 1 { 42 } else { 13 })
            }
            state.breakpoints += 1
            // Past the ebreak, compressed or not
            instruction :: intrinsics.volatile_load_u16(cast[ptr[u16]](frame.sepc))
            frame.sepc += if instruction & 3 == 3 { 4 } else { 2 }
            handled = true
        }
        if !from_supervisor && frame.scause == riscv64.CAUSE_USER_ECALL {
            handled = system_call(state, frame)
        }
        if !handled {
            write("unexpected trap\n")
            exit_qemu(20 + (frame.scause & 0xf))
        }
    }
}

/*
 * user_main's three calls, in a7: 1 is answered by the entry function returning, 2 through return_to_user, and 3 ends
 * user mode, with the last check.
 */
system_call :: fn(state: ptr[mut TestState], frame: ptr[mut riscv64.RegisterFrame]) -> bool {
    number :: frame.x[17]
    state.calls += 1
    if number != state.calls {
        exit_qemu(16)
    }
    // Past the ecall, which is never compressed
    frame.sepc += 4
    if number == 1 {
        if frame.x[10] != 6 {
            exit_qemu(17)
        }
        frame.x[10] = 100
        write("user mode\n")
        return true
    }
    if number == 2 {
        if frame.x[10] != 100 {
            exit_qemu(18)
        }
        frame.x[10] = 200
        riscv64.return_to_user(frame, &state.scratch)
    }
    if frame.x[10] != 200 {
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
 * User mode's code, run from USER_IMAGE: three system calls, each with the last one's answer plus one. It reaches
 * nothing in the kernel, since only its own code and stack are mapped for it.
 */
user_main #calling_convention(.c) #no_context :: fn(value: u64) #never_returns {
    first :: riscv64.syscall(1, value + 1)
    second :: riscv64.syscall(2, first)
    riscv64.syscall(3, second)
    loop {
    }
}

checks :: fn(carrier: ptr[mut runtime.CarrierBlock]) {
    if cast[rawptr](intrinsics.carrier()) != cast[rawptr](carrier) {
        exit_qemu(2)
    }
    // Atomics, on memory translation now maps
    counter : u64 = 5
    old, swapped := intrinsics.interlocked_compare_exchange_u64(&counter, 9, 5)
    if old != 5 || !swapped || intrinsics.interlocked_exchange_add_u64(&counter, 3) != 9 || counter != 12 {
        exit_qemu(3)
    }
    intrinsics.fence_sequentially_consistent()
    riscv64.fence(riscv64.FENCE_INPUT | riscv64.FENCE_OUTPUT, riscv64.FENCE_INPUT | riscv64.FENCE_OUTPUT)
    /*
     * Translation: the supervisor reaches the user alias of the image only with SUM set, and sees the image's own
     * bytes there
     */
    previous :: riscv64.csrrs(.SSTATUS, riscv64.SSTATUS_SUM)
    if previous & riscv64.SSTATUS_SUM != 0 {
        exit_qemu(4)
    }
    aliased :: intrinsics.volatile_load_u32(cast[ptr[u32]](USER_IMAGE))
    riscv64.csrrc(.SSTATUS, riscv64.SSTATUS_SUM)
    if aliased != intrinsics.volatile_load_u32(cast[ptr[u32]](IMAGE)) {
        exit_qemu(5)
    }
    // The clock counts, and Sstc's stimecmp takes a time far off, so no timer interrupt is pending
    before :: riscv64.csrr(.TIME)
    riscv64.csrw(.STIMECMP, 0xffff_ffff_ffff_ffff)
    if riscv64.csrr(.TIME) < before || riscv64.csrr(.SIP) & (1 << 5) != 0 {
        exit_qemu(6)
    }
    // A swap gives what was there: sscratch is 0 in supervisor mode
    if riscv64.csrrw(.SSCRATCH, 0) != 0 {
        exit_qemu(7)
    }
    // The SBI answers: its specification version, from the base extension
    version :: riscv64.sbi_call(0x10, 0)
    if version.error != 0 || version.value == 0 {
        exit_qemu(8)
    }
    riscv64.pause()
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
        if riscv64.csrr(.SATP) != 0 {
            exit_qemu(1)
        }
        map_memory()
        write("paging on\n")
        checks(&carrier)
        state := TestState.{carrier = cast[u64](&carrier)}
        state.scratch.kernel_stack = KERNEL_STACK_TOP
        riscv64.write_tp(cast[rawptr](&state))
        riscv64.csrw(.STVEC, cast[u64](trap))
        riscv64.ebreak()
        if state.breakpoints != 1 {
            exit_qemu(12)
        }
        write("breakpoint\n")
        // user_main's code is written: fetched again
        riscv64.fence_i()
        // Into user mode, with interrupts off there too (sstatus 0), at user_main as user mode sees it
        user : riscv64.RegisterFrame
        user.sepc = cast[u64](user_main) - IMAGE + USER_IMAGE
        user.x[2] = USER_STACK_ALIAS + MEGAPAGE_SIZE
        user.x[10] = 5
        riscv64.return_to_user(&user, &state.scratch)
    }
}
