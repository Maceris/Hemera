package collision_ok

import collision_a from "../collision_a"
import collision_b from "../collision_b"

// Both imports declare SHARED, but so does this package (in uses_second.hsc), so it is this one
USES_OWN :: SHARED
// Only one import declares ONLY_A
USES_A :: ONLY_A
// Qualified, either import's can be used
QUALIFIED :: collision_a.SHARED + collision_b.SHARED
