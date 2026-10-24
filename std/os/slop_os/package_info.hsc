/*
 * SlopOS's system ABI: the syscall table, handle and error types, channel ring and port packet
 * layouts, the startup block, and the ABI version. The kernel and std's OS layer for
 * OS == .SlopOS both import it, so it stays freestanding.
 *
 * Service protocols that std speaks on SlopOS (clock, entropy, storage) are packages in
 * subfolders, imported from "std/os/slop_os".
 *
 * So far: CpuFeatures (cpu_features.hsc), the startup block (startup.hsc), and the system calls with
 * their handles, rights and errors: the table (syscalls.hsc), and the stubs and the kernel's dispatch
 * generated from it (syscall_table.hsc).
 * See the SlopOS repository's knowledge/design/system-abi.md.
 */
package slop_os

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Freestanding
