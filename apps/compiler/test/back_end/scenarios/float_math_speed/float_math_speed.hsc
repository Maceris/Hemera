package float_math_speed

import io from "std"
import math from "std"
import runtime from "base"
import time from "std"

/*
 * How long std/math's functions take, in nanoseconds a value: f32 through f64's fdlibm (how f32 was first built), f32's
 * own kernel on one value at a time, and on eight lanes at once; and f64. Run by hand, built for the machine measured
 * (like --cpu=x86-64-v3); the numbers vary from run to run by a few percent.
 */

/** How many values each measure takes, and how many times over. */
VALUES :: 4096
ROUNDS :: 200

/** Values spread over where a renderer's arguments are: -10 to 10, none 0. */
make_values :: fn() -> f32[VALUES] {
    values : f32[VALUES]
    for &value, i in values {
        value^ = (cast[f32](i) - 2047.5) / 204.8
    }
    return values
}

/** Nanoseconds from a reading till now, as a float. */
elapsed :: fn(start: runtime.MonotonicTime) -> f64 {
    taken :: time.since(start)
    return cast[f64](taken.seconds) * 1e9 + cast[f64](taken.nanos)
}

/**
 * Time a function of f32s four ways, and print a line.
 *
 * @param name The function's name.
 * @param values The arguments.
 * @param through_f64 The f32 function through f64, as first built.
 * @param scalar f32's own kernel, a value at a time.
 * @param lanes The kernel on eight lanes.
 * @param wide The f64 function.
 */
measure :: fn(name: string, values: ptr[f32[VALUES]], through_f64: (fn(x: f32) -> f32), scalar: (fn(x: f32) -> f32),
    lanes: (fn(x: vector[f32, 8]) -> vector[f32, 8]), wide: (fn(x: f64) -> f64)) {

    sink := 0.0
    start := time.monotonic()
    for round in 0..<ROUNDS {
        for value in values^ {
            sink += cast[f64](through_f64(value))
        }
    }
    old :: elapsed(start) / (VALUES * ROUNDS)
    start = time.monotonic()
    for round in 0..<ROUNDS {
        for value in values^ {
            sink += cast[f64](scalar(value))
        }
    }
    one :: elapsed(start) / (VALUES * ROUNDS)
    start = time.monotonic()
    for round in 0..<ROUNDS {
        for i in 0..<VALUES / 8 {
            group :: bit_cast[vector[f32, 8]](cast[ptr[f32[8]]](&values[i * 8])^)
            sum :: bit_cast[f32[8]](lanes(group))
            sink += cast[f64](sum[0] + sum[7])
        }
    }
    eight :: elapsed(start) / (VALUES * ROUNDS)
    start = time.monotonic()
    for round in 0..<ROUNDS {
        for value in values^ {
            sink += wide(cast[f64](value))
        }
    }
    double :: elapsed(start) / (VALUES * ROUNDS)
    io.printf("%{<12} f32 through f64 %{>6.2} ns, f32 kernel %{>6.2} ns, 8 lanes %{>6.2} ns a value, f64 %{>6.2} ns  (%)\n",
        name, old, one, eight, double, sink > 1e300)
}

/* The f32 functions as first built: through f64's */
sin_through :: fn(x: f32) -> f32 { return cast[f32](math.sin_64(cast[f64](x))) }
cos_through :: fn(x: f32) -> f32 { return cast[f32](math.cos_64(cast[f64](x))) }
exp_through :: fn(x: f32) -> f32 { return cast[f32](math.exp_64(cast[f64](x))) }
log_through :: fn(x: f32) -> f32 { return cast[f32](math.log_64(cast[f64](abs(x)))) }
atan_through :: fn(x: f32) -> f32 { return cast[f32](math.atan_64(cast[f64](x))) }
cube_root_through :: fn(x: f32) -> f32 { return cast[f32](math.cube_root_64(cast[f64](x))) }

log_abs :: fn(x: f32) -> f32 { return math.log(abs(x)) }
log_abs_lanes :: fn(x: vector[f32, 8]) -> vector[f32, 8] {
    return math.log(bit_cast[vector[f32, 8]](bit_cast[vector[u32, 8]](x) & 0x7fff_ffff))
}
log_abs_64 :: fn(x: f64) -> f64 { return math.log(abs(x)) }

main :: fn() -> int {
    values := make_values()
    measure("sin", &values, sin_through, math.sin[f32], math.sin[vector[f32, 8]], math.sin[f64])
    measure("cos", &values, cos_through, math.cos[f32], math.cos[vector[f32, 8]], math.cos[f64])
    measure("exp", &values, exp_through, math.exp[f32], math.exp[vector[f32, 8]], math.exp[f64])
    measure("log", &values, log_through, log_abs, log_abs_lanes, log_abs_64)
    measure("atan", &values, atan_through, math.atan[f32], math.atan[vector[f32, 8]], math.atan[f64])
    measure("cube_root", &values, cube_root_through, math.cube_root[f32], math.cube_root[vector[f32, 8]], math.cube_root[f64])
    return 0
}
