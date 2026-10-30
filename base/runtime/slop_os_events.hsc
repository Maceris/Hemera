package runtime

import compiler from "base"
import intrinsics from "base"

/*
 * SlopOS's logger (the SlopOS repository's design/observability.md §2, decisions/0093): context.logger's records,
 * written into a ring the process shares with the events service, with no system call per record. A record is the
 * monotonic time, the level, the format string, and each argument as its type's schema hash and its value, written by
 * schema_write_value; the service renders it when it's read. A literal format string is named by its offset in the
 * program's image; any other is the record's first argument. The first time a process uses a format string or a type,
 * the ring is given its text or its schema first, so the service can render what follows without the program's image.
 *
 * The ring's layout is declared for every OS, for the events service to read it with.
 *
 * The ring: a SlopOsEventsRing, then size bytes of entries, each a SlopOsEventsEntry and what its kind has, padded to
 * 8 bytes. An entry never wraps: one that wouldn't fit before the end is put at the start, after a Pad. The writer
 * publishes what it wrote by moving written on, and the reader what it's read by moving read on; both only grow. A
 * full ring drops the newest records, which are counted, and reported in a Dropped entry once there's room. A reader
 * that sets waiting before it waits is woken by a one-byte message on the doorbell, the next time anything's written.
 * A reader that takes a ring over from one that ended moves reader on, and the writer gives every format string and
 * schema again from its next record, as the new reader knows none of them.
 */

SLOP_OS_EVENTS_MAGIC : u32 : 0x52545645
SLOP_OS_EVENTS_VERSION : u32 : 1
// A ring's bytes, its header's included, as the events service makes it
SLOP_OS_EVENTS_RING_BYTES : u64 : 16384

SlopOsEventsRing :: struct {
    magic : u32,
    version : u32,
    // Bytes of entries after the header
    size : u64,
    // Bytes ever written, which the writer moves on, and ever read, which the reader does
    written : u64,
    read : u64,
    // 1 while the reader waits for the doorbell; the writer clears it, and rings
    waiting : u32,
    // Which reader's: moved on by each that takes the ring over
    reader : u32,
    unused : u64[3],
}

#assert size_of(SlopOsEventsRing) == 64

SlopOsEventsEntry :: struct {
    // Its bytes, this header's included, a multiple of 8
    size : u32,
    kind : u16,
    reserved : u16,
}

// An entry's kinds.
SLOP_OS_EVENTS_PAD : u16 : 1
SLOP_OS_EVENTS_FORMAT : u16 : 2
SLOP_OS_EVENTS_SCHEMA : u16 : 3
SLOP_OS_EVENTS_RECORD : u16 : 4
SLOP_OS_EVENTS_DROPPED : u16 : 5

// A format string's text, then count bytes of it.
SlopOsEventsFormat :: struct {
    entry : SlopOsEventsEntry,
    // Its offset in the program's image
    offset : u64,
    count : u32,
    reserved : u32,
}

// A type's schema (schema_write), then count bytes of it.
SlopOsEventsSchema :: struct {
    entry : SlopOsEventsEntry,
    hash : u8[32],
    count : u32,
    reserved : u32,
}

// A record, then its arguments, each a SlopOsEventsArgument and count bytes of its value, padded to 8.
SlopOsEventsRecord :: struct {
    entry : SlopOsEventsEntry,
    // The monotonic clock's nanoseconds when it was written
    time : u64,
    // A LogLevel
    level : u8,
    argument_count : u8,
    // 1 if the format string is named by format; 0 if it's the first argument
    named : u8,
    reserved : u8,
    reserved_more : u32,
    format : u64,
}

SlopOsEventsArgument :: struct {
    hash : u8[32],
    count : u32,
    reserved : u32,
}

// How many records were dropped while the ring was full.
SlopOsEventsDropped :: struct {
    entry : SlopOsEventsEntry,
    count : u64,
}

// The most arguments a record holds, its format string's among them; any after them aren't written.
SLOP_OS_EVENTS_MAX_ARGUMENTS :: 32

// A number rounded up to 8.
slop_os_events_padded #no_context :: fn(count: u64) -> u64 {
    return (count + 7) & ~cast[u64](7)
}

#if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    // How many format strings' offsets and types' hashes a process remembers giving; past those, they're given again.
    SLOP_OS_EVENTS_FORMATS :: 128
    SLOP_OS_EVENTS_TYPES :: 64

    SlopOsEventsType :: struct {
        type : uintptr,
        hash : u8[32],
    }

    // What the process's logger keeps, in pages of its own (ProcessState's events_log).
    SlopOsEventsLog :: struct {
        ring : ptr[mut SlopOsEventsRing],
        doorbell : u32,
        lock : u32,
        // The ring's reader when formats and types were given
        reader : u32,
        // Records dropped and not reported yet
        dropped : u64,
        // Offsets given, plus 1, so 0 is a free place
        formats : u64[SLOP_OS_EVENTS_FORMATS],
        types : SlopOsEventsType[SLOP_OS_EVENTS_TYPES],
        type_count : usize,
        // Entries put together before they go in the ring, and a type's schema
        entries : u8[..],
        scratch : u8[..],
    }

    SLOP_OS_LOGGER :: Logger.{
        data = null,
        trace = slop_os_log_trace,
        debug = slop_os_log_debug,
        info = slop_os_log_info,
        warn = slop_os_log_warn,
        error = slop_os_log_error,
        fatal = slop_os_log_fatal,
        name = "slop_os",
    }

    slop_os_log_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.TRACE, "trace", format_string, params)
    }

    slop_os_log_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.DEBUG, "debug", format_string, params)
    }

    slop_os_log_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.INFO, "info", format_string, params)
    }

    slop_os_log_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.WARN, "warn", format_string, params)
    }

    slop_os_log_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.ERROR, "error", format_string, params)
    }

    slop_os_log_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.FATAL, "fatal", format_string, params)
    }

    // A record for the events service, or, for a process given no ring, a line as the standard logger writes it.
    slop_os_log :: fn(level: LogLevel, label: string, format_string: string, params: any[]) {
        if cast[int](level) < cast[int](context.log_level) {
            return void
        }
        log :: match events_log() {
            case Some(found) => found
            case None => {
                standard_log(level, label, format_string, params)
                return void
            }
        }
        loop {
            intrinsics.spin_hint()
        }
        while intrinsics.interlocked_exchange_u32(&log.lock, 1) != 0
        array_reset(&log.entries)
        // A new reader, which knows none of what was given
        reader :: intrinsics.atomic_load_u32_acquire(&log.ring.reader)
        if reader != log.reader {
            for i in 0..<log.formats.count {
                log.formats[i] = 0
            }
            log.type_count = 0
            log.reader = reader
        }
        if log.dropped > 0 {
            dropped :: events_begin(&log.entries, SLOP_OS_EVENTS_DROPPED, size_of(SlopOsEventsDropped))
            cast[ptr[mut SlopOsEventsDropped]](events_at(&log.entries, dropped)).count = log.dropped
        }
        // What's given for the first time, before the record
        named :: in_image(cast[rawptr](format_string.data))
        offset :: cast[u64](image_offset(cast[rawptr](format_string.data)))
        new_format :: named && !events_knows_format(log, offset)
        if new_format {
            at :: events_begin(&log.entries, SLOP_OS_EVENTS_FORMAT, size_of(SlopOsEventsFormat))
            events_bytes(&log.entries, cast[rawptr](format_string.data), format_string.count)
            format :: cast[ptr[mut SlopOsEventsFormat]](events_at(&log.entries, at))
            format.offset = offset
            format.count = cast[u32](format_string.count)
            events_end(&log.entries, at)
        }
        arguments : any[SLOP_OS_EVENTS_MAX_ARGUMENTS]
        argument_count : usize = 0
        if !named {
            arguments[0] = format_string
            argument_count = 1
        }
        for param in params {
            if argument_count < arguments.count {
                arguments[argument_count % SLOP_OS_EVENTS_MAX_ARGUMENTS] = param
                argument_count += 1
            }
        }
        // Each argument's type and hash, and whether the ring is given its schema with this record
        types : SlopOsEventsType[SLOP_OS_EVENTS_MAX_ARGUMENTS]
        new_types : bool[SLOP_OS_EVENTS_MAX_ARGUMENTS]
        for i in cast[usize](0)..<argument_count {
            type :: type_info_of(arguments[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].type)
            types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].type = cast[uintptr](type)
            match events_known_type(log, type) {
                case Some(known) => types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash = known
                case None => {
                    array_reset(&log.scratch)
                    schema_write(type, &log.scratch)
                    types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash = hash_blake3(log.scratch)
                    at :: events_begin(&log.entries, SLOP_OS_EVENTS_SCHEMA, size_of(SlopOsEventsSchema))
                    events_bytes(&log.entries, cast[rawptr](log.scratch.data), log.scratch.count)
                    schema :: cast[ptr[mut SlopOsEventsSchema]](events_at(&log.entries, at))
                    schema.hash = types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash
                    schema.count = cast[u32](log.scratch.count)
                    events_end(&log.entries, at)
                    new_types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS] = true
                }
            }
        }
        record_at :: events_begin(&log.entries, SLOP_OS_EVENTS_RECORD, size_of(SlopOsEventsRecord))
        for i in cast[usize](0)..<argument_count {
            argument_at :: log.entries.count
            for byte in 0..<size_of(SlopOsEventsArgument) {
                array_add(&log.entries, cast[u8](0))
            }
            value_at :: log.entries.count
            schema_write_value(arguments[i % SLOP_OS_EVENTS_MAX_ARGUMENTS], &log.entries)
            argument :: cast[ptr[mut SlopOsEventsArgument]](events_at(&log.entries, argument_at))
            argument.hash = types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash
            argument.count = cast[u32](log.entries.count - value_at)
            events_pad(&log.entries)
        }
        record :: cast[ptr[mut SlopOsEventsRecord]](events_at(&log.entries, record_at))
        record.time = cast[u64](system_monotonic(null))
        record.level = cast[u8](cast[int](level))
        record.argument_count = cast[u8](argument_count)
        record.named = if named { cast[u8](1) } else { cast[u8](0) }
        record.format = if named { offset } else { 0 }
        events_end(&log.entries, record_at)
        if events_put(log, log.entries) {
            log.dropped = 0
            // Known from here, now that the ring has them
            if new_format {
                events_remember_format(log, offset)
            }
            for i in cast[usize](0)..<argument_count {
                if new_types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS] {
                    events_remember_type(log, types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS])
                }
            }
        }
        else {
            log.dropped += 1
        }
        intrinsics.atomic_store_u32_release(&log.lock, 0)
    }

    // The process's ring, mapped the first time it's asked for, or null if it wasn't given one.
    events_log #no_context :: fn() -> ptr[mut SlopOsEventsLog]? {
        state :: intrinsics.process_state()
        loop {
            match intrinsics.atomic_load_u32_acquire(&state.events_state) {
                case CLOCK_PAGE_MAPPED => return cast[ptr[mut SlopOsEventsLog]](state.events_log)
                case CLOCK_PAGE_NONE => return null
                case CLOCK_PAGE_MAPPING => continue
                case _ => {}
            }
            _, claimed :: intrinsics.interlocked_compare_exchange_u32(&state.events_state, CLOCK_PAGE_MAPPING, CLOCK_PAGE_UNTRIED)
            if claimed {
                break
            }
        }
        state.events_log = map_events_log()
        if state.events_log == null {
            intrinsics.atomic_store_u32_release(&state.events_state, CLOCK_PAGE_NONE)
            return null
        }
        intrinsics.atomic_store_u32_release(&state.events_state, CLOCK_PAGE_MAPPED)
        return cast[ptr[mut SlopOsEventsLog]](state.events_log)
    }

    // The process's grants "events", a ring and its doorbell, mapped with what the logger keeps, or null.
    map_events_log #no_context :: fn() -> rawptr {
        state :: intrinsics.process_state()
        if state.startup_block == null {
            return null
        }
        startup :: cast[ptr[SlopOsStartup]](state.startup_block)
        ring_handle :: os_entry_grant("events", "Memory", "", false)
        doorbell :: os_entry_grant("events", "Channel", "", false)
        if ring_handle == 0 || doorbell == 0 {
            return null
        }
        address :: reserve_addresses(cast[usize](SLOP_OS_EVENTS_RING_BYTES)) or_return null
        mapped :: slop_os_call(SLOP_OS_CALL_MEMORY_MAP, cast[u64](ring_handle), cast[u64](startup.space), address, 0,
            SLOP_OS_EVENTS_RING_BYTES, SLOP_OS_PROTECTION_READ_WRITE)
        if mapped.tag != 0 {
            return null
        }
        ring :: cast[ptr[mut SlopOsEventsRing]](cast[rawptr](address))
        if ring.magic != SLOP_OS_EVENTS_MAGIC || ring.version != SLOP_OS_EVENTS_VERSION
            || ring.size + cast[u64](size_of(SlopOsEventsRing)) > SLOP_OS_EVENTS_RING_BYTES {
            return null
        }
        log :: cast[ptr[mut SlopOsEventsLog]](map_pages(size_of(SlopOsEventsLog)))
        if cast[rawptr](log) == null {
            return null
        }
        log.ring = ring
        log.doorbell = doorbell
        return cast[rawptr](log)
    }

    events_knows_format #no_context :: fn(log: ptr[SlopOsEventsLog], offset: u64) -> bool {
        for known in log.formats {
            if known == offset + 1 {
                return true
            }
        }
        return false
    }

    events_remember_format #no_context :: fn(log: ptr[mut SlopOsEventsLog], offset: u64) {
        for known, i in log.formats {
            if known == 0 {
                log.formats[i] = offset + 1
                return void
            }
        }
    }

    events_known_type #no_context :: fn(log: ptr[SlopOsEventsLog], type: ptr[compiler.TypeInfo]) -> u8[32]? {
        for i in cast[usize](0)..<log.type_count {
            if log.types[i % SLOP_OS_EVENTS_TYPES].type == cast[uintptr](type) {
                return log.types[i % SLOP_OS_EVENTS_TYPES].hash
            }
        }
        return null
    }

    events_remember_type #no_context :: fn(log: ptr[mut SlopOsEventsLog], known: SlopOsEventsType) {
        if log.type_count < log.types.count {
            log.types[log.type_count] = known
            log.type_count += 1
        }
    }

    // An entry of kind begun at the end of entries, header bytes of it zeroed: where it starts.
    events_begin :: fn(entries: ptr[mut u8[..]], kind: u16, header: usize) -> usize {
        at :: entries.count
        for i in 0..<header {
            array_add(entries, cast[u8](0))
        }
        entry :: cast[ptr[mut SlopOsEventsEntry]](events_at(entries, at))
        entry.kind = kind
        entry.size = cast[u32](header)
        return at
    }

    // The entry begun at `at`, padded, its size set to what's after it.
    events_end :: fn(entries: ptr[mut u8[..]], at: usize) {
        events_pad(entries)
        cast[ptr[mut SlopOsEventsEntry]](events_at(entries, at)).size = cast[u32](entries.count - at)
    }

    events_pad :: fn(entries: ptr[mut u8[..]]) {
        loop {
            if (entries.count & 7) == 0 {
                break
            }
            array_add(entries, cast[u8](0))
        }
    }

    events_bytes :: fn(entries: ptr[mut u8[..]], data: rawptr, count: usize) {
        for byte in view_of(cast[ptr[u8]](data), count) {
            array_add(entries, byte)
        }
    }

    events_at #no_context :: fn(entries: ptr[u8[..]], at: usize) -> rawptr {
        return cast[rawptr](cast[uintptr](entries.data) + cast[uintptr](at))
    }

    /*
     * The entries put in the ring whole, and published, and its reader woken if it's waiting; false, with nothing
     * put, if there isn't room for them all.
     */
    events_put #no_context :: fn(log: ptr[mut SlopOsEventsLog], entries: u8[]) -> bool {
        ring :: log.ring
        size :: ring.size
        data :: cast[uintptr](ring) + cast[uintptr](size_of(SlopOsEventsRing))
        written := ring.written
        free :: size - (written - intrinsics.atomic_load_u64_acquire(&ring.read))
        // Where each would go, and what padding it needs: room for them all first
        needed : u64 = 0
        at : usize = 0
        position := written
        loop {
            if at >= entries.count {
                break
            }
            entry_size :: cast[u64](cast[ptr[SlopOsEventsEntry]](cast[rawptr](cast[uintptr](entries.data) + cast[uintptr](at))).size)
            if entry_size == 0 || entry_size > size / 2 {
                return false
            }
            left :: size - position % size
            pad :: if left < entry_size { left } else { cast[u64](0) }
            needed += pad + entry_size
            position += pad + entry_size
            at += cast[usize](entry_size)
        }
        if needed > free {
            return false
        }
        at = 0
        loop {
            if at >= entries.count {
                break
            }
            source :: cast[uintptr](entries.data) + cast[uintptr](at)
            entry_size :: cast[u64](cast[ptr[SlopOsEventsEntry]](cast[rawptr](source)).size)
            left :: size - written % size
            if left < entry_size {
                pad :: cast[ptr[mut SlopOsEventsEntry]](cast[rawptr](data + cast[uintptr](written % size)))
                pad.size = cast[u32](left)
                pad.kind = SLOP_OS_EVENTS_PAD
                written += left
            }
            intrinsics.mem_copy_non_overlapping(cast[mut rawptr](data + cast[uintptr](written % size)), cast[rawptr](source),
                cast[usize](entry_size))
            written += entry_size
            at += cast[usize](entry_size)
        }
        intrinsics.atomic_store_u64_release(&ring.written, written)
        if intrinsics.interlocked_exchange_u32(&ring.waiting, 0) != 0 {
            bell : u8 = 1
            slop_os_call(SLOP_OS_CALL_CHANNEL_WRITE, cast[u64](log.doorbell), cast[u64](cast[uintptr](&bell)), 1, SLOP_OS_NO_BATCH)
        }
        return true
    }
}
