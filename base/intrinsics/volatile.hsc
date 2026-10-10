package intrinsics

/*
 * Volatile loads and stores, for memory-mapped device registers.
 *
 * Each one is exactly one access of the given width, which the compiler never removes,
 * merges, splits or invents, and never reorders with other volatile accesses. They are
 * not atomic and don't order other memory accesses or other CPUs; use the atomic fences
 * for that.
 *
 * Not for sharing memory between threads, which needs atomics.
 */

volatile_load_u8  : fn(source: ptr[u8] ) -> u8  : ---
volatile_load_u16 : fn(source: ptr[u16]) -> u16 : ---
volatile_load_u32 : fn(source: ptr[u32]) -> u32 : ---
volatile_load_u64 : fn(source: ptr[u64]) -> u64 : ---

volatile_store_u8  : fn(target: ptr[mut u8],  value: u8 ) : ---
volatile_store_u16 : fn(target: ptr[mut u16], value: u16) : ---
volatile_store_u32 : fn(target: ptr[mut u32], value: u32) : ---
volatile_store_u64 : fn(target: ptr[mut u64], value: u64) : ---
