package atomic

import intrinsics from "base"

// i8 atomics

atomic_add_i8 :: fn(target: ptr[mut i8], value: i8) -> i8 {
    return interlocked_exchange_add_i8(target, value)
}

atomic_sub_i8 :: fn(target: ptr[mut i8], value: i8) -> i8 {
    return interlocked_exchange_add_i8(target, -value)
}

atomic_increment_i8 :: fn(target: ptr[mut i8]) -> i8 {
    return interlocked_increment_i8(target)
}

atomic_decrement_i8 :: fn(target: ptr[mut i8]) -> i8 {
    return interlocked_decrement_i8(target)
}

// i16 atomics

atomic_add_i16 :: fn(target: ptr[mut i16], value: i16) -> i16 {
    return interlocked_exchange_add_i16(target, value)
}

atomic_sub_i16 :: fn(target: ptr[mut i16], value: i16) -> i16 {
    return interlocked_exchange_add_i16(target, -value)
}

atomic_increment_i16 :: fn(target: ptr[mut i16]) -> i16 {
    return interlocked_increment_i16(target)
}

atomic_decrement_i16 :: fn(target: ptr[mut i16]) -> i16 {
    return interlocked_decrement_i16(target)
}

// i32 atomics

atomic_add_i32 :: fn(target: ptr[mut i32], value: i32) -> i32 {
    return interlocked_exchange_add_i32(target, value)
}

atomic_sub_i32 :: fn(target: ptr[mut i32], value: i32) -> i32 {
    return interlocked_exchange_add_i32(target, -value)
}

atomic_increment_i32 :: fn(target: ptr[mut i32]) -> i32 {
    return interlocked_increment_i32(target)
}

atomic_decrement_i32 :: fn(target: ptr[mut i32]) -> i32 {
    return interlocked_decrement_i32(target)
}

// i64 atomics

atomic_add_i64 :: fn(target: ptr[mut i64], value: i64) -> i64 {
    return interlocked_exchange_add_i64(target, value)
}

atomic_sub_i64 :: fn(target: ptr[mut i64], value: i64) -> i64 {
    return interlocked_exchange_add_i64(target, -value)
}

atomic_increment_i64 :: fn(target: ptr[mut i64]) -> i64 {
    return interlocked_increment_i64(target)
}

atomic_decrement_i64 :: fn(target: ptr[mut i64]) -> i64 {
    return interlocked_decrement_i64(target)
}

// i128 atomics

atomic_add_i128 :: fn(target: ptr[mut i128], value: i128) -> i128 {
    return interlocked_exchange_add_i128(target, value)
}

atomic_sub_i128 :: fn(target: ptr[mut i128], value: i128) -> i128 {
    return interlocked_exchange_add_i128(target, -value)
}

atomic_increment_i128 :: fn(target: ptr[mut i128]) -> i128 {
    return interlocked_increment_i128(target)
}

atomic_decrement_i128 :: fn(target: ptr[mut i128]) -> i128 {
    return interlocked_decrement_i128(target)
}

// int atomics

atomic_add_int :: fn(target: ptr[mut int], value: int) -> int {
    return interlocked_exchange_add_int(target, value)
}

atomic_sub_int :: fn(target: ptr[mut int], value: int) -> int {
    return interlocked_exchange_add_int(target, -value)
}

atomic_increment_int :: fn(target: ptr[mut int]) -> int {
    return interlocked_increment_int(target)
}

atomic_decrement_int :: fn(target: ptr[mut int]) -> int {
    return interlocked_decrement_int(target)
}

// uint atomics

atomic_add_uint :: fn(target: ptr[mut uint], value: uint) -> uint {
    return interlocked_exchange_add_uint(target, value)
}

atomic_sub_uint :: fn(target: ptr[mut uint], value: uint) -> uint {
    return interlocked_exchange_add_uint(target, -value)
}

atomic_increment_uint :: fn(target: ptr[mut uint]) -> uint {
    return interlocked_increment_uint(target)
}

atomic_decrement_uint :: fn(target: ptr[mut uint]) -> uint {
    return interlocked_decrement_uint(target)
}

// uintptr atomics

atomic_add_uintptr :: fn(target: ptr[mut uintptr], value: uintptr) -> uintptr {
    return interlocked_exchange_add_uintptr(target, value)
}

atomic_sub_uintptr :: fn(target: ptr[mut uintptr], value: uintptr) -> uintptr {
    return interlocked_exchange_add_uintptr(target, -value)
}

atomic_increment_uintptr :: fn(target: ptr[mut uintptr]) -> uintptr {
    return interlocked_increment_uintptr(target)
}

atomic_decrement_uintptr :: fn(target: ptr[mut uintptr]) -> uintptr {
    return interlocked_decrement_uintptr(target)
}
