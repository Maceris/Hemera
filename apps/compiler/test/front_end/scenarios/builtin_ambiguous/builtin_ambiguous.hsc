package builtin_ambiguous

import builtin_shadow from "../builtin_shadow"

// Both the builtins and an import declare Result, and this package does not
latest :: fn() -> Result {
    todo()
}
