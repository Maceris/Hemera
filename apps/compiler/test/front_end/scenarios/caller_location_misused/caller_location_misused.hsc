package caller_location_misused

import runtime from "base:runtime"

/*
 * #caller_location is the caller's location, so it's only a parameter's default: in a body it's an error (E4014),
 * where #source_location is what's meant. As a default, typed or not, it's fine.
 */

called_from :: fn(location := #caller_location) -> u32 {
    return location.line
}

typed :: fn(at: runtime.SourceCodeLocation = #caller_location) -> u32 {
    return at.line
}

where :: fn() -> u32 {
    here := #caller_location
    there := #source_location
    return here.line + there.line + called_from() + typed()
}
