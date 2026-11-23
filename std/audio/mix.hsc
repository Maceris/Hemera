package audio

/**
 * Add samples into others, each scaled by a gain: how streams are mixed. Nothing's clipped here, so streams can be
 * added in any order, and clipped once (clip).
 *
 * @param into The samples added into, as floats.
 * @param from The samples added, as floats, the same channels and rate as into's.
 * @param gain What each of from's is multiplied by: 1 as it is, 0.5 about 6 dB quieter, 0 silent.
 * @return How many were added: the fewer of into's and from's.
 */
mix :: fn(into : mut f32[], from : f32[], gain : f32) -> usize {
    count :: if from.count < into.count { from.count } else { into.count }
    for i in 0..<count {
        if i < into.count && i < from.count {
            into[i] += from[i] * gain
        }
    }
    return count
}

/**
 * Scale samples in place by a gain.
 *
 * @param samples The samples, as floats.
 * @param gain What each is multiplied by.
 */
scale :: fn(samples : mut f32[], gain : f32) {
    for &sample in samples {
        sample^ *= gain
    }
}

/**
 * Clip samples in place to full scale, -1 to 1, NaN to silence, as they're to be encoded or played.
 *
 * @param samples The samples, as floats.
 * @return How many were outside full scale, or NaN: none for a mix that kept its headroom.
 */
clip :: fn(samples : mut f32[]) -> usize {
    outside := cast[usize](0)
    for &sample in samples {
        kept :: clipped(sample^)
        if kept != sample^ {
            outside += 1
        }
        sample^ = kept
    }
    return outside
}

/**
 * Make frames of one channel count into another's: one channel into each of several, several averaged into one, and
 * between two counts above one, the channels both have copied, the rest of the new ones silent.
 *
 * @param from The frames, interleaved, from_channels samples each.
 * @param from_channels Their channels, 1 to MAX_CHANNELS.
 * @param into Where the new frames go, interleaved, into_channels samples each.
 * @param into_channels Their channels, 1 to MAX_CHANNELS.
 * @return How many frames were made: the fewer of from's whole frames and into's room; 0 for a channel count of 0 or
 *     past MAX_CHANNELS.
 */
remix :: fn(from : f32[], from_channels : u32, into : mut f32[], into_channels : u32) -> usize {
    if from_channels == 0 || into_channels == 0 || from_channels > MAX_CHANNELS || into_channels > MAX_CHANNELS {
        return 0
    }
    source :: cast[usize](from_channels)
    target :: cast[usize](into_channels)
    frames :: if from.count / source < into.count / target { from.count / source } else { into.count / target }
    for frame in 0..<frames {
        first :: frame * source
        out :: frame * target
        if first + source > from.count || out + target > into.count {
            break
        }
        if source == 1 {
            for channel in 0..<target {
                if out + channel < into.count && first < from.count {
                    into[out + channel] = from[first]
                }
            }
        }
        else if target == 1 {
            sum := cast[f32](0.0)
            for channel in 0..<source {
                if first + channel < from.count {
                    sum += from[first + channel]
                }
            }
            if out < into.count {
                into[out] = sum / cast[f32](source)
            }
        }
        else {
            for channel in 0..<target {
                kept :: if channel < source && first + channel < from.count { from[first + channel] } else { 0.0 }
                if out + channel < into.count {
                    into[out + channel] = kept
                }
            }
        }
    }
    return frames
}
