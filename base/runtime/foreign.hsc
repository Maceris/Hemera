package runtime

/**
 * A library that foreign functions come from, made by #library("name"), which #foreign names (docs/directives.md,
 * #foreign).
 *
 * @example KERNEL32 :: #library("kernel32")
 *     ExitProcess #foreign(KERNEL32) : fn(code: u32) #never_returns : ---
 */
ForeignLibrary :: struct {
    /** The library's name as #library was given it, which the system's loader finds it by. */
    name : string,
}
