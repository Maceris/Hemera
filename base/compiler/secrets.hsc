package compiler

/*
 * Secrets (docs/memory.md, Secrets). The compiler works out each call's type from what it's given.
 */

// value, no longer a secret, as a type that isn't #secret: a #secret alias gives what it aliases. For a
// result that's public by design, like whether a tag matched once it's been compared in constant time.
declassify : fn[T](value: T) -> any : ---

// value, as a secret, for a local that holds secrets later, like acc := compiler.secret(cast[u32](0)).
secret : fn[T](value: T) -> T : ---
