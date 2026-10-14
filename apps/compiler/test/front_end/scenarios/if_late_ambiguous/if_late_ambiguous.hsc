package if_late_ambiguous

// Result may be used as the builtin before the #if adds an import declaring it too
#if true {
    import builtin_shadow from "../builtin_shadow"
}

latest :: fn() -> Result {
}
