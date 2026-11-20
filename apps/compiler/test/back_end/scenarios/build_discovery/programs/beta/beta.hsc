package beta

import kinds from "../../kinds"

KIND :: kinds.Kind.Library

helper :: fn() -> int {
    return 2
}

// Declared in a branch no build of it takes: compiler.declares still finds it
#if false {
    only_sometimes :: fn() -> int {
        return 3
    }
}
