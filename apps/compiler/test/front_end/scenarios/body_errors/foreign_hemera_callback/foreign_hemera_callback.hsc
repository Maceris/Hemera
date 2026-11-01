package foreign_hemera_callback

KERNEL32 :: #library("kernel32")

// C calls what it's given with its own convention, so a function given to it has to be a .c one
Callback :: alias fn(code_page: cstring) -> b32

EnumSystemCodePagesA #foreign(KERNEL32) : fn(callback: Callback?, flags: u32) -> b32 : ---
