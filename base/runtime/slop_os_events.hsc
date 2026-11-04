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

/** A ring's first four bytes, "EVTR" read as a little-endian u32; a ring without them isn't written to. */
SLOP_OS_EVENTS_MAGIC : u32 : 0x52545645
/** The ring layout's version this runtime writes; a ring of another version isn't written to. */
SLOP_OS_EVENTS_VERSION : u32 : 1
/** A ring's bytes, its header's included, as the events service makes it. */
SLOP_OS_EVENTS_RING_BYTES : u64 : 16384

/** The header at a ring's start, which its entries follow; 64 bytes. */
SlopOsEventsRing :: struct {
    /** SLOP_OS_EVENTS_MAGIC. */
    magic : u32,
    /** SLOP_OS_EVENTS_VERSION. */
    version : u32,
    /** Bytes of entries after the header, at most SLOP_OS_EVENTS_RING_BYTES less the header's. */
    size : u64,
    /** Bytes ever written, which only the writer moves on, and only grows; its place in the ring is modulo size. */
    written : u64,
    /** Bytes ever read, which only the reader moves on, and never past written. */
    read : u64,
    /** 1 while the reader waits for the doorbell; the writer clears it, and rings. */
    waiting : u32,
    /**
     * Which reader's the ring is: moved on by each that takes the ring over, which tells the writer to give every
     * format string and schema again.
     */
    reader : u32,
    /** Unused, zero, keeping the header 64 bytes. */
    unused : u64[3],
}

#assert size_of(SlopOsEventsRing) == 64

/** The header every entry in the ring starts with. */
SlopOsEventsEntry :: struct {
    /** Its bytes, this header's included, a multiple of 8. */
    size : u32,
    /** What it is: one of the SLOP_OS_EVENTS_ kinds, PAD to DROPPED. */
    kind : u16,
    /** Unused, zero. */
    reserved : u16,
}

// An entry's kinds.
/** An entry's kind: nothing, filling the ring's end where the next entry wouldn't fit; the reader skips it. */
SLOP_OS_EVENTS_PAD : u16 : 1
/** An entry's kind: a format string's text (SlopOsEventsFormat). */
SLOP_OS_EVENTS_FORMAT : u16 : 2
/** An entry's kind: a type's schema (SlopOsEventsSchema). */
SLOP_OS_EVENTS_SCHEMA : u16 : 3
/** An entry's kind: a log record (SlopOsEventsRecord). */
SLOP_OS_EVENTS_RECORD : u16 : 4
/** An entry's kind: a count of records dropped (SlopOsEventsDropped). */
SLOP_OS_EVENTS_DROPPED : u16 : 5

/** A format string's text, then count bytes of it. */
SlopOsEventsFormat :: struct {
    /** Its entry's header, kind SLOP_OS_EVENTS_FORMAT. */
    entry : SlopOsEventsEntry,
    /** The format string's offset in the program's image, which later records name it by. */
    offset : u64,
    /** How many bytes of text follow, not counting the padding to 8. */
    count : u32,
    /** Unused, zero. */
    reserved : u32,
}

/** A type's schema (schema_write), then count bytes of it. */
SlopOsEventsSchema :: struct {
    /** Its entry's header, kind SLOP_OS_EVENTS_SCHEMA. */
    entry : SlopOsEventsEntry,
    /** The type's schema hash, BLAKE3-256 of the bytes that follow, which later arguments name it by. */
    hash : u8[32],
    /** How many bytes of schema follow, not counting the padding to 8. */
    count : u32,
    /** Unused, zero. */
    reserved : u32,
}

/** A record, then its arguments, each a SlopOsEventsArgument and count bytes of its value, padded to 8. */
SlopOsEventsRecord :: struct {
    /** Its entry's header, kind SLOP_OS_EVENTS_RECORD. */
    entry : SlopOsEventsEntry,
    /** The monotonic clock's nanoseconds when it was written. */
    time : u64,
    /** Its LogLevel, as a number. */
    level : u8,
    /** How many arguments follow, the format string's among them when it isn't named, at most 32. */
    argument_count : u8,
    /** 1 if the format string is named by format; 0 if it's the first argument. */
    named : u8,
    /** Unused, zero. */
    reserved : u8,
    /** Unused, zero. */
    reserved_more : u32,
    /** The format string's offset in the program's image when named is 1, given before in a Format entry; else 0. */
    format : u64,
}

/** An argument's header in a record, which count bytes of its value follow, padded to 8. */
SlopOsEventsArgument :: struct {
    /** The schema hash of the argument's type, given before in a Schema entry. */
    hash : u8[32],
    /** How many bytes of value follow, as schema_write_value writes it, not counting the padding. */
    count : u32,
    /** Unused, zero. */
    reserved : u32,
}

/** How many records were dropped while the ring was full. */
SlopOsEventsDropped :: struct {
    /** Its entry's header, kind SLOP_OS_EVENTS_DROPPED. */
    entry : SlopOsEventsEntry,
    /** How many records were dropped since the last one written, at least 1. */
    count : u64,
}

/** The most arguments a record holds, its format string's among them; any after them aren't written. */
SLOP_OS_EVENTS_MAX_ARGUMENTS :: 32

/**
 * Round a number up to a multiple of 8, as every entry and argument in the ring is padded.
 *
 * @param count The number, in bytes; within 7 of u64's largest, it wraps.
 * @return The smallest multiple of 8 that's at least count; 0 for 0.
 */
slop_os_events_padded #no_context :: fn(count: u64) -> u64 {
    return (count + 7) & ~cast[u64](7)
}

#if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    // How many format strings' offsets and types' hashes a process remembers giving; past those, they're given again.
    /** How many format strings' offsets a process remembers giving; past those, each is given with every record. */
    SLOP_OS_EVENTS_FORMATS :: 128
    /** How many types' hashes a process remembers giving; past those, each's schema is given with every record. */
    SLOP_OS_EVENTS_TYPES :: 64

    /** A type the ring has been given the schema of, and its hash. */
    SlopOsEventsType :: struct {
        /** The type's compiler.TypeInfo, by its address, which is the same for the process's life. */
        type : uintptr,
        /** Its schema hash, BLAKE3-256 of its schema. */
        hash : u8[32],
    }

    /** What the process's logger keeps, in pages of its own (ProcessState's events_log). */
    SlopOsEventsLog :: struct {
        /** The ring, shared with the events service, mapped for the rest of the process's life. */
        ring : ptr[mut SlopOsEventsRing],
        /** The handle of the doorbell, the channel a one-byte message wakes a waiting reader by. */
        doorbell : u32,
        /** 1 while a thread writes a record, 0 otherwise; spun on, so one record goes in at a time. */
        lock : u32,
        /** The ring's reader when formats and types were given. */
        reader : u32,
        /** Records dropped and not reported yet. */
        dropped : u64,
        /** Format strings' offsets the ring was given, each plus 1, so 0 is a free place. */
        formats : u64[SLOP_OS_EVENTS_FORMATS],
        /** Types the ring was given the schemas of, the first type_count of them. */
        types : SlopOsEventsType[SLOP_OS_EVENTS_TYPES],
        /** How many of types are used, at most SLOP_OS_EVENTS_TYPES. */
        type_count : usize,
        /** Entries put together before they go in the ring, kept from one record to the next. */
        entries : u8[..],
        /** A type's schema, written to find its hash and copied into entries. */
        scratch : u8[..],
    }

    /** SlopOS's logger, which context.logger is in HOSTED_CONTEXT: each level's records go to slop_os_log. */
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

    /**
     * Log a record at the TRACE level, SLOP_OS_LOGGER's trace (slop_os_log).
     *
     * @param format_string The record's format string, as output_format reads it. A literal is named by its offset in
     *     the program's image; any other is written as the record's first argument.
     * @param params The values the format string's placeholders take, each written by its type's schema; only the
     *     first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's among them, are kept.
     * @param location Where it was logged from; unused, as records don't hold it.
     */
    slop_os_log_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.TRACE, "trace", format_string, params)
    }

    /**
     * Log a record at the DEBUG level, SLOP_OS_LOGGER's debug (slop_os_log).
     *
     * @param format_string The record's format string, as output_format reads it. A literal is named by its offset in
     *     the program's image; any other is written as the record's first argument.
     * @param params The values the format string's placeholders take, each written by its type's schema; only the
     *     first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's among them, are kept.
     * @param location Where it was logged from; unused, as records don't hold it.
     */
    slop_os_log_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.DEBUG, "debug", format_string, params)
    }

    /**
     * Log a record at the INFO level, SLOP_OS_LOGGER's info (slop_os_log).
     *
     * @param format_string The record's format string, as output_format reads it. A literal is named by its offset in
     *     the program's image; any other is written as the record's first argument.
     * @param params The values the format string's placeholders take, each written by its type's schema; only the
     *     first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's among them, are kept.
     * @param location Where it was logged from; unused, as records don't hold it.
     */
    slop_os_log_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.INFO, "info", format_string, params)
    }

    /**
     * Log a record at the WARN level, SLOP_OS_LOGGER's warn (slop_os_log).
     *
     * @param format_string The record's format string, as output_format reads it. A literal is named by its offset in
     *     the program's image; any other is written as the record's first argument.
     * @param params The values the format string's placeholders take, each written by its type's schema; only the
     *     first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's among them, are kept.
     * @param location Where it was logged from; unused, as records don't hold it.
     */
    slop_os_log_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.WARN, "warn", format_string, params)
    }

    /**
     * Log a record at the ERROR level, SLOP_OS_LOGGER's error (slop_os_log).
     *
     * @param format_string The record's format string, as output_format reads it. A literal is named by its offset in
     *     the program's image; any other is written as the record's first argument.
     * @param params The values the format string's placeholders take, each written by its type's schema; only the
     *     first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's among them, are kept.
     * @param location Where it was logged from; unused, as records don't hold it.
     */
    slop_os_log_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.ERROR, "error", format_string, params)
    }

    /**
     * Log a record at the FATAL level, SLOP_OS_LOGGER's fatal (slop_os_log).
     *
     * @param format_string The record's format string, as output_format reads it. A literal is named by its offset in
     *     the program's image; any other is written as the record's first argument.
     * @param params The values the format string's placeholders take, each written by its type's schema; only the
     *     first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's among them, are kept.
     * @param location Where it was logged from; unused, as records don't hold it.
     */
    slop_os_log_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
        slop_os_log(.FATAL, "fatal", format_string, params)
    }

    /**
     * Log a record for the events service, or, for a process given no ring, a line as the standard logger writes it
     * (standard_log), which goes nowhere while SlopOS gives no standard error (os_write).
     *
     * A record the ring hasn't room for, or that there isn't the memory to put together, is dropped and counted, and
     * the count reported before the next record that's written: logging never ends the process. Safe from several
     * threads at once: a lock, spun on, puts one record in at a time.
     *
     * @param level The record's level; one below context.log_level isn't logged.
     * @param label The level's name, like "info", for the standard logger's line; the ring's record doesn't hold it.
     * @param format_string The record's format string. A literal, in the program's image, is named by its offset, and
     *     its text given to the ring the first time; any other is written as the record's first argument.
     * @param params The format string's arguments; only the first SLOP_OS_EVENTS_MAX_ARGUMENTS, the format string's
     *     among them, are written.
     */
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
        // A new reader, which knows none of what was given
        reader :: intrinsics.atomic_load_u32_acquire(&log.ring.reader)
        if reader != log.reader {
            for i in 0..<log.formats.count {
                log.formats[i] = 0
            }
            log.type_count = 0
            log.reader = reader
        }
        if events_write(log, level, format_string, params) {
            log.dropped = 0
        }
        else {
            log.dropped += 1
        }
        intrinsics.atomic_store_u32_release(&log.lock, 0)
    }

    /**
     * Put a record in the ring, after a Dropped entry if any were dropped and what's given for the first time: its
     * format string's text and its arguments' types' schemas.
     *
     * The entries are put together in the log's entries first, then put in the ring all at once, or none of them.
     * What's given is remembered only once it's in the ring. The caller holds the log's lock.
     *
     * @param log The process's log, its ring mapped.
     * @param level The record's level.
     * @param format_string The record's format string: named by its offset if it's in the program's image, otherwise
     *     the record's first argument.
     * @param params The format string's arguments; any past SLOP_OS_EVENTS_MAX_ARGUMENTS, with the format string's,
     *     are left out.
     * @return True if it's all in the ring and published; false, with nothing put, if the ring hasn't room for them,
     *     an entry is more than half the ring, or there isn't the memory to put them together.
     */
    events_write :: fn(log: ptr[mut SlopOsEventsLog], level: LogLevel, format_string: string, params: any[]) -> bool {
        array_reset(&log.entries)
        if log.dropped > 0 {
            dropped :: events_begin(&log.entries, SLOP_OS_EVENTS_DROPPED, size_of(SlopOsEventsDropped)) or_return false
            cast[ptr[mut SlopOsEventsDropped]](events_at(&log.entries, dropped)).count = log.dropped
        }
        // What's given for the first time, before the record
        named :: in_image(cast[rawptr](format_string.data))
        offset :: cast[u64](image_offset(cast[rawptr](format_string.data)))
        new_format :: named && !events_knows_format(log, offset)
        if new_format {
            at :: events_begin(&log.entries, SLOP_OS_EVENTS_FORMAT, size_of(SlopOsEventsFormat)) or_return false
            if !events_bytes(&log.entries, cast[rawptr](format_string.data), format_string.count) {
                return false
            }
            format :: cast[ptr[mut SlopOsEventsFormat]](events_at(&log.entries, at))
            format.offset = offset
            format.count = cast[u32](format_string.count)
            if !events_end(&log.entries, at) {
                return false
            }
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
                    if schema_try_write(type, &log.scratch) != null {
                        return false
                    }
                    types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash = hash_blake3(log.scratch)
                    at :: events_begin(&log.entries, SLOP_OS_EVENTS_SCHEMA, size_of(SlopOsEventsSchema)) or_return false
                    if !events_bytes(&log.entries, cast[rawptr](log.scratch.data), log.scratch.count) {
                        return false
                    }
                    schema :: cast[ptr[mut SlopOsEventsSchema]](events_at(&log.entries, at))
                    schema.hash = types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash
                    schema.count = cast[u32](log.scratch.count)
                    if !events_end(&log.entries, at) {
                        return false
                    }
                    new_types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS] = true
                }
            }
        }
        record_at :: events_begin(&log.entries, SLOP_OS_EVENTS_RECORD, size_of(SlopOsEventsRecord)) or_return false
        for i in cast[usize](0)..<argument_count {
            argument_at :: events_zeroes(&log.entries, size_of(SlopOsEventsArgument)) or_return false
            value_at :: log.entries.count
            if schema_try_write_value(arguments[i % SLOP_OS_EVENTS_MAX_ARGUMENTS], &log.entries) != null {
                return false
            }
            argument :: cast[ptr[mut SlopOsEventsArgument]](events_at(&log.entries, argument_at))
            argument.hash = types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS].hash
            argument.count = cast[u32](log.entries.count - value_at)
            if !events_pad(&log.entries) {
                return false
            }
        }
        record :: cast[ptr[mut SlopOsEventsRecord]](events_at(&log.entries, record_at))
        record.time = cast[u64](system_monotonic(null))
        record.level = cast[u8](cast[int](level))
        record.argument_count = cast[u8](argument_count)
        record.named = if named { cast[u8](1) } else { cast[u8](0) }
        record.format = if named { offset } else { 0 }
        if !events_end(&log.entries, record_at) || !events_put(log, log.entries) {
            return false
        }
        // Known from here, now that the ring has them
        if new_format {
            events_remember_format(log, offset)
        }
        for i in cast[usize](0)..<argument_count {
            if new_types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS] {
                events_remember_type(log, types[i % SLOP_OS_EVENTS_MAX_ARGUMENTS])
            }
        }
        return true
    }

    /**
     * Find what the process's logger keeps, its ring mapped the first time it's asked for.
     *
     * Safe from several threads at once: one maps it, and the others wait for it to.
     *
     * @return The log, kept for the rest of the process's life; or null if the process wasn't given a ring or it
     *     couldn't be mapped, which every later call gives too.
     */
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

    /**
     * Map the process's grants "events", a ring and its doorbell, with pages of its own for what the logger keeps;
     * events_log calls it once.
     *
     * @return The SlopOsEventsLog, zeroed but for its ring and doorbell, mapped for the rest of the process's life; or
     *     null if there's no startup block, either grant is missing, the free range is used up, the kernel wouldn't
     *     map the ring or the log's pages, or the ring's magic, version or size is wrong. The ring stays mapped when
     *     what comes after it fails.
     */
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

    /**
     * Check whether the ring has been given a format string's text.
     *
     * @param log The process's log.
     * @param offset The format string's offset in the program's image.
     * @return True if it was remembered as given to this reader; false if it wasn't, or was past
     *     SLOP_OS_EVENTS_FORMATS and so never remembered.
     */
    events_knows_format #no_context :: fn(log: ptr[SlopOsEventsLog], offset: u64) -> bool {
        for known in log.formats {
            if known == offset + 1 {
                return true
            }
        }
        return false
    }

    /**
     * Remember that the ring has been given a format string's text, in the first free place.
     *
     * @param log The process's log.
     * @param offset The format string's offset in the program's image. With every place used, it isn't remembered,
     *     and is given again with each record.
     */
    events_remember_format #no_context :: fn(log: ptr[mut SlopOsEventsLog], offset: u64) {
        for known, i in log.formats {
            if known == 0 {
                log.formats[i] = offset + 1
                return void
            }
        }
    }

    /**
     * Find a type the ring has been given the schema of.
     *
     * @param log The process's log.
     * @param type The type, compared by address.
     * @return Its schema hash if it was remembered as given to this reader; null if it wasn't, or was past
     *     SLOP_OS_EVENTS_TYPES and so never remembered.
     */
    events_known_type #no_context :: fn(log: ptr[SlopOsEventsLog], type: ptr[compiler.TypeInfo]) -> u8[32]? {
        for i in cast[usize](0)..<log.type_count {
            if log.types[i % SLOP_OS_EVENTS_TYPES].type == cast[uintptr](type) {
                return log.types[i % SLOP_OS_EVENTS_TYPES].hash
            }
        }
        return null
    }

    /**
     * Remember that the ring has been given a type's schema.
     *
     * @param log The process's log.
     * @param known The type and its hash. With SLOP_OS_EVENTS_TYPES remembered already, it isn't, and its schema is
     *     given again with each record.
     */
    events_remember_type #no_context :: fn(log: ptr[mut SlopOsEventsLog], known: SlopOsEventsType) {
        if log.type_count < log.types.count {
            log.types[log.type_count] = known
            log.type_count += 1
        }
    }

    /*
     * What puts entries together. Each makes room first, so its array_adds never grow entries, and gives false, or
     * none, with nothing added, when there isn't the memory for it.
     */

    /**
     * Begin an entry at the end of entries, its header's bytes zeroed but for its kind and size.
     *
     * @param entries The entries being put together, which grow by header bytes.
     * @param kind The entry's kind, one of the SLOP_OS_EVENTS_ kinds.
     * @param header The size of the entry's struct in bytes, like size_of(SlopOsEventsRecord), at least a
     *     SlopOsEventsEntry's; its size until events_end sets it.
     * @return Where the entry starts in entries, for events_at and events_end; or null, with nothing added, without
     *     the memory.
     */
    events_begin :: fn(entries: ptr[mut u8[..]], kind: u16, header: usize) -> usize? {
        at :: events_zeroes(entries, header) or_return null
        entry :: cast[ptr[mut SlopOsEventsEntry]](events_at(entries, at))
        entry.kind = kind
        entry.size = cast[u32](header)
        return at
    }

    /**
     * End the entry begun at at: entries padded to 8 bytes, and the entry's size set to everything from at.
     *
     * @param entries The entries being put together, the entry the last of them.
     * @param at Where the entry starts, as events_begin gave it.
     * @return True once it's ended; false, with its size not set, without the memory to pad it.
     */
    events_end :: fn(entries: ptr[mut u8[..]], at: usize) -> bool {
        if !events_pad(entries) {
            return false
        }
        cast[ptr[mut SlopOsEventsEntry]](events_at(entries, at)).size = cast[u32](entries.count - at)
        return true
    }

    /**
     * Pad entries with zeros to a multiple of 8 bytes.
     *
     * @param entries The entries being put together; already a multiple of 8, nothing's added.
     * @return True once it's padded; false, with nothing added, without the memory.
     */
    events_pad :: fn(entries: ptr[mut u8[..]]) -> bool {
        return events_zeroes(entries, cast[usize](slop_os_events_padded(cast[u64](entries.count))) - entries.count) != null
    }

    /**
     * Add zeroed bytes at the end of entries.
     *
     * @param entries The entries being put together.
     * @param count How many bytes to add; 0 adds none.
     * @return Where they start in entries, its count before; or null, with nothing added, without the memory.
     */
    events_zeroes :: fn(entries: ptr[mut u8[..]], count: usize) -> usize? {
        at :: entries.count
        if !events_room(entries, count) {
            return null
        }
        for i in 0..<count {
            array_add(entries, cast[u8](0))
        }
        return at
    }

    /**
     * Copy bytes to the end of entries.
     *
     * @param entries The entries being put together.
     * @param data Where the bytes are, which are only read; may be null when count is 0.
     * @param count How many bytes to copy.
     * @return True once they're added; false, with nothing added, without the memory.
     */
    events_bytes :: fn(entries: ptr[mut u8[..]], data: rawptr, count: usize) -> bool {
        if !events_room(entries, count) {
            return false
        }
        for byte in view_of(cast[ptr[u8]](data), count) {
            array_add(entries, byte)
        }
        return true
    }

    /**
     * Make room for more bytes in entries, growing its capacity by doubling, as array_add does, so the array_adds
     * that follow never grow it and can't fail.
     *
     * @param entries The entries being put together; its count isn't changed.
     * @param count How many more bytes are wanted.
     * @return True if there's room, already or now; false, with entries as it was, without the memory.
     */
    events_room :: fn(entries: ptr[mut u8[..]], count: usize) -> bool {
        needed :: entries.count + count
        capacity :: resizable(entries).capacity
        if needed <= capacity {
            return true
        }
        doubled :: capacity * 2
        return array_try_reserve(entries, if doubled > needed { doubled } else { needed }) == null
    }

    /**
     * Find a place in entries, to write an entry's header through.
     *
     * @param entries The entries being put together.
     * @param at A place in them, in bytes from the start, as events_begin gave it; not checked against the count.
     * @return Its address, good until entries next grows.
     */
    events_at #no_context :: fn(entries: ptr[u8[..]], at: usize) -> rawptr {
        return cast[rawptr](cast[uintptr](entries.data) + cast[uintptr](at))
    }

    /**
     * Put entries in the ring whole, publish them, and wake the reader if it's waiting.
     *
     * An entry that wouldn't fit before the ring's end goes at its start, after a Pad entry filling the rest. The
     * caller holds the log's lock, as only one writer may move written on.
     *
     * @param log The process's log, its ring mapped.
     * @param entries Whole entries, each starting with a SlopOsEventsEntry whose size is a multiple of 8 and covers it.
     * @return True once they're all in the ring and written is moved past them; false, with nothing put, if there
     *     isn't room for them all, or an entry's size is 0 or more than half the ring.
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
