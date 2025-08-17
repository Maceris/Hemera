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

interlocked_and_i8 : fn(target: ptr[mut i8]) : ---
interlocked_and_i8_acquire : fn(target: ptr[mut i8]) : ---
interlocked_and_i8_no_fence : fn(target: ptr[mut i8]) : ---
interlocked_and_i8_release : fn(target: ptr[mut i8]) : ---
interlocked_compare_exchange_i8 : fn(target: ptr[mut i8], exchange: i8, expected: i8) : ---
interlocked_compare_exchange_i8_acquire : fn(target: ptr[mut i8], exchange: i8, expected: i8) : ---
interlocked_compare_exchange_i8_no_fence : fn(target: ptr[mut i8], exchange: i8, expected: i8) : ---
interlocked_compare_exchange_i8_release : fn(target: ptr[mut i8], exchange: i8, expected: i8) : ---
interlocked_decrement_i8 : fn(target: ptr[mut i8]) : ---
interlocked_exchange_i8 : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_i8_acquire : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_i8_no_fence : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_i8_release : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_add_i8 : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_add_i8_acquire : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_add_i8_no_fence : fn(target: ptr[mut i8], value: i8) : ---
interlocked_exchange_add_i8_release : fn(target: ptr[mut i8], value: i8) : ---
interlocked_increment_i8 : fn(target: ptr[mut i8]) : ---
interlocked_or_i8 : fn(target: ptr[mut i8]) : ---
interlocked_or_i8_acquire : fn(target: ptr[mut i8]) : ---
interlocked_or_i8_no_fence : fn(target: ptr[mut i8]) : ---
interlocked_or_i8_release : fn(target: ptr[mut i8]) : ---
interlocked_xor_i8 : fn(target: ptr[mut i8]) : ---
interlocked_xor_i8_acquire : fn(target: ptr[mut i8]) : ---
interlocked_xor_i8_no_fence : fn(target: ptr[mut i8]) : ---
interlocked_xor_i8_release : fn(target: ptr[mut i8]) : ---

interlocked_and_i16 : fn(target: ptr[mut i16]) : ---
interlocked_and_i16_acquire : fn(target: ptr[mut i16]) : ---
interlocked_and_i16_no_fence : fn(target: ptr[mut i16]) : ---
interlocked_and_i16_release : fn(target: ptr[mut i16]) : ---
interlocked_compare_exchange_i16 : fn(target: ptr[mut i16], exchange: i16, expected: i16) : ---
interlocked_compare_exchange_i16_acquire : fn(target: ptr[mut i16], exchange: i16, expected: i16) : ---
interlocked_compare_exchange_i16_no_fence : fn(target: ptr[mut i16], exchange: i16, expected: i16) : ---
interlocked_compare_exchange_i16_release : fn(target: ptr[mut i16], exchange: i16, expected: i16) : ---
interlocked_decrement_i16 : fn(target: ptr[mut i16]) : ---
interlocked_exchange_i16 : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_i16_acquire : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_i16_no_fence : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_i16_release : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_add_i16 : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_add_i16_acquire : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_add_i16_no_fence : fn(target: ptr[mut i16], value: i16) : ---
interlocked_exchange_add_i16_release : fn(target: ptr[mut i16], value: i16) : ---
interlocked_increment_i16 : fn(target: ptr[mut i16]) : ---
interlocked_or_i16 : fn(target: ptr[mut i16]) : ---
interlocked_or_i16_acquire : fn(target: ptr[mut i16]) : ---
interlocked_or_i16_no_fence : fn(target: ptr[mut i16]) : ---
interlocked_or_i16_release : fn(target: ptr[mut i16]) : ---
interlocked_xor_i16 : fn(target: ptr[mut i16]) : ---
interlocked_xor_i16_acquire : fn(target: ptr[mut i16]) : ---
interlocked_xor_i16_no_fence : fn(target: ptr[mut i16]) : ---
interlocked_xor_i16_release : fn(target: ptr[mut i16]) : ---

interlocked_and_i32 : fn(target: ptr[mut i32]) : ---
interlocked_and_i32_acquire : fn(target: ptr[mut i32]) : ---
interlocked_and_i32_no_fence : fn(target: ptr[mut i32]) : ---
interlocked_and_i32_release : fn(target: ptr[mut i32]) : ---
interlocked_compare_exchange_i32 : fn(target: ptr[mut i32], exchange: i32, expected: i32) : ---
interlocked_compare_exchange_i32_acquire : fn(target: ptr[mut i32], exchange: i32, expected: i32) : ---
interlocked_compare_exchange_i32_no_fence : fn(target: ptr[mut i32], exchange: i32, expected: i32) : ---
interlocked_compare_exchange_i32_release : fn(target: ptr[mut i32], exchange: i32, expected: i32) : ---
interlocked_decrement_i32 : fn(target: ptr[mut i32]) : ---
interlocked_exchange_i32 : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_i32_acquire : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_i32_no_fence : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_i32_release : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_add_i32 : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_add_i32_acquire : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_add_i32_no_fence : fn(target: ptr[mut i32], value: i32) : ---
interlocked_exchange_add_i32_release : fn(target: ptr[mut i32], value: i32) : ---
interlocked_increment_i32 : fn(target: ptr[mut i32]) : ---
interlocked_or_i32 : fn(target: ptr[mut i32]) : ---
interlocked_or_i32_acquire : fn(target: ptr[mut i32]) : ---
interlocked_or_i32_no_fence : fn(target: ptr[mut i32]) : ---
interlocked_or_i32_release : fn(target: ptr[mut i32]) : ---
interlocked_xor_i32 : fn(target: ptr[mut i32]) : ---
interlocked_xor_i32_acquire : fn(target: ptr[mut i32]) : ---
interlocked_xor_i32_no_fence : fn(target: ptr[mut i32]) : ---
interlocked_xor_i32_release : fn(target: ptr[mut i32]) : ---

interlocked_and_i64 : fn(target: ptr[mut i64]) : ---
interlocked_and_i64_acquire : fn(target: ptr[mut i64]) : ---
interlocked_and_i64_no_fence : fn(target: ptr[mut i64]) : ---
interlocked_and_i64_release : fn(target: ptr[mut i64]) : ---
interlocked_compare_exchange_i64 : fn(target: ptr[mut i64], exchange: i64, expected: i64) : ---
interlocked_compare_exchange_i64_acquire : fn(target: ptr[mut i64], exchange: i64, expected: i64) : ---
interlocked_compare_exchange_i64_no_fence : fn(target: ptr[mut i64], exchange: i64, expected: i64) : ---
interlocked_compare_exchange_i64_release : fn(target: ptr[mut i64], exchange: i64, expected: i64) : ---
interlocked_decrement_i64 : fn(target: ptr[mut i64]) : ---
interlocked_exchange_i64 : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_i64_acquire : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_i64_no_fence : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_i64_release : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_add_i64 : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_add_i64_acquire : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_add_i64_no_fence : fn(target: ptr[mut i64], value: i64) : ---
interlocked_exchange_add_i64_release : fn(target: ptr[mut i64], value: i64) : ---
interlocked_increment_i64 : fn(target: ptr[mut i64]) : ---
interlocked_or_i64 : fn(target: ptr[mut i64]) : ---
interlocked_or_i64_acquire : fn(target: ptr[mut i64]) : ---
interlocked_or_i64_no_fence : fn(target: ptr[mut i64]) : ---
interlocked_or_i64_release : fn(target: ptr[mut i64]) : ---
interlocked_xor_i64 : fn(target: ptr[mut i64]) : ---
interlocked_xor_i64_acquire : fn(target: ptr[mut i64]) : ---
interlocked_xor_i64_no_fence : fn(target: ptr[mut i64]) : ---
interlocked_xor_i64_release : fn(target: ptr[mut i64]) : ---

interlocked_and_i128 : fn(target: ptr[mut i128]) : ---
interlocked_and_i128_acquire : fn(target: ptr[mut i128]) : ---
interlocked_and_i128_no_fence : fn(target: ptr[mut i128]) : ---
interlocked_and_i128_release : fn(target: ptr[mut i128]) : ---
interlocked_compare_exchange_i128 : fn(target: ptr[mut i128], exchange: i128, expected: i128) : ---
interlocked_compare_exchange_i128_acquire : fn(target: ptr[mut i128], exchange: i128, expected: i128) : ---
interlocked_compare_exchange_i128_no_fence : fn(target: ptr[mut i128], exchange: i128, expected: i128) : ---
interlocked_compare_exchange_i128_release : fn(target: ptr[mut i128], exchange: i128, expected: i128) : ---
interlocked_decrement_i128 : fn(target: ptr[mut i128]) : ---
interlocked_exchange_i128 : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_i128_acquire : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_i128_no_fence : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_i128_release : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_add_i128 : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_add_i128_acquire : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_add_i128_no_fence : fn(target: ptr[mut i128], value: i128) : ---
interlocked_exchange_add_i128_release : fn(target: ptr[mut i128], value: i128) : ---
interlocked_increment_i128 : fn(target: ptr[mut i128]) : ---
interlocked_or_i128 : fn(target: ptr[mut i128]) : ---
interlocked_or_i128_acquire : fn(target: ptr[mut i128]) : ---
interlocked_or_i128_no_fence : fn(target: ptr[mut i128]) : ---
interlocked_or_i128_release : fn(target: ptr[mut i128]) : ---
interlocked_xor_i128 : fn(target: ptr[mut i128]) : ---
interlocked_xor_i128_acquire : fn(target: ptr[mut i128]) : ---
interlocked_xor_i128_no_fence : fn(target: ptr[mut i128]) : ---
interlocked_xor_i128_release : fn(target: ptr[mut i128]) : ---
