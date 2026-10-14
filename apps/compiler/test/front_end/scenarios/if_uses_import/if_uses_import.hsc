package if_uses_import

import collision_a from "../collision_a"

// The package does not declare ONLY_A, so the condition uses the import's
#if ONLY_A == 2 {
    PICKED :: 1
}
