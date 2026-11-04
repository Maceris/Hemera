package builtin

import compiler from "base"

/**
 * The operating system the program is compiled for, a value known when it's compiled, so `#if OS == .Windows` and
 * constants like `ON_WINDOWS :: OS == .Windows` choose code by it (docs/directives.md). None is freestanding code,
 * like a kernel.
 */
OS : OperatingSystem : ---
/**
 * The processor architecture the program is compiled for, a value known when it's compiled, so `#if TARGET_ARCH ==
 * .x86_64` chooses code by it (docs/directives.md).
 */
TARGET_ARCH : Architecture : ---
