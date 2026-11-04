package stream

/*
 * A stream's two ends (std/os's Sink[T] and Stream[T]) are one channel, tagged with this protocol. The writer makes a
 * ring of shared memory and sends Open with it, the ring's size and T's schema hash; the reader maps it, answering
 * Consumed(0), or WrongType for another T. The writer puts records in the ring, each its byte count, its kind and its
 * value, written as base's schema_write_value writes one (for a Stream[u8], the bytes themselves), padded to 8 bytes; a
 * record that wouldn't fit before the ring's end is preceded by a wrap, and starts again at the ring's start. Wrote
 * says how many bytes it has written in all, once a quarter of the ring is waiting or it flushes; the reader answers
 * each Wrote with Consumed, how many it has read in all, once it has read that far, so the writer waits for room only
 * while the ring is full. Ended ends the stream, with the writer's status, and is answered once the reader has read
 * everything.
 *
 *     ends :: stream.pair[Item](budget)?
 *     writer := stream.writer_on(ends.sink)?      // the writing end
 *     stream.write(&writer, Item.{...})
 *     stream.finish(&writer, 0)
 *
 *     reader := stream.reader_on(ends.stream)?    // the reading end
 *     loop { item :: stream.next(&reader) or_break ... }
 *
 * A record read is copied to the heap with context's allocator, as base's schema_read_value copies a value, so a
 * reader of many pushes an arena and resets it.
 */

#if base.OS == .SlopOS {
    import compiler from "base"
    import runtime from "base"
    import os from "std"
    import slop_os from "std/os"

    /**
     * The stream protocol, for the channel between a Sink[T] and its Stream[T]: the writer sends the requests, and the
     * reader answers them.
     */
    Stream :: struct {}

    /**
     * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that
     * the server, here the reader, pays for its work from its own budget.
     */
    PROTOCOL :: slop_os.Protocol.{name = "Stream", major_version = 1, lending = .Server}

    /** How big a stream's ring is, in bytes, unless it's asked to be bigger: 64 KiB. */
    RING_BYTES : u64 : 64 * 1024
    /** The bytes of a record's header in the ring: its value's byte count, then its kind, each a u32. */
    RECORD_HEADER : u64 : 8
    /** A record's kind: a value, its byte count of bytes after the header. */
    KIND_RECORD : u32 : 0
    /** A record's kind: a wrap, so the next record is at the ring's start; the rest of the ring before it is unused. */
    KIND_WRAP : u32 : 1
    /**
     * The most of the writer's Wrotes, and its Ended, the reader keeps to answer: the writer says one each quarter of
     * the ring, and waits for room, so far fewer are ever waiting. One past this many isn't answered.
     */
    MAX_MARKS :: 64

    /** What Open offers the reader: the ring, its size, and the type of what's in it. */
    Opening :: struct {
        /** The ring, a memory object, given to read only, which moves to the reader. */
        ring : slop_os.Memory,
        /** The ring's size in bytes, a multiple of 4096. */
        ring_bytes : u64,
        /** The records' type's schema hash (base's runtime.schema_hash); the reader checks it's the one it reads. */
        schema : u8[32],
    }

    /** What a stream's writer sends its reader. */
    Request :: union {
        /** The stream offered: the first request, answered with Consumed(0), or WrongType for another type. */
        Open(Opening),
        /**
         * How many bytes the writer has written to the ring in all, headers, padding and wraps included; only grows.
         * Answered with Consumed once the reader has read that far.
         */
        Wrote(u64),
        /**
         * The writer's done, with its status, 0 for success, any other value its own. Answered with Consumed once the
         * reader has read everything.
         */
        Ended(u32),
    }

    /** What a stream's reader answers. */
    Response :: union {
        /** The answer to Open, Wrote and Ended: how many bytes the reader has read in all, so the writer has room. */
        Consumed(u64),
        /** Open's answer when the reader reads another type; the stream goes no further. */
        WrongType,
        /** The answer to a request the reader doesn't know, as from a newer writer; every protocol has it. */
        Unsupported,
    }

    /**
     * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
     *
     * @param request The request, which isn't changed.
     * @return False for Open, which offers a ring once; true for Wrote and Ended, which say a total, not an amount.
     */
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case Open(_) => false
            case Wrote(_) => true
            case Ended(_) => true
        }
    }

    #insert os.protocol_code(Request, Response)

    /** Why a stream's end couldn't do what it was asked. */
    StreamError :: enum {
        /** The other end's gone, or broke the protocol; the stream can go no further. */
        Gone,
        /** The reader reads another type than the writer writes. */
        WrongType,
        /** A record bigger than half the ring, with its header and padding. */
        TooBig,
        /** Memory, or addresses to map it at, couldn't be had. */
        NoMemory,
    }

    /**
     * A stream's writing end, open: its ring, mapped, how much it has written and the reader has read, and its scratch.
     *
     * Its fields are the stream functions' to keep; a caller reads them at most. finish or close_writer lets go of
     * everything it holds.
     */
    Writer :: struct[T] {
        /** The channel's end, the writer's from writer_on on, closed by finish and close_writer. */
        end : slop_os.Channel,
        /** A port bound to end, the writer's own, waited on for the reader's answers and for room in end's ring. */
        port : slop_os.Port,
        /** The ring's memory object, the writer's own; the reader has a read-only handle to it. */
        ring : slop_os.Memory,
        /** Where the ring is mapped, readable and writable, in the process's address space. */
        address : u64,
        /** The ring's size in bytes, a multiple of 4096. */
        ring_bytes : u64,
        /** How many bytes it has put in the ring in all, headers, padding and wraps included; only grows. */
        produced : u64,
        /** What produced was when it last said Wrote, so what's past it the reader hasn't been told of. */
        announced : u64,
        /** How many bytes the reader has said it has read in all, as its last Consumed said. */
        consumed : u64,
        /** How many of its requests the reader hasn't answered yet: Wrotes, an Ended, and an Open not waited for. */
        waiting : u64,
        /** Where write puts a value's bytes before they go in the ring, from context's allocator; freed on closing. */
        scratch : u8[..],
    }

    /**
     * A stream's reading end, open.
     *
     * Its fields are the stream functions' to keep; a caller reads them at most. close_reader lets go of everything it
     * holds.
     */
    Reader :: struct[T] {
        /** The channel's end, the reader's from reader_on on, closed by close_reader. */
        end : slop_os.Channel,
        /** A port bound to end, the reader's own, waited on for the writer's requests. */
        port : slop_os.Port,
        /** The writer's ring, a read-only handle, the reader's own. */
        ring : slop_os.Memory,
        /** Where the ring is mapped, read-only, in the process's address space. */
        address : u64,
        /** The ring's size in bytes, as the writer's Open said. */
        ring_bytes : u64,
        /** How many bytes of the ring it has read in all, headers, padding and wraps included; only grows. */
        read : u64,
        /** How many bytes the writer has said it has written in all, as its last Wrote said. */
        produced : u64,
        /** The Wrotes, and the Ended, not answered yet, by how far each said, oldest first. */
        marks : u64[MAX_MARKS],
        /** How many of marks are in use, from the first: 0 to MAX_MARKS. */
        mark_count : usize,
        /** Whether the writer has ended, or its end is gone; nothing more will be written. */
        ended : bool,
        /**
         * The writer's status, once it has ended: what its Ended said, 0 for success; 0xffffffff if its end went
         * without one.
         */
        status : u32,
    }

    /** A new stream's two ends. */
    Pair :: struct[T] {
        /** The writing end, for writer_on, or to give the program that writes. */
        sink : os.Sink[T],
        /** The reading end, for reader_on, or to give the program that reads. */
        stream : os.Stream[T],
    }

    /**
     * Make a new stream: a channel for the stream protocol, its two ends typed for records of T.
     *
     * Nothing is sent yet: the writer's writer_on offers the ring, and the reader's reader_on takes it.
     *
     * @tparam T The records' type, which both ends have to agree on.
     * @param budget The memory budget that pays for the channel.
     * @return Both ends, the caller's to give away or open; each is closed by its writer or reader once opened.
     * @error OutOfMemory The kernel hadn't the memory for the channel.
     * @error TableFull The process's handle table had no room for the ends.
     * @error InvalidHandle The budget isn't a handle of the process's.
     * @error MissingRight The budget's handle can't be charged.
     */
    pair :: fn[T](budget: slop_os.MemoryBudget) -> Result[Pair[T], slop_os.ChannelError] {
        ends :: slop_os.channel_create(budget, 0, os.protocol_tag[Stream]())?
        return .Ok(Pair[T].{sink = os.Sink[T].{end = ends.a}, stream = os.Stream[T].{end = ends.b}})
    }

    /**
     * Open a stream's writing end: make a ring, map it, offer it to the reader, and wait for the reader's answer.
     *
     * The ring and its port are paid for by the process's own budget. This waits until the reader opens its end, so a
     * writer with something else to do first uses untyped_writer_on, which needn't wait.
     *
     * @tparam T The records' type, whose schema hash is offered to the reader.
     * @param sink The writing end, which the writer keeps from now on, and closes when it's finished. On an error the
     *     end isn't closed, and what was made for the writer by then isn't let go of.
     * @param ring_bytes The ring's size in bytes, rounded up to a multiple of 4096; 0 for RING_BYTES. A record can be
     *     at most half of it, with its header.
     * @return The open writer, to write to and then finish.
     * @error NoMemory The port or the ring couldn't be made, or the ring couldn't be mapped.
     * @error Gone The Open couldn't be sent, or the reader's end went, or answered something else, before it answered.
     * @error WrongType The reader reads another type.
     */
    writer_on :: fn[T](sink: os.Sink[T], ring_bytes: u64 = 0) -> Result[Writer[T], StreamError] {
        return opened_writer[T](sink.end, runtime.schema_hash(type_info_of(T)), ring_bytes, true)
    }

    /**
     * A stream's records known only by their schema, for code that meets their type as it runs, like a shell reading a
     * program's output by its manifest: a writer of them puts each one's bytes, as std/schema's write_value writes one
     * (put), and a reader of them takes each one's (next_bytes).
     */
    Untyped :: struct {}

    /**
     * Open a stream's writing end for records whose type's schema hash is schema: make a ring, map it, and offer it to
     * the reader.
     *
     * Unless it waits, the reader's answer to Open is taken with its others, as the writer waits for room or finishes:
     * for a writer that does something else before the reader opens its end, like a shell starting a program that
     * opens its output first. A reader of another type is then learned of as Gone, from the write or finish that takes
     * its answer.
     *
     * @param end The channel's writing end, which the writer keeps from now on, and closes when it's finished. On an
     *     error the end isn't closed, and what was made for the writer by then isn't let go of.
     * @param schema The records' type's schema hash, which the reader checks against its own.
     * @param ring_bytes The ring's size in bytes, rounded up to a multiple of 4096; 0 for RING_BYTES.
     * @param waits Whether to wait for the reader's answer to Open before returning.
     * @return The open writer, to put records to and then finish.
     * @error NoMemory The port or the ring couldn't be made, or the ring couldn't be mapped.
     * @error Gone The Open couldn't be sent; or, when it waits, the reader's end went, or answered something else.
     * @error WrongType The reader reads another type; only when it waits.
     */
    untyped_writer_on :: fn(end: slop_os.Channel, schema: u8[32], ring_bytes: u64 = 0, waits: bool = true) -> Result[Writer[Untyped], StreamError] {
        return opened_writer[Untyped](end, schema, ring_bytes, waits)
    }

    /**
     * Open a stream's writing end, as writer_on and untyped_writer_on do, for records whose type's schema hash is
     * schema.
     *
     * @tparam T The Writer's type parameter: the records' type, or Untyped.
     * @param end The channel's writing end, which the writer keeps from now on. On an error the end isn't closed, and
     *     what was made for the writer by then isn't let go of.
     * @param schema The records' type's schema hash.
     * @param ring_bytes The ring's size in bytes, rounded up to a multiple of 4096; 0 for RING_BYTES.
     * @param waits Whether to wait for the reader's answer to Open; if not, it's counted as waiting, and taken later.
     * @return The open writer.
     * @error NoMemory The port or the ring couldn't be made, or the ring couldn't be mapped.
     * @error Gone The Open couldn't be sent; or, when it waits, the reader's end went, or answered something else.
     * @error WrongType The reader reads another type; only when it waits.
     */
    opened_writer :: fn[T](end: slop_os.Channel, schema: u8[32], ring_bytes: u64, waits: bool) -> Result[Writer[T], StreamError] {
        block :: slop_os.startup_block()
        size :: if ring_bytes == 0 { RING_BYTES } else { (ring_bytes + 4095) & ~cast[u64](4095) }
        writer := Writer[T].{end = end, ring_bytes = size}
        writer.port = os.port_for(block.budget, end) or_return .Error(.NoMemory)
        writer.ring = slop_os.memory_create(block.budget, size) or_return .Error(.NoMemory)
        writer.address = runtime.reserve_addresses(cast[usize](size)) or_return .Error(.NoMemory)
        read_write :: cast[slop_os.Protection](cast[u32](slop_os.PROTECTION_READ) | cast[u32](slop_os.PROTECTION_WRITE))
        slop_os.memory_map(writer.ring, block.space, writer.address, 0, size, read_write) or_return .Error(.NoMemory)
        rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_TRANSFER))
        given :: cast[slop_os.Memory](slop_os.handle_duplicate(cast[slop_os.Handle](writer.ring), rights) or_return .Error(.NoMemory))
        out := os.Outgoing.{}
        os.begin[Request](&out)^ = .Open(Opening.{ring = given, ring_bytes = size, schema = schema})
        if send_request(writer.end, writer.port, &out) != null {
            return .Error(.Gone)
        }
        if !waits {
            writer.waiting = 1
            return .Ok(writer)
        }
        match answer(writer.end, writer.port) {
            case Some(response) => match response {
                case Consumed(_) => {}
                case WrongType => return .Error(.WrongType)
                case _ => return .Error(.Gone)
            }
            case None => return .Error(.Gone)
        }
        return .Ok(writer)
    }

    /**
     * Write a record: its value's bytes, as base's schema_write_value writes them, put in the ring.
     *
     * It waits while the ring has no room for it. The reader is told of what's written once a quarter of the ring is
     * waiting, or when the writer finishes.
     *
     * @tparam T The records' type.
     * @param writer The open writer.
     * @param value The record, copied into the ring; nothing of it is kept.
     * @return Null once it's in the ring; NoMemory if its bytes couldn't be made, TooBig if they're more than half the
     *     ring, or Gone if the reader went while it waited for room.
     */
    write :: fn[T](writer: ptr[mut Writer[T]], value: T) -> StreamError? {
        runtime.array_reset(&writer.scratch)
        if runtime.schema_try_write_value(value, &writer.scratch) != null {
            return .NoMemory
        }
        return put(writer, writer.scratch)
    }

    /**
     * Write bytes to a byte stream, as one record, which the reader's next_bytes gives whole.
     *
     * @param writer The open writer.
     * @param bytes The bytes, copied into the ring; empty makes an empty record.
     * @return Null once they're in the ring; TooBig if they're more than half the ring with their header, or Gone if
     *     the reader went while it waited for room.
     */
    write_bytes :: fn(writer: ptr[mut Writer[u8]], bytes: u8[]) -> StreamError? {
        return put(writer, bytes)
    }

    /**
     * Put a record's value bytes in the ring, after a wrap if it wouldn't fit before the ring's end.
     *
     * It waits while the ring has no room for it, and says Wrote once a quarter of the ring is written and unsaid.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The open writer.
     * @param value The value's bytes, as std/schema's write_value writes one, copied into the ring.
     * @return Null once they're in the ring; TooBig if they're more than half the ring with their header, or Gone if
     *     the reader went, or broke the protocol, while it waited for room.
     */
    put :: fn[T](writer: ptr[mut Writer[T]], value: u8[]) -> StreamError? {
        need :: RECORD_HEADER + padded(cast[u64](value.count))
        if need > writer.ring_bytes / 2 {
            return .TooBig
        }
        at :: writer.produced % writer.ring_bytes
        if at + need > writer.ring_bytes {
            left :: writer.ring_bytes - at
            match room(writer, left) {
                case Some(error) => return error
                case None => {}
            }
            header(writer.address + at, 0, KIND_WRAP)
            writer.produced += left
        }
        match room(writer, need) {
            case Some(error) => return error
            case None => {}
        }
        start :: writer.address + writer.produced % writer.ring_bytes
        header(start, cast[u32](value.count), KIND_RECORD)
        bytes :: view_of(cast[ptr[mut u8]](cast[uintptr](start + RECORD_HEADER)), value.count)
        for byte, i in value {
            if i < bytes.count {
                bytes[i] = byte
            }
        }
        writer.produced += need
        if writer.produced - writer.announced >= writer.ring_bytes / 4 {
            return flush(writer)
        }
        return null
    }

    /**
     * Tell the reader what's been written since it was last told, with a Wrote, if anything has.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The open writer.
     * @return Null if it was told, or there was nothing to tell; Gone if the Wrote couldn't be sent.
     */
    flush :: fn[T](writer: ptr[mut Writer[T]]) -> StreamError? {
        if writer.produced == writer.announced {
            return null
        }
        out := os.Outgoing.{}
        os.begin[Request](&out)^ = .Wrote(writer.produced)
        if send_request(writer.end, writer.port, &out) != null {
            return .Gone
        }
        writer.announced = writer.produced
        writer.waiting += 1
        return null
    }

    /**
     * Wait for room for count more bytes in the ring, taking the reader's answers until it has read enough.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The open writer.
     * @param count The bytes needed, at most the ring's size.
     * @return Null once there's room; Gone if the reader went, broke the protocol, or has nothing left to answer while
     *     the ring is still full.
     */
    room :: fn[T](writer: ptr[mut Writer[T]], count: u64) -> StreamError? {
        loop {
            if writer.produced + count - writer.consumed <= writer.ring_bytes {
                return null
            }
            // What's written but not said is said, so the reader can read it
            match flush(writer) {
                case Some(error) => return error
                case None => {}
            }
            if writer.waiting == 0 {
                return .Gone
            }
            match take_answer(writer) {
                case Some(error) => return error
                case None => {}
            }
        }
    }

    /**
     * Wait for one of the reader's answers, and take it: how far it has read.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The open writer, which has a request waiting for an answer.
     * @return Null once a Consumed is taken; Gone if the reader's end went, or it answered anything else, WrongType
     *     included.
     */
    take_answer :: fn[T](writer: ptr[mut Writer[T]]) -> StreamError? {
        response :: answer(writer.end, writer.port) or_return .Gone
        match response {
            case Consumed(count) => {
                writer.consumed = count
                writer.waiting = if writer.waiting > 0 { writer.waiting - 1 } else { 0 }
                return null
            }
            case _ => return .Gone
        }
    }

    /**
     * End the stream, with a status, and wait until the reader has read everything; then let go of the writer.
     *
     * The writer is closed (close_writer) whatever happens, so it isn't used again.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The open writer, closed by this.
     * @param status The writer's status, for the reader: 0 for success, any other value the writer's own.
     * @return Null once the reader has read everything; Gone if the reader went first, or broke the protocol, or the
     *     reader of a writer that didn't wait for Open's answer reads another type.
     */
    finish :: fn[T](writer: ptr[mut Writer[T]], status: u32) -> StreamError? {
        defer close_writer(writer)
        match flush(writer) {
            case Some(error) => return error
            case None => {}
        }
        out := os.Outgoing.{}
        os.begin[Request](&out)^ = .Ended(status)
        if send_request(writer.end, writer.port, &out) != null {
            return .Gone
        }
        writer.waiting += 1
        loop {
            if writer.waiting == 0 {
                return null
            }
            match take_answer(writer) {
                case Some(error) => return error
                case None => {}
            }
        }
    }

    /**
     * End the stream, with a status, without waiting for the reader to read what's written: for a writer with more to
     * do meanwhile, like a shell reading what the reader writes in turn.
     *
     * The writer isn't closed: it's closed with close_writer once the reader's done, and nothing more is written to it.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The open writer.
     * @param status The writer's status, for the reader: 0 for success, any other value the writer's own.
     * @return Null once the Ended is sent; Gone if it, or the Wrote before it, couldn't be.
     */
    end_without_waiting :: fn[T](writer: ptr[mut Writer[T]], status: u32) -> StreamError? {
        match flush(writer) {
            case Some(error) => return error
            case None => {}
        }
        out := os.Outgoing.{}
        os.begin[Request](&out)^ = .Ended(status)
        if send_request(writer.end, writer.port, &out) != null {
            return .Gone
        }
        return null
    }

    /**
     * Let go of a writer: unmap its ring, close the ring, its port and its end, and free its scratch.
     *
     * Without an Ended first, the reader sees the end gone, as a stream that ended with status 0xffffffff.
     *
     * @tparam T The Writer's type parameter.
     * @param writer The writer, not used again after this.
     */
    close_writer :: fn[T](writer: ptr[mut Writer[T]]) {
        _ = slop_os.memory_unmap(slop_os.startup_block().space, writer.address)
        _ = slop_os.handle_close(cast[slop_os.Handle](writer.ring))
        _ = slop_os.handle_close(cast[slop_os.Handle](writer.port))
        _ = slop_os.handle_close(cast[slop_os.Handle](writer.end))
        runtime.array_free(&writer.scratch)
    }

    /**
     * Open a stream's reading end: wait for the writer's Open, check its type, map its ring to read, and answer it.
     *
     * @tparam T The records' type, whose schema hash has to be the writer's.
     * @param source The reading end, which the reader keeps from now on, and closes in close_reader. On an error the
     *     end isn't closed, and the port made for it by then isn't let go of.
     * @return The open reader, to read with next, and then close.
     * @error NoMemory The port couldn't be made, or the ring couldn't be mapped.
     * @error Gone The writer's end went, or it sent something other than Open first.
     * @error WrongType The writer writes another type; it's told so, and its ring is let go of.
     */
    reader_on :: fn[T](source: os.Stream[T]) -> Result[Reader[T], StreamError] {
        return opened_reader[T](source.end, runtime.schema_hash(type_info_of(T)))
    }

    /**
     * Open a stream's reading end for records whose type's schema hash is schema, as reader_on does, for code that
     * meets their type as it runs; next_bytes reads them.
     *
     * @param end The channel's reading end, which the reader keeps from now on, and closes in close_reader. On an
     *     error the end isn't closed, and the port made for it by then isn't let go of.
     * @param schema The schema hash of the type to read, which has to be the writer's.
     * @return The open reader.
     * @error NoMemory The port couldn't be made, or the ring couldn't be mapped.
     * @error Gone The writer's end went, or it sent something other than Open first.
     * @error WrongType The writer writes another type; it's told so, and its ring is let go of.
     */
    untyped_reader_on :: fn(end: slop_os.Channel, schema: u8[32]) -> Result[Reader[Untyped], StreamError] {
        return opened_reader[Untyped](end, schema)
    }

    /**
     * Open a stream's reading end, as reader_on and untyped_reader_on do, for records whose type's schema hash is
     * schema.
     *
     * @tparam T The Reader's type parameter: the records' type, or Untyped.
     * @param end The channel's reading end, which the reader keeps from now on. On an error the end isn't closed, and
     *     the port made for it by then isn't let go of.
     * @param schema The schema hash of the type to read.
     * @return The open reader.
     * @error NoMemory The port couldn't be made, or the ring couldn't be mapped.
     * @error Gone The writer's end went, or it sent something other than Open first.
     * @error WrongType The writer writes another type; it's told so, and its ring is let go of.
     */
    opened_reader :: fn[T](end: slop_os.Channel, schema: u8[32]) -> Result[Reader[T], StreamError] {
        block :: slop_os.startup_block()
        reader := Reader[T].{end = end}
        reader.port = os.port_for(block.budget, end) or_return .Error(.NoMemory)
        into := os.Incoming.{}
        opening :: match take_request(reader.end, reader.port, &into) {
            case Some(request) => match request {
                case Open(opened) => opened
                case _ => return .Error(.Gone)
            }
            case None => return .Error(.Gone)
        }
        if !same_hash(opening.schema, schema) {
            _ = slop_os.handle_close(cast[slop_os.Handle](opening.ring))
            reply(reader.end, reader.port, .WrongType)
            return .Error(.WrongType)
        }
        reader.ring = opening.ring
        reader.ring_bytes = opening.ring_bytes
        reader.address = runtime.reserve_addresses(cast[usize](opening.ring_bytes)) or_return .Error(.NoMemory)
        slop_os.memory_map(reader.ring, block.space, reader.address, 0, opening.ring_bytes, slop_os.PROTECTION_READ) or_return .Error(.NoMemory)
        reply(reader.end, reader.port, .Consumed(0))
        return .Ok(reader)
    }

    /**
     * Read the next record's value bytes, waiting for the writer to write one.
     *
     * Before reading, it answers the writer's Wrotes it has read past, so the writer has room again.
     *
     * @tparam T The Reader's type parameter.
     * @param reader The open reader.
     * @return The record's value bytes, as they are in the ring: good only until the next call, or close_reader, after
     *     which the writer may write over them. Null once the writer has ended, or its end has gone, and everything's
     *     read; null too for a record whose header says it runs past the ring's end.
     */
    next_bytes :: fn[T](reader: ptr[mut Reader[T]]) -> u8[]? {
        loop {
            // Each Wrote the reader has read up to, answered
            answer_marks(reader)
            if reader.read < reader.produced {
                at :: reader.read % reader.ring_bytes
                start :: reader.address + at
                count, kind :: record_header(start)
                if kind == KIND_WRAP {
                    reader.read += reader.ring_bytes - at
                    continue
                }
                size :: RECORD_HEADER + padded(cast[u64](count))
                if at + size > reader.ring_bytes {
                    return null
                }
                reader.read += size
                return view_of(cast[ptr[u8]](cast[uintptr](start + RECORD_HEADER)), cast[usize](count))
            }
            if reader.ended {
                return null
            }
            into := os.Incoming.{}
            match take_request(reader.end, reader.port, &into) {
                case Some(request) => match request {
                    case Wrote(count) => {
                        reader.produced = count
                        add_mark(reader, count)
                    }
                    case Ended(status) => {
                        reader.ended = true
                        reader.status = status
                        add_mark(reader, reader.produced)
                    }
                    case _ => {}
                }
                case None => {
                    reader.ended = true
                    reader.status = 0xffffffff
                }
            }
        }
    }

    /**
     * Read the next record, waiting for the writer to write one, and copy its value out of the ring.
     *
     * @tparam T The records' type.
     * @param reader The open reader.
     * @return The record, its value's memory, if it has any, from context's allocator and the caller's to free; null
     *     once the writer has ended and everything's read, or if the record's bytes aren't a value of T.
     */
    next :: fn[T](reader: ptr[mut Reader[T]]) -> T? {
        bytes :: next_bytes(reader) or_return null
        value : T
        if !runtime.schema_read_value(bytes, type_info_of(T), cast[rawptr](&value)) {
            return null
        }
        return value
    }

    /**
     * Answer the Wrotes, and the Ended, whose bytes the reader has read, each with how far it has, and forget them.
     *
     * An answer that can't be sent is dropped.
     *
     * @tparam T The Reader's type parameter.
     * @param reader The open reader.
     */
    answer_marks :: fn[T](reader: ptr[mut Reader[T]]) {
        done : usize = 0
        for mark, i in reader.marks {
            if i >= reader.mark_count || mark > reader.read {
                break
            }
            reply(reader.end, reader.port, .Consumed(reader.read))
            done += 1
        }
        if done == 0 {
            return void
        }
        left :: reader.mark_count - done
        for i in 0..<left {
            from :: i + done
            if from < reader.marks.count && i < reader.marks.count {
                reader.marks[i] = reader.marks[from]
            }
        }
        reader.mark_count = left
    }

    /**
     * Remember a Wrote, or the Ended, to answer once the reader has read as far as it says.
     *
     * @tparam T The Reader's type parameter.
     * @param reader The open reader.
     * @param mark How many bytes the writer had written in all when it sent it. Past MAX_MARKS waiting, it's dropped,
     *     and never answered.
     */
    add_mark :: fn[T](reader: ptr[mut Reader[T]], mark: u64) {
        at :: reader.mark_count
        if at < reader.marks.count {
            reader.marks[at] = mark
            reader.mark_count = at + 1
        }
    }

    /**
     * Tell whether two schema hashes are the same.
     *
     * @param a One hash.
     * @param b The other.
     * @return True if every byte is the same.
     */
    same_hash :: fn(a: u8[32], b: u8[32]) -> bool {
        for byte, i in a {
            if byte != b[i] {
                return false
            }
        }
        return true
    }

    /**
     * Let go of a reader: answer what it has read, unmap and close its ring, and close its port and its end.
     *
     * A writer still writing, or waiting in finish for the rest to be read, sees the end gone (Gone).
     *
     * @tparam T The Reader's type parameter.
     * @param reader The reader, not used again after this; a view next_bytes gave is no good after it.
     */
    close_reader :: fn[T](reader: ptr[mut Reader[T]]) {
        answer_marks(reader)
        _ = slop_os.memory_unmap(slop_os.startup_block().space, reader.address)
        _ = slop_os.handle_close(cast[slop_os.Handle](reader.ring))
        _ = slop_os.handle_close(cast[slop_os.Handle](reader.port))
        _ = slop_os.handle_close(cast[slop_os.Handle](reader.end))
    }

    /**
     * Wait for the next response on an end, skipping any that isn't one: unknown, invalid, or of another protocol.
     *
     * @param end The end to read, kept by the caller.
     * @param port A port bound to end, waited on until a response comes.
     * @return The response; null if the end's gone, or reading it failed.
     */
    answer :: fn(end: slop_os.Channel, port: slop_os.Port) -> Response? {
        into := os.Incoming.{}
        loop {
            match receive_response(end, port, &into, true) {
                case Received => return os.message_of[Response](&into)^
                case Failed(error) => return null
                case _ => continue
            }
        }
    }

    /**
     * Wait for the next request on an end, skipping any that isn't one: unknown, invalid, or of another protocol.
     *
     * @param end The end to read, kept by the caller.
     * @param port A port bound to end, waited on until a request comes.
     * @param into Where the message is received, with any handles it brought, which are the caller's from then on.
     * @return The request, copied out of into; null if the end's gone, or reading it failed.
     */
    take_request :: fn(end: slop_os.Channel, port: slop_os.Port, into: ptr[mut os.Incoming]) -> Request? {
        loop {
            match receive_request(end, port, into, true) {
                case Received => return os.message_of[Request](into)^
                case Failed(error) => return null
                case _ => continue
            }
        }
    }

    /**
     * Send a response on an end; one that can't be sent is dropped.
     *
     * @param end The end to send on, kept by the caller.
     * @param port A port bound to end, waited on while end's ring is full.
     * @param response The response, which has no variable-size data.
     */
    reply :: fn(end: slop_os.Channel, port: slop_os.Port, response: Response) {
        out := os.Outgoing.{}
        os.begin[Response](&out)^ = response
        _ = send_response(end, port, &out)
    }

    /**
     * Write a record's header in the ring.
     *
     * @param address Where the header goes in the mapped ring, 8-byte aligned, with RECORD_HEADER bytes there.
     * @param count The record's value's byte count, without padding; 0 for a wrap.
     * @param kind KIND_RECORD or KIND_WRAP.
     */
    header :: fn(address: u64, count: u32, kind: u32) {
        words :: cast[ptr[mut u32[2]]](cast[uintptr](address))
        words^[0] = count
        words^[1] = kind
    }

    /**
     * Read a record's header from the ring.
     *
     * @param address Where the header is in the mapped ring, 8-byte aligned.
     * @return count The record's value's byte count, without padding, as the writer wrote it; not checked.
     * @return kind KIND_RECORD or KIND_WRAP, as the writer wrote it; not checked.
     */
    record_header :: fn(address: u64) -> (count : u32, kind : u32) {
        words :: cast[ptr[u32[2]]](cast[uintptr](address))
        return words^[0], words^[1]
    }

    /**
     * Round a byte count up to a multiple of 8, as each record is padded to in the ring.
     *
     * @param count The bytes.
     * @return The least multiple of 8 at least count; 0 for 0.
     */
    padded :: fn(count: u64) -> u64 {
        return (count + 7) & ~cast[u64](7)
    }
}
