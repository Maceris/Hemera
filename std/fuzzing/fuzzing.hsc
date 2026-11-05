package fuzzing

import runtime from "base"
import intrinsics from "base"
import os from "std"
import strings from "std"
import testing from "std"
import text_buffer from "std"
import time from "std"

/** How many changes, at most, make one input from another. */
MAX_CHANGES :: 4

/** How many bytes a path the fuzzer makes can have, a folder's and a file's name in it together. */
PATH_BYTES :: 512

/** What fuzz does, as hemera --fuzz gives it. */
FuzzOptions :: struct {
    /** How long it fuzzes, in seconds; 0 for no limit. */
    seconds : u64,
    /** How many inputs it tries at most; 0 for no limit. */
    runs : u64,
    /**
     * Where it keeps its inputs: <folder>/corpus those that reached new code, and <folder>/findings those that failed;
     * empty for fuzz/<the test's name>, from where it runs. The folders are made if they aren't there.
     */
    folder : string,
    /** The seed the changes to inputs come from, so a run can be repeated; 0 for one from the clock. */
    seed : u64,
}

/** What an assertion that fails in the test needs, to keep the input that made it: the context's, while one runs. */
Running :: struct {
    /** The input being run, a view of the fuzzer's room on the heap. */
    input : u8[],
    /** The findings folder, on the heap, where the input is written. */
    findings : string,
    /** The test's name, as it's reported. */
    name : string,
}

/** An input kept in the corpus: one that reached code no input before it had. */
Input :: struct {
    /** Its bytes, the fuzzer's own. */
    bytes : u8[..],
}

/** A fuzzer's state. */
Fuzzer :: struct {
    /** The test. */
    property : testing.Property,
    /** Its name, a copy on the heap. */
    name : string,
    /** The program's coverage counters. */
    counters : mut u8[],
    /** The constants the program compares with, which changes put in inputs. */
    constants : u64[],
    /**
     * For each counter, the ranges its counts have reached in some input, a bit each (bucket_of): an input that sets a
     * new one has reached new code, or reached code a new number of times.
     */
    seen : u8[..],
    /** How many bits of seen are set: how much coverage the corpus has. */
    reached : usize,
    /** The inputs kept. */
    corpus : Input[..],
    /** Where the input being run is, which its source reads from, on the heap so an assertion's handler can save it. */
    room : ptr[mut testing.Case],
    /** The state of the random generator the changes come from. */
    random : u64,
    /** How many inputs have been run. */
    runs : u64,
    /** Where the corpus is kept. */
    corpus_folder : string,
    /** Where failing inputs are kept. */
    findings_folder : string,
}

/** What running an input found. */
Ran :: struct {
    /** Whether the test failed on it. */
    failed : bool,
    /** Whether it reached code, or a number of times through code, that no input before it had. */
    new_coverage : bool,
}

/**
 * Write a line to standard output, each % replaced by the next value.
 *
 * @param format_string The line, without its newline.
 * @param values The values for its %s.
 */
say :: fn(format_string: string, values: any...) {
    storage : u8[2 * PATH_BYTES]
    line := text_buffer.make(storage)
    text_buffer.append_format(&line, format_string, values)
    text_buffer.append(&line, "\n")
    runtime.write_output(text_buffer.as_string(&line))
}

/**
 * Give which range a counter's count is in, as a bit: 1, 2, 3, 4 to 7, 8 to 15, 16 to 31, 32 to 127, or more.
 *
 * @param count The count, as the block's counter has it after an input; 0 for a block the input didn't reach.
 * @return The range's bit; 0 for a count of 0.
 */
bucket_of :: fn(count: u8) -> u8 {
    if count == 0 {
        return 0
    }
    if count <= 3 {
        return cast[u8](1) << (count - 1)
    }
    if count <= 7 {
        return 8
    }
    if count <= 15 {
        return 16
    }
    if count <= 31 {
        return 32
    }
    if count <= 127 {
        return 64
    }
    return 128
}

/**
 * Give a name for an input's file, from what's in it, so the same input is kept once.
 *
 * @param bytes The input.
 * @param into Where the name goes: 16 hexadecimal digits of its FNV-1a hash.
 */
name_of :: fn(bytes: u8[], into: ptr[mut text_buffer.TextBuffer]) {
    hash : u64 = 0xcbf29ce484222325
    for byte in bytes {
        hash = (hash ~ cast[u64](byte)) * 0x100000001b3
    }
    text_buffer.append_unsigned(into, hash, 16, 16)
}

/**
 * Give bytes as a string, for writing to a file.
 *
 * @param bytes The bytes.
 * @return A string of them, the same memory; "" for none.
 */
as_text :: fn(bytes: u8[]) -> string {
    if bytes.count == 0 {
        return ""
    }
    return string_of(cast[ptr[u8]](&bytes[0]), bytes.count)
}

/**
 * Write an input to a file in a folder, named for what's in it.
 *
 * @param folder The folder.
 * @param bytes The input.
 * @param path Where the file's path goes.
 * @return The error, if it couldn't be written; null if it was.
 */
keep :: fn(folder: string, bytes: u8[], path: ptr[mut text_buffer.TextBuffer]) -> os.OsError? {
    text_buffer.append(path, folder)
    text_buffer.append(path, "/")
    name_of(bytes, path)
    return os.write_entire_file(text_buffer.as_string(path), as_text(bytes))
}

/**
 * Make a folder, and each folder above it that isn't there.
 *
 * @param path The folder's path, its parts separated by /.
 * @return Whether it's there now.
 */
make_folders :: fn(path: string) -> bool {
    for character, i in path {
        if character == '/' && i > 0 && i <= path.count {
            above :: path[0..<i]
            if !os.is_directory(above) {
                _ = os.make_directory(above)
            }
        }
    }
    if !os.is_directory(path) {
        _ = os.make_directory(path)
    }
    return os.is_directory(path)
}

/**
 * Copy text to the heap, as what a context extension holds has to be.
 *
 * @param text The text.
 * @return The copy, from the context's allocator, never freed: it lasts for the program, as a fuzzer does.
 */
copied :: fn(text: string) -> string {
    copy, error :: runtime.new_array(u8, text.count)
    if error != null || copy.count == 0 {
        return ""
    }
    for character, i in text {
        if i < copy.count {
            copy[i] = cast[u8](character)
        }
    }
    return string_of(&copy[0], copy.count)
}

/**
 * End the program when an assertion fails in the test, keeping the input that made it in the findings folder,
 * unshrunk, as the program can't go on to shrink it: the fuzzer's assertion handler.
 *
 * @param location Where the assertion was.
 * @param message What failed.
 */
on_assertion : runtime.AssertionHandler : fn(location: runtime.SourceCodeLocation, message: string) #never_returns {
    match runtime.get_extension(Running) {
        case Some(running) => {
            storage : u8[PATH_BYTES]
            path := text_buffer.make(storage)
            error :: keep(running.findings, running.input, &path)
            say("fuzz %: an assertion failed: %", running.name, message)
            say("    %:%", location.file_path, location.line)
            if error == null {
                say("    the input is kept as %, as it was, not shrunk", text_buffer.as_string(&path))
            }
        }
        case None => {
            say("assertion failed: %", message)
        }
    }
    os.exit(1)
}

/**
 * Run the test on an input, and see what code it reached.
 *
 * @param fuzzer The fuzzer, whose counters are zeroed first, and whose seen and reached grow with what's new. Its room
 *     is left the bytes the test read: the input's, and zeros past its end.
 * @param input The input; past its end, the test reads zeros. More than testing.MAX_CASE_BYTES is cut.
 * @return What the run found.
 */
run_input :: fn(fuzzer: ptr[mut Fuzzer], input: u8[]) -> Ran {
    testing.set_case(fuzzer.room, input)
    counters :: fuzzer.counters
    for index in 0..<counters.count {
        counters[index] = 0
    }
    room :: fuzzer.room
    source := testing.source_in(room.bytes[0..<room.bytes.count], room.count, null)
    attempt := testing.T.{name = fuzzer.name}
    _ = fuzzer.property(&attempt, &source)
    fuzzer.runs += 1
    // The bytes it read are the input's: zeros past its end included, and not what it didn't read
    fuzzer.room.count = testing.read_bytes(&source).count
    ran := Ran.{failed = attempt.failure_count > 0 || source.unsupported.count > 0}
    for count, i in fuzzer.counters {
        bit :: bucket_of(count)
        if bit == 0 || i >= fuzzer.seen.count || (fuzzer.seen[i] & bit) != 0 {
            continue
        }
        fuzzer.seen[i] = fuzzer.seen[i] | bit
        fuzzer.reached += 1
        ran.new_coverage = true
    }
    return ran
}

/**
 * Keep an input in the corpus, and in the corpus folder unless it came from there.
 *
 * @param fuzzer The fuzzer, whose corpus grows by one.
 * @param bytes The input, copied.
 * @param save Whether to write it to the corpus folder.
 */
add_input :: fn(fuzzer: ptr[mut Fuzzer], bytes: u8[], save: bool) {
    kept := Input.{}
    for byte in bytes {
        runtime.array_add(&kept.bytes, byte)
    }
    runtime.array_add(&fuzzer.corpus, kept)
    if save {
        storage : u8[PATH_BYTES]
        path := text_buffer.make(storage)
        _ = keep(fuzzer.corpus_folder, bytes, &path)
    }
}

/**
 * Report a failing input: shrink it, report the smallest as a test that failed, and keep it in the findings folder.
 *
 * @param fuzzer The fuzzer.
 * @param failing The input, on which the test failed.
 * @param how How it was found, like "the corpus" or "fuzzing, 5120 inputs in".
 */
report_finding :: fn(fuzzer: ptr[mut Fuzzer], failing: u8[], how: string) {
    t := testing.T.{name = fuzzer.name}
    smallest : testing.Case
    _ = testing.report_shrunk(&t, fuzzer.property, failing, &smallest, "%", how)
    testing.report_failed(testing.STANDARD_OUTPUT, &t)
    storage : u8[PATH_BYTES]
    path := text_buffer.make(storage)
    if keep(fuzzer.findings_folder, testing.case_bytes(&smallest), &path) == null {
        say("    kept as %, which hemera --fuzz=% runs first, until the test passes on it", text_buffer.as_string(&path), fuzzer.name)
    }
}

/**
 * Run the test on each input a folder has, as the fuzzer starts.
 *
 * @param fuzzer The fuzzer.
 * @param folder The folder, whose files are inputs; one that isn't there has none.
 * @param keep_new Whether to keep in the corpus those that reach new code: for the corpus folder's, not the findings'.
 * @return Whether the test passed on them all; one that fails is reported.
 */
run_folder :: fn(fuzzer: ptr[mut Fuzzer], folder: string, keep_new: bool) -> bool {
    // A folder that isn't there has no inputs
    entries :: os.list_directory(folder) or_return true
    defer os.free_directory_listing(entries)
    for entry in entries {
        if entry.is_directory {
            continue
        }
        storage : u8[PATH_BYTES]
        path := text_buffer.make(storage)
        text_buffer.append(&path, folder)
        text_buffer.append(&path, "/")
        text_buffer.append(&path, entry.name)
        contents :: os.read_entire_file(text_buffer.as_string(&path)) or_else ""
        defer strings.free_string(contents)
        bytes : u8[..]
        defer runtime.array_free(&bytes)
        for character in contents {
            runtime.array_add(&bytes, cast[u8](character))
        }
        ran :: run_input(fuzzer, bytes)
        if ran.failed {
            report_finding(fuzzer, bytes, if keep_new { "the corpus" } else { "an input kept from an earlier run" })
            return false
        }
        if keep_new && ran.new_coverage {
            add_input(fuzzer, testing.case_bytes(fuzzer.room), false)
        }
    }
    return true
}

/**
 * Draw a number below a bound, from the fuzzer's generator.
 *
 * @param fuzzer The fuzzer, whose generator advances.
 * @param bound One more than the largest number wanted; 0 gives 0.
 * @return A number from 0 to bound - 1.
 */
below :: fn(fuzzer: ptr[mut Fuzzer], bound: usize) -> usize {
    if bound == 0 {
        return 0
    }
    return cast[usize](testing.next_random(&fuzzer.random) % cast[u64](bound))
}

/**
 * Put a byte in an input, moving those after it along; an input that's full is left as it is.
 *
 * @param input The input.
 * @param at Where, 0 to its count.
 * @param byte The byte.
 */
put_in :: fn(input: ptr[mut testing.Case], at: usize, byte: u8) {
    if input.count >= input.bytes.count || at > input.count {
        return void
    }
    place := input.count
    loop {
        if place <= at || place >= input.bytes.count {
            break
        }
        input.bytes[place] = input.bytes[place - 1]
        place -= 1
    }
    if at < input.bytes.count {
        input.bytes[at] = byte
    }
    input.count += 1
}

/**
 * Take a byte out of an input, moving those after it back.
 *
 * @param input The input.
 * @param at Which; past its count, nothing is taken out.
 */
take_out :: fn(input: ptr[mut testing.Case], at: usize) {
    if at >= input.count || input.count > input.bytes.count {
        return void
    }
    for place in at..<input.count - 1 {
        if place < input.bytes.count && place + 1 < input.bytes.count {
            input.bytes[place] = input.bytes[place + 1]
        }
    }
    input.count -= 1
}

/**
 * Make a new input from a corpus input by changing it a few times: flipping a bit, setting a byte, putting in a value
 * at an edge or a constant the program compares with, putting in or taking out bytes, copying some of it elsewhere in
 * it, or bringing in some of another input.
 *
 * @param fuzzer The fuzzer, whose generator advances.
 * @param parent The input changed.
 * @param other Another input, which some of may be brought in.
 * @param into Where the new input goes, at most testing.MAX_CASE_BYTES.
 */
mutate :: fn(fuzzer: ptr[mut Fuzzer], parent: u8[], other: u8[], into: ptr[mut testing.Case]) {
    testing.set_case(into, parent)
    edges :: u64.[0, 1, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff, 0x7fff_ffff, 0x8000_0000, 0xffff_ffff, ~cast[u64](0)]
    changes :: 1 + below(fuzzer, MAX_CHANGES)
    for change in 0..<changes {
        count :: if into.count < into.bytes.count { into.count } else { into.bytes.count }
        kind :: below(fuzzer, 10)
        switch kind {
            case 0:
                // A bit flipped
                at :: below(fuzzer, count)
                if at < count && at < into.bytes.count {
                    into.bytes[at] = into.bytes[at] ~ (cast[u8](1) << cast[u8](below(fuzzer, 8)))
                }
            case 1:
                // A byte set
                at :: below(fuzzer, count)
                if at < count && at < into.bytes.count {
                    into.bytes[at] = cast[u8](below(fuzzer, 256))
                }
            case 2:
                // Fresh bytes put in
                at :: below(fuzzer, count + 1)
                for index in 0..<1 + below(fuzzer, 4) {
                    put_in(into, at, cast[u8](below(fuzzer, 256)))
                }
            case 3:
                // Bytes taken out
                if count > 0 {
                    at :: below(fuzzer, count)
                    for index in 0..<1 + below(fuzzer, 8) {
                        take_out(into, at)
                    }
                }
            case 4:
                // A value at an edge, in 1, 2, 4 or 8 bytes, either way round
                size :: cast[usize](1) << below(fuzzer, 4)
                value :: edges[below(fuzzer, edges.count) % edges.count]
                at :: below(fuzzer, count)
                big :: below(fuzzer, 2) == 0
                for index in 0..<size {
                    shift :: if big { (size - 1 - index) * 8 } else { index * 8 }
                    if at + index < count && at + index < into.bytes.count {
                        into.bytes[at + index] = cast[u8]((value >> cast[u64](shift)) & 0xff)
                    }
                }
            case 5:
                // A small step up or down
                at :: below(fuzzer, count)
                step :: cast[u8](1 + below(fuzzer, 16))
                if at < count && at < into.bytes.count {
                    into.bytes[at] = if below(fuzzer, 2) == 0 { into.bytes[at] + step } else { into.bytes[at] - step }
                }
            case 6:
                // Some of it copied elsewhere in it
                from :: below(fuzzer, count)
                to :: below(fuzzer, count)
                for index in 0..<1 + below(fuzzer, 16) {
                    if from + index < count && to + index < count && from + index < into.bytes.count && to + index < into.bytes.count {
                        into.bytes[to + index] = into.bytes[from + index]
                    }
                }
            case 7, 8:
                // A constant the program compares with, in as few bytes as it fits, either way round, over it or put in
                if fuzzer.constants.count > 0 {
                    value :: fuzzer.constants[below(fuzzer, fuzzer.constants.count) % fuzzer.constants.count]
                    size :: if value <= 0xff { cast[usize](1) } else if value <= 0xffff { cast[usize](2) } else if value <= 0xffff_ffff { cast[usize](4) } else { cast[usize](8) }
                    at :: below(fuzzer, count + 1)
                    big :: below(fuzzer, 2) == 0
                    over :: below(fuzzer, 2) == 0
                    for index in 0..<size {
                        shift :: if big { (size - 1 - index) * 8 } else { index * 8 }
                        byte :: cast[u8]((value >> cast[u64](shift)) & 0xff)
                        if over && at + index < into.count && at + index < into.bytes.count {
                            into.bytes[at + index] = byte
                        }
                        else {
                            put_in(into, at + index, byte)
                        }
                    }
                }
            case _:
                // Some of another input, written over it or after it
                from :: below(fuzzer, other.count)
                to :: below(fuzzer, count + 1)
                for index in 0..<1 + below(fuzzer, 32) {
                    if from + index >= other.count {
                        break
                    }
                    byte :: other[from + index]
                    if to + index < into.count && to + index < into.bytes.count {
                        into.bytes[to + index] = byte
                    }
                    else {
                        put_in(into, into.count, byte)
                    }
                }
        }
    }
}

/**
 * Report how far the fuzzer has got: inputs run, coverage, the corpus, and inputs a second.
 *
 * @param fuzzer The fuzzer.
 * @param start When it started.
 */
report_progress :: fn(fuzzer: ptr[Fuzzer], start: runtime.MonotonicTime) {
    took :: time.since(start)
    milliseconds :: cast[u64](took.seconds) * 1000 + cast[u64](took.nanos) / 1_000_000
    rate :: if milliseconds == 0 { cast[u64](0) } else { fuzzer.runs * 1000 / milliseconds }
    say("fuzz %: % inputs, coverage %, corpus %, % a second", fuzzer.name, fuzzer.runs, fuzzer.reached, fuzzer.corpus.count, rate)
}

/**
 * Fuzz a property test: run it on inputs from the corpus folder and the findings folder, then on input after input
 * made by changing those kept, keeping each that reaches code no input before it had, until the time or the runs
 * options give run out, or the test fails. A failing input is shrunk, reported as a test that failed is, and kept in
 * the findings folder; an assertion that fails ends the program with the input kept as it was. Progress is reported
 * to standard output every second or so.
 *
 * The program has to be built with hemera --fuzz, which counts the blocks each input reaches; hemera --fuzz=name
 * builds one whose entry calls this.
 *
 * @param property The test.
 * @param name Its name, as reports give it, and its folder's.
 * @param options How long, and where its inputs are kept.
 * @return The program's exit code: 0 if the test passed on every input; 1 if it failed on one; 2 if the program
 *     wasn't built for fuzzing, or its folders can't be made.
 */
fuzz :: fn(property: testing.Property, name: string, options: FuzzOptions) -> int {
    counters :: intrinsics.coverage_counters()
    if counters.count == 0 {
        say("fuzz %: the program counts no coverage; build it with hemera --fuzz=%", name, name)
        return 2
    }
    storage : u8[PATH_BYTES]
    folder := text_buffer.make(storage)
    if options.folder.count > 0 {
        text_buffer.append(&folder, options.folder)
    }
    else {
        text_buffer.append_format(&folder, "fuzz/%", name)
    }
    corpus_storage : u8[PATH_BYTES]
    corpus_path := text_buffer.make(corpus_storage)
    text_buffer.append_format(&corpus_path, "%/corpus", text_buffer.as_string(&folder))
    findings_storage : u8[PATH_BYTES]
    findings_path := text_buffer.make(findings_storage)
    text_buffer.append_format(&findings_path, "%/findings", text_buffer.as_string(&folder))
    if !make_folders(text_buffer.as_string(&corpus_path)) || !make_folders(text_buffer.as_string(&findings_path)) {
        say("fuzz %: can't make the folders in %", name, text_buffer.as_string(&folder))
        return 2
    }
    room :: runtime.new(testing.Case)
    findings :: copied(text_buffer.as_string(&findings_path))
    test_name :: copied(name)
    fuzzer := Fuzzer.{property = property, name = test_name, counters = counters, constants = intrinsics.coverage_constants(), room = room,
        random = if options.seed != 0 { options.seed } else { cast[u64](time.monotonic()) }, corpus_folder = copied(text_buffer.as_string(&corpus_path)),
        findings_folder = findings}
    for index in 0..<counters.count {
        runtime.array_add(&fuzzer.seen, 0)
    }
    running :: runtime.new(Running)
    running.input = room.bytes[0..<room.bytes.count]
    running.findings = findings
    running.name = test_name
    node := runtime.extension_node(running)
    result := 0
    push_context fuzzing (assertion_handler = on_assertion, extensions = &node) {
        result = fuzz_with(&fuzzer, options)
    }
    return result
}

/**
 * Fuzz, once the fuzzer is set up, as fuzz does.
 *
 * @param fuzzer The fuzzer.
 * @param options How long.
 * @return fuzz's exit code.
 */
fuzz_with :: fn(fuzzer: ptr[mut Fuzzer], options: FuzzOptions) -> int {
    start :: time.monotonic()
    if !run_folder(fuzzer, fuzzer.findings_folder, false) || !run_folder(fuzzer, fuzzer.corpus_folder, true) {
        return 1
    }
    if fuzzer.corpus.count == 0 {
        empty :: u8.[]
        ran :: run_input(fuzzer, empty)
        if ran.failed {
            report_finding(fuzzer, empty, "the empty input")
            return 1
        }
        add_input(fuzzer, testing.case_bytes(fuzzer.room), true)
    }
    say("fuzz %: % inputs to start from, coverage %", fuzzer.name, fuzzer.corpus.count, fuzzer.reached)
    candidate : testing.Case
    last_report : i64 = 0
    loop {
        if options.runs > 0 && fuzzer.runs >= options.runs {
            break
        }
        // The clock is read now and then, as reading it costs more than a run of a small test
        if fuzzer.runs % 64 == 0 {
            took :: time.since(start)
            if options.seconds > 0 && took.seconds >= cast[i64](options.seconds) {
                break
            }
            if took.seconds > last_report {
                last_report = took.seconds
                report_progress(fuzzer, start)
            }
        }
        parent :: below(fuzzer, fuzzer.corpus.count)
        other :: below(fuzzer, fuzzer.corpus.count)
        if parent >= fuzzer.corpus.count || other >= fuzzer.corpus.count {
            break
        }
        mutate(fuzzer, fuzzer.corpus[parent].bytes, fuzzer.corpus[other].bytes, &candidate)
        ran :: run_input(fuzzer, testing.case_bytes(&candidate))
        if ran.failed {
            storage : u8[64]
            how := text_buffer.make(storage)
            text_buffer.append_format(&how, "fuzzing, % inputs in", fuzzer.runs)
            report_finding(fuzzer, testing.case_bytes(&candidate), text_buffer.as_string(&how))
            return 1
        }
        if ran.new_coverage {
            add_input(fuzzer, testing.case_bytes(fuzzer.room), true)
        }
    }
    report_progress(fuzzer, start)
    return 0
}
