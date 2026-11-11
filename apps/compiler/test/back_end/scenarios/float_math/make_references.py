"""
Write float_math_references.hsc: std/math's functions' exact values, as f64 pairs hi + lo, at arguments chosen and
drawn at random, for float_math.hsc to hold each function to its ulp bound. The values are worked out with Python's
decimal, to far more digits than an f64 has, and fractions where they're exact.

    python make_references.py
"""

import math
import random
import struct
from decimal import Decimal, getcontext, localcontext
from fractions import Fraction
from pathlib import Path

getcontext().prec = 80
HERE = Path(__file__).parent


def pi_to(digits):
    with localcontext() as context:
        context.prec = digits + 10

        def arctan_inverse(n):
            x = Decimal(1) / n
            x2 = x * x
            term, total, k = x, Decimal(0), 0
            while True:
                add = term / (2 * k + 1)
                if add == 0 or abs(add) < Decimal(10) ** -(digits + 8):
                    break
                total += add if k % 2 == 0 else -add
                term *= x2
                k += 1
            return total

        return +(4 * (4 * arctan_inverse(5) - arctan_inverse(239)))


PI = pi_to(800)


def d(x):
    return Decimal(x)


def sin_cos_exact(x):
    """sin x and cos x for a float x, with x reduced by 2π in enough digits for any f64."""
    with localcontext() as context:
        exponent = max(0, math.frexp(x)[1])
        context.prec = 60 + exponent // 3 + 20
        two_pi = 2 * PI
        r = d(x) % two_pi
        context.prec = 80
        r = +r
        # Taylor series, after halving r to speed it, then doubling back
        halvings = 8
        r = r / (2 ** halvings)
        r2 = r * r
        s, term, n = Decimal(0), r, 1
        while abs(term) > Decimal(10) ** -100:
            s += term
            term = -term * r2 / ((n + 1) * (n + 2))
            n += 2
        c, term, n = Decimal(0), Decimal(1), 0
        while abs(term) > Decimal(10) ** -100:
            c += term
            term = -term * r2 / ((n + 1) * (n + 2))
            n += 2
        for _ in range(halvings):
            s, c = 2 * s * c, c * c - s * s
        return s, c


def atan_exact(x):
    x = d(x)
    if x < 0:
        return -atan_exact(-x)
    if x > 1:
        return PI / 2 - atan_exact(1 / x)
    # Halve the angle until small: atan x = 2 atan(x / (1 + √(1 + x²)))
    halvings = 0
    while x > Decimal("0.01"):
        x = x / (1 + (1 + x * x).sqrt())
        halvings += 1
    x2 = x * x
    total, term, k = Decimal(0), x, 0
    while abs(term) > Decimal(10) ** -100 * abs(x):
        total += term / (2 * k + 1) if k % 2 == 0 else -term / (2 * k + 1)
        term *= x2
        k += 1
    return total * (2 ** halvings)


def expm1_exact(x):
    x = d(x)
    if abs(x) < Decimal("1e-5"):
        total, term, n = Decimal(0), x, 1
        while abs(term) > Decimal(10) ** -100 * abs(x):
            total += term
            n += 1
            term = term * x / n
        return total
    with localcontext() as context:
        context.prec = 120
        return +(x.exp() - 1)


def log1p_exact(x):
    x = d(x)
    if abs(x) < Decimal("1e-5"):
        total, term, n = Decimal(0), x, 1
        while abs(term) > Decimal(10) ** -100 * abs(x):
            total += term / n
            n += 1
            term = -term * x
        return total
    with localcontext() as context:
        context.prec = 120
        return +(1 + x).ln()


def erf_exact(x):
    x = d(x)
    if abs(x) >= 2:
        return (1 - erfc_exact(abs(x))) * (1 if x > 0 else -1)
    with localcontext() as context:
        context.prec = 120
        x2 = x * x
        total, term, n = Decimal(0), x, 0
        while abs(term) > Decimal(10) ** -110:
            total += term / (2 * n + 1)
            n += 1
            term = -term * x2 / n
        return total * 2 / PI.sqrt()


def erfc_exact(x):
    x = d(x)
    if x < 2:
        with localcontext() as context:
            context.prec = 120
            return 1 - erf_exact(x)
    # Continued fraction: erfc x = e^(-x²)/√π × 1/(x + (1/2)/(x + 1/(x + (3/2)/(x + ...)))), from the far end
    with localcontext() as context:
        context.prec = 100
        tail = Decimal(0)
        for k in range(2000, 0, -1):
            tail = (Decimal(k) / 2) / (x + tail)
        return (-x * x).exp() / PI.sqrt() / (x + tail)


BERNOULLI = [Fraction(1, 6), Fraction(-1, 30), Fraction(1, 42), Fraction(-1, 30), Fraction(5, 66), Fraction(-691, 2730),
             Fraction(7, 6), Fraction(-3617, 510), Fraction(43867, 798), Fraction(-174611, 330),
             Fraction(854513, 138), Fraction(-236364091, 2730), Fraction(8553103, 6), Fraction(-23749461029, 870)]


def log_gamma_positive(x):
    """ln Γ(x) for x > 0, by recurrence up to 40 and Stirling's series."""
    with localcontext() as context:
        context.prec = 120
        x = d(x)
        shift = Decimal(0)
        while x < 40:
            shift += x.ln()
            x += 1
        total = (x - Decimal("0.5")) * x.ln() - x + (2 * PI).ln() / 2
        power = x
        x2 = x * x
        for k, b in enumerate(BERNOULLI, start=1):
            total += Decimal(b.numerator) / Decimal(b.denominator) / (2 * k * (2 * k - 1)) / power
            power *= x2
        return total - shift


def log_gamma_exact(x):
    if x > 0:
        return log_gamma_positive(x)
    # Reflection: ln |Γ(x)| = ln π - ln |sin(π x)| - ln |Γ(1 - x)|
    with localcontext() as context:
        context.prec = 120
        s, _ = sin_cos_exact_pi(x)
        return PI.ln() - abs(s).ln() - log_gamma_positive(1 - x)


def sin_cos_exact_pi(x):
    """sin(π x), exactly reduced: x modulo 2 is exact."""
    with localcontext() as context:
        context.prec = 120
        r = d(x) % 2
        angle = r * PI
        halvings = 8
        angle = angle / (2 ** halvings)
        a2 = angle * angle
        s, term, n = Decimal(0), angle, 1
        while abs(term) > Decimal(10) ** -110:
            s += term
            term = -term * a2 / ((n + 1) * (n + 2))
            n += 2
        c, term, n = Decimal(0), Decimal(1), 0
        while abs(term) > Decimal(10) ** -110:
            c += term
            term = -term * a2 / ((n + 1) * (n + 2))
            n += 2
        for _ in range(halvings):
            s, c = 2 * s * c, c * c - s * s
        return s, c


def gamma_exact(x):
    with localcontext() as context:
        context.prec = 120
        if x > 0:
            return log_gamma_positive(x).exp()
        s, _ = sin_cos_exact_pi(x)
        # Γ(x) = π / (sin(π x) Γ(1 - x))
        return PI / (s * log_gamma_positive(1 - x).exp())


def cube_root_exact(x):
    x = d(x)
    if x == 0:
        return x
    sign = 1 if x > 0 else -1
    x = abs(x)
    with localcontext() as context:
        context.prec = 120
        r = Decimal(float(x) ** (1.0 / 3.0))
        for _ in range(8):
            r = r - (r * r * r - x) / (3 * r * r)
        return sign * r


def asin_exact(x):
    x = d(x)
    if x == 1:
        return PI / 2
    if x == -1:
        return -PI / 2
    return atan_exact_decimal(x / (1 - x * x).sqrt())


def atan_exact_decimal(x):
    return atan_exact(x)


def atan2_exact(y, x):
    if x > 0:
        return atan_exact(d(y) / d(x))
    if x < 0:
        a = atan_exact(d(y) / d(x))
        return a + PI if y >= 0 else a - PI
    return PI / 2 if y > 0 else -PI / 2


def asinh_exact(x):
    x = d(x)
    if abs(x) < Decimal("1e-5"):
        # x - x³/6 + 3x^5/40 - ...
        total, term, n = Decimal(0), x, 0
        coefficient = Decimal(1)
        while abs(term) > Decimal(10) ** -100 * abs(x):
            total += coefficient * term / (2 * n + 1)
            coefficient = -coefficient * (2 * n + 1) / (2 * n + 2)
            term *= x * x
            n += 1
        return total
    with localcontext() as context:
        context.prec = 120
        return (abs(x) + (x * x + 1).sqrt()).ln() * (1 if x > 0 else -1)


def atanh_exact(x):
    x = d(x)
    if abs(x) < Decimal("1e-5"):
        total, term, n = Decimal(0), x, 0
        while abs(term) > Decimal(10) ** -100 * abs(x):
            total += term / (2 * n + 1)
            term *= x * x
            n += 1
        return total
    with localcontext() as context:
        context.prec = 120
        return ((1 + x) / (1 - x)).ln() / 2


def fmod_exact(x, y):
    fx, fy = Fraction(x), Fraction(y)
    q = abs(fx) // abs(fy)
    r = abs(fx) - q * abs(fy)
    return Decimal(r.numerator) / Decimal(r.denominator) * (1 if x > 0 else -1)


def remainder_exact(x, y):
    fx, fy = Fraction(x), Fraction(y)
    quotient = fx / fy
    n = math.floor(quotient)
    if quotient - n > Fraction(1, 2) or (quotient - n == Fraction(1, 2) and n % 2 == 1):
        n += 1
    r = fx - n * fy
    with localcontext() as context:
        context.prec = 400
        return Decimal(r.numerator) / Decimal(r.denominator)


def power_exact(x, y):
    with localcontext() as context:
        context.prec = 120
        if x < 0:
            value = (-d(x)).ln() * d(y)
            sign = -1 if int(y) % 2 == 1 else 1
            return sign * value.exp()
        return (d(x).ln() * d(y)).exp()


def erf_inverse_exact(y):
    # Newton on erf, in decimal, from the f64 guess
    x = Decimal(guess_erf_inverse(y))
    target = d(y)
    for _ in range(30):
        if abs(target) < Decimal("0.5"):
            f = erf_exact(x) - target
        elif target > 0:
            f = (1 - target) - erfc_exact(x)
        else:
            f = erfc_exact(-x) - (1 + target)
        slope = 2 / PI.sqrt() * (-x * x).exp()
        step = f / slope
        x -= step
        if abs(step) < Decimal(10) ** -60 * abs(x):
            break
    return x


def guess_erf_inverse(y):
    # Bisection on math.erf, good enough to start Newton
    low, high = -6.0, 6.0
    for _ in range(80):
        mid = (low + high) / 2
        if math.erf(mid) < y:
            low = mid
        else:
            high = mid
    return (low + high) / 2


FUNCTIONS = {
    "exp": (lambda x: d(x).exp(), 1),
    "exp2": (lambda x: (d(x) * Decimal(2).ln()).exp(), 1),
    "exp_minus_one": (expm1_exact, 1),
    "log": (lambda x: d(x).ln(), 1),
    "log2": (lambda x: d(x).ln() / Decimal(2).ln(), 1),
    "log10": (lambda x: d(x).log10(), 1),
    "log_one_plus": (log1p_exact, 1),
    "sin": (lambda x: sin_cos_exact(x)[0], 1),
    "cos": (lambda x: sin_cos_exact(x)[1], 1),
    "tan": (lambda x: (lambda s, c: s / c)(*sin_cos_exact(x)), 1),
    "asin": (asin_exact, 1),
    "acos": (lambda x: PI / 2 - asin_exact(x), 1),
    "atan": (atan_exact, 1),
    "sinh": (lambda x: (lambda e: (e - 1 / e) / 2)(d(x).exp()) if abs(x) > 1e-5 else asinh_series_sinh(x), 1),
    "cosh": (lambda x: (lambda e: (e + 1 / e) / 2)(d(x).exp()), 1),
    "tanh": (lambda x: tanh_exact(x), 1),
    "asinh": (asinh_exact, 1),
    "acosh": (lambda x: (d(x) + (d(x) * d(x) - 1).sqrt()).ln(), 1),
    "atanh": (atanh_exact, 1),
    "cube_root": (cube_root_exact, 1),
    "erf": (erf_exact, 1),
    "erfc": (erfc_exact, 1),
    "erf_inverse": (erf_inverse_exact, 2),
    "gamma": (gamma_exact, 0),
    "log_gamma": (lambda x: log_gamma_exact(x), 0),
}

BINARY = {
    "power": (power_exact, 1),
    "atan2": (atan2_exact, 1),
    "hypotenuse": (lambda x, y: (d(x) * d(x) + d(y) * d(y)).sqrt(), 1),
    "truncated_remainder": (fmod_exact, 0),
    "remainder": (remainder_exact, 0),
}


def asinh_series_sinh(x):
    x = d(x)
    total, term, n = Decimal(0), x, 1
    while abs(term) > Decimal(10) ** -100 * abs(x):
        total += term
        term = term * x * x / ((n + 1) * (n + 2))
        n += 2
    return total


def tanh_exact(x):
    with localcontext() as context:
        context.prec = 120
        if abs(x) > 40:
            return Decimal(1 if x > 0 else -1)
        if abs(x) < 1e-5:
            s = asinh_series_sinh(x)
            return s / (1 + s * s).sqrt()
        e = (2 * d(x)).exp()
        return (e - 1) / (e + 1)


def random_float(rng, low_exponent, high_exponent, signs=True):
    exponent = rng.uniform(low_exponent, high_exponent)
    value = 2.0 ** exponent * rng.uniform(1, 2) / 2
    return -value if signs and rng.random() < 0.5 else value


def arguments(name, rng):
    """Chosen arguments, then random ones over the function's domain."""
    chosen = {
        "exp": [1.0, -1.0, 0.5, 709.7, -708.0, -745.0, 1e-10, 0.6931471805599453, 2.0, 10.0, -20.0, 700.0],
        "exp2": [0.5, -0.5, 1023.5, -1074.0, -1060.25, 0.1, 3.3, -1022.5],
        "exp_minus_one": [1e-300, -1e-20, 0.5, -0.5, 1.0, 40.0, -40.0, 0.3465, 1e-6, -1e-6, 700.0],
        "log": [2.0, 0.5, 1e-300, 5e-324, 1.0000001, 0.9999999, 1e300, 1.7976931348623157e308, 10.0],
        "log2": [3.0, 0.75, 1e-310, 1.0000000001, 1e300],
        "log10": [2.0, 0.3, 1e-310, 1.0000000001, 1e300, 1e22],
        "log_one_plus": [1e-300, -1e-20, -0.5, 0.4142, -0.2929, 1.0, 1e300, -0.999999999],
        "sin": [1.0, 3.141592653589793, 1e22, 1e300, 1e-8, 6381956970095103.0 * 2.0 ** 797, 1.5707963267948966,
                3 * 1.5707963267948966, 4 * 1.5707963267948966, 7.0, 0.785398163397448, 1e10],
        "cos": [1.0, 3.141592653589793, 1e22, 1e300, 1e-8, 6381956970095103.0 * 2.0 ** 797, 1.5707963267948966, 7.0,
                0.785398163397448, 1e10],
        "tan": [1.0, 1.5707963267948966, 1e22, 1e300, 0.7, 1e-10, 3.0, 1e10],
        "asin": [0.5, -0.5, 0.99, 0.975, 0.9999999, 1e-10, 0.3],
        "acos": [0.5, -0.5, 0.99, -0.99, 0.9999999, 1e-10, -0.9999999],
        "atan": [0.5, 1.0, 1.5, 2.4375, 0.4375, 1e10, -1e10, 1e-10, 0.6875, 1.1875],
        "sinh": [1e-10, 0.5, 1.0, 20.0, 700.0, 710.0, -3.0],
        "cosh": [1e-10, 0.5, 1.0, 20.0, 700.0, 710.0, -3.0],
        "tanh": [1e-10, 0.3, 0.5, 1.0, 19.0, 21.0, -0.7, 1e-310],
        "asinh": [1e-10, 0.5, 2.0, 1e10, -3.0, 1e300],
        "acosh": [1.0000001, 1.5, 2.0, 1e10, 1e300],
        "atanh": [1e-10, 0.4, 0.5, 0.9, -0.99999],
        "cube_root": [8.0, 27.0, 2.0, -2.0, 1e-310, 1e300, 0.001],
        "erf": [0.5, 0.84375, 1.0, 1.25, 2.0, 2.857, 3.0, 5.0, 5.9, 1e-10, -1.5],
        "erfc": [0.5, 0.84375, 1.0, 1.25, 2.0, 2.857, 3.0, 5.0, 10.0, 20.0, 27.0, -1.0, -5.0, 0.2],
        "erf_inverse": [0.5, -0.5, 0.9, 0.999, 0.999999, 1e-10, 0.1, -0.99999999],
        "gamma": [0.5, 1.5, 2.5, 4.5, 10.25, 30.5, 100.5, 170.5, -0.5, -1.5, -2.5, -10.5, 1e-10, 0.001],
        "log_gamma": [0.5, 1.5, 2.5, 3.5, 7.9, 10.0, 100.0, 1e10, 1e100, -0.5, -2.5, -10.5, 0.1, 0.9, 1.2, 1.8],
    }
    values = list(chosen.get(name, []))
    ranges = {
        "exp": (-745, 709.7, False),
        "exp2": (-1074, 1023.9, False),
        "exp_minus_one": None,
        "log": None,
        "log2": None,
        "log10": None,
        "log_one_plus": None,
        "sin": None,
        "cos": None,
        "tan": None,
        "asin": (-1, 1, False),
        "acos": (-1, 1, False),
        "atan": None,
        "sinh": (-700, 700, False),
        "cosh": (-700, 700, False),
        "tanh": (-25, 25, False),
        "asinh": None,
        "acosh": None,
        "atanh": (-1, 1, False),
        "cube_root": None,
        "erf": (-6, 6, False),
        "erfc": (-6, 27, False),
        "erf_inverse": (-1, 1, False),
        "gamma": (-170, 171, False),
        "log_gamma": None,
    }
    for _ in range(140):
        kind = ranges[name]
        if kind is not None:
            low, high, _ = kind
            values.append(rng.uniform(low, high))
            continue
        if name in ("log", "log2", "log10", "acosh", "log_gamma"):
            x = abs(random_float(rng, -1074, 1024, False))
            if name == "acosh":
                x = 1 + x if x < 1e300 else x
            values.append(x)
        elif name == "log_one_plus":
            values.append(random_float(rng, -60, 30) if rng.random() < 0.5 else rng.uniform(-1, 3))
        elif name == "exp_minus_one":
            values.append(random_float(rng, -60, 9))
        elif name in ("sin", "cos", "tan"):
            values.append(random_float(rng, -30, 30) if rng.random() < 0.7 else random_float(rng, 30, 1024))
        else:
            values.append(random_float(rng, -60, 60))
    return values


def binary_arguments(name, rng):
    chosen = {
        "power": [(2.0, 0.5), (-2.0, 3.0), (10.0, -3.0), (1.0000001, 1e7), (0.5, 1074.0), (2.0, 1023.5), (1.1, 300.0),
                  (3.0, -0.75), (-0.5, 5.0), (7.0, 1.0 / 3.0)],
        "atan2": [(1.0, 1.0), (1.0, -1.0), (-1.0, -1.0), (1e-300, 1e300), (1e300, 1e-300), (3.0, -1e-200), (0.5, 2.0)],
        "hypotenuse": [(3.0, 4.0), (1e300, 1e300), (1e-300, 1e-300), (1.0, 1e-20), (5e-324, 5e-324)],
        "truncated_remainder": [(10.0, 3.0), (-10.0, 3.0), (1e300, 3.0), (5.5, 1e-300), (1.0, 0.1)],
        "remainder": [(10.0, 3.0), (-10.0, 3.0), (1e300, 3.0), (2.5, 1.0), (3.5, 1.0), (1.0, 0.1)],
    }
    values = list(chosen[name])
    for _ in range(100):
        if name == "power":
            x = abs(random_float(rng, -20, 20, False))
            y = random_float(rng, -8, 8)
            if rng.random() < 0.2:
                x = -x
                y = float(rng.randint(-60, 60))
            values.append((x, y))
        elif name == "atan2":
            values.append((random_float(rng, -60, 60), random_float(rng, -60, 60)))
        elif name == "hypotenuse":
            values.append((random_float(rng, -500, 500), random_float(rng, -500, 500)))
        else:
            values.append((random_float(rng, -40, 60), random_float(rng, -40, 40)))
    return values


def f32_bits(value):
    """The bits of the f32 nearest a Fraction, ties to even, exactly."""
    sign = 0x8000_0000 if value < 0 else 0
    x = abs(value)
    if x == 0:
        return sign
    exponent = x.numerator.bit_length() - x.denominator.bit_length()
    if Fraction(2) ** exponent > x:
        exponent -= 1
    quantum_exponent = max(exponent, -126) - 23
    m = x / Fraction(2) ** quantum_exponent
    n = m.numerator // m.denominator
    rest = m - n
    if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and n % 2 == 1):
        n += 1
    if n >= 2 ** 24:
        n //= 2
        quantum_exponent += 1
    if n < 2 ** 23:
        return sign | n
    biased = quantum_exponent + 23 + 127
    if biased >= 255:
        return sign | 0x7f80_0000
    return sign | (biased << 23) | (n - 2 ** 23)


def f64_bits(value):
    """The bits of the f64 nearest a Fraction, ties to even: Python's float of a Fraction rounds correctly."""
    try:
        f = float(value)
    except OverflowError:
        f = math.inf if value > 0 else -math.inf
    if f == 0 and value < 0:
        f = -0.0
    return struct.unpack("<Q", struct.pack("<d", f))[0]


def exact_text(value):
    """A Fraction with a power-of-two denominator, written out exactly in decimal."""
    sign = "-" if value < 0 else ""
    value = abs(value)
    whole = value.numerator // value.denominator
    rest = value - whole
    digits = []
    while rest:
        rest *= 10
        digit = rest.numerator // rest.denominator
        digits.append(str(digit))
        rest -= digit
    return sign + str(whole) + ("." + "".join(digits) if digits else "")


def around(middle):
    """A halfway point written exactly, and a hair above and below it, as text."""
    text = exact_text(middle)
    places = len(text.split(".")[1]) if "." in text else 0
    hair = Fraction(1, 10 ** (places + 9))
    return [text, exact_text(middle + hair), exact_text(middle - hair)]

def parse_cases(rng):
    """Text, and what parse[f64] and parse[f32] give: their bits, or None where it isn't a number."""
    texts = ["0", "-0", "1", "0.1", "1e23", "8.98846567431158e307", "1.7976931348623157e308", "1.7976931348623158e308",
             "1.7976931348623159e308", "2.2250738585072011e-308", "2.2250738585072012e-308", "4.9e-324", "5e-324",
             "2.4703282292062327e-324", "2.4703282292062328e-324", "1e-400", "1e400", "123456789012345678901234567890",
             "0.000000000000000000000000000001", ".5", "7.", "+3.25", "-12.5e3", "1E5", "1e-5", "3.4028235e38",
             "3.4028236e38", "1.17549435e-38", "1.4e-45", "7e-46", "0.7e-45", "16777217", "9007199254740993",
             "1.00000005960464477550", "1.000000059604644775390625",
             "000000000000000000000000000000012.5", "1.0000000000000002220446049250313080847263336181640625",
             "1.0000000000000001110223024625156540423631668090820312", "4.4501477170144022721148195934182639518696390927032912960468522194496444440421538910330590478162701758282983178260792422137401728773891892910553144148156412434867599762821265346585071045737627442980259622449029037796981144446145705102663115100318287949527959668236039986479250965780342141637013812613333119898765515451440315261253813266652951306000184917766328660755595837392240989947807556594098101021612198814605258742579179000071675999344145086087205681577915435923018910334964869420614052182892431445797605163650903606514140377217442262561590244668525767372446430075513332450079650686719491377688478005309963967709758965844137894433796621993967316936280457084866613206797017728916080020698679408551343728867675409720757232455434770912461317493580281734466552734375"]
    for _ in range(300):
        f = struct.unpack("<d", struct.pack("<Q", rng.getrandbits(64)))[0]
        if not math.isfinite(f):
            continue
        texts.append(repr(f).replace("e+", "e"))
        texts.append(f"{f:.17e}".replace("e+", "e"))
        texts.append(f"{f:.25g}".replace("e+", "e"))
    # Halfway between two f64s exactly, which rounds to the even one, and a hair either side, which the slow path decides
    for _ in range(60):
        f = abs(struct.unpack("<d", struct.pack("<Q", rng.getrandbits(64)))[0])
        if not math.isfinite(f) or f == 0:
            continue
        middle = (Fraction(f) + Fraction(math.nextafter(f, math.inf))) / 2
        texts += around(middle)
    # The same for f32s
    for _ in range(60):
        bits = rng.getrandbits(31)
        if (bits >> 23) == 0xff:
            continue
        f = struct.unpack("<f", struct.pack("<I", bits))[0]
        g = struct.unpack("<f", struct.pack("<I", bits + 1))[0]
        if not math.isfinite(g):
            continue
        middle = (Fraction(f) + Fraction(g)) / 2
        texts += around(middle)
    cases = []
    for text in texts:
        value = Fraction(text)
        if value == 0 and text.startswith("-"):
            cases.append((text, 0x8000_0000_0000_0000, 0x8000_0000))
            continue
        cases.append((text, f64_bits(value), f32_bits(value)))
    cases += [("1e99999999999", 0x7ff0_0000_0000_0000, 0x7f80_0000), ("-1e-99999999999", 0x8000_0000_0000_0000, 0x8000_0000)]
    for text in ["", "-", "+", ".", "e5", "1e", "1e+", "1.2.3", "abc", " 1", "1 ", "0x10", "--1", "1_000", "1e5.5", "in"]:
        cases.append((text, None, None))
    return cases


def as_hemera(x):
    text = repr(float(x))
    if text in ("inf", "-inf", "nan"):
        raise ValueError(text)
    text = text.replace("e+", "e")
    return text if ("e" in text or "." in text) else text + ".0"


def split(value):
    """A Decimal as hi + lo, f64s."""
    hi = float(value)
    with localcontext() as context:
        context.prec = 200
        lo = float(value - Decimal(hi)) if math.isfinite(hi) else 0.0
    return hi, lo


def main():
    rng = random.Random(20261111)
    rows = []
    for name, (function, bound) in FUNCTIONS.items():
        for x in arguments(name, rng):
            try:
                value = function(x)
                hi, lo = split(value)
            except (ValueError, ArithmeticError, OverflowError):
                continue
            if not math.isfinite(hi) or (hi == 0 and value != 0):
                continue
            rows.append((name, x, 0.0, hi, lo))
    for name, (function, bound) in BINARY.items():
        for x, y in binary_arguments(name, rng):
            try:
                value = function(x, y)
                hi, lo = split(value)
            except (ValueError, ArithmeticError, OverflowError):
                continue
            if not math.isfinite(hi) or (hi == 0 and value != 0):
                continue
            rows.append((name, x, y, hi, lo))
    names = list(FUNCTIONS) + list(BINARY)
    out = ["package float_math", "", "/*",
           " * Made by make_references.py: each function's exact value, as hi + lo, at chosen and random arguments. Don't",
           " * edit; run the script again.", " */", "",
           "/** The functions the references are of, in the order of make_references.py's tables. */",
           "Function :: enum {"]
    out += [f"    {''.join(part.capitalize() for part in name.split('_'))}," for name in names]
    out += ["}", "", "/** How many functions there are. */", f"FUNCTION_COUNT :: {len(names)}", "",
            "/** One function's exact value at its argument, or arguments, as hi + lo. */",
            "Reference :: struct {", "    function : Function,", "    x : f64,", "    y : f64,", "    hi : f64,",
            "    lo : f64,", "}", "", "REFERENCES :: Reference.["]
    for name, x, y, hi, lo in rows:
        member = "".join(part.capitalize() for part in name.split("_"))
        out.append(f"    Reference.{{function = .{member}, x = {as_hemera(x)}, y = {as_hemera(y)}, hi = {as_hemera(hi)}, "
                   f"lo = {as_hemera(lo)}}},")
    out += ["]", "", "/** Text, and the bits parse[f64] and parse[f32] give, or that they give none. */",
            "ParseCase :: struct {", "    text : string,", "    valid : bool,", "    bits_64 : u64,", "    bits_32 : u32,", "}",
            "", "PARSE_CASES :: ParseCase.["]
    cases = parse_cases(rng)
    for text, bits_64, bits_32 in cases:
        if bits_64 is None:
            out.append(f'    ParseCase.{{text = "{text}", valid = false}},')
        else:
            out.append(f'    ParseCase.{{text = "{text}", valid = true, bits_64 = 0x{bits_64:016x}, bits_32 = 0x{bits_32:08x}}},')
    out += ["]", ""]
    (HERE / "float_math_references.hsc").write_text("\n".join(out), encoding="utf-8")
    print(f"{len(rows)} references, {len(cases)} parse cases")


if __name__ == "__main__":
    main()
