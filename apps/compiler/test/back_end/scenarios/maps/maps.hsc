/*
 * std/maps' HashMap, with the hash functions std gives and one of its own: main returns 42 if every
 * check worked, or the number of the first one that didn't.
 */
package maps_test

import maps from "std"

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
    return 42
}
