package if_chains_cycle

// Each #if may import what the other needs, so neither can be decided first
#if BAR {
    import if_lib_bat from "../if_lib_bat"
}

#if BAT {
    import if_lib_bar from "../if_lib_bar"
}
