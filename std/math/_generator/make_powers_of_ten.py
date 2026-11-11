"""
Write powers_of_ten.hsc: 10^e for e from -348 to 347, each as its top 128 bits, rounded down, for parse's
Eisel-Lemire step.

    python _generator/make_powers_of_ten.py
"""

from fractions import Fraction
from pathlib import Path

LOWEST = -348
HIGHEST = 347

lines = [
    "package math",
    "",
    "/*",
    " * Made by _generator/make_powers_of_ten.py; don't edit, run it again. 10^e for e from POWERS_OF_TEN_LOWEST to",
    " * POWERS_OF_TEN_HIGHEST, each as its top 128 bits rounded down: the high 64 bits then the low, the top bit set.",
    " */",
    "",
    "/** The least power of ten in the table. */",
    f"POWERS_OF_TEN_LOWEST : i32 : {LOWEST}",
    "/** The greatest. */",
    f"POWERS_OF_TEN_HIGHEST : i32 : {HIGHEST}",
    "",
    "/** The powers, two u64s each, high then low, from the least. */",
    "POWERS_OF_TEN :: u64.[",
]
for e in range(LOWEST, HIGHEST + 1):
    value = Fraction(10) ** e
    # The k with 2^127 <= 10^e × 2^k < 2^128
    k = 127 - (value.numerator.bit_length() - value.denominator.bit_length())
    scaled = value * Fraction(2) ** k
    while scaled >= 2 ** 128:
        k -= 1
        scaled = value * Fraction(2) ** k
    while scaled < 2 ** 127:
        k += 1
        scaled = value * Fraction(2) ** k
    bits = scaled.numerator // scaled.denominator
    lines.append(f"    0x{bits >> 64:016x}, 0x{bits & (2 ** 64 - 1):016x}, // 1e{e}")
lines += ["]", ""]
(Path(__file__).parent.parent / "powers_of_ten.hsc").write_text("\n".join(lines), encoding="utf-8")
print(HIGHEST - LOWEST + 1, "powers")
