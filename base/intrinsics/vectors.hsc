package intrinsics

/*
 * Vectors and bits (docs/types.md, Vectors). The compiler works out each call's types from what
 * it's given, so these are written loosely: V is a vector, T an integer or a vector of integers,
 * and a lane is one of V's. An argument named count or amount that has to be a constant says so.
 */

/**
 * Make a vector with the same value in every lane: splat[vector[u32, 4]](1).
 *
 * @tparam V The vector type to fill, given explicitly; a vector with lanes, not v128 and the like.
 * @param lane The value, of V's lane type.
 * @return A V with lane in each of its lanes.
 */
splat : fn[V](lane: any) -> V : ---

/**
 * Choose each lane, or a whole value, from one of two, without a branch.
 *
 * For vectors, each lane comes from chosen where mask's lane is true, otherwise from otherwise. For integers, bools and
 * enums, it's chosen when mask is true, otherwise otherwise, worked out with a mask the optimizer can't see through, so
 * never with a branch either, which keeps it constant time for secrets (docs/memory.md, Secrets).
 *
 * @tparam V The type chosen: a vector, an integer, a bool or an enum.
 * @param mask For vectors, a vector of bools with as many lanes as V; otherwise a bool.
 * @param chosen What's taken where mask is true.
 * @param otherwise What's taken where mask is false.
 * @return The value made from both, of type V.
 */
select : fn[V](mask: any, chosen: V, otherwise: V) -> V : ---

/**
 * Move a vector's lanes down, the first ones coming round to the end: rotate_lanes(vector[u32, 4].{a, b, c, d}, 1) is
 * .{b, c, d, a}.
 *
 * @tparam V The vector type, with lanes.
 * @param vector The lanes to move.
 * @param count How many places, a constant from 0 to one less than V's lane count: lane i of the result is vector's
 *     lane i + count, wrapping round.
 * @return The moved lanes, of type V.
 */
rotate_lanes : fn[V](vector: V, count: usize) -> V : ---

/**
 * Add the lanes of a vector of integers together.
 *
 * @tparam V The vector type, of integers.
 * @param vector The lanes to add.
 * @return Their sum, of the lane type, wrapping round on overflow as integer addition in a lane does.
 */
reduce_add : fn[V](vector: V) -> any : ---
/**
 * And the lanes of a vector of integers together, bit by bit.
 *
 * @tparam V The vector type, of integers.
 * @param vector The lanes to combine.
 * @return The bits set in every lane, of the lane type.
 */
reduce_and : fn[V](vector: V) -> any : ---
/**
 * Or the lanes of a vector of integers together, bit by bit.
 *
 * @tparam V The vector type, of integers.
 * @param vector The lanes to combine.
 * @return The bits set in any lane, of the lane type.
 */
reduce_or : fn[V](vector: V) -> any : ---
/**
 * Xor the lanes of a vector of integers together, bit by bit.
 *
 * @tparam V The vector type, of integers.
 * @param vector The lanes to combine.
 * @return The bits set in an odd number of lanes, of the lane type.
 */
reduce_xor : fn[V](vector: V) -> any : ---

/**
 * Tell whether any lane of a vector of bools is true, like a comparison's result.
 *
 * @tparam V The vector type, of bools.
 * @param mask The lanes to test.
 * @return True when at least one lane is true.
 */
any_true : fn[V](mask: V) -> bool : ---
/**
 * Tell whether every lane of a vector of bools is true, like a comparison's result.
 *
 * @tparam V The vector type, of bools.
 * @param mask The lanes to test.
 * @return True when every lane is true.
 */
all_true : fn[V](mask: V) -> bool : ---

/**
 * Rotate an integer's bits, or each lane's, toward its top: bits shifted out of the top come back in at the bottom.
 *
 * @tparam T An integer, or a vector of integers.
 * @param value The bits to rotate.
 * @param amount How many places, taken modulo the integer's (or lane's) width in bits, so any amount is valid.
 * @return The rotated bits, of type T.
 */
rotate_left : fn[T](value: T, amount: u32) -> T : ---
/**
 * Rotate an integer's bits, or each lane's, toward its bottom: bits shifted out of the bottom come back in at the top.
 *
 * @tparam T An integer, or a vector of integers.
 * @param value The bits to rotate.
 * @param amount How many places, taken modulo the integer's (or lane's) width in bits, so any amount is valid.
 * @return The rotated bits, of type T.
 */
rotate_right : fn[T](value: T, amount: u32) -> T : ---

/**
 * Reverse an integer's bytes, or each lane's: 0x1122_3344 becomes 0x4433_2211.
 *
 * @tparam T An integer of 2 bytes or more, or a vector of them.
 * @param value The bytes to reverse.
 * @return The bytes in the other order, of type T.
 */
byte_swap : fn[T](value: T) -> T : ---
