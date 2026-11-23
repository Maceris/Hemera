package audio

/** Why bytes weren't read as a WAV file. */
WavError :: enum #backed_by(u8) {
    /** Not a RIFF file of WAVE. */
    NotWav = 1,
    /** No fmt chunk before the data, or no data chunk. */
    Incomplete = 2,
    /** A fmt chunk this doesn't read: a compressed format, an unusual sample size, or no channels or rate. */
    Unsupported = 3,
    /** A fmt chunk that doesn't hold together: too short, or its block size not its channels' samples. */
    Malformed = 4,
}

/** A WAV file read: its format, and its samples' bytes, a view of the file's. */
Wav :: struct {
    /** Its samples' format, rate and channels. */
    format : Format,
    /** Its samples' bytes, whole frames, interleaved: a view of the bytes it was read from. */
    data : u8[],
    /** How many frames that is. */
    frames : usize,
}

/** The bytes a WAV file this writes takes before its samples: RIFF's header, a fmt chunk of 16 bytes, data's header. */
WAV_HEADER_BYTES : usize : 44

/** WAVE_FORMAT_PCM, integer samples. */
FORMAT_PCM : u16 : 1
/** WAVE_FORMAT_IEEE_FLOAT. */
FORMAT_FLOAT : u16 : 3
/** WAVE_FORMAT_EXTENSIBLE, whose real format is its sub-format's first two bytes. */
FORMAT_EXTENSIBLE : u16 : 0xfffe

/**
 * Read a WAV file from its bytes, which may be anyone's: a RIFF file of WAVE whose fmt chunk says PCM of 16, 24 or 32
 * bits, IEEE float of 32, or either as WAVE_FORMAT_EXTENSIBLE, 1 to MAX_CHANNELS channels; its other chunks skipped.
 * A data chunk said to run past the bytes is taken as far as they go, as a file written as it was recorded may have
 * no size yet; its last part frame is left.
 *
 * @param bytes The file's bytes, which the Wav's data views.
 * @return The file; or why not.
 * @error NotWav No RIFF header, or not WAVE.
 * @error Incomplete No fmt chunk before a data chunk, or no data chunk.
 * @error Unsupported A format other than these, or none of channels or rate.
 * @error Malformed A fmt chunk under 16 bytes, an extensible one under 40, or a block size that isn't its frame's.
 */
read_wav :: fn(bytes : u8[]) -> Result[Wav, WavError] {
    if bytes.count < 12 || !has_tag(bytes, 0, "RIFF") || !has_tag(bytes, 8, "WAVE") {
        return .Error(.NotWav)
    }
    format : Format? = null
    at := cast[usize](12)
    loop {
        if at + 8 > bytes.count {
            return .Error(.Incomplete)
        }
        size :: cast[usize](read_u32(bytes, at + 4))
        body :: at + 8
        // What's there of it, past which the file ends
        there :: if size > bytes.count - body { bytes.count - body } else { size }
        if has_tag(bytes, at, "fmt ") {
            format = .Some(fmt_of(bytes[body..<body + there])?)
        }
        else if has_tag(bytes, at, "data") {
            found :: format or_return .Error(.Incomplete)
            frame :: frame_bytes(found)
            if frame == 0 {
                return .Error(.Unsupported)
            }
            frames :: there / frame
            return .Ok(Wav.{format = found, data = bytes[body..<body + frames * frame], frames = frames})
        }
        // A chunk of an odd size is padded to an even one
        step :: there + (there & 1)
        if step > bytes.count - body {
            return .Error(.Incomplete)
        }
        at = body + step
    }
}

/**
 * Read a fmt chunk.
 *
 * @param chunk Its body.
 * @return Its format; or why it isn't one this reads.
 */
fmt_of :: fn(chunk : u8[]) -> Result[Format, WavError] {
    if chunk.count < 16 {
        return .Error(.Malformed)
    }
    tag := read_u16(chunk, 0)
    channels :: cast[u32](read_u16(chunk, 2))
    rate :: read_u32(chunk, 4)
    block :: cast[usize](read_u16(chunk, 12))
    bits :: read_u16(chunk, 14)
    if tag == FORMAT_EXTENSIBLE {
        // cbSize, valid bits, the channel mask, then the sub-format's GUID, whose first two bytes are the format
        if chunk.count < 40 {
            return .Error(.Malformed)
        }
        tag = read_u16(chunk, 24)
    }
    if channels == 0 || channels > MAX_CHANNELS || rate == 0 {
        return .Error(.Unsupported)
    }
    sample :: if tag == FORMAT_PCM && bits == 16 {
        SampleFormat.S16
    }
    else if tag == FORMAT_PCM && bits == 24 {
        SampleFormat.S24
    }
    else if tag == FORMAT_PCM && bits == 32 {
        SampleFormat.S32
    }
    else if tag == FORMAT_FLOAT && bits == 32 {
        SampleFormat.F32
    }
    else {
        return .Error(.Unsupported)
    }
    format :: Format.{sample = sample, rate = rate, channels = channels}
    if block != frame_bytes(format) {
        return .Error(.Malformed)
    }
    return .Ok(format)
}

/**
 * Tell whether bytes have a four-character tag at a place.
 *
 * @param bytes The bytes.
 * @param at Where the tag would start.
 * @param tag The tag, four ASCII characters.
 * @return True if the four bytes there are the tag's.
 */
has_tag :: fn(bytes : u8[], at : usize, tag : string) -> bool {
    if at + 4 > bytes.count || tag.count != 4 {
        return false
    }
    for i in cast[usize](0)..<4 {
        if i < tag.count && byte_at(bytes, at + i) != cast[u8](tag[i]) {
            return false
        }
    }
    return true
}

/**
 * How many bytes a WAV file of some frames takes, as write_wav writes it.
 *
 * @param format The samples' format.
 * @param frames How many frames.
 * @return WAV_HEADER_BYTES and the samples' bytes; null if that's past what a WAV file's 32-bit sizes hold.
 */
wav_bytes :: fn(format : Format, frames : usize) -> usize? {
    data :: cast[u64](frames) * cast[u64](frame_bytes(format))
    if data > 0xffffffff - cast[u64](WAV_HEADER_BYTES) {
        return null
    }
    return cast[usize](data) + WAV_HEADER_BYTES
}

/**
 * Write a WAV file: RIFF's header, a fmt chunk of PCM for integers or IEEE float for floats, and the samples.
 *
 * @param format The samples' format, 1 to MAX_CHANNELS channels.
 * @param data The samples' bytes, whole frames, interleaved, as format stores them; a part frame at the end is left.
 * @param into Where the file goes, with room for wav_bytes of data's frames.
 * @return How many bytes were written; null if into hasn't room, the format has no channels or too many, or the file
 *     would be past 32-bit sizes.
 */
write_wav :: fn(format : Format, data : u8[], into : mut u8[]) -> usize? {
    frame :: frame_bytes(format)
    if format.channels == 0 || format.channels > MAX_CHANNELS || frame == 0 {
        return null
    }
    frames :: data.count / frame
    total :: wav_bytes(format, frames) or_return null
    if total > into.count {
        return null
    }
    samples :: frames * frame
    put_tag(into, 0, "RIFF")
    write_u32(into, 4, cast[u32](total - 8))
    put_tag(into, 8, "WAVE")
    put_tag(into, 12, "fmt ")
    write_u32(into, 16, 16)
    write_u16(into, 20, if format.sample == .F32 { FORMAT_FLOAT } else { FORMAT_PCM })
    write_u16(into, 22, cast[u16](format.channels))
    write_u32(into, 24, format.rate)
    write_u32(into, 28, cast[u32](cast[u64](format.rate) * cast[u64](frame)))
    write_u16(into, 32, cast[u16](frame))
    write_u16(into, 34, cast[u16](sample_bytes(format.sample) * 8))
    put_tag(into, 36, "data")
    write_u32(into, 40, cast[u32](samples))
    for byte, i in data {
        if i >= samples {
            break
        }
        put_byte(into, WAV_HEADER_BYTES + i, byte)
    }
    return total
}

/** Write a four-character tag at a place, if it fits. */
put_tag :: fn(into : mut u8[], at : usize, tag : string) {
    for i in 0..<tag.count {
        if i < tag.count {
            put_byte(into, at + i, cast[u8](tag[i]))
        }
    }
}
