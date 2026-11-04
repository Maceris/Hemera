/**
 * Time zones, from TZif data (RFC 8536): the transitions a zone has had, the local time type each one starts, and the
 * POSIX TZ rule in its footer, which says how local time goes after the last transition. parse_zone reads a TZif file's
 * bytes, which whoever has the zone files gives it, and offset_of and local give the offset from UTC at an instant, and
 * the local time there.
 *
 *     zone := time_zones.parse_zone(bytes)?
 *     defer time_zones.free_zone(&zone)
 *     here :: time_zones.local(&zone, time.now()?)       // here.date_time, here.abbreviation, here.offset
 *
 * Only version 2 and later data is read when a file has it (64-bit times); a version 1 file's 32-bit times are read
 * otherwise. Leap seconds are ignored, as POSIX time ignores them.
 *
 * Apart from time, which stays Freestanding, as a zone's tables are allocated.
 */
package time_zones

import tiers from "std"

/** The package's tier, Allocating: a zone's tables come from the context's allocator; no system call is made. */
PACKAGE_TIER :: tiers.Tier.Allocating
