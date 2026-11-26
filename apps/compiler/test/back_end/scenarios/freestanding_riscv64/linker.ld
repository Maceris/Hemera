/*
 * Places the RISC-V freestanding test for QEMU's virt machine, where OpenSBI starts it in supervisor mode at
 * 0x80200000 with translation off and no stack. So its first instructions, written here since Hemera has no assembly,
 * set the stack pointer relative to themselves and jump to kernel_entry:
 *
 *     auipc sp, %pcrel_hi(stack_top)      // 0x00000117 with the upper 20 bits
 *     addi  sp, sp, %pcrel_lo(stack_top)  // 0x00010113 with the lower 12 bits
 *     j     kernel_entry                  // 0x0000006f with the offset's bits scattered as jal has them
 *
 * The image is in the 2 MiB at 0x80200000, which the test maps again for user mode to run its user code from.
 */
OUTPUT_FORMAT(elf64-littleriscv)
ENTRY(start)

PHDRS
{
    text PT_LOAD;
    rodata PT_LOAD;
    data PT_LOAD;
}

STACK_OFFSET = stack_top - start;
STACK_HIGH = (STACK_OFFSET + 0x800) >> 12;
STACK_LOW = STACK_OFFSET - (STACK_HIGH << 12);
ENTRY_OFFSET = kernel_entry - (start + 8);

SECTIONS
{
    . = 0x80200000;

    .text : {
        start = .;
        LONG(((STACK_HIGH & 0xfffff) << 12) | 0x117)
        LONG(((STACK_LOW & 0xfff) << 20) | 0x10113)
        LONG((((ENTRY_OFFSET >> 20) & 1) << 31) | (((ENTRY_OFFSET >> 1) & 0x3ff) << 21)
            | (((ENTRY_OFFSET >> 11) & 1) << 20) | (((ENTRY_OFFSET >> 12) & 0xff) << 12) | 0x6f)
        *(.text .text.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .data : { *(.data .data.* .sdata .sdata.*) } :data
    .bss : {
        *(.bss .bss.* .sbss .sbss.*) *(COMMON)
        . = ALIGN(16);
        . += 0x10000;
        stack_top = .;
    } :data

    /DISCARD/ : { *(.eh_frame*) *(.note .note.*) *(.riscv.attributes) }
}
