/*
 * Places the AArch64 freestanding test for QEMU's virt machine, which loads it into RAM (from 0x40000000) and
 * starts it at EL1 with the MMU off and no stack. So its first instructions, written here since Hemera has
 * no assembly, set the stack pointer from the literal after them and branch to kernel_entry:
 *
 *     ldr x0, 1f           // 0x58000080: the literal 16 bytes on
 *     mov sp, x0           // 0x9100001f
 *     b   kernel_entry     // 0x14000000 with the word offset in the low 26 bits
 *     .word 0              // so the literal is 8-byte aligned
 * 1:  .quad stack_top
 *
 * The image is in the 2 MiB at 0x40200000, which the test maps again for EL0 to run its user code from.
 */
OUTPUT_FORMAT(elf64-littleaarch64)
ENTRY(start)

PHDRS
{
    text PT_LOAD;
    rodata PT_LOAD;
    data PT_LOAD;
    dynamic PT_DYNAMIC;
}

SECTIONS
{
    . = 0x40200000;

    .text : {
        start = .;
        LONG(0x58000080)
        LONG(0x9100001f)
        LONG(0x14000000 | (((kernel_entry - (start + 8)) >> 2) & 0x3ffffff))
        LONG(0)
        QUAD(stack_top)
        *(.text .text.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .rodata : { *(.rodata .rodata.*) } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .data : { *(.data .data.*) } :data
    .bss : {
        *(.bss .bss.*) *(COMMON)
        . = ALIGN(16);
        . += 0x10000;
        stack_top = .;
    } :data

    .dynamic : { *(.dynamic) } :data :dynamic
    /DISCARD/ : { *(.eh_frame*) *(.note .note.*) }
}
