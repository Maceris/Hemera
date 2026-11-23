package audio

import intrinsics from "base:intrinsics"
import math from "std:math"

/** How many input frames each output frame is made from: its filter's taps. */
RESAMPLE_TAPS : usize : 64
/** How many of the filter's phases between two input frames are kept, the ones between interpolated. */
RESAMPLE_PHASES : usize : 128
/** How far below the lower rate's half the filter's passband reaches: 0.9 of it, its stopband from about 0.98. */
RESAMPLE_ROLLOFF : f64 : 0.9
/** The Kaiser window's beta: about 80 dB down in the stopband. */
RESAMPLE_BETA : f64 : 8.0
/** The fixed point a position counts in: 32 bits of a frame's fraction. */
FRACTION_BITS : u64 : 32

/**
 * A resampler: one stream's rate changed to another, a block at a time, each output frame filtered from the input
 * frames around where it falls. Its delay is half its taps, 32 input frames; what it's given first comes out after
 * that, silence before.
 *
 * Make one with resampler_for, into memory the caller keeps: it's about 33 KiB, so the heap, not a stack.
 */
Resampler :: struct {
    /** The input's rate, in frames a second. */
    from_rate : u32,
    /** The output's. */
    to_rate : u32,
    /** Samples a frame, the same in and out. */
    channels : u32,
    /** Input frames for each output frame, in FRACTION_BITS fixed point. */
    step : u64,
    /** Where the next output frame falls, in input frames since the history's first, fixed point. */
    position : u64,
    /** Each phase's taps, RESAMPLE_PHASES + 1 of them, the last the first one frame on, scaled to unity gain. */
    filter : f32[(RESAMPLE_PHASES + 1) * RESAMPLE_TAPS],
    /** The last RESAMPLE_TAPS input frames, interleaved, oldest first. */
    history : f32[RESAMPLE_TAPS * MAX_CHANNELS],
}

/**
 * Set a resampler up for two rates: its filter made, its history silent.
 *
 * @param resampler Where it goes, the caller's.
 * @param from_rate The input's rate, more than 0.
 * @param to_rate The output's, more than 0; the same as the input's passes it through, delayed.
 * @param channels Samples a frame, 1 to MAX_CHANNELS.
 * @return False, nothing set, for a rate of 0 or a channel count of 0 or past MAX_CHANNELS.
 */
resampler_for :: fn(resampler : ptr[mut Resampler], from_rate : u32, to_rate : u32, channels : u32) -> bool {
    if from_rate == 0 || to_rate == 0 || channels == 0 || channels > MAX_CHANNELS {
        return false
    }
    resampler.from_rate = from_rate
    resampler.to_rate = to_rate
    resampler.channels = channels
    resampler.step = (cast[u64](from_rate) << FRACTION_BITS) / cast[u64](to_rate)
    // The first output frame centred on the history's middle, so its taps are all in it
    resampler.position = cast[u64](RESAMPLE_TAPS / 2 - 1) << FRACTION_BITS
    for &sample in resampler.history {
        sample^ = 0.0
    }
    // Cut off at the lower rate's half, as a fraction of the input's half, below its rolloff
    ratio :: cast[f64](to_rate) / cast[f64](from_rate)
    cutoff :: (if ratio < 1.0 { ratio } else { 1.0 }) * RESAMPLE_ROLLOFF
    half :: cast[f64](RESAMPLE_TAPS / 2)
    for phase in 0..<(RESAMPLE_PHASES + 1) {
        offset :: cast[f64](phase) / cast[f64](RESAMPLE_PHASES)
        sum := cast[f64](0.0)
        for tap in 0..<RESAMPLE_TAPS {
            // How far the tap's input frame is from where the output falls
            distance :: cast[f64](tap) - half + 1.0 - offset
            sum += tap_weight(distance, cutoff, half)
        }
        for tap in 0..<RESAMPLE_TAPS {
            distance :: cast[f64](tap) - half + 1.0 - offset
            at :: phase * RESAMPLE_TAPS + tap
            if at < resampler.filter.count {
                resampler.filter[at] = cast[f32](tap_weight(distance, cutoff, half) / sum)
            }
        }
    }
    return true
}

/**
 * A tap's weight: a sinc low-pass at the cutoff, windowed by a Kaiser window over the taps.
 *
 * @param distance How far the tap's frame is from where the output falls, in input frames.
 * @param cutoff The cutoff, as a fraction of the input's half rate.
 * @param half Half the taps, the window's reach.
 * @return The weight, before the phase's are scaled to sum to 1.
 */
tap_weight :: fn(distance : f64, cutoff : f64, half : f64) -> f64 {
    x :: distance * cutoff
    sinc :: if x == 0.0 { 1.0 } else { math.sin(math.PI * x) / (math.PI * x) }
    reach :: distance / half
    if reach <= -1.0 || reach >= 1.0 {
        return 0.0
    }
    window :: bessel_i0(RESAMPLE_BETA * intrinsics.square_root(1.0 - reach * reach)) / bessel_i0(RESAMPLE_BETA)
    return cutoff * sinc * window
}

/**
 * The modified Bessel function of the first kind, order 0, by its series, for the Kaiser window.
 *
 * @param x Its argument, here 0 to RESAMPLE_BETA.
 * @return I0(x), to well past f32's precision.
 */
bessel_i0 :: fn(x : f64) -> f64 {
    sum := cast[f64](1.0)
    term := cast[f64](1.0)
    half :: x / 2.0
    for k in 1..<40 {
        factor :: half / cast[f64](k)
        term *= factor * factor
        sum += term
        if term < sum * 1e-17 {
            break
        }
    }
    return sum
}

/**
 * How many output frames a block of input frames can make: the most resample writes for it.
 *
 * @param resampler The resampler.
 * @param frames The input frames.
 * @return At most this many; resample's into should have room for it.
 */
resampled_frames :: fn(resampler : ptr[Resampler], frames : usize) -> usize {
    if resampler.step == 0 {
        return 0
    }
    return cast[usize]((cast[u64](frames) << FRACTION_BITS) / resampler.step) + 2
}

/**
 * Resample a block of input frames, after those given before: each output frame that falls before the block's last
 * half a filter's frames is made, the rest once the next block comes.
 *
 * @param resampler The resampler, its history and position moved on past the block.
 * @param from The input frames, interleaved, the resampler's channels each; a part frame at the end is left.
 * @param into Where the output frames go, interleaved; with room for resampled_frames of the block, every one fits,
 *     and past a shorter one's room the rest are lost.
 * @return How many output frames were made.
 */
resample :: fn(resampler : ptr[mut Resampler], from : f32[], into : mut f32[]) -> usize {
    channels :: cast[usize](resampler.channels)
    if channels == 0 || channels > cast[usize](MAX_CHANNELS) {
        return 0
    }
    given :: from.count / channels
    room :: into.count / channels
    made := cast[usize](0)
    // Output frames whose last tap is among the history and the block
    loop {
        whole :: cast[usize](resampler.position >> FRACTION_BITS)
        if whole + RESAMPLE_TAPS / 2 >= RESAMPLE_TAPS + given || made >= room {
            break
        }
        fraction :: resampler.position & ((cast[u64](1) << FRACTION_BITS) - 1)
        // Its phase, and how far it is to the next, to interpolate between their taps
        scaled :: fraction * cast[u64](RESAMPLE_PHASES)
        phase :: cast[usize](scaled >> FRACTION_BITS)
        between :: cast[f32](cast[f64](scaled & ((cast[u64](1) << FRACTION_BITS) - 1)) / 4294967296.0)
        first :: whole + 1 - RESAMPLE_TAPS / 2
        for channel in 0..<channels {
            sum := cast[f32](0.0)
            for tap in 0..<RESAMPLE_TAPS {
                at :: phase * RESAMPLE_TAPS + tap
                if at >= resampler.filter.count || at + RESAMPLE_TAPS >= resampler.filter.count {
                    continue
                }
                weight :: resampler.filter[at] + (resampler.filter[at + RESAMPLE_TAPS] - resampler.filter[at]) * between
                sum += weight * input_sample(resampler, from, first + tap, channel)
            }
            out :: made * channels + channel
            if out < into.count {
                into[out] = sum
            }
        }
        made += 1
        resampler.position += resampler.step
    }
    // Those that didn't fit in into are lost, so the next block's are in time
    loop {
        if cast[usize](resampler.position >> FRACTION_BITS) + RESAMPLE_TAPS / 2 >= RESAMPLE_TAPS + given {
            break
        }
        resampler.position += resampler.step
    }
    // The block's last frames are the history now, and positions count from them
    if given >= RESAMPLE_TAPS {
        for frame in 0..<RESAMPLE_TAPS {
            for channel in 0..<channels {
                at :: frame * channels + channel
                source :: (given - RESAMPLE_TAPS + frame) * channels + channel
                if at < resampler.history.count && source < from.count {
                    resampler.history[at] = from[source]
                }
            }
        }
    }
    else if given > 0 {
        // Moved on by the block's frames, then the block after them
        for frame in 0..<RESAMPLE_TAPS {
            for channel in 0..<channels {
                at :: frame * channels + channel
                // Read before it's written, as frame + given is past frame
                kept :: input_sample(resampler, from, frame + given, channel)
                if at < resampler.history.count {
                    resampler.history[at] = kept
                }
            }
        }
    }
    resampler.position -= cast[u64](given) << FRACTION_BITS
    return made
}

/**
 * A sample of the history followed by the block: frame index counts from the history's first.
 *
 * @param resampler The resampler, whose history is read.
 * @param from The block.
 * @param frame The frame, from 0, the history's first; past the history, the block's.
 * @param channel The channel.
 * @return The sample; 0 past the block.
 */
input_sample :: fn(resampler : ptr[Resampler], from : f32[], frame : usize, channel : usize) -> f32 {
    channels :: cast[usize](resampler.channels)
    if frame < RESAMPLE_TAPS {
        at :: frame * channels + channel
        return if at < resampler.history.count { resampler.history[at] } else { 0.0 }
    }
    at :: (frame - RESAMPLE_TAPS) * channels + channel
    return if at < from.count { from[at] } else { 0.0 }
}
