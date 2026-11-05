/*
 * std/maps' HashMap, with the hash functions std gives and one of its own.
 */
package maps_test

import maps from "std"
import runtime from "base"
import testing from "std"

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

keeps_the_last_value_put_for_a_key #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    ages : StringMap[int]
    defer maps.map_free(&ages)
    maps.map_put(&ages, "Ada", 36)
    maps.map_put(&ages, "Grace", 85)
    maps.map_put(&ages, "Ada", 37)
    testing.expect_eq(t, ages.count, 2, "putting Ada again replaces her age rather than adding a key")
    testing.expect_eq(t, maps.map_get(&ages, "Ada"), 37, "the second age put for Ada")
    testing.expect_eq(t, maps.map_get(&ages, "Grace"), 85, "Grace's age, put once")
    testing.expect(t, !maps.map_has(&ages, "Alan"), "Alan was never put")
    return .Ok
}

grows_and_removes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Enough to grow several times, then every other one taken out
    squares : maps.HashMap[int, int, maps.hash_integer[int]]
    defer maps.map_free(&squares)
    for i in 0..<1000 {
        maps.map_put(&squares, i, i * i)
    }
    removed := 0
    for i in 0..<500 {
        if maps.map_remove(&squares, i * 2) {
            removed += 1
        }
    }
    testing.expect_eq(t, removed, 500, "every even key was put, so each is there to remove")
    testing.expect_eq(t, squares.count, 500, "the odd keys are left")
    testing.expect(t, !maps.map_has(&squares, 10), "a removed key is gone")
    testing.expect(t, !maps.map_remove(&squares, 10), "and can't be removed again")
    wrong := 0
    for i in 0..<500 {
        if maps.map_get(&squares, i * 2 + 1) != (i * 2 + 1) * (i * 2 + 1) {
            wrong += 1
        }
    }
    testing.expect_eq(t, wrong, 0, "every odd key keeps its square through growing and removals")
    maps.map_clear(&squares)
    testing.expect_eq(t, squares.count, 0, "clearing takes every key out")
    testing.expect(t, !maps.map_has(&squares, 1), "so no key is found after")
    return .Ok
}

hashes_keys_with_a_function_of_its_own #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    cells : maps.HashMap[u64, Point, hash_cell]
    defer maps.map_free(&cells)
    maps.map_put(&cells, cell_of(Point.{x = 3, y = 4}), Point.{x = 3, y = 4})
    found :: maps.map_get(&cells, cell_of(Point.{x = 3, y = 4}))
    point :: testing.require_some(t, found, "the point is found by the cell it was put under")?
    testing.expect(t, points_equal(point, Point.{x = 3, y = 4}), "the value found is the point put")
    return .Ok
}

/*
 * map_try_put grows when it can, and without memory gives the error and leaves the map as it was.
 */
tries_to_put_without_memory #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    counts : maps.HashMap[u64, u64, maps.hash_integer[u64]]
    defer maps.map_free(&counts)
    for i in 0..<6 {
        put :: maps.map_try_put(&counts, cast[u64](i), cast[u64](i) * 2)
        testing.expect_none(t, put, "there's memory to grow into")
    }
    // Six of eight slots: a seventh needs more, which an allocator with no memory can't give
    failed : runtime.AllocatorError? = null
    push_context starved (allocator = runtime.FAILING_ALLOCATOR) {
        failed = maps.map_try_put(&counts, 6, 12)
    }
    testing.expect_some(t, failed, "the seventh key needs the map to grow, which an allocator with no memory refuses")
    testing.expect_eq(t, counts.count, 6, "the refused key isn't counted")
    testing.expect(t, !maps.map_has(&counts, 6), "nor found")
    testing.expect_eq(t, maps.map_get(&counts, 5) or_else 0, 10, "what was there before is still there")
    again :: maps.map_try_put(&counts, 6, 12)
    testing.expect_none(t, again, "with memory again, the map grows")
    testing.expect_eq(t, maps.map_get(&counts, 6) or_else 0, 12, "and the key is put")
    return .Ok
}
