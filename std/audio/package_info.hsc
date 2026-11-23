/**
 * Audio: samples and the streams they make. A stream's samples are stored as 16-, 24- or 32-bit integers or 32-bit
 * floats, little-endian, its channels interleaved in frames; they're decoded into floats, where full scale is 1, to be
 * mixed, scaled, clipped and resampled, and encoded back. A resampler changes a stream's rate, between 44.1, 48 and
 * 96 kHz or any two rates, a block at a time, with a windowed-sinc filter whose stopband keeps what's above the lower
 * rate's half from folding back. WAV files are read from their bytes, which may be anyone's, and written.
 *
 * Freestanding: everything works in memory the caller gives, a resampler's state included.
 */
package audio

import tiers from "std:tiers"

/** The package's tier, Freestanding: it needs only base and std/math. */
PACKAGE_TIER :: tiers.Tier.Freestanding
