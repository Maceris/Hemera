package if_needs_own_declaration

// The condition needs FLAG, which only the #if itself would declare
#if FLAG {
    FLAG :: true
}
