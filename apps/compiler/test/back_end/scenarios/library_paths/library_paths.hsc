/*
 * A #library only a folder given to the linker has: hemera_library_paths.lib, which the back end's test makes, an import
 * library for kernel32's GetCurrentProcessId. main returns 42 if the call reaches it.
 */
package library_paths

PATHS :: #library("hemera_library_paths")

GetCurrentProcessId #foreign(PATHS) : fn() -> u32 : ---

main :: fn() -> int {
    if GetCurrentProcessId() == 0 {
        return 1
    }
    return 42
}
