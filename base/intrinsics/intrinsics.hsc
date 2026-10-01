package intrinsics

atomic_load_i8           : fn(target: ptr[i8]               ) -> i8 : ---
atomic_load_i8_acquire   : fn(target: ptr[i8]               ) -> i8 : ---
atomic_load_i8_no_fence  : fn(target: ptr[i8]               ) -> i8 : ---
atomic_store_i8          : fn(target: ptr[mut i8], value: i8)       : ---
atomic_store_i8_release  : fn(target: ptr[mut i8], value: i8)       : ---
atomic_store_i8_no_fence : fn(target: ptr[mut i8], value: i8)       : ---

atomic_load_u8           : fn(target: ptr[u8]               ) -> u8 : ---
atomic_load_u8_acquire   : fn(target: ptr[u8]               ) -> u8 : ---
atomic_load_u8_no_fence  : fn(target: ptr[u8]               ) -> u8 : ---
atomic_store_u8          : fn(target: ptr[mut u8], value: u8)       : ---
atomic_store_u8_release  : fn(target: ptr[mut u8], value: u8)       : ---
atomic_store_u8_no_fence : fn(target: ptr[mut u8], value: u8)       : ---

atomic_load_i16           : fn(target: ptr[i16]                ) -> i16 : ---
atomic_load_i16_acquire   : fn(target: ptr[i16]                ) -> i16 : ---
atomic_load_i16_no_fence  : fn(target: ptr[i16]                ) -> i16 : ---
atomic_store_i16          : fn(target: ptr[mut i16], value: i16)        : ---
atomic_store_i16_release  : fn(target: ptr[mut i16], value: i16)        : ---
atomic_store_i16_no_fence : fn(target: ptr[mut i16], value: i16)        : ---

atomic_load_u16           : fn(target: ptr[u16]                ) -> u16 : ---
atomic_load_u16_acquire   : fn(target: ptr[u16]                ) -> u16 : ---
atomic_load_u16_no_fence  : fn(target: ptr[u16]                ) -> u16 : ---
atomic_store_u16          : fn(target: ptr[mut u16], value: u16)        : ---
atomic_store_u16_release  : fn(target: ptr[mut u16], value: u16)        : ---
atomic_store_u16_no_fence : fn(target: ptr[mut u16], value: u16)        : ---

atomic_load_i32           : fn(target: ptr[i32]                ) -> i32 : ---
atomic_load_i32_acquire   : fn(target: ptr[i32]                ) -> i32 : ---
atomic_load_i32_no_fence  : fn(target: ptr[i32]                ) -> i32 : ---
atomic_store_i32          : fn(target: ptr[mut i32], value: i32)        : ---
atomic_store_i32_release  : fn(target: ptr[mut i32], value: i32)        : ---
atomic_store_i32_no_fence : fn(target: ptr[mut i32], value: i32)        : ---

atomic_load_u32           : fn(target: ptr[u32]                ) -> u32 : ---
atomic_load_u32_acquire   : fn(target: ptr[u32]                ) -> u32 : ---
atomic_load_u32_no_fence  : fn(target: ptr[u32]                ) -> u32 : ---
atomic_store_u32          : fn(target: ptr[mut u32], value: u32)        : ---
atomic_store_u32_release  : fn(target: ptr[mut u32], value: u32)        : ---
atomic_store_u32_no_fence : fn(target: ptr[mut u32], value: u32)        : ---

atomic_load_i64           : fn(target: ptr[i64]                ) -> i64 : ---
atomic_load_i64_acquire   : fn(target: ptr[i64]                ) -> i64 : ---
atomic_load_i64_no_fence  : fn(target: ptr[i64]                ) -> i64 : ---
atomic_store_i64          : fn(target: ptr[mut i64], value: i64)        : ---
atomic_store_i64_release  : fn(target: ptr[mut i64], value: i64)        : ---
atomic_store_i64_no_fence : fn(target: ptr[mut i64], value: i64)        : ---

atomic_load_u64           : fn(target: ptr[u64]                ) -> u64 : ---
atomic_load_u64_acquire   : fn(target: ptr[u64]                ) -> u64 : ---
atomic_load_u64_no_fence  : fn(target: ptr[u64]                ) -> u64 : ---
atomic_store_u64          : fn(target: ptr[mut u64], value: u64)        : ---
atomic_store_u64_release  : fn(target: ptr[mut u64], value: u64)        : ---
atomic_store_u64_no_fence : fn(target: ptr[mut u64], value: u64)        : ---

atomic_load_i128           : fn(target: ptr[i128]                 ) -> i128 : ---
atomic_load_i128_acquire   : fn(target: ptr[i128]                 ) -> i128 : ---
atomic_load_i128_no_fence  : fn(target: ptr[i128]                 ) -> i128 : ---
atomic_store_i128          : fn(target: ptr[mut i128], value: i128)         : ---
atomic_store_i128_release  : fn(target: ptr[mut i128], value: i128)         : ---
atomic_store_i128_no_fence : fn(target: ptr[mut i128], value: i128)         : ---

atomic_load_u128           : fn(target: ptr[u128]                 ) -> u128 : ---
atomic_load_u128_acquire   : fn(target: ptr[u128]                 ) -> u128 : ---
atomic_load_u128_no_fence  : fn(target: ptr[u128]                 ) -> u128 : ---
atomic_store_u128          : fn(target: ptr[mut u128], value: u128)         : ---
atomic_store_u128_release  : fn(target: ptr[mut u128], value: u128)         : ---
atomic_store_u128_no_fence : fn(target: ptr[mut u128], value: u128)         : ---

atomic_load_int           : fn(target: ptr[int]                ) -> int : ---
atomic_load_int_acquire   : fn(target: ptr[int]                ) -> int : ---
atomic_load_int_no_fence  : fn(target: ptr[int]                ) -> int : ---
atomic_store_int          : fn(target: ptr[mut int], value: int)        : ---
atomic_store_int_release  : fn(target: ptr[mut int], value: int)        : ---
atomic_store_int_no_fence : fn(target: ptr[mut int], value: int)        : ---

atomic_load_uint           : fn(target: ptr[uint]                 ) -> uint : ---
atomic_load_uint_acquire   : fn(target: ptr[uint]                 ) -> uint : ---
atomic_load_uint_no_fence  : fn(target: ptr[uint]                 ) -> uint : ---
atomic_store_uint          : fn(target: ptr[mut uint], value: uint)         : ---
atomic_store_uint_release  : fn(target: ptr[mut uint], value: uint)         : ---
atomic_store_uint_no_fence : fn(target: ptr[mut uint], value: uint)         : ---

atomic_load_uintptr           : fn(target: ptr[uintptr]                    ) -> uintptr : ---
atomic_load_uintptr_acquire   : fn(target: ptr[uintptr]                    ) -> uintptr : ---
atomic_load_uintptr_no_fence  : fn(target: ptr[uintptr]                    ) -> uintptr : ---
atomic_store_uintptr          : fn(target: ptr[mut uintptr], value: uintptr)            : ---
atomic_store_uintptr_release  : fn(target: ptr[mut uintptr], value: uintptr)            : ---
atomic_store_uintptr_no_fence : fn(target: ptr[mut uintptr], value: uintptr)            : ---

/*
 * Later loads/stores cannot move before earlier loads, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_acquire : fn() : ---
/*
 * Later loads/stores cannot move before earlier loads, and also
 * earlier loads/stores cannot move after later stores, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_acquire_release : fn() : ---
/*
 * Earlier loads/stores cannot move after later stores, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_release : fn() : ---
/*
 * A full barrier, including store->load ordering, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_sequentially_consistent : fn() : ---

/*
 * Later loads/stores cannot move before earlier loads.
 */
fence_acquire : fn() : ---
/*
 * Later loads/stores cannot move before earlier loads, and also
 * earlier loads/stores cannot move after later stores.
 */
fence_acquire_release : fn() : ---
/*
 * Earlier loads/stores cannot move after later stores.
 */
fence_release : fn() : ---
/*
 * A full barrier, including store->load ordering.
 */
fence_sequentially_consistent : fn() : ---

/*
 * Returns the location that the current function call will return to once
 * done.
 * Intended for fiber schedulers.
 */
get_return_address : fn() -> rawptr : ---

/*
 * Fetch the current stack pointer. Intended for fiber schedulers.
 */
get_stack_pointer : fn() -> rawptr : ---
/*
 * Fetch the current stack base pointer. Intended for fiber schedulers.
 */
get_stack_base_pointer : fn() -> rawptr : ---

interlocked_and_i8                              : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_and_i8_acquire                      : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_and_i8_acquire_release              : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_and_i8_no_fence                     : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_and_i8_release                      : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_compare_exchange_i8                 : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> (old: i8, success: bool) : ---
interlocked_compare_exchange_i8_acquire         : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> (old: i8, success: bool) : ---
interlocked_compare_exchange_i8_acquire_release : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> (old: i8, success: bool) : ---
interlocked_compare_exchange_i8_no_fence        : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> (old: i8, success: bool) : ---
interlocked_compare_exchange_i8_release         : fn(target: ptr[mut i8], exchange: i8, expected: i8) -> (old: i8, success: bool) : ---
interlocked_decrement_i8                        : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_decrement_i8_acquire                : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_decrement_i8_acquire_release        : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_decrement_i8_no_fence               : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_decrement_i8_release                : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_exchange_i8                         : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_i8_acquire                 : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_i8_acquire_release         : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_i8_no_fence                : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_i8_release                 : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_add_i8                     : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_add_i8_acquire             : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_add_i8_acquire_release     : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_add_i8_no_fence            : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_exchange_add_i8_release             : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_increment_i8                        : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_increment_i8_acquire                : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_increment_i8_acquire_release        : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_increment_i8_no_fence               : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_increment_i8_release                : fn(target: ptr[mut i8]                            ) -> (old: i8)                : ---
interlocked_or_i8                               : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_or_i8_acquire                       : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_or_i8_acquire_release               : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_or_i8_no_fence                      : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_or_i8_release                       : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_xor_i8                              : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_xor_i8_acquire                      : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_xor_i8_acquire_release              : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_xor_i8_no_fence                     : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---
interlocked_xor_i8_release                      : fn(target: ptr[mut i8], value: i8                 ) -> i8                       : ---

interlocked_and_u8                              : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_and_u8_acquire                      : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_and_u8_acquire_release              : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_and_u8_no_fence                     : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_and_u8_release                      : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_compare_exchange_u8                 : fn(target: ptr[mut u8], exchange: u8, expected: u8) -> (old: u8, success: bool) : ---
interlocked_compare_exchange_u8_acquire         : fn(target: ptr[mut u8], exchange: u8, expected: u8) -> (old: u8, success: bool) : ---
interlocked_compare_exchange_u8_acquire_release : fn(target: ptr[mut u8], exchange: u8, expected: u8) -> (old: u8, success: bool) : ---
interlocked_compare_exchange_u8_no_fence        : fn(target: ptr[mut u8], exchange: u8, expected: u8) -> (old: u8, success: bool) : ---
interlocked_compare_exchange_u8_release         : fn(target: ptr[mut u8], exchange: u8, expected: u8) -> (old: u8, success: bool) : ---
interlocked_decrement_u8                        : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_decrement_u8_acquire                : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_decrement_u8_acquire_release        : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_decrement_u8_no_fence               : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_decrement_u8_release                : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_exchange_u8                         : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_u8_acquire                 : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_u8_acquire_release         : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_u8_no_fence                : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_u8_release                 : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_add_u8                     : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_add_u8_acquire             : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_add_u8_acquire_release     : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_add_u8_no_fence            : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_exchange_add_u8_release             : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_increment_u8                        : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_increment_u8_acquire                : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_increment_u8_acquire_release        : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_increment_u8_no_fence               : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_increment_u8_release                : fn(target: ptr[mut u8]                            ) -> (old: u8)                : ---
interlocked_or_u8                               : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_or_u8_acquire                       : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_or_u8_acquire_release               : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_or_u8_no_fence                      : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_or_u8_release                       : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_xor_u8                              : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_xor_u8_acquire                      : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_xor_u8_acquire_release              : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_xor_u8_no_fence                     : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---
interlocked_xor_u8_release                      : fn(target: ptr[mut u8], value: u8                 ) -> u8                       : ---

interlocked_and_i16                              : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_and_i16_acquire                      : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_and_i16_acquire_release              : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_and_i16_no_fence                     : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_and_i16_release                      : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_compare_exchange_i16                 : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> (old: i16, success: bool) : ---
interlocked_compare_exchange_i16_acquire         : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> (old: i16, success: bool) : ---
interlocked_compare_exchange_i16_acquire_release : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> (old: i16, success: bool) : ---
interlocked_compare_exchange_i16_no_fence        : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> (old: i16, success: bool) : ---
interlocked_compare_exchange_i16_release         : fn(target: ptr[mut i16], exchange: i16, expected: i16) -> (old: i16, success: bool) : ---
interlocked_decrement_i16                        : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_decrement_i16_acquire                : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_decrement_i16_acquire_release        : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_decrement_i16_no_fence               : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_decrement_i16_release                : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_exchange_i16                         : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_i16_acquire                 : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_i16_acquire_release         : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_i16_no_fence                : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_i16_release                 : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_add_i16                     : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_add_i16_acquire             : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_add_i16_acquire_release     : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_add_i16_no_fence            : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_exchange_add_i16_release             : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_increment_i16                        : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_increment_i16_acquire                : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_increment_i16_acquire_release        : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_increment_i16_no_fence               : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_increment_i16_release                : fn(target: ptr[mut i16]                              ) -> (old: i16)                : ---
interlocked_or_i16                               : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_or_i16_acquire                       : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_or_i16_acquire_release               : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_or_i16_no_fence                      : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_or_i16_release                       : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_xor_i16                              : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_xor_i16_acquire                      : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_xor_i16_acquire_release              : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_xor_i16_no_fence                     : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---
interlocked_xor_i16_release                      : fn(target: ptr[mut i16], value: i16                  ) -> i16                       : ---

interlocked_and_u16                              : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_and_u16_acquire                      : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_and_u16_acquire_release              : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_and_u16_no_fence                     : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_and_u16_release                      : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_compare_exchange_u16                 : fn(target: ptr[mut u16], exchange: u16, expected: u16) -> (old: u16, success: bool) : ---
interlocked_compare_exchange_u16_acquire         : fn(target: ptr[mut u16], exchange: u16, expected: u16) -> (old: u16, success: bool) : ---
interlocked_compare_exchange_u16_acquire_release : fn(target: ptr[mut u16], exchange: u16, expected: u16) -> (old: u16, success: bool) : ---
interlocked_compare_exchange_u16_no_fence        : fn(target: ptr[mut u16], exchange: u16, expected: u16) -> (old: u16, success: bool) : ---
interlocked_compare_exchange_u16_release         : fn(target: ptr[mut u16], exchange: u16, expected: u16) -> (old: u16, success: bool) : ---
interlocked_decrement_u16                        : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_decrement_u16_acquire                : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_decrement_u16_acquire_release        : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_decrement_u16_no_fence               : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_decrement_u16_release                : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_exchange_u16                         : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_u16_acquire                 : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_u16_acquire_release         : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_u16_no_fence                : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_u16_release                 : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_add_u16                     : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_add_u16_acquire             : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_add_u16_acquire_release     : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_add_u16_no_fence            : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_exchange_add_u16_release             : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_increment_u16                        : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_increment_u16_acquire                : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_increment_u16_acquire_release        : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_increment_u16_no_fence               : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_increment_u16_release                : fn(target: ptr[mut u16]                              ) -> (old: u16)                : ---
interlocked_or_u16                               : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_or_u16_acquire                       : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_or_u16_acquire_release               : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_or_u16_no_fence                      : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_or_u16_release                       : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_xor_u16                              : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_xor_u16_acquire                      : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_xor_u16_acquire_release              : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_xor_u16_no_fence                     : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---
interlocked_xor_u16_release                      : fn(target: ptr[mut u16], value: u16                  ) -> u16                       : ---

interlocked_and_i32                              : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_and_i32_acquire                      : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_and_i32_acquire_release              : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_and_i32_no_fence                     : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_and_i32_release                      : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_compare_exchange_i32                 : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> (old: i32, success: bool) : ---
interlocked_compare_exchange_i32_acquire         : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> (old: i32, success: bool) : ---
interlocked_compare_exchange_i32_acquire_release : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> (old: i32, success: bool) : ---
interlocked_compare_exchange_i32_no_fence        : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> (old: i32, success: bool) : ---
interlocked_compare_exchange_i32_release         : fn(target: ptr[mut i32], exchange: i32, expected: i32) -> (old: i32, success: bool) : ---
interlocked_decrement_i32                        : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_decrement_i32_acquire                : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_decrement_i32_acquire_release        : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_decrement_i32_no_fence               : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_decrement_i32_release                : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_exchange_i32                         : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_i32_acquire                 : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_i32_acquire_release         : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_i32_no_fence                : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_i32_release                 : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_add_i32                     : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_add_i32_acquire             : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_add_i32_acquire_release     : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_add_i32_no_fence            : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_exchange_add_i32_release             : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_increment_i32                        : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_increment_i32_acquire                : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_increment_i32_acquire_release        : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_increment_i32_no_fence               : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_increment_i32_release                : fn(target: ptr[mut i32]                              ) -> (old: i32)                : ---
interlocked_or_i32                               : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_or_i32_acquire                       : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_or_i32_acquire_release               : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_or_i32_no_fence                      : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_or_i32_release                       : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_xor_i32                              : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_xor_i32_acquire                      : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_xor_i32_acquire_release              : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_xor_i32_no_fence                     : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---
interlocked_xor_i32_release                      : fn(target: ptr[mut i32], value: i32                  ) -> i32                       : ---

interlocked_and_u32                              : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_and_u32_acquire                      : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_and_u32_acquire_release              : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_and_u32_no_fence                     : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_and_u32_release                      : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_compare_exchange_u32                 : fn(target: ptr[mut u32], exchange: u32, expected: u32) -> (old: u32, success: bool) : ---
interlocked_compare_exchange_u32_acquire         : fn(target: ptr[mut u32], exchange: u32, expected: u32) -> (old: u32, success: bool) : ---
interlocked_compare_exchange_u32_acquire_release : fn(target: ptr[mut u32], exchange: u32, expected: u32) -> (old: u32, success: bool) : ---
interlocked_compare_exchange_u32_no_fence        : fn(target: ptr[mut u32], exchange: u32, expected: u32) -> (old: u32, success: bool) : ---
interlocked_compare_exchange_u32_release         : fn(target: ptr[mut u32], exchange: u32, expected: u32) -> (old: u32, success: bool) : ---
interlocked_decrement_u32                        : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_decrement_u32_acquire                : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_decrement_u32_acquire_release        : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_decrement_u32_no_fence               : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_decrement_u32_release                : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_exchange_u32                         : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_u32_acquire                 : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_u32_acquire_release         : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_u32_no_fence                : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_u32_release                 : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_add_u32                     : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_add_u32_acquire             : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_add_u32_acquire_release     : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_add_u32_no_fence            : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_exchange_add_u32_release             : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_increment_u32                        : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_increment_u32_acquire                : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_increment_u32_acquire_release        : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_increment_u32_no_fence               : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_increment_u32_release                : fn(target: ptr[mut u32]                              ) -> (old: u32)                : ---
interlocked_or_u32                               : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_or_u32_acquire                       : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_or_u32_acquire_release               : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_or_u32_no_fence                      : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_or_u32_release                       : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_xor_u32                              : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_xor_u32_acquire                      : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_xor_u32_acquire_release              : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_xor_u32_no_fence                     : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---
interlocked_xor_u32_release                      : fn(target: ptr[mut u32], value: u32                  ) -> u32                       : ---

interlocked_and_i64                              : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_and_i64_acquire                      : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_and_i64_acquire_release              : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_and_i64_no_fence                     : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_and_i64_release                      : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_compare_exchange_i64                 : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> (old: i64, success: bool) : ---
interlocked_compare_exchange_i64_acquire         : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> (old: i64, success: bool) : ---
interlocked_compare_exchange_i64_acquire_release : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> (old: i64, success: bool) : ---
interlocked_compare_exchange_i64_no_fence        : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> (old: i64, success: bool) : ---
interlocked_compare_exchange_i64_release         : fn(target: ptr[mut i64], exchange: i64, expected: i64) -> (old: i64, success: bool) : ---
interlocked_decrement_i64                        : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_decrement_i64_acquire                : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_decrement_i64_acquire_release        : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_decrement_i64_no_fence               : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_decrement_i64_release                : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_exchange_i64                         : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_i64_acquire                 : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_i64_acquire_release         : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_i64_no_fence                : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_i64_release                 : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_add_i64                     : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_add_i64_acquire             : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_add_i64_acquire_release     : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_add_i64_no_fence            : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_exchange_add_i64_release             : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_increment_i64                        : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_increment_i64_acquire                : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_increment_i64_acquire_release        : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_increment_i64_no_fence               : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_increment_i64_release                : fn(target: ptr[mut i64]                              ) -> (old: i64)                : ---
interlocked_or_i64                               : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_or_i64_acquire                       : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_or_i64_acquire_release               : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_or_i64_no_fence                      : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_or_i64_release                       : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_xor_i64                              : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_xor_i64_acquire                      : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_xor_i64_acquire_release              : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_xor_i64_no_fence                     : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---
interlocked_xor_i64_release                      : fn(target: ptr[mut i64], value: i64                  ) -> i64                       : ---

interlocked_and_u64                              : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_and_u64_acquire                      : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_and_u64_acquire_release              : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_and_u64_no_fence                     : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_and_u64_release                      : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_compare_exchange_u64                 : fn(target: ptr[mut u64], exchange: u64, expected: u64) -> (old: u64, success: bool) : ---
interlocked_compare_exchange_u64_acquire         : fn(target: ptr[mut u64], exchange: u64, expected: u64) -> (old: u64, success: bool) : ---
interlocked_compare_exchange_u64_acquire_release : fn(target: ptr[mut u64], exchange: u64, expected: u64) -> (old: u64, success: bool) : ---
interlocked_compare_exchange_u64_no_fence        : fn(target: ptr[mut u64], exchange: u64, expected: u64) -> (old: u64, success: bool) : ---
interlocked_compare_exchange_u64_release         : fn(target: ptr[mut u64], exchange: u64, expected: u64) -> (old: u64, success: bool) : ---
interlocked_decrement_u64                        : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_decrement_u64_acquire                : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_decrement_u64_acquire_release        : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_decrement_u64_no_fence               : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_decrement_u64_release                : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_exchange_u64                         : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_u64_acquire                 : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_u64_acquire_release         : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_u64_no_fence                : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_u64_release                 : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_add_u64                     : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_add_u64_acquire             : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_add_u64_acquire_release     : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_add_u64_no_fence            : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_exchange_add_u64_release             : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_increment_u64                        : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_increment_u64_acquire                : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_increment_u64_acquire_release        : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_increment_u64_no_fence               : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_increment_u64_release                : fn(target: ptr[mut u64]                              ) -> (old: u64)                : ---
interlocked_or_u64                               : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_or_u64_acquire                       : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_or_u64_acquire_release               : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_or_u64_no_fence                      : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_or_u64_release                       : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_xor_u64                              : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_xor_u64_acquire                      : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_xor_u64_acquire_release              : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_xor_u64_no_fence                     : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---
interlocked_xor_u64_release                      : fn(target: ptr[mut u64], value: u64                  ) -> u64                       : ---

interlocked_and_i128                              : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_and_i128_acquire                      : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_and_i128_acquire_release              : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_and_i128_no_fence                     : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_and_i128_release                      : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_compare_exchange_i128                 : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> (old: i128, success: bool) : ---
interlocked_compare_exchange_i128_acquire         : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> (old: i128, success: bool) : ---
interlocked_compare_exchange_i128_acquire_release : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> (old: i128, success: bool) : ---
interlocked_compare_exchange_i128_no_fence        : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> (old: i128, success: bool) : ---
interlocked_compare_exchange_i128_release         : fn(target: ptr[mut i128], exchange: i128, expected: i128) -> (old: i128, success: bool) : ---
interlocked_decrement_i128                        : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_decrement_i128_acquire                : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_decrement_i128_acquire_release        : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_decrement_i128_no_fence               : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_decrement_i128_release                : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_exchange_i128                         : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_i128_acquire                 : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_i128_acquire_release         : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_i128_no_fence                : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_i128_release                 : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_add_i128                     : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_add_i128_acquire             : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_add_i128_acquire_release     : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_add_i128_no_fence            : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_exchange_add_i128_release             : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_increment_i128                        : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_increment_i128_acquire                : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_increment_i128_acquire_release        : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_increment_i128_no_fence               : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_increment_i128_release                : fn(target: ptr[mut i128]                                ) -> (old: i128)                : ---
interlocked_or_i128                               : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_or_i128_acquire                       : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_or_i128_acquire_release               : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_or_i128_no_fence                      : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_or_i128_release                       : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_xor_i128                              : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_xor_i128_acquire                      : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_xor_i128_acquire_release              : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_xor_i128_no_fence                     : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---
interlocked_xor_i128_release                      : fn(target: ptr[mut i128], value: i128                   ) -> i128                       : ---

interlocked_and_u128                              : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_and_u128_acquire                      : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_and_u128_acquire_release              : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_and_u128_no_fence                     : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_and_u128_release                      : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_compare_exchange_u128                 : fn(target: ptr[mut u128], exchange: u128, expected: u128) -> (old: u128, success: bool) : ---
interlocked_compare_exchange_u128_acquire         : fn(target: ptr[mut u128], exchange: u128, expected: u128) -> (old: u128, success: bool) : ---
interlocked_compare_exchange_u128_acquire_release : fn(target: ptr[mut u128], exchange: u128, expected: u128) -> (old: u128, success: bool) : ---
interlocked_compare_exchange_u128_no_fence        : fn(target: ptr[mut u128], exchange: u128, expected: u128) -> (old: u128, success: bool) : ---
interlocked_compare_exchange_u128_release         : fn(target: ptr[mut u128], exchange: u128, expected: u128) -> (old: u128, success: bool) : ---
interlocked_decrement_u128                        : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_decrement_u128_acquire                : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_decrement_u128_acquire_release        : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_decrement_u128_no_fence               : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_decrement_u128_release                : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_exchange_u128                         : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_u128_acquire                 : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_u128_acquire_release         : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_u128_no_fence                : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_u128_release                 : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_add_u128                     : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_add_u128_acquire             : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_add_u128_acquire_release     : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_add_u128_no_fence            : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_exchange_add_u128_release             : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_increment_u128                        : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_increment_u128_acquire                : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_increment_u128_acquire_release        : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_increment_u128_no_fence               : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_increment_u128_release                : fn(target: ptr[mut u128]                                ) -> (old: u128)                : ---
interlocked_or_u128                               : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_or_u128_acquire                       : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_or_u128_acquire_release               : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_or_u128_no_fence                      : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_or_u128_release                       : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_xor_u128                              : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_xor_u128_acquire                      : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_xor_u128_acquire_release              : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_xor_u128_no_fence                     : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---
interlocked_xor_u128_release                      : fn(target: ptr[mut u128], value: u128                   ) -> u128                       : ---

interlocked_and_int                              : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_and_int_acquire                      : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_and_int_acquire_release              : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_and_int_no_fence                     : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_and_int_release                      : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_compare_exchange_int                 : fn(target: ptr[mut int], exchange: int, expected: int) -> (old: int, success: bool) : ---
interlocked_compare_exchange_int_acquire         : fn(target: ptr[mut int], exchange: int, expected: int) -> (old: int, success: bool) : ---
interlocked_compare_exchange_int_acquire_release : fn(target: ptr[mut int], exchange: int, expected: int) -> (old: int, success: bool) : ---
interlocked_compare_exchange_int_no_fence        : fn(target: ptr[mut int], exchange: int, expected: int) -> (old: int, success: bool) : ---
interlocked_compare_exchange_int_release         : fn(target: ptr[mut int], exchange: int, expected: int) -> (old: int, success: bool) : ---
interlocked_decrement_int                        : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_decrement_int_acquire                : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_decrement_int_acquire_release        : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_decrement_int_no_fence               : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_decrement_int_release                : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_exchange_int                         : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_int_acquire                 : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_int_acquire_release         : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_int_no_fence                : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_int_release                 : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_add_int                     : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_add_int_acquire             : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_add_int_acquire_release     : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_add_int_no_fence            : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_exchange_add_int_release             : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_increment_int                        : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_increment_int_acquire                : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_increment_int_acquire_release        : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_increment_int_no_fence               : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_increment_int_release                : fn(target: ptr[mut int]                              ) -> (old: int)                : ---
interlocked_or_int                               : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_or_int_acquire                       : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_or_int_acquire_release               : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_or_int_no_fence                      : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_or_int_release                       : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_xor_int                              : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_xor_int_acquire                      : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_xor_int_acquire_release              : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_xor_int_no_fence                     : fn(target: ptr[mut int], value: int                  ) -> int                       : ---
interlocked_xor_int_release                      : fn(target: ptr[mut int], value: int                  ) -> int                       : ---

interlocked_and_uint                              : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_and_uint_acquire                      : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_and_uint_acquire_release              : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_and_uint_no_fence                     : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_and_uint_release                      : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_compare_exchange_uint                 : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> (old: uint, success: bool) : ---
interlocked_compare_exchange_uint_acquire         : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> (old: uint, success: bool) : ---
interlocked_compare_exchange_uint_acquire_release : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> (old: uint, success: bool) : ---
interlocked_compare_exchange_uint_no_fence        : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> (old: uint, success: bool) : ---
interlocked_compare_exchange_uint_release         : fn(target: ptr[mut uint], exchange: uint, expected: uint) -> (old: uint, success: bool) : ---
interlocked_decrement_uint                        : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_decrement_uint_acquire                : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_decrement_uint_acquire_release        : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_decrement_uint_no_fence               : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_decrement_uint_release                : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_exchange_uint                         : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_uint_acquire                 : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_uint_acquire_release         : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_uint_no_fence                : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_uint_release                 : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_add_uint                     : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_add_uint_acquire             : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_add_uint_acquire_release     : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_add_uint_no_fence            : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_exchange_add_uint_release             : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_increment_uint                        : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_increment_uint_acquire                : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_increment_uint_acquire_release        : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_increment_uint_no_fence               : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_increment_uint_release                : fn(target: ptr[mut uint]                                ) -> (old: uint)                : ---
interlocked_or_uint                               : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_or_uint_acquire                       : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_or_uint_acquire_release               : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_or_uint_no_fence                      : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_or_uint_release                       : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_xor_uint                              : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_xor_uint_acquire                      : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_xor_uint_acquire_release              : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_xor_uint_no_fence                     : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---
interlocked_xor_uint_release                      : fn(target: ptr[mut uint], value: uint                   ) -> uint                       : ---

interlocked_and_uintptr                              : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_and_uintptr_acquire                      : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_and_uintptr_acquire_release              : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_and_uintptr_no_fence                     : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_and_uintptr_release                      : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_compare_exchange_uintptr                 : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> (old: uintptr, success: bool) : ---
interlocked_compare_exchange_uintptr_acquire         : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> (old: uintptr, success: bool) : ---
interlocked_compare_exchange_uintptr_acquire_release : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> (old: uintptr, success: bool) : ---
interlocked_compare_exchange_uintptr_no_fence        : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> (old: uintptr, success: bool) : ---
interlocked_compare_exchange_uintptr_release         : fn(target: ptr[mut uintptr], exchange: uintptr, expected: uintptr) -> (old: uintptr, success: bool) : ---
interlocked_decrement_uintptr                        : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_decrement_uintptr_acquire                : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_decrement_uintptr_acquire_release        : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_decrement_uintptr_no_fence               : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_decrement_uintptr_release                : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_exchange_uintptr                         : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_uintptr_acquire                 : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_uintptr_acquire_release         : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_uintptr_no_fence                : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_uintptr_release                 : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_add_uintptr                     : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_add_uintptr_acquire             : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_add_uintptr_acquire_release     : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_add_uintptr_no_fence            : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_exchange_add_uintptr_release             : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_increment_uintptr                        : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_increment_uintptr_acquire                : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_increment_uintptr_acquire_release        : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_increment_uintptr_no_fence               : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_increment_uintptr_release                : fn(target: ptr[mut uintptr]                                      ) -> (old: uintptr)                : ---
interlocked_or_uintptr                               : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_or_uintptr_acquire                       : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_or_uintptr_acquire_release               : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_or_uintptr_no_fence                      : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_or_uintptr_release                       : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_xor_uintptr                              : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_xor_uintptr_acquire                      : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_xor_uintptr_acquire_release              : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_xor_uintptr_no_fence                     : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---
interlocked_xor_uintptr_release                      : fn(target: ptr[mut uintptr], value: uintptr                      ) -> uintptr                       : ---

/*
 * Jump to an address in executable memory. Should not be called outside of core code like a fiber scheduler.
 */
jump_to_address : fn(base_pointer: rawptr) : ---

mem_copy : fn(dest, source: rawptr, len: usize) : ---
mem_copy_non_overlapping : fn(dest, source: rawptr, len: usize) : ---
mem_zero : fn(target: rawptr, len: usize) : ---

/*
 * Sets the location that the current function will return to once done.
 * Only valid for functions that don't have any return values.
 * Intended for fiber schedulers, in general this is wildly unsafe to use.
 */
set_return_address : fn(base_pointer: rawptr) : ---
