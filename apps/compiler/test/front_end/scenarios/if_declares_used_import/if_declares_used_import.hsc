package if_declares_used_import

import collision_a from "../collision_a"

// The package's own ONLY_A would win over the import's, but only this #if may declare it, so
// deciding the #if needs the #if decided: a cycle
#if ONLY_A == 2 {
    ONLY_A :: 3
}
