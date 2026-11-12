package float_math

import intrinsics from "base"
import math from "std"
import testing from "std"

/*
 * std/math against references worked out in more precision than f64 (float_math_references.hsc, made by
 * make_references.py with Python's decimal): every function within its ulp bound of the exact value, on chosen and
 * random arguments; then special values, and f32.
 */

/**
 * Give a function's f64 value at a reference's arguments.
 *
 * @param reference Which function, and its arguments.
 * @return The function's value.
 */
evaluate :: fn(reference: Reference) -> f64 {
    x :: reference.x
    y :: reference.y
    match reference.function {
        case .Exp => return math.exp(x)
        case .Exp2 => return math.exp2(x)
        case .ExpMinusOne => return math.exp_minus_one(x)
        case .Log => return math.log(x)
        case .Log2 => return math.log2(x)
        case .Log10 => return math.log10(x)
        case .LogOnePlus => return math.log_one_plus(x)
        case .Sin => return math.sin(x)
        case .Cos => return math.cos(x)
        case .Tan => return math.tan(x)
        case .Asin => return math.asin(x)
        case .Acos => return math.acos(x)
        case .Atan => return math.atan(x)
        case .Sinh => return math.sinh(x)
        case .Cosh => return math.cosh(x)
        case .Tanh => return math.tanh(x)
        case .Asinh => return math.asinh(x)
        case .Acosh => return math.acosh(x)
        case .Atanh => return math.atanh(x)
        case .CubeRoot => return math.cube_root(x)
        case .Erf => return math.erf(x)
        case .Erfc => return math.erfc(x)
        case .ErfInverse => return math.erf_inverse(x)
        case .Gamma => return math.gamma(x)
        case .LogGamma => return math.log_gamma(x)
        case .Power => return math.power(x, y)
        case .Atan2 => return math.atan2(x, y)
        case .Hypotenuse => return math.hypotenuse(x, y)
        case .TruncatedRemainder => return math.truncated_remainder(x, y)
        case .Remainder => return math.remainder(x, y)
    }
}

/**
 * Give how far a result is from the exact value, in units of the last place of the exact value rounded.
 *
 * @param result What the function gave.
 * @param hi The exact value rounded to f64.
 * @param lo The exact value less hi.
 * @return |result - (hi + lo)| / ulp(hi); infinity for a NaN or infinite result.
 */
ulps_off :: fn(result: f64, hi: f64, lo: f64) -> f64 {
    if !math.is_finite(result) {
        return math.infinity[f64]()
    }
    return abs((result - hi) - lo) / math.ulp(hi)
}

/** 1, or 0 to have every function's worst error reported as a failure. */
SHOW :: 1.0

/** The most ulp each function may be off: fdlibm's 1, but where its documentation says otherwise. */
bound_of :: fn(function: Function) -> f64 {
    match function {
        case .Atanh => return 1.5
        case .Erfc => return 2
        case .ErfInverse => return 2
        case .Gamma => return 6
        case .LogGamma => return 1
        case .TruncatedRemainder => return 0
        case .Remainder => return 0
        case _ => return 1
    }
}

/** ln Γ, whose error is small absolutely where its value is below 1, near its zeros: measured in ulp(1) there. */
near_log_gamma_zero :: fn(reference: Reference) -> bool {
    return reference.function == .LogGamma && abs(reference.hi) < 1
}

is_within_ulps_of_exact #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    worst : f64[FUNCTION_COUNT]
    worst_at : f64[FUNCTION_COUNT]
    for reference in REFERENCES {
        result :: evaluate(reference)
        off :: if near_log_gamma_zero(reference) { abs((result - reference.hi) - reference.lo) / 2.220446049250313e-16 }
            else { ulps_off(result, reference.hi, reference.lo) }
        index :: cast[usize](reference.function)
        if index >= worst.count {
            continue
        }
        if off > worst[index] {
            worst[index] = off
            worst_at[index] = reference.x
        }
    }
    for off, index in worst {
        function :: cast[Function](index)
        testing.note(t, "% at %", function, worst_at[index])
        testing.expect_le(t, off, bound_of(function) * SHOW, "worst error, in ulp: % against a bound of %")
        testing.end_note(t)
    }
    return .Ok
}

knows_special_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    infinity :: math.infinity[f64]()
    nan :: math.nan[f64]()
    testing.expect(t, math.exp(-infinity) == 0 && math.exp(infinity) == infinity && math.is_nan(math.exp(nan)), "exp")
    testing.expect(t, math.exp(1000.0) == infinity && math.exp(-1000.0) == 0, "exp beyond its range")
    testing.expect(t, math.log(0.0) == -infinity && math.is_nan(math.log(-1.0)) && math.log(infinity) == infinity, "log")
    testing.expect(t, math.log2(1024.0) == 10 && math.log2(5e-324) == -1074, "log2 of powers of two")
    testing.expect(t, math.exp2(-1074.0) == 5e-324 && math.exp2(1024.0) == infinity, "exp2 at its ends")
    testing.expect(t, math.log_one_plus(-1.0) == -infinity && math.is_nan(math.log_one_plus(-2.0)), "log_one_plus")
    testing.expect(t, math.exp_minus_one(-infinity) == -1 && math.exp_minus_one(-100.0) == -1, "exp_minus_one")
    testing.expect(t, math.is_nan(math.sin(infinity)) && math.is_nan(math.cos(-infinity)) && math.is_nan(math.tan(nan)), "trig")
    testing.expect(t, math.sign_bit(math.sin(-0.0)) && math.sign_bit(math.tan(-0.0)) && math.cos(-0.0) == 1, "signs of zero")
    testing.expect(t, math.is_nan(math.asin(1.5)) && math.asin(1.0) == 1.5707963267948966 && math.acos(-1.0) == 3.141592653589793,
        "asin and acos")
    testing.expect(t, math.atan(infinity) == 1.5707963267948966 && math.atan2(0.0, -1.0) == 3.141592653589793
        && math.atan2(-0.0, -1.0) == -3.141592653589793 && math.atan2(infinity, -infinity) == 2.356194490192345, "atan2")
    testing.expect(t, math.power(nan, 0.0) == 1 && math.power(1.0, nan) == 1 && math.is_nan(math.power(-2.0, 0.5)), "power's NaNs")
    testing.expect(t, math.power(-0.0, -3.0) == -infinity && math.power(0.0, -2.0) == infinity && math.power(-8.0, 1.0 / 3.0) != -2,
        "power of zero")
    testing.expect(t, math.power(2.0, -1074.0) == 5e-324 && math.power(2.0, 1024.0) == infinity, "power at its ends")
    testing.expect(t, math.hypotenuse(infinity, nan) == infinity && math.is_nan(math.hypotenuse(nan, 1.0)), "hypotenuse")
    testing.expect(t, math.cube_root(-27.0) == -3 && math.cube_root(-0.0) == 0 && math.sign_bit(math.cube_root(-0.0)), "cube_root")
    testing.expect(t, math.tanh(infinity) == 1 && math.atanh(1.0) == infinity && math.is_nan(math.acosh(0.5)), "hyperbolic")
    testing.expect(t, math.erf(infinity) == 1 && math.erfc(-infinity) == 2 && math.erfc(30.0) == 0, "erf")
    testing.expect(t, math.erf_inverse(1.0) == infinity && math.erf_inverse(0.0) == 0 && math.is_nan(math.erf_inverse(1.5)),
        "erf_inverse")
    testing.expect(t, math.gamma(5.0) == 24 && math.gamma(23.0) == 1124000727777607680000.0 && math.is_nan(math.gamma(-3.0))
        && math.gamma(0.0) == infinity && math.gamma(200.0) == infinity, "gamma")
    testing.expect(t, math.log_gamma(1.0) == 0 && math.log_gamma(2.0) == 0 && math.log_gamma(-2.0) == infinity, "log_gamma")
    _, negative :: math.log_gamma_signed(-0.5)
    _, positive :: math.log_gamma_signed(-1.5)
    testing.expect(t, negative == -1 && positive == 1, "Γ's sign between the poles")
    testing.expect(t, math.is_nan(math.truncated_remainder(1.0, 0.0)) && math.truncated_remainder(5.0, infinity) == 5
        && math.sign_bit(math.truncated_remainder(-6.0, 3.0)), "truncated_remainder")
    testing.expect(t, math.remainder(5.0, 2.0) == 1 && math.remainder(7.0, 2.0) == -1 && math.sign_bit(math.remainder(-4.0, 2.0)),
        "remainder, halfway to even")
    return .Ok
}

knows_floats_bits #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, math.next_up(1.0), 1.0000000000000002, "next_up")
    testing.expect_eq(t, math.next_down(1.0), 0.9999999999999999, "next_down")
    testing.expect_eq(t, math.next_up(-0.0), 5e-324, "next_up of -0")
    testing.expect_eq(t, math.next_up(math.largest[f64]()), math.infinity[f64](), "past the largest")
    testing.expect_eq(t, math.ulp(1.0), math.epsilon[f64](), "ulp(1)")
    testing.expect_eq(t, math.ulp(0.0), 5e-324, "ulp(0)")
    testing.expect_eq(t, math.ulp(cast[f32](1)), math.epsilon[f32](), "ulp(1) in f32")
    testing.expect_eq(t, math.next_up(cast[f32](1)), cast[f32](1.0000001), "next_up in f32")
    fraction, exponent :: math.fraction_and_exponent(48.0)
    testing.expect(t, fraction == 0.75 && exponent == 6, "fraction_and_exponent")
    small, small_exponent :: math.fraction_and_exponent(5e-324)
    testing.expect(t, small == 0.5 && small_exponent == -1073, "of a subnormal")
    testing.expect_eq(t, math.scale_by_power_of_two(0.75, 6), 48.0, "scale_by_power_of_two")
    testing.expect_eq(t, math.scale_by_power_of_two(1.0, -1074), 5e-324, "to the least subnormal")
    testing.expect_eq(t, math.scale_by_power_of_two(cast[f32](1), 200), math.infinity[f32](), "overflowing in f32")
    testing.expect(t, math.is_subnormal(5e-324) && !math.is_normal(5e-324) && math.is_normal(1.0) && !math.is_subnormal(0.0),
        "normal and subnormal")
    testing.expect(t, math.is_infinite(math.infinity[f32]()) && !math.is_finite(math.nan[f64]()) && math.is_finite(1.0), "finite")
    return .Ok
}

/**
 * How far an f32 result is from the f64 function's, in units of its last place as an f32: 0 for two NaNs or the same
 * infinity, infinity for a NaN or infinity against something else.
 */
ulps_off_32 :: fn(result: f32, reference: f64) -> f64 {
    rounded :: cast[f32](reference)
    if result != result || rounded != rounded {
        return if result != result && rounded != rounded { 0.0 } else { math.infinity[f64]() }
    }
    if math.is_infinite(result) || math.is_infinite(rounded) {
        return if result == rounded { 0.0 } else { math.infinity[f64]() }
    }
    return abs(cast[f64](result) - reference) / cast[f64](math.ulp(rounded))
}

/** The functions with f32 kernels of their own, by an index, for checking them alike. */
FUNCTIONS_32 :: 14

/** Give one of the f32 kernels' functions on eight lanes, and its f64 reference, by index. */
function_32 :: fn(index: i32, x: vector[f32, 8]) -> vector[f32, 8] {
    match index {
        case 0 => return math.exp(x)
        case 1 => return math.exp2(x)
        case 2 => return math.exp_minus_one(x)
        case 3 => return math.log(x)
        case 4 => return math.log2(x)
        case 5 => return math.log10(x)
        case 6 => return math.log_one_plus(x)
        case 7 => return math.sin(x)
        case 8 => return math.cos(x)
        case 9 => return math.tan(x)
        case 10 => return math.asin(x)
        case 11 => return math.acos(x)
        case 12 => return math.atan(x)
        case _ => return math.cube_root(x)
    }
}

/** The same function on one f32. */
scalar_32 :: fn(index: i32, x: f32) -> f32 {
    match index {
        case 0 => return math.exp(x)
        case 1 => return math.exp2(x)
        case 2 => return math.exp_minus_one(x)
        case 3 => return math.log(x)
        case 4 => return math.log2(x)
        case 5 => return math.log10(x)
        case 6 => return math.log_one_plus(x)
        case 7 => return math.sin(x)
        case 8 => return math.cos(x)
        case 9 => return math.tan(x)
        case 10 => return math.asin(x)
        case 11 => return math.acos(x)
        case 12 => return math.atan(x)
        case _ => return math.cube_root(x)
    }
}

/** Its f64 reference. */
reference_64 :: fn(index: i32, x: f64) -> f64 {
    match index {
        case 0 => return math.exp(x)
        case 1 => return math.exp2(x)
        case 2 => return math.exp_minus_one(x)
        case 3 => return math.log(x)
        case 4 => return math.log2(x)
        case 5 => return math.log10(x)
        case 6 => return math.log_one_plus(x)
        case 7 => return math.sin(x)
        case 8 => return math.cos(x)
        case 9 => return math.tan(x)
        case 10 => return math.asin(x)
        case 11 => return math.acos(x)
        case 12 => return math.atan(x)
        case _ => return math.cube_root(x)
    }
}

/**
 * f32's kernels on every 65537th f32, all 65,536 of them through the whole range: within 1 ulp of the f64 functions,
 * and on eight lanes the same bits as one at a time. float_math_exhaustive does every f32, by hand.
 */
works_in_f32 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for index in 0..<FUNCTIONS_32 {
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
            results :: bit_cast[f32[8]](function_32(function, bit_cast[vector[f32, 8]](lanes)))
            for result, i in results {
                one :: scalar_32(function, lanes[i])
                same = same && (bit_cast[u32](one) == bit_cast[u32](result) || (one != one && result != result))
                off :: ulps_off_32(result, reference_64(function, cast[f64](lanes[i])))
                if off > worst {
                    worst = off
                    worst_at = lanes[i]
                }
            }
            bits += 65537
        }
        while bits < 8192 * 65537
        testing.note(t, "function % at %", index, worst_at)
        testing.expect_le(t, worst, 1.0, "worst error, in f32 ulp: % against %")
        testing.expect(t, same, "eight lanes give one at a time's bits")
        testing.end_note(t)
    }
    s, c :: math.sin_cos(cast[f32](2.5))
    testing.expect(t, s == math.sin(cast[f32](2.5)) && c == math.cos(cast[f32](2.5)), "sin_cos as sin and cos")
    return .Ok
}

/** f32's functions of two, on random pairs, within 1 ulp of f64's. */
works_in_f32_on_pairs #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    x :: bit_cast[f32](testing.draw[u32](source))
    y :: bit_cast[f32](testing.draw[u32](source))
    small :: cast[f32](testing.draw_between(source, 1, 1600)) / 100
    exponent :: cast[f32](testing.draw_between(source, -6400, 6400)) / 100
    check_pair(t, x, y)
    check_pair(t, small, exponent)
    return .Ok
}

/** Hold power, atan2 and hypotenuse on one pair of f32s to 1 ulp of f64's. */
check_pair :: fn(t: ptr[mut testing.T], a: f32, b: f32) {
    testing.expect_le(t, ulps_off_32(math.power(a, b), math.power(cast[f64](a), cast[f64](b))), 1.0, "power: % against %")
    testing.expect_le(t, ulps_off_32(math.atan2(a, b), math.atan2(cast[f64](a), cast[f64](b))), 1.0, "atan2: % against %")
    testing.expect_le(t, ulps_off_32(math.hypotenuse(a, b), math.hypotenuse(cast[f64](a), cast[f64](b))), 1.0,
        "hypotenuse: % against %")
}

/** sin² + cos² = 1, exp and log undo each other, and the like, over arguments drawn anywhere. */
keeps_identities #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    x :: bit_cast[f64](testing.draw[u64](source))
    testing.assume(t, math.is_finite(x), "a finite x")?
    s, c :: math.sin_cos(x)
    testing.expect_within(t, s * s + c * c, 1 - 4e-16, 1 + 4e-16, "sin² + cos² is %, not within % to %")
    testing.expect_within(t, s, -1.0, 1.0, "sin within ±1: %, not within % to %")
    small :: math.truncated_remainder(x, 700.0)
    testing.expect_within(t, math.log(math.exp(small)), small - 1e-12 - abs(small) * 1e-15, small + 1e-12 + abs(small) * 1e-15,
        "log(exp(x)) is %, not within % to %")
    root :: math.cube_root(x)
    testing.expect_within(t, root * root * root, x - abs(x) * 1e-15, x + abs(x) * 1e-15, "∛x³ is %, not within % to %")
    return .Ok
}

computes_constants_at_compile_time #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    SINE :: #run math.sin(0.5)
    testing.expect_eq(t, SINE, math.sin(0.5), "the same at compile time as at run time")
    return .Ok
}

/** Every case's text parses to the f64 and f32 nearest it, or to none where it isn't a number. */
parses_correctly_rounded #test(PARSE_CASES) :: fn(t: ptr[mut testing.T], item: ParseCase) -> testing.Outcome {
    wide :: math.parse[f64](item.text)
    narrow :: math.parse[f32](item.text)
    if !item.valid {
        testing.expect(t, (wide is_none) && (narrow is_none), "not a number")
        return .Ok
    }
    testing.expect_eq(t, bit_cast[u64](wide or_else 0), item.bits_64, "f64: %{x} against %{x}")
    testing.expect_eq(t, bit_cast[u32](narrow or_else 0), item.bits_32, "f32: %{x} against %{x}")
    return .Ok
}

parses_special_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, math.parse[f64]("inf") == math.infinity[f64]() && math.parse[f64]("-Infinity") == -math.infinity[f64](),
        "infinities")
    testing.expect(t, math.is_nan(math.parse[f64]("NaN") or_else 0) && math.is_nan(math.parse[f32]("nan") or_else 0), "NaN")
    return .Ok
}

/** A compile-time call in a generic's #if decides for each instance: the same node, other answers. */
kind_of :: fn[F]() -> i32 {
    #if math.float_kind(F) == math.FLOAT_32 {
        return 32
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return 64
    }
    #else {
        return 0
    }
}

picks_branches_for_each_instance #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, kind_of[f32](), 32, "f32")
    testing.expect_eq(t, kind_of[f64](), 64, "f64, not f32's answer again")
    testing.expect_eq(t, kind_of[u8](), 0, "neither")
    return .Ok
}

/** Vectors: n bound from vector[T, n], lanes cast as numbers, and functions without kernels lane by lane. */
works_on_vectors #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    v :: vector[f32, 4].{1.5, -2.5, 3, 0.25}
    whole :: cast[vector[i32, 4]](v)
    testing.expect(t, intrinsics.all_true(whole == vector[i32, 4].{1, -2, 3, 0}), "f32 lanes to i32, truncated")
    testing.expect(t, intrinsics.all_true(cast[vector[f64, 4]](whole) == vector[f64, 4].{1, -2, 3, 0}), "and to f64")
    wide :: vector[f64, 2].{0.5, 2}
    lanes :: bit_cast[f64[2]](math.sinh(wide))
    testing.expect(t, lanes[0] == math.sinh(0.5) && lanes[1] == math.sinh(2.0), "an f64 function lane by lane")
    narrow :: bit_cast[f32[4]](math.erf(v))
    testing.expect(t, narrow[1] == math.erf(cast[f32](-2.5)), "an f32 one")
    return .Ok
}

/** Whether two f64s are the same bits, any NaN being any other. */
same_64 :: fn(a: f64, b: f64) -> bool {
    return (a != a && b != b) || bit_cast[u64](a) == bit_cast[u64](b)
}

/** An f64 drawn from any bits, or near where the functions' branches part. */
draw_64 :: fn(source: ptr[mut testing.Source]) -> f64 {
    match testing.draw_below(source, 5) {
        case 0 => return bit_cast[f64](testing.draw[u64](source))
        case 1 => return cast[f64](testing.draw_between(source, -2000000, 2000000)) / 1000000
        case 2 => return cast[f64](testing.draw_between(source, -100000000, 100000000)) / 1000
        case 3 => return cast[f64](testing.draw_between(source, -64000000, 64000000)) / 1000000
        case _ => return bit_cast[f64](testing.draw[u64](source) & 0x3fff_ffff_ffff_ffff) * (if testing.draw_bool(source) { 1.0 } else { -1.0 })
    }
}

/** f64's kernels on four lanes give each lane the scalar function's bits exactly. */
works_on_f64_lanes #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    xs : f64[4]
    ys : f64[4]
    wholes : f64[4]
    for i in 0..<4 {
        xs[i] = draw_64(source)
        ys[i] = draw_64(source)
        wholes[i] = cast[f64](testing.draw_between(source, -40, 40))
    }
    v :: bit_cast[vector[f64, 4]](xs)
    w :: bit_cast[vector[f64, 4]](ys)
    exp :: bit_cast[f64[4]](math.exp(v))
    log :: bit_cast[f64[4]](math.log(v))
    sin :: bit_cast[f64[4]](math.sin(v))
    cos :: bit_cast[f64[4]](math.cos(v))
    tan :: bit_cast[f64[4]](math.tan(v))
    atan :: bit_cast[f64[4]](math.atan(v))
    asin :: bit_cast[f64[4]](math.asin(v))
    acos :: bit_cast[f64[4]](math.acos(v))
    atan2 :: bit_cast[f64[4]](math.atan2(v, w))
    exp2 :: bit_cast[f64[4]](math.exp2(v))
    exp_minus_one :: bit_cast[f64[4]](math.exp_minus_one(v))
    log2 :: bit_cast[f64[4]](math.log2(v))
    log10 :: bit_cast[f64[4]](math.log10(v))
    log_one_plus :: bit_cast[f64[4]](math.log_one_plus(v))
    cube_root :: bit_cast[f64[4]](math.cube_root(v))
    hypotenuse :: bit_cast[f64[4]](math.hypotenuse(v, w))
    power :: bit_cast[f64[4]](math.power(v, w))
    whole_power :: bit_cast[f64[4]](math.power(v, bit_cast[vector[f64, 4]](wholes)))
    for x, i in xs {
        testing.note(t, "lane %: % and %", i, x, ys[i])
        testing.expect(t, same_64(exp[i], math.exp(x)), "exp")
        testing.expect(t, same_64(log[i], math.log(x)), "log")
        testing.expect(t, same_64(sin[i], math.sin(x)), "sin")
        testing.expect(t, same_64(cos[i], math.cos(x)), "cos")
        testing.expect(t, same_64(tan[i], math.tan(x)), "tan")
        testing.expect(t, same_64(atan[i], math.atan(x)), "atan")
        testing.expect(t, same_64(asin[i], math.asin(x)), "asin")
        testing.expect(t, same_64(acos[i], math.acos(x)), "acos")
        testing.expect(t, same_64(atan2[i], math.atan2(x, ys[i])), "atan2")
        testing.expect(t, same_64(exp2[i], math.exp2(x)), "exp2")
        testing.expect(t, same_64(exp_minus_one[i], math.exp_minus_one(x)), "exp_minus_one")
        testing.expect(t, same_64(log2[i], math.log2(x)), "log2")
        testing.expect(t, same_64(log10[i], math.log10(x)), "log10")
        testing.expect(t, same_64(log_one_plus[i], math.log_one_plus(x)), "log_one_plus")
        testing.expect(t, same_64(cube_root[i], math.cube_root(x)), "cube_root")
        testing.expect(t, same_64(hypotenuse[i], math.hypotenuse(x, ys[i])), "hypotenuse")
        testing.expect(t, same_64(power[i], math.power(x, ys[i])), "power")
        testing.expect(t, same_64(whole_power[i], math.power(x, wholes[i])), "power to a whole number")
        testing.end_note(t)
    }
    return .Ok
}
