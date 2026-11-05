/*
 * A name two imported packages declare, which code an #insert puts in this package declares too: this package's own
 * wins, wherever it's used, however the #insert's code and the uses are scheduled (docs/packages.md, Name Collision;
 * docs/compilation.md, The Top Level). Uses come first, and the inserted code takes a while to make.
 */
package inserted_over_imports

import compiler from "base"
import testing from "std"
import one from "./one"
import two from "./two"

use_0 :: fn() -> int {
    return pick()
}

use_1 :: fn() -> int {
    return pick()
}

use_2 :: fn() -> int {
    return pick()
}

use_3 :: fn() -> int {
    return pick()
}

use_4 :: fn() -> int {
    return pick()
}

use_5 :: fn() -> int {
    return pick()
}

use_6 :: fn() -> int {
    return pick()
}

use_7 :: fn() -> int {
    return pick()
}

use_8 :: fn() -> int {
    return pick()
}

use_9 :: fn() -> int {
    return pick()
}

use_10 :: fn() -> int {
    return pick()
}

use_11 :: fn() -> int {
    return pick()
}

use_12 :: fn() -> int {
    return pick()
}

use_13 :: fn() -> int {
    return pick()
}

use_14 :: fn() -> int {
    return pick()
}

use_15 :: fn() -> int {
    return pick()
}

use_16 :: fn() -> int {
    return pick()
}

use_17 :: fn() -> int {
    return pick()
}

use_18 :: fn() -> int {
    return pick()
}

use_19 :: fn() -> int {
    return pick()
}

use_20 :: fn() -> int {
    return pick()
}

use_21 :: fn() -> int {
    return pick()
}

use_22 :: fn() -> int {
    return pick()
}

use_23 :: fn() -> int {
    return pick()
}

use_24 :: fn() -> int {
    return pick()
}

use_25 :: fn() -> int {
    return pick()
}

use_26 :: fn() -> int {
    return pick()
}

use_27 :: fn() -> int {
    return pick()
}

use_28 :: fn() -> int {
    return pick()
}

use_29 :: fn() -> int {
    return pick()
}

use_30 :: fn() -> int {
    return pick()
}

use_31 :: fn() -> int {
    return pick()
}

use_32 :: fn() -> int {
    return pick()
}

use_33 :: fn() -> int {
    return pick()
}

use_34 :: fn() -> int {
    return pick()
}

use_35 :: fn() -> int {
    return pick()
}

use_36 :: fn() -> int {
    return pick()
}

use_37 :: fn() -> int {
    return pick()
}

use_38 :: fn() -> int {
    return pick()
}

use_39 :: fn() -> int {
    return pick()
}

finds_its_own_declaration_over_imports #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    total :: use_0() + use_1() + use_2() + use_3() + use_4() + use_5() + use_6() + use_7() + use_8() + use_9() + use_10() + use_11() + use_12() + use_13() + use_14() + use_15() + use_16() + use_17() + use_18() + use_19() + use_20() + use_21() + use_22() + use_23() + use_24() + use_25() + use_26() + use_27() + use_28() + use_29() + use_30() + use_31() + use_32() + use_33() + use_34() + use_35() + use_36() + use_37() + use_38() + use_39()
    testing.expect_eq(t, total, 40, "each of the 40 uses finds this package's pick, which gives 1")
    testing.expect_eq(t, one.pick(), 1, "one's pick, qualified, is still one's")
    testing.expect_eq(t, two.pick(), 2, "two's pick, qualified, is still two's")
    return .Ok
}

// The declaration, made slowly, so the uses above are looked up while it's still being made
declaration :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    // A quote as an if's branch, which is the quote, not a directive and a statement after it
    return if spin >= 0 { #code {
        pick :: fn() -> int {
            return 1
        }
    } } else { #code {} }
}

#insert declaration()
