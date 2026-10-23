package macro_expands_forever

import compiler from "base"

// Its code calls it again, so it never stops expanding
forever #macro :: fn() -> compiler.Code {
    return #code(forever!() + 1)
}

main :: fn() -> int {
    return forever!()
}
