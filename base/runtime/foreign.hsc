package runtime

/*
 * A library that foreign functions come from, made by #library("name"), which #foreign names
 * (docs/directives.md, #foreign):
 *
 *     KERNEL32 :: #library("kernel32")
 *     ExitProcess #foreign(KERNEL32) : fn(code: u32) #never_returns : ---
 */
ForeignLibrary :: struct {
    name : string,
}
