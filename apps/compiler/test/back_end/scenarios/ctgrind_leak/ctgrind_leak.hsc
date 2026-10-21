/*
 * The check's own check: a secret read through a rawptr, where the compiler doesn't follow it, decides
 * what main returns. Built with --valgrind-secrets, Memcheck must report it, so under valgrind
 * --error-exitcode=99 this exits with 99 (docs/memory.md, Checking the Machine Code).
 */
package ctgrind_leak_test

import compiler from "base"
import crypto from "std"

main :: fn() -> int {
    key := compiler.secret(cast[crypto.Key256](u8.[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]))
    first := cast[ptr[u8]](cast[rawptr](&key))^
    if first == 1 {
        return 42
    }
    return 7
}
