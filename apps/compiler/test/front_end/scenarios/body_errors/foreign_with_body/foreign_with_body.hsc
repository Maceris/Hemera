package foreign_with_body

KERNEL32 :: #library("kernel32")

// A #foreign function is the library's, so it has no body of its own
GetLastError #foreign(KERNEL32) :: fn() -> u32 {
    return 0
}
