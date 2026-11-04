package compiler

/*
 * Secrets (docs/memory.md, Secrets). The compiler works out each call's type from what it's given.
 */

/**
 * Make a secret public, for a result that's public by design, like whether a tag matched once it's been compared in
 * constant time.
 *
 * It changes only what the checker knows: no code is generated for it, except that with --valgrind-secrets it tells
 * Memcheck the value is defined again.
 *
 * @tparam T The secret's type.
 * @param value A value the checker treats as a secret; its bits come back unchanged.
 * @return value, no longer a secret, as a type that isn't #secret: a #secret alias gives what it aliases. A #secret
 *     struct has no public form, so declassifying one is an error; declassify what's in it.
 */
declassify : fn[T](value: T) -> any : ---

/**
 * Make a value a secret, for a local that holds secrets later, like acc := compiler.secret(cast[u32](0)).
 *
 * It changes only what the checker knows, except that with --valgrind-secrets it tells Memcheck the value is
 * undefined, so Memcheck reports what depends on it.
 *
 * @tparam T The value's type.
 * @param value Any value, public or secret already; its bits come back unchanged.
 * @return value, as a secret, of the same type.
 */
secret : fn[T](value: T) -> T : ---
