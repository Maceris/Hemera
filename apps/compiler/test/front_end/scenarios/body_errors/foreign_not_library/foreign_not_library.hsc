package foreign_not_library

KERNEL32 :: "kernel32"

// #foreign names a constant declared as #library("name"), not just any string
GetLastError #foreign(KERNEL32) : fn() -> u32 : ---
