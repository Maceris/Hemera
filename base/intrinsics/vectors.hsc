package intrinsics

/*
 * Vectors and bits (docs/types.md, Vectors). The compiler works out each call's types from what
 * it's given, so these are written loosely: V is a vector, T an integer or a vector of integers,
 * and a lane is one of V's. An argument named count or amount that has to be a constant says so.
 */

// lane in every lane of V: splat[vector[u32, 4]](1).
splat : fn[V](lane: any) -> V : ---

// Each lane from chosen where mask's lane is true, otherwise from otherwise, without a branch. mask is a
// vector of bools with as many lanes.
select : fn[V](mask: any, chosen: V, otherwise: V) -> V : ---

// The lanes moved down by count, a constant: lane i is vector's lane i + count, the first ones coming
// round to the end. rotate_lanes(vector[u32, 4].{a, b, c, d}, 1) is .{b, c, d, a}.
rotate_lanes : fn[V](vector: V, count: usize) -> V : ---

// The lanes of a vector of integers added, and'ed, or'ed or xor'ed together, as one lane.
reduce_add : fn[V](vector: V) -> any : ---
reduce_and : fn[V](vector: V) -> any : ---
reduce_or : fn[V](vector: V) -> any : ---
reduce_xor : fn[V](vector: V) -> any : ---

// Whether any lane, or every lane, of a vector of bools is true.
any_true : fn[V](mask: V) -> bool : ---
all_true : fn[V](mask: V) -> bool : ---

// An integer's bits, or each lane's, rotated by amount: bits shifted out of one end come back in the other.
rotate_left : fn[T](value: T, amount: u32) -> T : ---
rotate_right : fn[T](value: T, amount: u32) -> T : ---

// An integer's bytes in the other order, or each lane's: 0x1122_3344 becomes 0x4433_2211.
byte_swap : fn[T](value: T) -> T : ---
