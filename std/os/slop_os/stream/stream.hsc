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

    Stream :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "Stream", major_version = 1, lending = .Server}

    // How big a stream's ring is, unless it's asked to be bigger
    RING_BYTES : u64 : 64 * 1024
    // A record's header: its value's bytes, and its kind
    RECORD_HEADER : u64 : 8
    KIND_RECORD : u32 : 0
    KIND_WRAP : u32 : 1
    // The most of the writer's Wrotes not answered yet: it says one each quarter of the ring, and waits for room
    MAX_MARKS :: 64

    Opening :: struct {
        ring : slop_os.Memory,
        ring_bytes : u64,
        schema : u8[32],
    }

    Request :: union {
        Open(Opening),
        // How many bytes the writer has written in all
        Wrote(u64),
        // The writer's done, with its status, 0 for success
        Ended(u32),
    }

    Response :: union {
        // How many bytes the reader has read in all
        Consumed(u64),
        // Open's answer when the reader reads another type
        WrongType,
        Unsupported,
    }

    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case Open(_) => false
            case Wrote(_) => true
            case Ended(_) => true
        }
    }

    #insert os.protocol_code(Request, Response)

    StreamError :: enum {
        // The other end's gone
        Gone,
        // The reader reads another type than the writer writes
        WrongType,
        // A record bigger than the ring
        TooBig,
        NoMemory,
    }

    // A stream's writing end, open: its ring, mapped, how much it has written and the reader has read, and its scratch.
    Writer :: struct[T] {
        end : slop_os.Channel,
        port : slop_os.Port,
        ring : slop_os.Memory,
        address : u64,
        ring_bytes : u64,
        produced : u64,
        announced : u64,
        consumed : u64,
        // Wrotes the reader hasn't answered yet
        waiting : u64,
        scratch : u8[..],
    }

    // A stream's reading end, open.
    Reader :: struct[T] {
        end : slop_os.Channel,
        port : slop_os.Port,
        ring : slop_os.Memory,
        address : u64,
        ring_bytes : u64,
        // How far it has read, and how far the writer has said it has written
        read : u64,
        produced : u64,
        // The Wrotes, and the Ended, not answered yet, by how far each said, oldest first
        marks : u64[MAX_MARKS],
        mark_count : usize,
        // The writer's status, once it's Ended
        ended : bool,
        status : u32,
    }

    // A new stream's two ends.
    Pair :: struct[T] {
        sink : os.Sink[T],
        stream : os.Stream[T],
    }

    pair :: fn[T](budget: slop_os.MemoryBudget) -> Result[Pair[T], slop_os.ChannelError] {
        ends :: slop_os.channel_create(budget, 0, os.protocol_tag[Stream]())?
        return .Ok(Pair[T].{sink = os.Sink[T].{end = ends.a}, stream = os.Stream[T].{end = ends.b}})
    }

    /*
     * A stream's writing end opened: a ring of ring_bytes (RING_BYTES for 0) made and mapped, and offered to the
     * reader, whose answer is waited for.
     */
    writer_on :: fn[T](sink: os.Sink[T], ring_bytes: u64 = 0) -> Result[Writer[T], StreamError] {
        return opened_writer[T](sink.end, runtime.schema_hash(type_info_of(T)), ring_bytes, true)
    }

    /*
     * A stream's records known only by their schema, for code that meets their type as it runs, like a shell reading a
     * program's output by its manifest: a writer of them puts each one's bytes, as std/schema's write_value writes one
     * (put), and a reader of them takes each one's (next_bytes).
     */
    Untyped :: struct {}

    /*
     * A stream's writing end opened, for records whose type's schema hash is schema. Unless it waits, the reader's
     * answer to Open is taken with its others, as the writer waits for room or finishes: for a writer that does
     * something else before the reader opens its end, like a shell starting a program that opens its output first.
     */
    untyped_writer_on :: fn(end: slop_os.Channel, schema: u8[32], ring_bytes: u64 = 0, waits: bool = true) -> Result[Writer[Untyped], StreamError] {
        return opened_writer[Untyped](end, schema, ring_bytes, waits)
    }

    // writer_on's, for records whose type's schema hash is schema.
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

    // A record of T written, waiting for room if the ring's full.
    write :: fn[T](writer: ptr[mut Writer[T]], value: T) -> StreamError? {
        runtime.array_reset(&writer.scratch)
        if runtime.schema_try_write_value(value, &writer.scratch) != null {
            return .NoMemory
        }
        return put(writer, writer.scratch)
    }

    // Bytes written to a byte stream, as one record.
    write_bytes :: fn(writer: ptr[mut Writer[u8]], bytes: u8[]) -> StreamError? {
        return put(writer, bytes)
    }

    // A record's value bytes put in the ring, after a wrap if it wouldn't fit before the ring's end.
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

    // What's been written, said to the reader.
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

    // Room for count more bytes, waited for: the reader's answers taken until it has read enough.
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

    // One of the reader's answers, waited for.
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

    /*
     * The stream ended, with status: what's written said, Ended sent, and every answer waited for, so the reader has
     * read everything; then the ring and the end closed.
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

    /*
     * The stream ended, with status, without waiting for the reader to read what's written: for a writer with more to do
     * meanwhile, like a shell reading what the reader writes in turn. It's closed with close_writer once the reader's
     * done.
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

    close_writer :: fn[T](writer: ptr[mut Writer[T]]) {
        _ = slop_os.memory_unmap(slop_os.startup_block().space, writer.address)
        _ = slop_os.handle_close(cast[slop_os.Handle](writer.ring))
        _ = slop_os.handle_close(cast[slop_os.Handle](writer.port))
        _ = slop_os.handle_close(cast[slop_os.Handle](writer.end))
        runtime.array_free(&writer.scratch)
    }

    // A stream's reading end opened: the writer's Open waited for, its type checked, and its ring mapped to read.
    reader_on :: fn[T](source: os.Stream[T]) -> Result[Reader[T], StreamError] {
        return opened_reader[T](source.end, runtime.schema_hash(type_info_of(T)))
    }

    // A stream's reading end opened, for records whose type's schema hash is schema.
    untyped_reader_on :: fn(end: slop_os.Channel, schema: u8[32]) -> Result[Reader[Untyped], StreamError] {
        return opened_reader[Untyped](end, schema)
    }

    // reader_on's, for records whose type's schema hash is schema.
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

    /*
     * The next record's value bytes, waited for, as they are in the ring until the next call: null once the writer has
     * ended and everything's read.
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

    // The next record, waited for, copied to the heap: null once the writer has ended and everything's read.
    next :: fn[T](reader: ptr[mut Reader[T]]) -> T? {
        bytes :: next_bytes(reader) or_return null
        value : T
        if !runtime.schema_read_value(bytes, type_info_of(T), cast[rawptr](&value)) {
            return null
        }
        return value
    }

    // The Wrotes, and the Ended, whose bytes the reader has read, answered with how far it has.
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

    add_mark :: fn[T](reader: ptr[mut Reader[T]], mark: u64) {
        at :: reader.mark_count
        if at < reader.marks.count {
            reader.marks[at] = mark
            reader.mark_count = at + 1
        }
    }

    same_hash :: fn(a: u8[32], b: u8[32]) -> bool {
        for byte, i in a {
            if byte != b[i] {
                return false
            }
        }
        return true
    }

    // The reading end let go of: its ring unmapped and closed, and its end closed, which the writer sees as Gone.
    close_reader :: fn[T](reader: ptr[mut Reader[T]]) {
        answer_marks(reader)
        _ = slop_os.memory_unmap(slop_os.startup_block().space, reader.address)
        _ = slop_os.handle_close(cast[slop_os.Handle](reader.ring))
        _ = slop_os.handle_close(cast[slop_os.Handle](reader.port))
        _ = slop_os.handle_close(cast[slop_os.Handle](reader.end))
    }

    // A response waited for on end, or null if the end's gone.
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

    // A request waited for on end, into into, or null if the end's gone.
    take_request :: fn(end: slop_os.Channel, port: slop_os.Port, into: ptr[mut os.Incoming]) -> Request? {
        loop {
            match receive_request(end, port, into, true) {
                case Received => return os.message_of[Request](into)^
                case Failed(error) => return null
                case _ => continue
            }
        }
    }

    reply :: fn(end: slop_os.Channel, port: slop_os.Port, response: Response) {
        out := os.Outgoing.{}
        os.begin[Response](&out)^ = response
        _ = send_response(end, port, &out)
    }

    header :: fn(address: u64, count: u32, kind: u32) {
        words :: cast[ptr[mut u32[2]]](cast[uintptr](address))
        words^[0] = count
        words^[1] = kind
    }

    record_header :: fn(address: u64) -> (count : u32, kind : u32) {
        words :: cast[ptr[u32[2]]](cast[uintptr](address))
        return words^[0], words^[1]
    }

    padded :: fn(count: u64) -> u64 {
        return (count + 7) & ~cast[u64](7)
    }
}
