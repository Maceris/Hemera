/**
 * The builtin generic types. Unlike the rest of builtin, which describes names the compiler
 * knows itself, the compiler compiles this file: their instances, like int? or
 * Result[int, string], are made like any generic type's.
 */
package builtin

/**
 * A value that may be missing: T? is Optional[T], and null is its None (docs/types.md, Optional Types).
 *
 * None comes first, so an optional that starts zeroed is None. An optional of a pointer that's never null, like
 * ptr[T]? or cstring?, is just the pointer, with None as address 0, so it matches a nullable pointer in C.
 *
 * @tparam T What it holds when there's something.
 */
Optional :: union[T] {
    /** Nothing: the value is missing. Its tag is 0. */
    None,
    /** The value. */
    Some(T),
}

/**
 * What a function that can fail gives back: its value, or why it has none (docs/types.md, Result Types).
 *
 * @tparam T The value it gives when it succeeds.
 * @tparam E What it gives when it fails, often an enum or a union whose variants a function's @error tags name.
 */
Result :: union[T, E] {
    /** It succeeded, with this value. */
    Ok(T),
    /** It failed, for this reason. */
    Error(E),
}
