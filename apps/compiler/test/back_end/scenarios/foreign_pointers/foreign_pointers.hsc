/*
 * #foreign functions taking pointers that aren't ptr[T] or rawptr, which are each one register as C sees them:
 * a cstring, an optional pointer and an optional cstring (null for None), and a function value C calls back.
 * main returns 42 if everything worked, or the number of the first check that failed.
 */
package foreign_pointers

import runtime from "base"

KERNEL32 :: #library("kernel32")

CodePageCallback :: alias fn(code_page: cstring) -> b32 #calling_convention(.c)

lstrlenA #foreign(KERNEL32) : fn(text: cstring) -> i32 : ---
GetModuleHandleA #foreign(KERNEL32) : fn(name: cstring?) -> rawptr : ---
QueryPerformanceFrequency #foreign(KERNEL32) : fn(frequency: ptr[mut i64]?) -> b32 : ---
GetComputerNameA #foreign(KERNEL32) : fn(buffer: ptr[mut u8]?, size: ptr[mut u32]) -> b32 : ---
EnumSystemCodePagesA #foreign(KERNEL32) : fn(callback: CodePageCallback, flags: u32) -> b32 : ---

// Counts the code pages C gives it, through context.user_data
count_code_page #calling_convention(.c) :: fn(code_page: cstring) -> b32 {
    count :: cast[ptr[mut u64]](context.user_data)
    count^ += 1
    return true
}

main :: fn() -> int {
    if lstrlenA("hello") != 5 {
        return 1
    }
    // None is null: the program's own module
    if GetModuleHandleA(null) == null {
        return 2
    }
    if GetModuleHandleA("kernel32.dll") == null {
        return 3
    }
    frequency : i64 = 0
    if !QueryPerformanceFrequency(&frequency) || frequency <= 0 {
        return 4
    }
    // Without a buffer it gives false, and the size the name needs
    size : u32 = 0
    if GetComputerNameA(null, &size) || size == 0 {
        return 5
    }
    count := runtime.new(u64)
    push_context with_count (user_data = cast[rawptr](count)) {
        // CP_INSTALLED
        if !EnumSystemCodePagesA(count_code_page, 1) {
            return 6
        }
    }
    if count^ == 0 {
        return 7
    }
    return 42
}
