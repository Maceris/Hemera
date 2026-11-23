/*
 * std/audio: samples decoded and encoded in each format, clipped, NaN silent; mixed, scaled and remixed between channel
 * counts; resampled, a tone keeping its frequency and level, what's above the lower rate's half kept from folding back,
 * the same however the input's split into blocks; and WAV files written and read, as others write them, refused when
 * they aren't, and any bytes read without harm.
 */

package audio_test

import runtime from "base:runtime"
import audio from "std:audio"
import math from "std:math"
import testing from "std:testing"

/**
 * How strong a frequency is in a signal, by the Goertzel algorithm: its amplitude, as a sine of that frequency and
 * amplitude would give.
 *
 * @param samples The signal, one channel.
 * @param frequency The frequency, in Hz.
 * @param rate The signal's rate, in samples a second.
 * @return The amplitude.
 */
strength :: fn(samples : f32[], frequency : f64, rate : f64) -> f64 {
    omega :: 2.0 * math.PI * frequency / rate
    coefficient :: 2.0 * math.cos(omega)
    previous := cast[f64](0.0)
    before := cast[f64](0.0)
    for sample in samples {
        now :: cast[f64](sample) + coefficient * previous - before
        before = previous
        previous = now
    }
    power :: previous * previous + before * before - coefficient * previous * before
    root :: math.power(if power < 0.0 { 0.0 } else { power }, 0.5)
    return 2.0 * root / cast[f64](samples.count)
}

/** Expect a measured value within a tolerance of what it should be. */
near :: fn(t : ptr[mut testing.T], value : f64, expected : f64, tolerance : f64, message : string) {
    gap :: if value > expected { value - expected } else { expected - value }
    testing.expect(t, gap <= tolerance, message)
}

/** Samples from start to end, as far as there are any: none past them. */
part :: fn(samples : f32[], start : usize, end : usize) -> f32[] {
    if start <= end && end <= samples.count {
        return samples[start..<end]
    }
    if start < samples.count {
        return samples[start..<samples.count]
    }
    return samples[0..<0]
}

/** An array of silence, of a count, on the heap, the caller's to free. */
zeros :: fn(count : usize) -> f32[..] {
    out : f32[..]
    runtime.array_reserve(&out, count)
    for i in 0..<count {
        runtime.array_add(&out, 0.0)
    }
    return out
}

/** A sine's samples, one channel, starting at phase 0. */
tone :: fn(into : mut f32[], frequency : f64, rate : f64, amplitude : f64) {
    for &sample, i in into {
        sample^ = cast[f32](amplitude * math.sin(2.0 * math.PI * frequency * cast[f64](i) / rate))
    }
}

decodes_and_encodes_each_format #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    values :: f32.[-1.0, -0.5, 0.0, 0.25, 0.5]
    for sample in audio.SampleFormat.[.S16, .S24, .S32, .F32] {
        bytes : u8[20]
        written :: audio.encode(values[0..<values.count], sample, bytes[0..<bytes.count])
        testing.expect_eq(t, written, 5, "five samples fit in twenty bytes in every format")
        back : f32[5]
        read :: audio.decode(sample, bytes[0..<bytes.count], back[0..<back.count])
        testing.expect_eq(t, read, 5, "each sample's decoded")
        for value, i in values {
            if i < back.count {
                testing.expect_eq(t, back[i], value, "a sample that's a power of two's fraction comes back exactly")
            }
        }
    }
    loud :: f32.[2.0, -3.0, math.nan[f32](), 1.0]
    bytes : u8[8]
    _ = audio.encode(loud[0..<loud.count], .S16, bytes[0..<bytes.count])
    back : f32[4]
    _ = audio.decode(.S16, bytes[0..<bytes.count], back[0..<back.count])
    testing.expect_eq(t, back[0], 32767.0 / 32768.0, "past full scale is clipped to the most")
    testing.expect_eq(t, back[1], -1.0, "and under it to the least")
    testing.expect_eq(t, back[2], 0.0, "NaN is silence")
    testing.expect_eq(t, back[3], 32767.0 / 32768.0, "1 is the most a 16-bit integer holds")
    nan_bytes : u8[4]
    not_a_number :: f32.[math.nan[f32]()]
    _ = audio.encode(not_a_number[0..<1], .F32, nan_bytes[0..<4])
    nan_back : f32[1]
    _ = audio.decode(.F32, nan_bytes[0..<4], nan_back[0..<1])
    testing.expect_eq(t, nan_back[0], 0.0, "a float NaN is encoded and decoded as silence")
    testing.expect_eq(t, audio.decode(.S24, bytes[0..<5], back[0..<back.count]), 1, "a part sample at the end is left")
    return .Ok
}

mixes_scales_and_clips #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    into := f32.[0.5, 0.5, -0.5]
    from :: f32.[0.75, -0.25]
    testing.expect_eq(
        t,
        audio.mix(into[0..<into.count], from[0..<from.count], 1.0),
        2,
        "the shorter's samples are added"
    )
    testing.expect_eq(t, into[0], 1.25, "added, not yet clipped")
    testing.expect_eq(t, into[2], -0.5, "past the shorter, as it was")
    testing.expect_eq(t, audio.clip(into[0..<into.count]), 1, "one sample was past full scale")
    testing.expect_eq(t, into[0], 1.0, "clipped to it")
    audio.scale(into[0..<into.count], 0.5)
    testing.expect_eq(t, into[1], 0.125, "scaled by half")
    half := f32.[1.0, 1.0]
    _ = audio.mix(half[0..<half.count], from[0..<from.count], 0.5)
    testing.expect_eq(t, half[1], 0.875, "mixed at half gain")
    return .Ok
}

remixes_between_channel_counts #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    mono :: f32.[0.25, -0.5]
    stereo : f32[4]
    testing.expect_eq(t, audio.remix(mono[0..<2], 1, stereo[0..<4], 2), 2, "two frames of mono make two of stereo")
    testing.expect_eq(t, stereo[2], -0.5, "each mono sample in both channels")
    testing.expect_eq(t, stereo[3], -0.5, "the right too")
    down : f32[2]
    pair :: f32.[0.5, 0.25, -1.0, 0.0]
    testing.expect_eq(t, audio.remix(pair[0..<4], 2, down[0..<2], 1), 2, "two frames of stereo make two of mono")
    testing.expect_eq(t, down[0], 0.375, "averaged")
    four : f32[8]
    testing.expect_eq(t, audio.remix(pair[0..<4], 2, four[0..<8], 4), 2, "stereo into four channels")
    testing.expect_eq(t, four[1], 0.25, "the channels both have copied")
    testing.expect_eq(t, four[3], 0.0, "the new ones silent")
    testing.expect_eq(t, audio.remix(pair[0..<4], 0, four[0..<8], 4), 0, "no channels make nothing")
    return .Ok
}

/**
 * Resample a mono signal in blocks of a size, collecting what comes out.
 *
 * @return The output, on the heap, the caller's to free; its count is how many frames came out.
 */
resampled :: fn(from_rate : u32, to_rate : u32, input : f32[], block : usize) -> f32[..] {
    resampler :: runtime.new(audio.Resampler)
    defer runtime.free(resampler)
    _ = audio.resampler_for(resampler, from_rate, to_rate, 1)
    out : f32[..]
    piece := zeros(0)
    piece = zeros(audio.resampled_frames(resampler, block))
    defer runtime.array_free(&piece)
    at := cast[usize](0)
    loop {
        if at >= input.count {
            break
        }
        end :: if at + block < input.count { at + block } else { input.count }
        made :: audio.resample(resampler, part(input, at, end), piece[0..<piece.count])
        for i in 0..<made {
            if i < piece.count {
                runtime.array_add(&out, piece[i])
            }
        }
        at = end
    }
    return out
}

resamples_a_tone_keeping_its_frequency_and_level #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    input := zeros(44100)
    defer runtime.array_free(&input)
    tone(input[0..<input.count], 1000.0, 44100.0, 0.5)
    out := resampled(44100, 48000, input[0..<input.count], 441)
    defer runtime.array_free(&out)
    testing.expect_ge(t, out.count, 47900, "a second at 44.1 kHz is about a second at 48 kHz, less the filter's delay")
    // 100 ms past the delay: a whole number of the tone's cycles
    window :: part(out[0..<out.count], 2000, 6800)
    near(t, strength(window, 1000.0, 48000.0), 0.5, 0.005, "the tone keeps its level")
    testing.expect_lt(t, strength(window, 3000.0, 48000.0), 0.0005, "and gains no third harmonic")
    testing.expect_lt(t, strength(window, 9100.0, 48000.0), 0.0005, "nor an image of the input's rate")
    at_48 := zeros(48000)
    defer runtime.array_free(&at_48)
    tone(at_48[0..<at_48.count], 1000.0, 48000.0, 0.5)
    same := resampled(48000, 48000, at_48[0..<at_48.count], 480)
    defer runtime.array_free(&same)
    near(
        t,
        strength(part(same[0..<same.count], 2000, 6800), 1000.0, 48000.0),
        0.5,
        0.005,
        "the same rate passes it through"
    )
    return .Ok
}

keeps_what_is_above_the_lower_half_from_folding_back #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    input := zeros(48000)
    defer runtime.array_free(&input)
    // Above 44.1 kHz's half, 22.05 kHz: unfiltered, it would fold back to 21.1 kHz
    tone(input[0..<input.count], 23000.0, 48000.0, 0.5)
    out := resampled(48000, 44100, input[0..<input.count], 480)
    defer runtime.array_free(&out)
    window :: part(out[0..<out.count], 2000, 6410)
    testing.expect_lt(t, strength(window, 21100.0, 44100.0), 0.0005, "folded back at under a thousandth of its level")
    passband := zeros(48000)
    defer runtime.array_free(&passband)
    tone(passband[0..<passband.count], 10000.0, 48000.0, 0.5)
    kept := resampled(48000, 44100, passband[0..<passband.count], 480)
    defer runtime.array_free(&kept)
    near(
        t,
        strength(part(kept[0..<kept.count], 2000, 6410), 10000.0, 44100.0),
        0.5,
        0.005,
        "while 10 kHz keeps its level"
    )
    return .Ok
}

gives_the_same_however_the_input_is_blocked #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    input := zeros(9600)
    defer runtime.array_free(&input)
    tone(input[0..<input.count], 440.0, 48000.0, 0.8)
    whole := resampled(48000, 44100, input[0..<input.count], 9600)
    defer runtime.array_free(&whole)
    pieces := resampled(48000, 44100, input[0..<input.count], 7)
    defer runtime.array_free(&pieces)
    testing.expect_eq(t, pieces.count, whole.count, "as many frames in blocks of 7 as in one block")
    worst := cast[f32](0.0)
    for value, i in whole {
        if i < pieces.count {
            gap :: if value > pieces[i] { value - pieces[i] } else { pieces[i] - value }
            worst = if gap > worst { gap } else { worst }
        }
    }
    testing.expect_lt(t, worst, 0.000001, "and the same frames")
    return .Ok
}

writes_and_reads_a_wav #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    format :: audio.Format.{sample = .S16, rate = 48000, channels = 2}
    samples : f32[200]
    tone(samples[0..<200], 1000.0, 48000.0, 0.5)
    data : u8[400]
    _ = audio.encode(samples[0..<200], .S16, data[0..<400])
    file : u8[444]
    testing.expect_eq(t, audio.wav_bytes(format, 100) or_else 0, 444, "100 stereo 16-bit frames and the header")
    written :: testing.require_some(t, audio.write_wav(format, data[0..<400], file[0..<444]), "it's written")?
    testing.expect_eq(t, written, 444, "all of it")
    read :: testing.require_ok(t, audio.read_wav(file[0..<444]), "and read back")?
    testing.expect_eq(t, read.format, format, "its format")
    testing.expect_eq(t, read.frames, 100, "its frames")
    same := true
    for byte, i in read.data {
        if i < data.count && byte != data[i] {
            same = false
        }
    }
    testing.expect(t, same && read.data.count == 400, "its samples' bytes as written")
    testing.expect_none(t, audio.write_wav(format, data[0..<400], file[0..<443]), "a byte short, nothing's written")
    return .Ok
}

/** A little-endian word into bytes. */
put :: fn(into : ptr[mut u8[..]], value : u64, count : usize) {
    for i in 0..<count {
        runtime.array_add(into, cast[u8](value >> (8 * cast[u64](i))))
    }
}

/** Some ASCII into bytes. */
put_text :: fn(into : ptr[mut u8[..]], text : string) {
    for byte in text {
        runtime.array_add(into, cast[u8](byte))
    }
}

/**
 * A WAV file as another program might write it: a fmt chunk of a tag and size, a LIST chunk of odd size before the
 * data, and a data chunk.
 */
other_wav :: fn(tag : u16, bits : u16, extensible : bool, data_size : u32) -> u8[..] {
    out : u8[..]
    channels :: cast[u64](2)
    block :: channels * cast[u64](bits / 8)
    put_text(&out, "RIFF")
    put(&out, 0, 4)
    put_text(&out, "WAVE")
    put_text(&out, "fmt ")
    put(&out, if extensible { 40 } else { 18 }, 4)
    put(&out, if extensible { 0xfffe } else { cast[u64](tag) }, 2)
    put(&out, channels, 2)
    put(&out, 44100, 4)
    put(&out, 44100 * block, 4)
    put(&out, block, 2)
    put(&out, cast[u64](bits), 2)
    if extensible {
        put(&out, 22, 2)
        put(&out, cast[u64](bits), 2)
        put(&out, 3, 4)
        put(&out, cast[u64](tag), 2)
        // The rest of the sub-format's GUID, 00000000-0010-8000-00aa00389b71's bytes after its first two
        for byte in u8.[0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71] {
            runtime.array_add(&out, byte)
        }
    }
    else {
        put(&out, 0, 2)
    }
    put_text(&out, "LIST")
    put(&out, 3, 4)
    put_text(&out, "abc\0")
    put_text(&out, "data")
    put(&out, cast[u64](data_size), 4)
    for i in 0..<(4 * block) {
        runtime.array_add(&out, cast[u8](i))
    }
    return out
}

reads_wavs_as_others_write_them #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    extensible := other_wav(1, 24, true, 24)
    defer runtime.array_free(&extensible)
    read :: testing.require_ok(t, audio.read_wav(extensible[0..<extensible.count]), "an extensible 24-bit file")?
    testing.expect_eq(t, read.format.sample, audio.SampleFormat.S24, "its samples 24-bit")
    testing.expect_eq(t, read.frames, 4, "four frames, past the odd-sized LIST chunk")
    float := other_wav(3, 32, false, 0xffffffff)
    defer runtime.array_free(&float)
    streamed :: testing.require_ok(
        t,
        audio.read_wav(float[0..<float.count]),
        "a float file whose data has no size yet"
    )?
    testing.expect_eq(t, streamed.format.sample, audio.SampleFormat.F32, "its samples floats")
    testing.expect_eq(t, streamed.frames, 4, "its data taken as far as the file goes")
    return .Ok
}

refuses_what_is_not_a_wav_it_reads #test :: fn(t : ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_error(t, audio.read_wav(string_bytes("RIFX....WAVE")), audio.WavError.NotWav, "not RIFF")
    compressed := other_wav(2, 16, false, 16)
    defer runtime.array_free(&compressed)
    testing.expect_error(
        t,
        audio.read_wav(compressed[0..<compressed.count]),
        audio.WavError.Unsupported,
        "ADPCM isn't read"
    )
    odd := other_wav(1, 16, false, 16)
    defer runtime.array_free(&odd)
    // The block size, two stereo 16-bit samples, made 3
    if odd.count > 32 {
        odd[32] = 3
    }
    testing.expect_error(
        t,
        audio.read_wav(odd[0..<odd.count]),
        audio.WavError.Malformed,
        "a block that isn't its frame"
    )
    header : u8[..]
    defer runtime.array_free(&header)
    put_text(&header, "RIFF")
    put(&header, 4, 4)
    put_text(&header, "WAVE")
    testing.expect_error(t, audio.read_wav(header[0..<header.count]), audio.WavError.Incomplete, "no chunks")
    return .Ok
}

/** Any bytes are refused as a WAV file, or read, its data within them and whole frames. */
reads_any_bytes_as_a_wav #test :: fn(t : ptr[mut testing.T], source : ptr[mut testing.Source]) -> testing.Outcome {
    start := other_wav(1, 16, testing.draw_bool(source), 16)
    defer runtime.array_free(&start)
    // A real header with some of its bytes changed, or bytes drawn whole
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    if testing.draw_bool(source) {
        for byte in start {
            runtime.array_add(&bytes, byte)
        }
        for change in 0..<testing.draw_count(source, 8) {
            view :: bytes[0..<bytes.count]
            at :: cast[usize](testing.draw_below(source, cast[u64](view.count)))
            if at < view.count {
                view[at] = testing.draw_byte(source)
            }
        }
    }
    else {
        for byte in testing.draw_bytes(source, 300) {
            runtime.array_add(&bytes, byte)
        }
    }
    match audio.read_wav(bytes[0..<bytes.count]) {
        case Ok(read) => {
            frame :: audio.frame_bytes(read.format)
            testing.expect(t, frame > 0 && read.data.count == read.frames * frame, "whole frames")
            testing.expect(t, read.data.count <= bytes.count, "within the bytes")
            samples : f32[64]
            _ = audio.decode(read.format.sample, read.data, samples[0..<samples.count])
        }
        case Error(_) => {}
    }
    return .Ok
}
