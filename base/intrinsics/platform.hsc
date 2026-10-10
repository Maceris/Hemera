package intrinsics

/*
 * Platform-specific intrinsics, each in its own package under this folder, imported only
 * when compiling for that platform, since their instructions don't exist anywhere else.
 */

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "./x86_64"
}
