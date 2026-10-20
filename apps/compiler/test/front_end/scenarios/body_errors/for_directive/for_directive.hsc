// A for loop takes #reverse and nothing else (docs/control_flow.md, Range-based for)
package for_directive

main :: fn() -> int {
    total := 0
    for i in 0..<3 #at_least_once {
        total += i
    }
    return total
}
