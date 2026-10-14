package if_chains_ok

import if_lib_bar from "../if_lib_bar"

// No other #if may declare or import BAR, so this is decided first
#if BAR {
    import if_lib_bat from "../if_lib_bat"
}
#else {
    BAT :: false
}

// BAT may be declared, or imported, by the #if above, so this waits for it
#if BAT {
    PICKED :: 1
}
