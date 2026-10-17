package foreign_convention

KERNEL32 :: #library("kernel32")

// #foreign decides the convention: the platform's C convention, without a context
GetLastError #foreign(KERNEL32) #calling_convention(.interrupt) : fn() -> u32 : ---
