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

/**
 * Read a byte with one volatile access.
 *
 * @param source The byte, like a device register; it's read exactly once.
 * @return What was there.
 */
volatile_load_u8  : fn(source: ptr[u8] ) -> u8  : ---
/**
 * Read two bytes with one volatile access, in the target's byte order.
 *
 * @param source Where they are, aligned to 2 bytes as a u16 is; they're read exactly once.
 * @return What was there.
 */
volatile_load_u16 : fn(source: ptr[u16]) -> u16 : ---
/**
 * Read four bytes with one volatile access, in the target's byte order.
 *
 * @param source Where they are, aligned to 4 bytes as a u32 is; they're read exactly once.
 * @return What was there.
 */
volatile_load_u32 : fn(source: ptr[u32]) -> u32 : ---
/**
 * Read eight bytes with one volatile access, in the target's byte order.
 *
 * @param source Where they are, aligned to 8 bytes as a u64 is; they're read exactly once.
 * @return What was there.
 */
volatile_load_u64 : fn(source: ptr[u64]) -> u64 : ---

/**
 * Write a byte with one volatile access.
 *
 * @param target The byte, like a device register; it's written exactly once.
 * @param value What to write.
 */
volatile_store_u8  : fn(target: ptr[mut u8],  value: u8 ) : ---
/**
 * Write two bytes with one volatile access, in the target's byte order.
 *
 * @param target Where they go, aligned to 2 bytes as a u16 is; they're written exactly once.
 * @param value What to write.
 */
volatile_store_u16 : fn(target: ptr[mut u16], value: u16) : ---
/**
 * Write four bytes with one volatile access, in the target's byte order.
 *
 * @param target Where they go, aligned to 4 bytes as a u32 is; they're written exactly once.
 * @param value What to write.
 */
volatile_store_u32 : fn(target: ptr[mut u32], value: u32) : ---
/**
 * Write eight bytes with one volatile access, in the target's byte order.
 *
 * @param target Where they go, aligned to 8 bytes as a u64 is; they're written exactly once.
 * @param value What to write.
 */
volatile_store_u64 : fn(target: ptr[mut u64], value: u64) : ---
