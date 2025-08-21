package intrinsics

/*
 * Returns the location that the current function call will return to once
 * done.
 * Intended for fiber schedulers.
 */
get_return_address : fn() -> rawptr : ---
/*
 * Sets the location that the current function will return to once done.
 * Only valid for functions that don't have any return values.
 * Intended for fiber schedulers, in general this is wildly unsafe to use.
 */
set_return_address : fn(base_pointer: rawptr) : ---

interlocked_and_i8 : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_and_i8_acquire : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_and_i8_no_fence : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_and_i8_release : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_compare_exchange_i8 : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> i8 : ---
interlocked_compare_exchange_i8_acquire : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> i8 : ---
interlocked_compare_exchange_i8_no_fence : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> i8 : ---
interlocked_compare_exchange_i8_release : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> i8 : ---
interlocked_decrement_i8 : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_exchange_i8 : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_i8_acquire : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_i8_no_fence : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_i8_release : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_add_i8 : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_add_i8_acquire : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_add_i8_no_fence : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_exchange_add_i8_release : fn(target: ptr[mut i8], value: i8) -> i8 : ---
interlocked_increment_i8 : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_or_i8 : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_or_i8_acquire : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_or_i8_no_fence : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_or_i8_release : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_xor_i8 : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_xor_i8_acquire : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_xor_i8_no_fence : fn(target: ptr[mut i8]) -> i8 : ---
interlocked_xor_i8_release : fn(target: ptr[mut i8]) -> i8 : ---

interlocked_and_i16 : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_and_i16_acquire : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_and_i16_no_fence : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_and_i16_release : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_compare_exchange_i16 : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> i16 : ---
interlocked_compare_exchange_i16_acquire : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> i16 : ---
interlocked_compare_exchange_i16_no_fence : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> i16 : ---
interlocked_compare_exchange_i16_release : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> i16 : ---
interlocked_decrement_i16 : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_exchange_i16 : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_i16_acquire : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_i16_no_fence : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_i16_release : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_add_i16 : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_add_i16_acquire : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_add_i16_no_fence : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_exchange_add_i16_release : fn(target: ptr[mut i16], value: i16) -> i16 : ---
interlocked_increment_i16 : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_or_i16 : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_or_i16_acquire : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_or_i16_no_fence : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_or_i16_release : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_xor_i16 : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_xor_i16_acquire : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_xor_i16_no_fence : fn(target: ptr[mut i16]) -> i16 : ---
interlocked_xor_i16_release : fn(target: ptr[mut i16]) -> i16 : ---

interlocked_and_i32 : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_and_i32_acquire : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_and_i32_no_fence : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_and_i32_release : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_compare_exchange_i32 : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> i32 : ---
interlocked_compare_exchange_i32_acquire : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> i32 : ---
interlocked_compare_exchange_i32_no_fence : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> i32 : ---
interlocked_compare_exchange_i32_release : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> i32 : ---
interlocked_decrement_i32 : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_exchange_i32 : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_i32_acquire : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_i32_no_fence : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_i32_release : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_add_i32 : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_add_i32_acquire : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_add_i32_no_fence : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_exchange_add_i32_release : fn(target: ptr[mut i32], value: i32) -> i32 : ---
interlocked_increment_i32 : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_or_i32 : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_or_i32_acquire : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_or_i32_no_fence : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_or_i32_release : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_xor_i32 : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_xor_i32_acquire : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_xor_i32_no_fence : fn(target: ptr[mut i32]) -> i32 : ---
interlocked_xor_i32_release : fn(target: ptr[mut i32]) -> i32 : ---

interlocked_and_i64 : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_and_i64_acquire : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_and_i64_no_fence : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_and_i64_release : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_compare_exchange_i64 : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> i64 : ---
interlocked_compare_exchange_i64_acquire : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> i64 : ---
interlocked_compare_exchange_i64_no_fence : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> i64 : ---
interlocked_compare_exchange_i64_release : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> i64 : ---
interlocked_decrement_i64 : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_exchange_i64 : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_i64_acquire : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_i64_no_fence : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_i64_release : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_add_i64 : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_add_i64_acquire : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_add_i64_no_fence : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_exchange_add_i64_release : fn(target: ptr[mut i64], value: i64) -> i64 : ---
interlocked_increment_i64 : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_or_i64 : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_or_i64_acquire : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_or_i64_no_fence : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_or_i64_release : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_xor_i64 : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_xor_i64_acquire : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_xor_i64_no_fence : fn(target: ptr[mut i64]) -> i64 : ---
interlocked_xor_i64_release : fn(target: ptr[mut i64]) -> i64 : ---

interlocked_and_i128 : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_and_i128_acquire : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_and_i128_no_fence : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_and_i128_release : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_compare_exchange_i128 : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> i128 : ---
interlocked_compare_exchange_i128_acquire : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> i128 : ---
interlocked_compare_exchange_i128_no_fence : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> i128 : ---
interlocked_compare_exchange_i128_release : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> i128 : ---
interlocked_decrement_i128 : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_exchange_i128 : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_i128_acquire : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_i128_no_fence : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_i128_release : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_add_i128 : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_add_i128_acquire : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_add_i128_no_fence : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_exchange_add_i128_release : fn(target: ptr[mut i128], value: i128) -> i128 : ---
interlocked_increment_i128 : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_or_i128 : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_or_i128_acquire : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_or_i128_no_fence : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_or_i128_release : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_xor_i128 : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_xor_i128_acquire : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_xor_i128_no_fence : fn(target: ptr[mut i128]) -> i128 : ---
interlocked_xor_i128_release : fn(target: ptr[mut i128]) -> i128 : ---

interlocked_and_int : fn(target: ptr[mut int]) -> int : ---
interlocked_and_int_acquire : fn(target: ptr[mut int]) -> int : ---
interlocked_and_int_no_fence : fn(target: ptr[mut int]) -> int : ---
interlocked_and_int_release : fn(target: ptr[mut int]) -> int : ---
interlocked_compare_exchange_int : fn(target: ptr[mut int], exchange: int, expected: int) -> int : ---
interlocked_compare_exchange_int_acquire : fn(target: ptr[mut int], exchange: int, expected: int) -> int : ---
interlocked_compare_exchange_int_no_fence : fn(target: ptr[mut int], exchange: int, expected: int) -> int : ---
interlocked_compare_exchange_int_release : fn(target: ptr[mut int], exchange: int, expected: int) -> int : ---
interlocked_decrement_int : fn(target: ptr[mut int]) -> int : ---
interlocked_exchange_int : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_int_acquire : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_int_no_fence : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_int_release : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_add_int : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_add_int_acquire : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_add_int_no_fence : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_exchange_add_int_release : fn(target: ptr[mut int], value: int) -> int : ---
interlocked_increment_int : fn(target: ptr[mut int]) -> int : ---
interlocked_or_int : fn(target: ptr[mut int]) -> int : ---
interlocked_or_int_acquire : fn(target: ptr[mut int]) -> int : ---
interlocked_or_int_no_fence : fn(target: ptr[mut int]) -> int : ---
interlocked_or_int_release : fn(target: ptr[mut int]) -> int : ---
interlocked_xor_int : fn(target: ptr[mut int]) -> int : ---
interlocked_xor_int_acquire : fn(target: ptr[mut int]) -> int : ---
interlocked_xor_int_no_fence : fn(target: ptr[mut int]) -> int : ---
interlocked_xor_int_release : fn(target: ptr[mut int]) -> int : ---

interlocked_and_uint : fn(target: ptr[mut uint]) -> uint : ---
interlocked_and_uint_acquire : fn(target: ptr[mut uint]) -> uint : ---
interlocked_and_uint_no_fence : fn(target: ptr[mut uint]) -> uint : ---
interlocked_and_uint_release : fn(target: ptr[mut uint]) -> uint : ---
interlocked_compare_exchange_uint : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> uint : ---
interlocked_compare_exchange_uint_acquire : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> uint : ---
interlocked_compare_exchange_uint_no_fence : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> uint : ---
interlocked_compare_exchange_uint_release : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> uint : ---
interlocked_decrement_uint : fn(target: ptr[mut uint]) -> uint : ---
interlocked_exchange_uint : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_uint_acquire : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_uint_no_fence : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_uint_release : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_add_uint : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_add_uint_acquire : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_add_uint_no_fence : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_exchange_add_uint_release : fn(target: ptr[mut uint], value: uint) -> uint : ---
interlocked_increment_uint : fn(target: ptr[mut uint]) -> uint : ---
interlocked_or_uint : fn(target: ptr[mut uint]) -> uint : ---
interlocked_or_uint_acquire : fn(target: ptr[mut uint]) -> uint : ---
interlocked_or_uint_no_fence : fn(target: ptr[mut uint]) -> uint : ---
interlocked_or_uint_release : fn(target: ptr[mut uint]) -> uint : ---
interlocked_xor_uint : fn(target: ptr[mut uint]) -> uint : ---
interlocked_xor_uint_acquire : fn(target: ptr[mut uint]) -> uint : ---
interlocked_xor_uint_no_fence : fn(target: ptr[mut uint]) -> uint : ---
interlocked_xor_uint_release : fn(target: ptr[mut uint]) -> uint : ---

interlocked_and_uintptr : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_and_uintptr_acquire : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_and_uintptr_no_fence : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_and_uintptr_release : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_compare_exchange_uintptr : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> uintptr : ---
interlocked_compare_exchange_uintptr_acquire : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> uintptr : ---
interlocked_compare_exchange_uintptr_no_fence : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> uintptr : ---
interlocked_compare_exchange_uintptr_release : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> uintptr : ---
interlocked_decrement_uintptr : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_exchange_uintptr : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_uintptr_acquire : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_uintptr_no_fence : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_uintptr_release : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_add_uintptr : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_add_uintptr_acquire : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_add_uintptr_no_fence : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_exchange_add_uintptr_release : fn(target: ptr[mut uintptr], value: uintptr) -> uintptr : ---
interlocked_increment_uintptr : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_or_uintptr : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_or_uintptr_acquire : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_or_uintptr_no_fence : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_or_uintptr_release : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_xor_uintptr : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_xor_uintptr_acquire : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_xor_uintptr_no_fence : fn(target: ptr[mut uintptr]) -> uintptr : ---
interlocked_xor_uintptr_release : fn(target: ptr[mut uintptr]) -> uintptr : ---
