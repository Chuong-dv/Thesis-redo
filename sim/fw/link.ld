OUTPUT_ARCH(riscv)
ENTRY(_start)

/* RAM 8 KB o 0x0000_0000. Phan tren cung (0x1F00-0x1FFF) de danh cho mailbox, khong dung cho code/stack. */
MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x1F00
}

SECTIONS
{
    .text   : { *(.init) *(.text*) }                     > RAM
    .rodata : { *(.rodata*) *(.srodata*) }               > RAM
    .data   : { *(.data*) *(.sdata*) }                   > RAM
    .bss    : { *(.bss*) *(.sbss*) *(COMMON) }           > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
