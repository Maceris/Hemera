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

/** f32's functions are f64's rounded once, so within 1 ulp of f32 of the exact value, which the f64 one is near. */
works_in_f32 #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    x :: cast[f32](testing.draw_between(source, -2000, 2000)) / 100
    wide :: cast[f64](x)
    testing.expect_eq(t, math.sin(x), cast[f32](math.sin(wide)), "sin")
    testing.expect_eq(t, math.exp(x), cast[f32](math.exp(wide)), "exp")
    testing.expect_eq(t, math.atan(x), cast[f32](math.atan(wide)), "atan")
    s, c :: math.sin_cos(x)
    testing.expect(t, s == math.sin(x) && c == math.cos(x), "sin_cos as sin and cos")
    if x > 0 {
        testing.expect_eq(t, math.log(x), cast[f32](math.log(wide)), "log")
        testing.expect_eq(t, math.power(x, cast[f32](1.5)), cast[f32](math.power(wide, 1.5)), "power")
    }
    return .Ok
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
