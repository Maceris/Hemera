package documented

/*
 * What the documentation scenario reads back: documentation comments on a function, an enum's members, and a
 * function with a plain comment and one with @brief. Reflection reads an imported package's, never its own reader's:
 * a constant reading its own package would compute itself.
 */

/**
 * Copies files into a directory. Each one keeps its name.
 *
 * Nothing is replaced unless asked.
 *
 * @param from the files to copy
 * @param into where they go,
 *     beneath the home
 * @param force replace what's there
 * @return how many were copied
 * @error NoSpace the volume filled
 * @example copy notes backup
 */
copy :: fn(from: string, into: string, force: bool) -> Result[int, CopyError] {
    return .Ok(0)
}

/** Why a copy stopped. */
CopyError :: enum {
    /** The volume filled. */
    NoSpace,
    Missing, /**< Nothing was there. */
}

// A plain comment, which documents nothing
plain :: fn() -> int {
    return 1
}

/** @brief Stated. And more. */
stated :: fn() -> int {
    return 2
}

/**
 * Read some bytes.
 *
 * @param from Where to read.
 * @return count How many were read.
 * @return error Why it stopped, or null.
 */
read_some :: fn(from: string) -> (count : usize, error : string?) {
    return 0, null
}

/**
 * Split a number.
 *
 * @param number The number.
 * @return Its high half.
 * @return Its low half.
 */
halves :: fn(number: u64) -> (u32, u32) {
    return cast[u32](number >> 32), cast[u32](number)
}

/** A count, wrapped. */
Wrapped :: struct {
    /** The count inside, whose fields are the wrapper's. */
    using inner : Inner,
}

/** What a Wrapped holds. */
Inner :: struct {
    /** How many there are, from 0. */
    count : int,
}
