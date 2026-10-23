// A function type whose default uses this package's own names, which a caller elsewhere doesn't import.
package scaled

FACTOR :: 7

factor :: fn() -> int {
    return FACTOR
}

ScaleFn :: alias fn(n: int, by: int = factor() * 2) -> int
