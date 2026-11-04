/**
 * Typed streams between programs: a Sink[T] writes records of T, and the Stream[T] at its other end reads them, through
 * a ring of shared memory, with backpressure; a Stream[u8] is a byte stream.
 */
package stream

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
