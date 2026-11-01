/*
 * UEFI's tables and protocols, for programs built for OS == .UEFI (docs/compilation.md, UEFI Applications), like a
 * bootloader: the system table base's runtime keeps, the runtime services, and the protocols as they're needed. base's
 * runtime has the parts it uses itself (uefi.hsc): the table headers, the system table, the console's output, the pool
 * and Exit.
 */
package uefi

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Freestanding
