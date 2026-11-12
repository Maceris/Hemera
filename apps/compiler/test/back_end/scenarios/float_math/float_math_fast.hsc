package float_math

import fast from "std/math"
import intrinsics from "base"
import math from "std"
import testing from "std"

/*
 * std/math/fast: its f32 kernels on every 65537th f32 and on pairs, against f64's functions; its f64 kernels against
 * the exact references and against std/math's on random arguments; each within its bound, eight or four lanes giving
 * one at a time's bits; and its special values.
 */

/** fast's bound, in ulp, where it has a kernel of its own. */
FAST_BOUND :: 3.5

/** fast's f32 kernels of one argument, by an index, for checking them alike. */
FAST_32 :: 11

/** One of fast's f32 kernels on eight lanes, by index. */
fast_32 :: fn(index: i32, x: vector[f32, 8]) -> vector[f32, 8] {
    match index {
        case 0 => return fast.exp(x)
        case 1 => return fast.exp2(x)
        case 2 => return fast.log(x)
        case 3 => return fast.log2(x)
        case 4 => return fast.sin(x)
        case 5 => return fast.cos(x)
        case 6 => return fast.tan(x)
        case 7 => return fast.asin(x)
        case 8 => return fast.acos(x)
        case 9 => return fast.atan(x)
        case _ => return fast.cube_root(x)
    }
}

/** The same on one f32. */
fast_scalar_32 :: fn(index: i32, x: f32) -> f32 {
    match index {
        case 0 => return fast.exp(x)
        case 1 => return fast.exp2(x)
        case 2 => return fast.log(x)
        case 3 => return fast.log2(x)
        case 4 => return fast.sin(x)
        case 5 => return fast.cos(x)
        case 6 => return fast.tan(x)
        case 7 => return fast.asin(x)
        case 8 => return fast.acos(x)
        case 9 => return fast.atan(x)
        case _ => return fast.cube_root(x)
    }
}

/** Its reference: std/math's f64 function. */
fast_reference_32 :: fn(index: i32, x: f64) -> f64 {
    match index {
        case 0 => return math.exp(x)
        case 1 => return math.exp2(x)
        case 2 => return math.log(x)
        case 3 => return math.log2(x)
        case 4 => return math.sin(x)
        case 5 => return math.cos(x)
        case 6 => return math.tan(x)
        case 7 => return math.asin(x)
        case 8 => return math.acos(x)
        case 9 => return math.atan(x)
        case _ => return math.cube_root(x)
    }
}

/** fast's f32 kernels on every 65537th f32 through the whole range: within its bound, eight lanes as one at a time. */
fast_is_within_its_bound_in_f32 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for index in 0..<FAST_32 {
        function :: cast[i32](index)
        worst := 0.0
        worst_at : f32 = 0
        same := true
        bits : u64 = 0
        loop {
            lanes : f32[8]
            for &lane, i in lanes {
                lane^ = bit_cast[f32](cast[u32]((bits + cast[u64](i) * 65537 * 8192) & 0xffff_ffff))
            }
            results :: bit_cast[f32[8]](fast_32(function, bit_cast[vector[f32, 8]](lanes)))
            for result, i in results {
                one :: fast_scalar_32(function, lanes[i])
                same = same && (bit_cast[u32](one) == bit_cast[u32](result) || (one != one && result != result))
                off :: ulps_off_32(result, fast_reference_32(function, cast[f64](lanes[i])))
                if off > worst {
                    worst = off
                    worst_at = lanes[i]
                }
            }
            bits += 65537
        }
        while bits < 8192 * 65537
        testing.note(t, "function % at %", index, worst_at)
        testing.expect_le(t, worst, FAST_BOUND * SHOW, "worst error, in f32 ulp: % against %")
        testing.expect(t, same, "eight lanes give one at a time's bits")
        testing.end_note(t)
    }
    return .Ok
}

/** fast's f32 atan2 on random pairs and on ordinary ones: within its bound of f64's. */
fast_atan2_is_within_its_bound_in_f32 #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    pairs : f32[8]
    for &value, i in pairs {
        value^ = if i < 4 { bit_cast[f32](testing.draw[u32](source)) }
            else { cast[f32](testing.draw_between(source, -100000, 100000)) / 1000 }
    }
    ys :: bit_cast[vector[f32, 8]](pairs)
    xs :: bit_cast[vector[f32, 8]](intrinsics.rotate_lanes(ys, 1))
    angles :: bit_cast[f32[8]](fast.atan2(ys, xs))
    others :: bit_cast[f32[8]](xs)
    for y, i in pairs {
        x :: others[i]
        testing.note(t, "atan2(%, %)", y, x)
        testing.expect_le(t, ulps_off_32(angles[i], math.atan2(cast[f64](y), cast[f64](x))), FAST_BOUND, "% ulp against %")
        one :: fast.atan2(y, x)
        testing.expect(t, bit_cast[u32](one) == bit_cast[u32](angles[i]) || (one != one && angles[i] != angles[i]),
            "eight lanes give one at a time's bits")
        testing.end_note(t)
    }
    return .Ok
}

/** Whether fast has a kernel of its own for a function on f64, and its value if so. */
fast_evaluate_64 :: fn(reference: Reference) -> f64? {
    x :: reference.x
    match reference.function {
        case .Exp => return fast.exp(x)
        case .Exp2 => return fast.exp2(x)
        case .Log => return fast.log(x)
        case .Log2 => return fast.log2(x)
        case .Sin => return fast.sin(x)
        case .Cos => return fast.cos(x)
        case .Asin => return fast.asin(x)
        case .Acos => return fast.acos(x)
        case .Atan => return fast.atan(x)
        case .Atan2 => return fast.atan2(x, reference.y)
        case _ => return null
    }
}

/** fast's f64 kernels against the exact references: within its bound. */
fast_is_within_its_bound_of_exact_in_f64 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    worst : f64[FUNCTION_COUNT]
    worst_at : f64[FUNCTION_COUNT]
    for reference in REFERENCES {
        result :: fast_evaluate_64(reference)
        if result is_none {
            continue
        }
        value :: result or_else 0.0
        // An infinite or NaN reference must be met exactly
        off :: if !math.is_finite(reference.hi) {
            if bit_cast[u64](value) == bit_cast[u64](reference.hi) || (value != value && reference.hi != reference.hi) { 0.0 }
            else { math.infinity[f64]() }
        }
        else { ulps_off(value, reference.hi, reference.lo) }
        index :: cast[usize](reference.function)
        if off > worst[index] {
            worst[index] = off
            worst_at[index] = reference.x
        }
    }
    for off, index in worst {
        testing.note(t, "% at %", cast[Function](index), worst_at[index])
        testing.expect_le(t, off, FAST_BOUND * SHOW, "worst error, in ulp: % against a bound of %")
        testing.end_note(t)
    }
    return .Ok
}

/** How far a fast f64 result is from std/math's, in ulp of std/math's. */
ulps_from_precise :: fn(result: f64, precise: f64) -> f64 {
    if result != result || precise != precise {
        return if result != result && precise != precise { 0.0 } else { math.infinity[f64]() }
    }
    if !math.is_finite(result) || !math.is_finite(precise) {
        return if result == precise { 0.0 } else { math.infinity[f64]() }
    }
    return abs(result - precise) / math.ulp(precise)
}

/**
 * fast's f64 kernels on random arguments: within 2.5 ulp of std/math's, which is within 1 of exact, so within its
 * bound of exact; four lanes as one at a time.
 */
fast_is_within_its_bound_in_f64 #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    xs : f64[4]
    ys : f64[4]
    for i in 0..<4 {
        xs[i] = draw_64(source)
        ys[i] = draw_64(source)
    }
    v :: bit_cast[vector[f64, 4]](xs)
    w :: bit_cast[vector[f64, 4]](ys)
    exp :: bit_cast[f64[4]](fast.exp(v))
    exp2 :: bit_cast[f64[4]](fast.exp2(v))
    log :: bit_cast[f64[4]](fast.log(v))
    log2 :: bit_cast[f64[4]](fast.log2(v))
    sin :: bit_cast[f64[4]](fast.sin(v))
    cos :: bit_cast[f64[4]](fast.cos(v))
    asin :: bit_cast[f64[4]](fast.asin(v))
    acos :: bit_cast[f64[4]](fast.acos(v))
    atan :: bit_cast[f64[4]](fast.atan(v))
    atan2 :: bit_cast[f64[4]](fast.atan2(v, w))
    for x, i in xs {
        y :: ys[i]
        testing.note(t, "lane %: % and %", i, x, y)
        testing.expect_le(t, ulps_from_precise(exp[i], math.exp(x)), 2.5, "exp: % ulp against %")
        testing.expect_le(t, ulps_from_precise(exp2[i], math.exp2(x)), 2.5, "exp2: % ulp against %")
        testing.expect_le(t, ulps_from_precise(log[i], math.log(x)), 2.5, "log: % ulp against %")
        testing.expect_le(t, ulps_from_precise(log2[i], math.log2(x)), 2.5, "log2: % ulp against %")
        testing.expect_le(t, ulps_from_precise(sin[i], math.sin(x)), 2.5, "sin: % ulp against %")
        testing.expect_le(t, ulps_from_precise(cos[i], math.cos(x)), 2.5, "cos: % ulp against %")
        testing.expect_le(t, ulps_from_precise(asin[i], math.asin(x)), 2.5, "asin: % ulp against %")
        testing.expect_le(t, ulps_from_precise(acos[i], math.acos(x)), 2.5, "acos: % ulp against %")
        testing.expect_le(t, ulps_from_precise(atan[i], math.atan(x)), 2.5, "atan: % ulp against %")
        testing.expect_le(t, ulps_from_precise(atan2[i], math.atan2(x, y)), 2.5, "atan2: % ulp against %")
        testing.expect(t, same_64(exp[i], fast.exp(x)) && same_64(exp2[i], fast.exp2(x)) && same_64(log[i], fast.log(x))
            && same_64(log2[i], fast.log2(x)) && same_64(sin[i], fast.sin(x)) && same_64(cos[i], fast.cos(x))
            && same_64(asin[i], fast.asin(x)) && same_64(acos[i], fast.acos(x)) && same_64(atan[i], fast.atan(x))
            && same_64(atan2[i], fast.atan2(x, y)), "four lanes give one at a time's bits")
        testing.end_note(t)
    }
    return .Ok
}

fast_knows_special_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    infinity :: math.infinity[f32]()
    nan :: math.nan[f32]()
    testing.expect(t, fast.exp(-infinity) == 0 && fast.exp(infinity) == infinity && math.is_nan(fast.exp(nan)), "exp")
    testing.expect(t, fast.exp(cast[f32](89)) == infinity && fast.exp(cast[f32](-105)) == 0, "exp beyond its range")
    testing.expect(t, fast.exp2(cast[f32](10)) == 1024 && fast.exp2(cast[f32](-149)) == 1e-45, "exp2 of whole numbers")
    testing.expect(t, fast.log(cast[f32](0)) == -infinity && math.is_nan(fast.log(cast[f32](-1))) && fast.log(infinity) == infinity
        && math.is_nan(fast.log(nan)), "log")
    testing.expect(t, fast.log2(cast[f32](1024)) == 10 && fast.log2(cast[f32](1e-45)) == -149, "log2 of powers of two")
    testing.expect(t, math.is_nan(fast.sin(infinity)) && math.is_nan(fast.cos(-infinity)) && math.is_nan(fast.tan(nan)), "trig")
    testing.expect(t, math.sign_bit(fast.sin(cast[f32](-0.0))) && math.sign_bit(fast.tan(cast[f32](-0.0)))
        && fast.cos(cast[f32](-0.0)) == 1, "signs of zero")
    testing.expect(t, math.is_nan(fast.asin(cast[f32](1.5))) && math.is_nan(fast.acos(cast[f32](-1.5))), "asin and acos past 1")
    testing.expect(t, fast.atan(infinity) == cast[f32](1.5707963267948966) && math.is_nan(fast.atan(nan)), "atan")
    testing.expect(t, fast.atan2(cast[f32](0), cast[f32](-1)) == cast[f32](3.141592653589793)
        && math.sign_bit(fast.atan2(cast[f32](-0.0), cast[f32](1))) && fast.atan2(infinity, -infinity) == cast[f32](2.356194490192345),
        "atan2 at its ends")
    testing.expect(t, fast.cube_root(cast[f32](-27)) == -3 && fast.cube_root(-infinity) == -infinity
        && math.sign_bit(fast.cube_root(cast[f32](-0.0))) && fast.cube_root(cast[f32](1e-40)) == math.cube_root(cast[f32](1e-40)),
        "cube_root")
    infinity_64 :: math.infinity[f64]()
    testing.expect(t, fast.exp(-infinity_64) == 0 && fast.exp(infinity_64) == infinity_64 && fast.exp(710.0) == infinity_64
        && fast.exp(-746.0) == 0, "exp in f64")
    testing.expect(t, fast.exp2(-1074.0) == 5e-324 && fast.exp2(1024.0) == infinity_64, "exp2 at its ends in f64")
    testing.expect(t, fast.log(0.0) == -infinity_64 && math.is_nan(fast.log(-1.0)) && fast.log2(5e-324) == -1074, "log in f64")
    testing.expect(t, math.is_nan(fast.sin(infinity_64)) && math.sign_bit(fast.sin(-0.0)) && fast.cos(0.0) == 1, "trig in f64")
    testing.expect(t, fast.sin(1e300) == math.sin(1e300) && fast.cos(-1e10) == math.cos(-1e10), "huge angles by std/math")
    testing.expect(t, fast.asin(1.0) == 1.5707963267948966 && fast.acos(-1.0) == 3.141592653589793 && math.is_nan(fast.acos(2.0)),
        "asin and acos at their ends in f64")
    testing.expect(t, fast.atan2(0.0, -0.0) == 3.141592653589793 && fast.atan2(-infinity_64, 1.0) == -1.5707963267948966,
        "atan2 at its ends in f64")
    testing.expect(t, fast.power(2.0, 10.0) == 1024 && fast.hypotenuse(cast[f32](3), cast[f32](4)) == 5, "std/math's own")
    return .Ok
}
