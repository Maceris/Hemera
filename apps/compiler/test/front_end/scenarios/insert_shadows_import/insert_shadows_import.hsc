package insert_shadows_import

import compiler from "base"
import collision_a from "../collision_a"

make :: fn() -> compiler.Code {
    return #code {
        ONLY_A :: 7
    }
}

// collision_a declares ONLY_A, and so does this package's #insert: its own is the one used, however soon it's looked for
USES_OWN :: ONLY_A
#insert make()

#assert USES_OWN == 7
