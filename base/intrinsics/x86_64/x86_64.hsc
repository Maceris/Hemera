package x86_64

/*
 * Privileged and system instructions for x86-64, for kernels and other freestanding code.
 *
 * Each function is one instruction, named after it. Most of them fault outside ring 0.
 * Only exists when TARGET_ARCH == .x86_64, where intrinsics' platform.hsc imports it,
 * so use it from architecture-specific code only.
 */

// The operand of lgdt and lidt.
DescriptorTablePointer :: struct #packed {
    // Size of the table in bytes, minus one.
    limit : u16,
    base : u64,
}

/*
 * What the CPU pushes when entering an interrupt function (#calling_convention(.interrupt)),
 * from the lowest address up.
 */
InterruptFrame :: struct {
    rip : u64,
    cs : u64,
    rflags : u64,
    rsp : u64,
    ss : u64,
}

/*
 * The interrupted code's registers, saved by the generated code of entry functions
 * (#calling_convention(.entry) and .syscall_entry) and restored by return_to_user, from the lowest address up.
 * Its layout is part of the calling convention version.
 */
RegisterFrame :: struct {
    r15 : u64,
    r14 : u64,
    r13 : u64,
    r12 : u64,
    r11 : u64,
    r10 : u64,
    r9 : u64,
    r8 : u64,
    rbp : u64,
    rdi : u64,
    rsi : u64,
    rdx : u64,
    rcx : u64,
    rbx : u64,
    rax : u64,
    // The vector that arrived, or SYSCALL_VECTOR for a SYSCALL.
    vector : u64,
    // The CPU's error code, or 0 for vectors without one.
    error_code : u64,
    // Pushed by the CPU, or filled in by a .syscall_entry function's generated code.
    rip : u64,
    cs : u64,
    rflags : u64,
    rsp : u64,
    ss : u64,
}

// RegisterFrame.vector for a frame saved by a .syscall_entry function.
SYSCALL_VECTOR :: 0xffff_ffff_ffff_ffff

/*
 * What the gs base must point at while in the kernel, at offset 0, for .syscall_entry functions:
 * their generated code saves the user's stack pointer here, and loads kernel_stack.
 */
SyscallScratch :: struct {
    // The top of the stack SYSCALL entry switches to.
    kernel_stack : u64,
    user_stack : u64,
}

// Addresses for the 256 interrupt descriptor table entries, from entry_points.
EntryPoints :: struct {
    addresses : u64[256],
}

CpuidResult :: struct {
    eax : u32,
    ebx : u32,
    ecx : u32,
    edx : u32,
}

// Interrupts

// Disable maskable interrupts.
cli : fn() : ---
// Enable maskable interrupts, starting after the next instruction.
sti : fn() : ---
// Wait for the next interrupt.
hlt : fn() : ---
// Hint that this is a spin-wait loop.
pause : fn() : ---
// The flags register, for checking whether interrupts are enabled (bit 9).
read_rflags : fn() -> u64 : ---

// Descriptor tables

lgdt : fn(table: ptr[DescriptorTablePointer]) : ---
lidt : fn(table: ptr[DescriptorTablePointer]) : ---
// Load the task register with the selector of a TSS descriptor in the GDT.
ltr : fn(selector: u16) : ---
/*
 * Load cs with a far return, and ds, es, fs, gs and ss with data_selector, after lgdt.
 * fs and gs bases set through MSRs are reset, so set them after this.
 */
load_segments : fn(code_selector, data_selector: u16) : ---
// Swap the gs base with the IA32_KERNEL_GS_BASE MSR.
swapgs : fn() : ---

// I/O ports

in_u8  : fn(port: u16) -> u8  : ---
in_u16 : fn(port: u16) -> u16 : ---
in_u32 : fn(port: u16) -> u32 : ---
out_u8  : fn(port: u16, value: u8 ) : ---
out_u16 : fn(port: u16, value: u16) : ---
out_u32 : fn(port: u16, value: u32) : ---

// System calls, from user mode

/*
 * A system call with Linux's x86-64 convention: the number in rax, up to six arguments in rdi,
 * rsi, rdx, r10, r8 and r9, and the result in rax, where -4095 to -1 are errors (-errno). rcx and
 * r11 are clobbered. It doesn't use the stack, so it works on a fiber's small one.
 */
syscall : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 : ---

/*
 * Linux's clone for a new thread, which starts on stack (its top) by calling entry(argument), with
 * the C convention; entry must end the thread with the exit system call rather than return. The
 * kernel stores the new thread's ID through parent_tid before this returns, and clears it through
 * child_tid, waking futex waiters there, once the thread has exited (with CLONE_PARENT_SETTID and
 * CLONE_CHILD_CLEARTID in flags). Returns the new thread's ID, or -errno.
 */
clone_thread : fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
    argument: rawptr) -> i64 : ---

// Model-specific registers

rdmsr : fn(msr: u32) -> u64 : ---
wrmsr : fn(msr: u32, value: u64) : ---

// Control registers and paging

read_cr0 : fn() -> u64 : ---
write_cr0 : fn(value: u64) : ---
// The address of the last page fault.
read_cr2 : fn() -> u64 : ---
// The physical address of the top-level page table, and its flags or PCID.
read_cr3 : fn() -> u64 : ---
// Switch page tables, flushing non-global TLB entries unless PCID says otherwise.
write_cr3 : fn(value: u64) : ---
read_cr4 : fn() -> u64 : ---
write_cr4 : fn(value: u64) : ---
// Flush the TLB entry for the page containing address.
invlpg : fn(address: rawptr) : ---

// Entry and return

/*
 * One entry point per vector for handler, an entry function (#calling_convention(.entry)).
 * The compiler generates a small stub per vector that records the vector number (and an error code of 0
 * where the CPU doesn't push one), then enters handler. handler may return, for NMIs: the frame is
 * restored and the interrupted code resumes.
 *
 * handler is also a generic parameter, so it must be known at compile time, and the stubs are
 * generated once for each handler this is called with.
 */
entry_points : fn[handler](handler: (fn(frame: ptr[mut RegisterFrame]))) -> ptr[EntryPoints] : ---

/*
 * Restore every register from frame and return to user mode: swapgs, then sysretq when
 * rcx == rip, r11 == rflags and rip is canonical, otherwise iretq.
 */
return_to_user #never_returns : fn(frame: ptr[RegisterFrame]) : ---

// The current gs base: rdgsbase if FSGSBASE is enabled, otherwise the IA32_GS_BASE MSR.
read_gs_base : fn() -> rawptr : ---

// Vector state

/*
 * Save or restore the state components selected by mask (XCR0 bits) to or from area,
 * which is 64-byte aligned and sized from CPUID leaf 0xD.
 */
xsave : fn(area: rawptr, mask: u64) : ---
// Compacted format, leaving out components in their initial state.
xsavec : fn(area: rawptr, mask: u64) : ---
// Skips components unchanged since the last xrstor from the same area.
xsaveopt : fn(area: rawptr, mask: u64) : ---
xrstor : fn(area: rawptr, mask: u64) : ---
// Read or write an extended control register; register 0 is XCR0.
xgetbv : fn(register: u32) -> u64 : ---
xsetbv : fn(register: u32, value: u64) : ---

// Identification and timing

cpuid : fn(leaf: u32, subleaf: u32 = 0) -> CpuidResult : ---
// The time-stamp counter. Not serializing, so it may run before earlier instructions finish.
rdtsc : fn() -> u64 : ---
// A value from the CPU's entropy source, or null when none was ready (the carry flag was clear).
rdseed : fn() -> u64? : ---
// A value from the CPU's random number generator, seeded from its entropy source, or null when none was ready.
rdrand : fn() -> u64? : ---
