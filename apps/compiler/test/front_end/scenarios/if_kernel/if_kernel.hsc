package if_kernel

// OS is found (a builtin) without waiting for the #if below, though it has an import
KERNEL :: OS == .None

#if KERNEL {
    import if_lib_bar from "../if_lib_bar"
}
#else {
    HOSTED :: 1
}
