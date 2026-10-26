/*
 * The builtin generic types. Unlike the rest of builtin, which describes names the compiler
 * knows itself, the compiler compiles this file: their instances, like int? or
 * Result[int, string], are made like any generic type's.
 */
package builtin

// Optional values: T? is Optional[T]. None comes first, so an optional that starts zeroed is None.
Optional :: union[T] {
    None,
    Some(T),
}

Result :: union[T, E] {
    Ok(T),
    Error(E),
}
