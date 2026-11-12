package float_math_exhaustive

import intrinsics from "base"
import io from "std"
import math from "std"
import runtime from "base"
import strings from "std"

/*
 * Every f32 through one of std/math's f32 functions, eight lanes at a time, against the f64 function rounded: how many
 * ulp of f32 the worst is off, and how many are past 1 ulp. Run by hand, as it takes minutes a function; HemeraTest's
 * float_math samples instead.
 *
 *     float_math_exhaustive <function> [part parts]
 *
 * part and parts split the inputs, for running parts at once.
 */

Lanes :: vector[f32, 8]

/** A function checked: its lanes' form, and its f64 one, the reference. */
Checked :: struct {
    name : string,
    lanes : fn(x: Lanes) -> Lanes,
    reference : fn(x: f64) -> f64,
}

FUNCTIONS :: Checked.[
    Checked.{name = "exp", lanes = math.exp[Lanes], reference = math.exp[f64]},
    Checked.{name = "exp2", lanes = math.exp2[Lanes], reference = math.exp2[f64]},
    Checked.{name = "exp_minus_one", lanes = math.exp_minus_one[Lanes], reference = math.exp_minus_one[f64]},
    Checked.{name = "log", lanes = math.log[Lanes], reference = math.log[f64]},
    Checked.{name = "log2", lanes = math.log2[Lanes], reference = math.log2[f64]},
    Checked.{name = "log10", lanes = math.log10[Lanes], reference = math.log10[f64]},
    Checked.{name = "log_one_plus", lanes = math.log_one_plus[Lanes], reference = math.log_one_plus[f64]},
    Checked.{name = "sin", lanes = math.sin[Lanes], reference = math.sin[f64]},
    Checked.{name = "cos", lanes = math.cos[Lanes], reference = math.cos[f64]},
    Checked.{name = "tan", lanes = math.tan[Lanes], reference = math.tan[f64]},
    Checked.{name = "asin", lanes = math.asin[Lanes], reference = math.asin[f64]},
    Checked.{name = "acos", lanes = math.acos[Lanes], reference = math.acos[f64]},
    Checked.{name = "atan", lanes = math.atan[Lanes], reference = math.atan[f64]},
    Checked.{name = "cube_root", lanes = math.cube_root[Lanes], reference = math.cube_root[f64]},
]

/**
 * How far a result is from the reference, in units of the reference's last place as an f32.
 *
 * @param result What the f32 function gave.
 * @param reference What the f64 function gave.
 * @return The distance in f32 ulp; 0 for both NaN, and for the same infinity; infinity for one NaN, or an infinity
 *     the reference rounded to f32 isn't.
 */
ulps_off :: fn(result: f32, reference: f64) -> f64 {
    rounded :: cast[f32](reference)
    if result != result || rounded != rounded {
        return if result != result && rounded != rounded { 0.0 } else { math.infinity[f64]() }
    }
    if math.is_infinite(result) || math.is_infinite(rounded) {
        return if result == rounded { 0.0 } else { math.infinity[f64]() }
    }
    return abs(cast[f64](result) - reference) / cast[f64](math.ulp(rounded))
}

/** A function of two checked: its lanes' form, and its f64 one. */
CheckedPair :: struct {
    name : string,
    lanes : fn(x: Lanes, y: Lanes) -> Lanes,
    reference : fn(x: f64, y: f64) -> f64,
}

PAIRS :: CheckedPair.[
    CheckedPair.{name = "power", lanes = math.power[Lanes], reference = math.power[f64]},
    CheckedPair.{name = "atan2", lanes = math.atan2[Lanes], reference = math.atan2[f64]},
    CheckedPair.{name = "hypotenuse", lanes = math.hypotenuse[Lanes], reference = math.hypotenuse[f64]},
]

/** How many pairs a function of two is checked on: 2^28, half any bits, half where graphics' arguments are. */
PAIR_COUNT :: 1 << 28

/** The next of a xorshift sequence. */
next_random :: fn(state: ptr[mut u64]) -> u64 {
    x := state^
    x = x ~ (x << 13)
    x = x ~ (x >> 7)
    x = x ~ (x << 17)
    state^ = x
    return x
}

/**
 * Check a function of two on random pairs.
 *
 * @param checked The function.
 * @return 0 if none is past 1 ulp, 1 otherwise.
 */
check_pairs :: fn(checked: CheckedPair) -> int {
    state := cast[u64](0x9e37_79b9_7f4a_7c15)
    worst := 0.0
    worst_x : f32 = 0
    worst_y : f32 = 0
    over := cast[u64](0)
    for group in 0..<PAIR_COUNT / 8 {
        xs : f32[8]
        ys : f32[8]
        for i in 0..<8 {
            random :: next_random(&state)
            if group % 2 == 0 {
                xs[i] = bit_cast[f32](cast[u32](random))
                ys[i] = bit_cast[f32](cast[u32](random >> 32))
            }
            else {
                // x from 0 to 16, y from -64 to 64, as powers and angles in a renderer are
                xs[i] = cast[f32](random & 0xff_ffff) / 1048576.0
                ys[i] = cast[f32](cast[i64]((random >> 32) & 0xff_ffff) - 0x80_0000) / 131072.0
            }
        }
        results :: bit_cast[f32[8]](checked.lanes(bit_cast[Lanes](xs), bit_cast[Lanes](ys)))
        for result, i in results {
            off :: ulps_off(result, checked.reference(cast[f64](xs[i]), cast[f64](ys[i])))
            if off > 1 {
                over += 1
            }
            if off > worst {
                worst = off
                worst_x = xs[i]
                worst_y = ys[i]
            }
        }
    }
    io.printf("%: worst % ulp, at (%, %); % of % past 1 ulp\n", checked.name, worst, worst_x, worst_y, over, PAIR_COUNT)
    return if over == 0 { 0 } else { 1 }
}

main :: fn() -> int {
    arguments :: runtime.process_arguments()
    if arguments.count < 2 {
        io.println("float_math_exhaustive <function> [part parts]")
        return 2
    }
    name :: arguments[1]
    for checked in PAIRS {
        if checked.name == name {
            return check_pairs(checked)
        }
    }
    part : u64 = 0
    parts : u64 = 1
    if arguments.count >= 4 {
        part = strings.parse_unsigned(arguments[2]) or_else 0
        parts = strings.parse_unsigned(arguments[3]) or_else 1
    }
    for checked in FUNCTIONS {
        if checked.name != name {
            continue
        }
        span :: (cast[u64](1) << 32) / parts
        first :: part * span
        last :: first + span
        worst := 0.0
        worst_at : f32 = 0
        over := cast[u64](0)
        bits := first
        loop {
            lane_bits :: vector[u32, 8].{0, 1, 2, 3, 4, 5, 6, 7} + intrinsics.splat[vector[u32, 8]](cast[u32](bits))
            x :: bit_cast[Lanes](lane_bits)
            results :: bit_cast[f32[8]](checked.lanes(x))
            inputs :: bit_cast[f32[8]](x)
            for result, i in results {
                off :: ulps_off(result, checked.reference(cast[f64](inputs[i])))
                if off > 1 {
                    over += 1
                }
                if off > worst {
                    worst = off
                    worst_at = inputs[i]
                }
            }
            bits += 8
        }
        while bits < last
        io.printf("%: worst % ulp, at % (bits %{x}); % past 1 ulp\n", name, worst, worst_at, bit_cast[u32](worst_at), over)
        return if over == 0 { 0 } else { 1 }
    }
    io.printf("no function %\n", name)
    return 2
}
