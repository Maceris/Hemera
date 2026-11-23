package audio

import intrinsics from "base:intrinsics"

/** The most channels a stream has here: 7.1's eight. */
MAX_CHANNELS : u32 : 8

/** How each sample of a stream is stored: little-endian, signed integers at full scale on their range. */
SampleFormat :: enum #backed_by(u8) {
    /** A 16-bit signed integer, full scale at 32768. */
    S16 = 1,
    /** A 24-bit signed integer in 3 bytes, as WAV files keep it, full scale at 2^23. */
    S24 = 2,
    /** A 32-bit signed integer, full scale at 2^31. */
    S32 = 3,
    /** An IEEE 754 binary32, full scale at 1. */
    F32 = 4,
}

/** A stream's format: how its samples are stored, how many frames a second, and how many channels each frame has. */
Format :: struct {
    /** How each sample is stored. */
    sample : SampleFormat,
    /** Frames a second, as 48000 for 48 kHz. */
    rate : u32,
    /** Samples a frame, one for each channel, interleaved: 1 for mono, 2 for stereo, up to MAX_CHANNELS. */
    channels : u32,
}

/**
 * How many bytes a sample takes.
 *
 * @param sample How it's stored.
 * @return 2, 3 or 4.
 */
sample_bytes :: fn(sample : SampleFormat) -> usize {
    return match sample {
        case .S16 => 2
        case .S24 => 3
        case .S32 => 4
        case .F32 => 4
    }
}

/**
 * How many bytes a frame takes: a sample for each channel.
 *
 * @param format The stream's format.
 * @return Its sample's bytes times its channels; 0 for no channels.
 */
frame_bytes :: fn(format : Format) -> usize {
    return sample_bytes(format.sample) * cast[usize](format.channels)
}

/**
 * Decode stored samples into floats, where an integer's full scale is 1: -32768 as a 16-bit integer is -1, 32767 just
 * under 1. A float is taken as it is, but NaN, which is silence.
 *
 * @param sample How they're stored.
 * @param bytes Their bytes, as many whole samples as there are; a part of one at the end is left.
 * @param into Where the floats go.
 * @return How many were decoded: the fewer of the whole samples in bytes and into's room.
 */
decode :: fn(sample : SampleFormat, bytes : u8[], into : mut f32[]) -> usize {
    size :: sample_bytes(sample)
    count :: if bytes.count / size < into.count { bytes.count / size } else { into.count }
    for i in 0..<count {
        at :: i * size
        if at + size > bytes.count || i >= into.count {
            break
        }
        into[i] = decoded(sample, bytes, at)
    }
    return count
}

/**
 * Decode one stored sample.
 *
 * @param sample How it's stored.
 * @param bytes The bytes it's in.
 * @param at Where it starts; bytes past the end read as 0.
 * @return It as a float, full scale 1; NaN as 0.
 */
decoded :: fn(sample : SampleFormat, bytes : u8[], at : usize) -> f32 {
    if sample == .S16 {
        return cast[f32](cast[i16](read_u16(bytes, at))) / 32768.0
    }
    if sample == .S24 {
        raw :: cast[u32](byte_at(bytes, at))
            | cast[u32](byte_at(bytes, at + 1)) << 8
            | cast[u32](byte_at(bytes, at + 2)) << 16
        // Its sign taken from its 24th bit
        signed :: cast[i32](raw << 8) >> 8
        return cast[f32](signed) / 8388608.0
    }
    if sample == .S32 {
        return cast[f32](cast[f64](cast[i32](read_u32(bytes, at))) / 2147483648.0)
    }
    value :: bit_cast[f32](read_u32(bytes, at))
    return if value != value { 0.0 } else { value }
}

/**
 * Encode floats as stored samples: each clipped to full scale, -1 to 1, NaN as silence, and rounded to the nearest of
 * the integer's values; a 16-bit integer's 1 is 32767, its -1 -32768.
 *
 * @param samples The floats.
 * @param sample How they're to be stored.
 * @param into Where their bytes go.
 * @return How many were encoded: the fewer of samples and the whole samples into has room for.
 */
encode :: fn(samples : f32[], sample : SampleFormat, into : mut u8[]) -> usize {
    size :: sample_bytes(sample)
    count :: if into.count / size < samples.count { into.count / size } else { samples.count }
    for i in 0..<count {
        at :: i * size
        if at + size > into.count || i >= samples.count {
            break
        }
        value :: clipped(samples[i])
        match sample {
            case .S16 => write_u16(
                into,
                at,
                cast[u16](cast[i16](rounded(cast[f64](value) * 32768.0, -32768.0, 32767.0)))
            )
            case .S24 => {
                bits :: cast[u32](cast[i32](rounded(cast[f64](value) * 8388608.0, -8388608.0, 8388607.0)))
                put_byte(into, at, cast[u8](bits))
                put_byte(into, at + 1, cast[u8](bits >> 8))
                put_byte(into, at + 2, cast[u8](bits >> 16))
            }
            case .S32 => write_u32(
                into,
                at,
                cast[u32](cast[i32](rounded(cast[f64](value) * 2147483648.0, -2147483648.0, 2147483647.0)))
            )
            case .F32 => write_u32(into, at, bit_cast[u32](value))
        }
    }
    return count
}

/**
 * Clip a sample to full scale.
 *
 * @param value The sample.
 * @return It, within -1 to 1; 0 for NaN.
 */
clipped :: fn(value : f32) -> f32 {
    if value != value {
        return 0.0
    }
    return if value > 1.0 { 1.0 } else if value < -1.0 { -1.0 } else { value }
}

/**
 * Round a scaled sample to the nearest whole number, halves away from zero, within an integer's range.
 *
 * @param scaled The sample at the integer's scale.
 * @param least The integer's least value.
 * @param most Its most.
 * @return The whole number, within least and most.
 */
rounded :: fn(scaled : f64, least : f64, most : f64) -> i64 {
    near :: cast[f64](cast[i64](if scaled < 0.0 { scaled - 0.5 } else { scaled + 0.5 }))
    return cast[i64](if near > most { most } else if near < least { least } else { near })
}

/** A byte at a place in bytes; 0 past their end. */
byte_at :: fn(bytes : u8[], at : usize) -> u8 {
    return if at < bytes.count { bytes[at] } else { 0 }
}

/** Write a byte at a place in bytes, if it's within them. */
put_byte :: fn(into : mut u8[], at : usize, value : u8) {
    if at < into.count {
        into[at] = value
    }
}

/** A little-endian u32 at a place in bytes; bytes past their end read as 0. */
read_u32 :: fn(bytes : u8[], at : usize) -> u32 {
    return cast[u32](byte_at(bytes, at))
        | cast[u32](byte_at(bytes, at + 1)) << 8
        | cast[u32](byte_at(bytes, at + 2)) << 16
        | cast[u32](byte_at(bytes, at + 3)) << 24
}

/** A little-endian u16 at a place in bytes; bytes past their end read as 0. */
read_u16 :: fn(bytes : u8[], at : usize) -> u16 {
    return cast[u16](byte_at(bytes, at)) | cast[u16](byte_at(bytes, at + 1)) << 8
}

/** Write a little-endian u32 at a place in bytes, as much of it as is within them. */
write_u32 :: fn(into : mut u8[], at : usize, value : u32) {
    put_byte(into, at, cast[u8](value))
    put_byte(into, at + 1, cast[u8](value >> 8))
    put_byte(into, at + 2, cast[u8](value >> 16))
    put_byte(into, at + 3, cast[u8](value >> 24))
}

/** Write a little-endian u16 at a place in bytes, as much of it as is within them. */
write_u16 :: fn(into : mut u8[], at : usize, value : u16) {
    put_byte(into, at, cast[u8](value))
    put_byte(into, at + 1, cast[u8](value >> 8))
}
