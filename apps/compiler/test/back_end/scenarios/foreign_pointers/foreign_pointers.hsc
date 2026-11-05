/*
 * #foreign functions taking pointers that aren't ptr[T] or rawptr, which are each one register as C sees them:
 * a cstring, an optional pointer and an optional cstring (null for None), and a function value C calls back.
 * Run with hemera --test.
 */
package foreign_pointers

import runtime from "base"
import testing from "std"

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

passes_a_cstring #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, lstrlenA("hello"), 5, "C finds the string's five bytes before its terminator")
    return .Ok
}

passes_optional_pointers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, GetModuleHandleA(null) != null, "an optional cstring's None is null, which names the program's own module")
    testing.expect(t, GetModuleHandleA("kernel32.dll") != null, "an optional cstring holding a name reaches C as that name")
    frequency : i64 = 0
    testing.expect(t, cast[bool](QueryPerformanceFrequency(&frequency)), "an optional pointer holding one reaches C as that pointer")
    testing.expect_gt(t, frequency, 0, "C wrote the counter's frequency through the pointer")
    // Without a buffer it gives false, and the size the name needs
    size : u32 = 0
    testing.expect(t, !cast[bool](GetComputerNameA(null, &size)), "a null buffer is too small for the computer's name")
    testing.expect_ne(t, size, 0, "C wrote the size the name needs through the pointer after the null one")
    return .Ok
}

passes_a_function_c_calls_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    count := runtime.new(u64)
    defer runtime.free(count)
    enumerated := false
    push_context with_count (user_data = cast[rawptr](count)) {
        // CP_INSTALLED
        enumerated = cast[bool](EnumSystemCodePagesA(count_code_page, 1))
    }
    testing.expect(t, enumerated, "C can call the function value back")
    testing.expect_ne(t, count^, 0, "the callback, with this context, counted each installed code page")
    return .Ok
}

