/*
 * std/maps' HashMap, with the hash functions std gives and one of its own: main returns 42 if every
 * check worked, or the number of the first one that didn't.
 */
package maps_test

import maps from "std"
import runtime from "base"

// A combination that's used often, by name
StringMap :: alias[V] maps.HashMap[string, V, maps.hash_string]

Point :: struct {
    x : int,
    y : int,
}

points_equal :: fn(a: Point, b: Point) -> bool {
    return a.x == b.x && a.y == b.y
}

// Points have no ==, so they're keyed by what they're made of
hash_cell :: fn(cell: u64) -> u64 {
    return maps.hash_integer(cell)
}

cell_of :: fn(point: Point) -> u64 {
    return cast[u64](point.x) * 1000 + cast[u64](point.y)
}

main :: fn() -> int {
    ages : StringMap[int]
    maps.map_put(&ages, "Ada", 36)
    maps.map_put(&ages, "Grace", 85)
    maps.map_put(&ages, "Ada", 37)
    if ages.count != 2 || maps.map_get(&ages, "Ada") != 37 || maps.map_get(&ages, "Grace") != 85 || maps.map_has(&ages, "Alan") {
        return 1
    }
    // Enough to grow several times, then every other one taken out
    squares : maps.HashMap[int, int, maps.hash_integer[int]]
    for i in 0..<1000 {
        maps.map_put(&squares, i, i * i)
    }
    for i in 0..<500 {
        if !maps.map_remove(&squares, i * 2) {
            return 2
        }
    }
    if squares.count != 500 || maps.map_has(&squares, 10) || maps.map_remove(&squares, 10) {
        return 3
    }
    for i in 0..<500 {
        if maps.map_get(&squares, i * 2 + 1) != (i * 2 + 1) * (i * 2 + 1) {
            return 4
        }
    }
    // A hash of its own, for keys made from points
    cells : maps.HashMap[u64, Point, hash_cell]
    maps.map_put(&cells, cell_of(Point.{x = 3, y = 4}), Point.{x = 3, y = 4})
    found :: maps.map_get(&cells, cell_of(Point.{x = 3, y = 4}))
    match found {
        case Some(point) => {
            if !points_equal(point, Point.{x = 3, y = 4}) {
                return 5
            }
        }
        case None => return 5
    }
    maps.map_clear(&squares)
    if squares.count != 0 || maps.map_has(&squares, 1) {
        return 6
    }
    maps.map_free(&squares)
    maps.map_free(&ages)
    maps.map_free(&cells)
    return check_try_put()
}

// map_try_put grows when it can, and without memory gives the error and leaves the map as it was.
check_try_put :: fn() -> int {
    counts : maps.HashMap[u64, u64, maps.hash_integer[u64]]
    for i in 0..<6 {
        if maps.map_try_put(&counts, cast[u64](i), cast[u64](i) * 2) != null {
            return 7
        }
    }
    // Six of eight slots: a seventh needs more, which an allocator with no memory can't give
    failed : runtime.AllocatorError? = null
    push_context starved (allocator = runtime.FAILING_ALLOCATOR) {
        failed = maps.map_try_put(&counts, 6, 12)
    }
    if failed == null || counts.count != 6 || maps.map_has(&counts, 6) || (maps.map_get(&counts, 5) or_else 0) != 10 {
        return 8
    }
    if maps.map_try_put(&counts, 6, 12) != null || (maps.map_get(&counts, 6) or_else 0) != 12 {
        return 9
    }
    maps.map_free(&counts)
    return 42
}
