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

// Identification and timing

cpuid : fn(leaf: u32, subleaf: u32 = 0) -> CpuidResult : ---
// The time-stamp counter. Not serializing, so it may run before earlier instructions finish.
rdtsc : fn() -> u64 : ---
