package os

/*
 * SlopOS's protocols (the SlopOS repository's decisions 0040, 0071): a protocol is a package with a Request and a
 * Response union, a type named after the protocol for os.Channel[P], and, at its top level,
 *
 *     #insert os.protocol_code(Request, Response)
 *
 * which generates its messages' validators and its send and receive functions from the two types:
 * validate_request and validate_response, send_request and send_response, receive_request and receive_response,
 * and answer_unsupported. The package imports os from "std" and slop_os from "std/os", which the generated code
 * names. A message is its union's own layout, then its variable-size data (slop_os.Relative[T]) after it; a
 * handle in it travels as its index in the message's batch.
 *
 *     out := os.Outgoing.{}
 *     request :: os.begin[storage.Request](&out)
 *     request^ = .Write(storage.Write.{block = 7, data = os.append(&out, bytes)})
 *     storage.send_request(end, port, &out)
 *
 *     into := os.Incoming.{}
 *     match storage.receive_request(end, port, &into, true) {
 *         case Received => handle(os.message_of[storage.Request](&into), &into)
 *         case Unsupported => _ = storage.answer_unsupported(end, port)
 *         case _ => {}
 *     }
 *
 * A message's types hold only plain data (integers, floats, characters, bools, enums, and structs and arrays of
 * them), handles (slop_os's handle types, os.Channel[P] and os.Listener[P]) and Relative[T]s of plain data;
 * anything else is a compile error where the protocol generates its code.
 */
#if OS == .SlopOS {
    import compiler from "base"
    import intrinsics from "base"
    import runtime from "base"
    import slop_os from "std/os"

    /**
     * The most a message has here, in 8-byte words: 512, 4096 bytes, what fits a ring of 8 KiB or more (a message is
     * at most half its ring).
     */
    MESSAGE_WORDS :: 512
    /** The most bytes a message has here, its fixed part and its variable-size data together: 4096. */
    MESSAGE_BYTES :: MESSAGE_WORDS * 8

    /** A message being built: its bytes so far, and the handles it moves, gathered as it's sent. */
    Outgoing :: struct {
        /** The message's bytes, from its start; words, so it's aligned for any field. */
        words : u64[MESSAGE_WORDS],
        /** How many bytes of words the message uses so far, its fixed part rounded up to 8 and its appended data. */
        used : u32,
        /** The handles it moves, in their batch's order, gathered by send_<side> as it's sent. */
        handles : slop_os.Handle[slop_os.MAX_HANDLES_PER_BATCH],
        /** How many of handles are gathered. */
        handle_count : u32,
    }

    /** A message received: its bytes, zeros past its size up to its type's, and the handles that came with it. */
    Incoming :: struct {
        /** The message's bytes, from its start, zeros past size. */
        words : u64[MESSAGE_WORDS],
        /** How many bytes the message has. */
        size : u32,
        /**
         * The handles that came with it, in their batch's order, now the caller's; once it's Received, each handle
         * field holds its handle, and these are what to close if the message isn't used.
         */
        handles : slop_os.Handle[slop_os.MAX_HANDLES_PER_BATCH],
        /** How many of handles came with it. */
        handle_count : u32,
    }

    /** What receiving a message gave. */
    Arrival :: union {
        /** A valid message, which message_of reads, its handles in place and the caller's. */
        Received,
        /** None yet, without waiting. */
        Empty,
        /** A request of a variant this side doesn't know, which answer_unsupported answers; its handles were closed. */
        Unsupported,
        /**
         * A message that breaks its type's rules: out of bounds, an impossible tag or value, a missing handle. Its
         * handles were closed.
         */
        Invalid,
        /** A channel in it, or arriving where one was expected, speaks another protocol; its handles were closed. */
        WrongProtocol,
        /** Receiving failed, with the kernel's error, like PeerClosed when the other end is closed. */
        Failed(slop_os.ChannelError),
    }

    /** What a message's validator found. */
    Validity :: enum {
        /** The message is one of its type, safe to read. */
        Valid,
        /** Its tag is past its union's variants: a variant this side doesn't know, from a newer protocol. */
        Unknown,
        /** It breaks its type's rules: too short, an impossible value, a handle index or Relative out of bounds. */
        Invalid,
    }

    /**
     * Start a message of T in out, zeroed: where to write it.
     *
     * Its variable-size data goes after it (append).
     *
     * @tparam T The message's type: a protocol's Request or Response.
     * @param out The message being built; whatever it held is cleared, its handles too (not closed).
     * @return Where the message is, in out, good as long as out is; zeroed, for the caller to fill.
     */
    begin :: fn[T](out: ptr[mut Outgoing]) -> ptr[mut T] {
        out^ = Outgoing.{}
        out.used = cast[u32]((size_of(T) + 7) & ~cast[usize](7))
        return cast[ptr[mut T]](&out.words[0])
    }

    /**
     * Append items to a message being built, after what it has so far, aligned for E.
     *
     * It's a failed assertion if they don't fit in MESSAGE_BYTES.
     *
     * @tparam E The items' type: plain data.
     * @param out The message being built, after begin.
     * @param items What's appended, copied; empty appends nothing.
     * @return Where they are, for a Relative field: their offset from the message's start and their count.
     */
    append :: fn[E](out: ptr[mut Outgoing], items: E[]) -> slop_os.Relative[E] {
        alignment :: cast[u32](align_of(E))
        start :: (out.used + alignment - 1) & ~(alignment - 1)
        bytes :: cast[u32](items.count * size_of(E))
        if cast[u64](start) + cast[u64](bytes) > cast[u64](MESSAGE_BYTES) {
            runtime.assert(false, "a message's variable-size data fits MESSAGE_BYTES")
        }
        if bytes != 0 {
            intrinsics.mem_copy_non_overlapping(cast[mut rawptr](cast[u64](&out.words[0]) + cast[u64](start)), cast[rawptr](items.data),
                cast[usize](bytes))
        }
        out.used = start + bytes
        return slop_os.Relative[E].{offset = start, count = cast[u32](items.count)}
    }

    /**
     * View a received message as its type.
     *
     * @tparam T The message's type, the one its receive function checked.
     * @param into The message, only once its receive function said Received.
     * @return The message, in into, good as long as into is and isn't received into again.
     */
    message_of :: fn[T](into: ptr[Incoming]) -> ptr[T] {
        return cast[ptr[T]](&into.words[0])
    }

    /**
     * View a Relative's items in a received message.
     *
     * @tparam E The items' type.
     * @param into The message, received and validated, which checked the Relative is inside it.
     * @param relative The Relative field, from the message.
     * @return Its items, in into, good as long as into is.
     */
    items :: fn[E](into: ptr[Incoming], relative: slop_os.Relative[E]) -> E[] {
        return view_of(cast[ptr[E]](cast[u64](&into.words[0]) + cast[u64](relative.offset)), cast[usize](relative.count))
    }

    // ---- What the generated code calls

    /**
     * View a received message's bytes, for its validator.
     *
     * @param into The message.
     * @return All MESSAGE_BYTES of its words, not only its size, good as long as into is.
     */
    bytes_of_incoming :: fn(into: ptr[Incoming]) -> u8[] {
        return view_of(cast[ptr[u8]](&into.words[0]), MESSAGE_BYTES)
    }

    /**
     * Read a little-endian integer from a message.
     *
     * @param message The message's bytes.
     * @param offset Where the integer starts, in bytes from the message's start.
     * @param size How many bytes it has, from 0 to 8.
     * @return Its value; bytes past the message's end read as 0.
     */
    read_message :: fn(message: u8[], offset: usize, size: usize) -> u64 {
        value : u64 = 0
        for i in 0..<size {
            at :: offset + i
            if at < message.count {
                value = value | (cast[u64](message[at]) << cast[u64](8 * i))
            }
        }
        return value
    }

    /**
     * Check whether a Relative in a message points after the message's fixed part and inside it.
     *
     * @param message The message's bytes.
     * @param size The message's size in bytes, which the Relative's items have to end within.
     * @param offset Where the Relative field is, in bytes from the message's start.
     * @param fixed The size of the message's fixed part in bytes, which its items have to start at or after.
     * @param element_size The size of one of its items, in bytes.
     * @param alignment The alignment its items' start needs, in bytes; not 0.
     * @return True if it has no items, or its items start at or after fixed, aligned, and end within size; false
     *     otherwise.
     */
    relative_fits :: fn(message: u8[], size: u32, offset: usize, fixed: usize, element_size: usize, alignment: usize) -> bool {
        start :: read_message(message, offset, 4)
        count :: read_message(message, offset + 4, 4)
        if count == 0 {
            return true
        }
        end :: start + count * cast[u64](element_size)
        return start >= cast[u64](fixed) && start % cast[u64](alignment) == 0 && count <= cast[u64](MESSAGE_BYTES) && end <= cast[u64](size)
    }

    /**
     * Check whether a handle field's index is in the message's batch.
     *
     * @param message The message's bytes.
     * @param offset Where the handle field is, in bytes from the message's start.
     * @param handle_count How many handles came with the message.
     * @return True if the index is below handle_count, or is NO_HANDLE_INDEX, for none.
     */
    index_fits :: fn(message: u8[], offset: usize, handle_count: u32) -> bool {
        index :: cast[u32](read_message(message, offset, 4))
        return index == slop_os.NO_HANDLE_INDEX || index < handle_count
    }

    /**
     * Encode a handle field for sending: the handle goes in out's batch, and its index takes its place.
     *
     * @param out The message being sent.
     * @param offset Where the handle field is, in bytes from the message's start. A field of 0, no handle, becomes
     *     NO_HANDLE_INDEX. A handle past MAX_HANDLES_PER_BATCH is left as it is, which the receiver will find invalid.
     */
    encode_handle :: fn(out: ptr[mut Outgoing], offset: usize) {
        at :: cast[ptr[mut u32]](cast[u64](&out.words[0]) + cast[u64](offset))
        handle :: at^
        if handle == 0 {
            at^ = slop_os.NO_HANDLE_INDEX
            return void
        }
        count :: cast[usize](out.handle_count)
        if count < out.handles.count {
            out.handles[count] = cast[slop_os.Handle](handle)
            at^ = cast[u32](count)
            out.handle_count += 1
        }
    }

    /**
     * Decode a handle field of a received message: the handle whose index is there takes its place.
     *
     * @param into The message received.
     * @param offset Where the handle field is, in bytes from the message's start. An index for no handle, or past the
     *     batch, leaves 0, no handle.
     * @param tag The protocol tag the handle's channel has to have, or 0 for a handle of any kind.
     * @return False if tag isn't 0 and the handle's channel isn't tagged with it (or isn't a channel); true otherwise,
     *     with no handle too.
     */
    decode_handle :: fn(into: ptr[mut Incoming], offset: usize, tag: u64) -> bool {
        at :: cast[ptr[mut u32]](cast[u64](&into.words[0]) + cast[u64](offset))
        index :: cast[usize](at^)
        at^ = 0
        if index >= cast[usize](into.handle_count) || index >= into.handles.count {
            return true
        }
        handle :: into.handles[index]
        at^ = cast[u32](handle)
        if tag == 0 {
            return true
        }
        speaking :: slop_os.channel_tag(cast[slop_os.Channel](handle)) or_else 0
        return speaking == tag
    }

    /**
     * Read the next message into into, before it's checked.
     *
     * @param end The end it's read from, which stays the caller's.
     * @param port A port bound to end (port_for), waited on when wait is true.
     * @param into Where the message goes: zeroed first, so it's zeros past its size; its handles are the caller's.
     * @param wait Whether to wait for a message when there's none yet.
     * @return Received with the message in into; Empty when there's none and wait is false; Failed with the kernel's
     *     error otherwise.
     */
    arrive :: fn(end: slop_os.Channel, port: slop_os.Port, into: ptr[mut Incoming], wait: bool) -> Arrival {
        into^ = Incoming.{}
        buffer :: view_of(cast[ptr[mut u8]](&into.words[0]), MESSAGE_BYTES)
        handles :: view_of(&into.handles[0], into.handles.count)
        received := Received.{}
        if wait {
            match receive(end, port, buffer, handles) {
                case Ok(got) => received = got
                case Error(error) => return .Failed(error)
            }
        }
        else {
            match try_receive(end, buffer, handles) {
                case Ok(got) => received = got
                case Error(error) => return if error == .Empty { Arrival.Empty } else { Arrival.Failed(error) }
            }
        }
        into.size = received.size
        into.handle_count = received.handle_count
        return .Received
    }

    /**
     * Close the handles a refused message brought.
     *
     * @param into The message; its handle_count is 0 afterwards.
     */
    refuse :: fn(into: ptr[mut Incoming]) {
        for handle, i in into.handles {
            if i < cast[usize](into.handle_count) {
                _ = slop_os.handle_close(handle)
            }
        }
        into.handle_count = 0
    }

    /**
     * Send a message that's been built, with its handles, through end.
     *
     * @param end The end it's sent through, which stays the caller's.
     * @param port A port bound to end (port_for), waited on while the ring is full.
     * @param out The message, its used bytes sent, and its gathered handles moved out of the caller's table.
     * @return Null once it's sent; otherwise why not, as send gives it.
     */
    send_outgoing :: fn(end: slop_os.Channel, port: slop_os.Port, out: ptr[mut Outgoing]) -> slop_os.ChannelError? {
        bytes :: view_of(cast[ptr[u8]](&out.words[0]), cast[usize](out.used))
        return send(end, port, bytes, view_of(&out.handles[0], cast[usize](out.handle_count)))
    }

    // ---- The generator

    /** What kind of check a field of a message needs. */
    FieldKind :: enum {
        /** A bool, which has to be 0 or 1. */
        Bool,
        /** An enum, which has to be one of its members' values. */
        Enum,
        /** A handle, whose index has to be in the batch, and which is encoded and decoded. */
        Handle,
        /** A Relative, whose items have to be inside the message. */
        Relative,
    }

    /** What a message's type needs checked, and its handles: one per field that needs either. */
    FieldCheck :: struct {
        /** What kind of field it is. */
        kind : FieldKind,
        /** Where it is, in bytes from the message's start. */
        offset : usize,
        /** An enum's size, or a Relative's element's size, in bytes; 0 for other kinds. */
        size : usize,
        /** A Relative's element's alignment, in bytes; 0 for other kinds. */
        alignment : usize,
        /** An enum's members' values; empty for other kinds. */
        values : u128[],
        /** A typed channel's protocol tag, 0 for a plain handle or another kind. */
        tag : u64,
    }

    /**
     * Generate the code a protocol package inserts at its top level.
     *
     * That's its validators and its send and receive functions for Request and Response, and answer_unsupported, from
     * Response's Unsupported variant, which every Response needs (decisions/0040). A Response without one, or a
     * message type that holds what a message can't, is a failed assertion at compile time.
     *
     * @param Request The protocol's Request union, with a tag.
     * @param Response The protocol's Response union, with a tag and an Unsupported variant holding nothing.
     * @return The code: validate_request, validate_response, send_request, send_response, receive_request,
     *     receive_response and answer_unsupported.
     */
    protocol_code :: fn(Request: type, Response: type) -> compiler.Code {
        made : compiler.Code[..]
        array_add(&made, side_code(Request, "request"))
        array_add(&made, side_code(Response, "response"))
        unsupported := false
        for variant in union_of(Response).variants {
            unsupported = unsupported || (variant.name == "Unsupported" && variant.types.count == 0)
        }
        runtime.assert(unsupported, "a protocol's Response has an Unsupported variant, with nothing in it (decisions/0040)")
        array_add(&made, #code {
            // Says the request wasn't one this side knows (decisions/0040).
            answer_unsupported :: fn(end: slop_os.Channel, port: slop_os.Port) -> slop_os.ChannelError? {
                out := os.Outgoing.{}
                response :: os.begin[#insert Response](&out)
                response^ = .Unsupported
                return send_response(end, port, &out)
            }
        })
        return compiler.list(made)
    }

    /**
     * Get a protocol's message type's union info; a type that isn't a union is a failed assertion.
     *
     * @param T The Request or Response type.
     * @return Its type info, as a union's.
     */
    union_of :: fn(T: type) -> ptr[compiler.TypeInfoUnion] {
        info :: type_info_of(T)
        runtime.assert(info.variant == .UNION, "a protocol's Request and Response are unions")
        return cast[ptr[compiler.TypeInfoUnion]](info)
    }

    /**
     * Generate validate_<side>, send_<side> and receive_<side> for one of a protocol's unions.
     *
     * @param T The union, Request or Response, which has to have a tag.
     * @param side Its name in the functions' names: "request" or "response".
     * @return The three functions' code.
     */
    side_code :: fn(T: type, side: string) -> compiler.Code {
        info :: union_of(T)
        tag_size :: match info.tag_type {
            case Some(tag) => tag.size
            case None => cast[usize](0)
        }
        runtime.assert(tag_size != 0, "a protocol's unions have tags")
        fixed :: (info.size + 7) & ~cast[usize](7)
        checking : compiler.Code[..]
        encoding : compiler.Code[..]
        decoding : compiler.Code[..]
        for variant, i in info.variants {
            fields : FieldCheck[..]
            for type, j in variant.types {
                if j < variant.offsets.count {
                    collect(type, variant.offsets[j], &fields)
                }
            }
            array_add(&checking, #code {
                if tag == #insert cast[u64](i) {
                    #insert checks_of(fields, fixed)
                    return .Valid
                }
            })
            array_add(&encoding, #code {
                if tag == #insert cast[u64](i) {
                    #insert handles_of(fields, true)
                }
            })
            array_add(&decoding, #code {
                if tag == #insert cast[u64](i) {
                    #insert handles_of(fields, false)
                }
            })
        }
        variants :: cast[u64](info.variants.count)
        mask :: if tag_size >= 8 { cast[u64](0xffffffffffffffff) } else { (cast[u64](1) << cast[u64](8 * tag_size)) - 1 }
        validator :: compiler.name("validate_", side)
        return #code {
            // Whether a message of #insert side's type is one: its tag, values, handles' indices and variable-size data.
            #insert compiler.name("validate_", side) :: fn(message: u8[], size: u32, handle_count: u32) -> os.Validity {
                if size < #insert cast[u32](tag_size) {
                    return .Invalid
                }
                tag :: os.read_message(message, 0, #insert tag_size)
                if tag >= #insert variants {
                    return .Unknown
                }
                #insert compiler.list(checking)
                return .Invalid
            }

            // out's message, with its handles moved into its batch.
            #insert compiler.name("send_", side) :: fn(end: slop_os.Channel, port: slop_os.Port, out: ptr[mut os.Outgoing]) -> slop_os.ChannelError? {
                tag :: out.words[0] & #insert mask
                #insert compiler.list(encoding)
                return os.send_outgoing(end, port, out)
            }

            /*
             * The next message into into, waiting for one if wait: Received once it's checked, its handles in place.
             * Anything else leaves nothing in into, its handles closed.
             */
            #insert compiler.name("receive_", side) :: fn(end: slop_os.Channel, port: slop_os.Port, into: ptr[mut os.Incoming], wait: bool) -> os.Arrival {
                arrived :: os.arrive(end, port, into, wait)
                match arrived {
                    case Received => {}
                    case _ => return arrived
                }
                validate :: #insert validator
                validity :: validate(os.bytes_of_incoming(into), into.size, into.handle_count)
                if validity != .Valid {
                    os.refuse(into)
                    return if validity == .Unknown { os.Arrival.Unsupported } else { os.Arrival.Invalid }
                }
                tag :: os.read_message(os.bytes_of_incoming(into), 0, #insert tag_size)
                speaks := true
                #insert compiler.list(decoding)
                if !speaks {
                    os.refuse(into)
                    return .WrongProtocol
                }
                return .Received
            }
        }
    }

    /**
     * Generate the checks a variant's fields need, for its validator.
     *
     * @param fields The variant's fields that need checking, from collect.
     * @param fixed The size of the message's fixed part in bytes, which Relatives' items start at or after.
     * @return Code that returns .Invalid on the first field that fails, and nothing else.
     */
    checks_of :: fn(fields: FieldCheck[], fixed: usize) -> compiler.Code {
        made : compiler.Code[..]
        for field in fields {
            offset :: field.offset
            if field.kind == .Bool {
                array_add(&made, #code {
                    if os.read_message(message, #insert offset, 1) > 1 {
                        return .Invalid
                    }
                })
            }
            else if field.kind == .Enum {
                condition := #code(false)
                for value in field.values {
                    condition = #code(#insert condition || value == #insert cast[u64](value))
                }
                array_add(&made, #code {
                    {
                        value :: os.read_message(message, #insert offset, #insert field.size)
                        if !(#insert condition) {
                            return .Invalid
                        }
                    }
                })
            }
            else if field.kind == .Handle {
                array_add(&made, #code {
                    if !os.index_fits(message, #insert offset, handle_count) {
                        return .Invalid
                    }
                })
            }
            else {
                array_add(&made, #code {
                    if !os.relative_fits(message, size, #insert offset, #insert fixed, #insert field.size, #insert field.alignment) {
                        return .Invalid
                    }
                })
            }
        }
        return compiler.list(made)
    }

    /**
     * Generate each handle field's encoding into out's batch when sending, or decoding from into's when receiving.
     *
     * @param fields The variant's fields that need checking, from collect; only its handles are used.
     * @param sending True for the encoding, for send_<side>; false for the decoding, for receive_<side>, which clears
     *     speaks when a handle's channel speaks another protocol.
     * @return The code.
     */
    handles_of :: fn(fields: FieldCheck[], sending: bool) -> compiler.Code {
        made : compiler.Code[..]
        for field in fields {
            if field.kind != .Handle {
                continue
            }
            offset :: field.offset
            if sending {
                array_add(&made, #code(os.encode_handle(out, #insert offset)))
            }
            else {
                array_add(&made, #code {
                    speaks = os.decode_handle(into, #insert offset, #insert field.tag) && speaks
                })
            }
        }
        return compiler.list(made)
    }

    /**
     * Collect what a type, at an offset in a message, needs checked, into fields.
     *
     * Anything a message can't hold (pointers, strings, views, unions, functions, Relatives of anything but plain
     * data) is a failed assertion, which stops the build.
     *
     * @param type The type: plain data, a handle, a Channel[P] or Listener[P], a Relative, or a struct or static array
     *     of those.
     * @param offset Where it is, in bytes from the message's start.
     * @param fields Where its checks are added, one per bool, enum, handle and Relative in it, in their order.
     */
    collect :: fn(type: ptr[compiler.TypeInfo], offset: usize, fields: ptr[mut FieldCheck[..]]) {
        if type.variant == .INTEGER || type.variant == .FLOAT || type.variant == .CHAR {
            return void
        }
        if type.variant == .BOOLEAN {
            array_add(fields, FieldCheck.{kind = .Bool, offset = offset})
            return void
        }
        if type.variant == .ENUM {
            enumeration :: cast[ptr[compiler.TypeInfoEnum]](type)
            array_add(fields, FieldCheck.{kind = .Enum, offset = offset, size = type.size, values = enumeration.values})
            return void
        }
        if type.variant == .ALIAS {
            alias :: cast[ptr[compiler.TypeInfoAlias]](type)
            if is_handle(type) {
                array_add(fields, FieldCheck.{kind = .Handle, offset = offset})
                return void
            }
            collect(alias.base_type, offset, fields)
            return void
        }
        if type.variant == .ARRAY {
            // Every dimension's elements, one after another, as the innermost element type
            array :: cast[ptr[compiler.TypeInfoArray]](type)
            count := cast[usize](1)
            for dimension in array.dimensions {
                runtime.assert(dimension.type == .STATIC, "a message holds static arrays, not views or dynamic arrays")
                count *= dimension.count
            }
            element_size :: if count == 0 { cast[usize](0) } else { type.size / count }
            for i in 0..<count {
                collect(array.base_type, offset + i * element_size, fields)
            }
            return void
        }
        if type.variant == .STRUCT {
            structure :: cast[ptr[compiler.TypeInfoStruct]](type)
            if starts_with(structure.name, "Channel[") || starts_with(structure.name, "Listener[") {
                array_add(fields, FieldCheck.{kind = .Handle, offset = offset, tag = end_tag(type)})
                return void
            }
            if starts_with(structure.name, "Relative[") {
                held := type
                for member in structure.members {
                    if member.name == "elements" {
                        held = cast[ptr[compiler.TypeInfoArray]](member.member_type).base_type
                    }
                }
                runtime.assert(held != type, "a Relative names its elements' type")
                inner : FieldCheck[..]
                collect(held, 0, &inner)
                runtime.assert(inner.count == 0, "a Relative's elements are plain data: no bools, enums, handles or Relatives")
                array_add(fields, FieldCheck.{kind = .Relative, offset = offset, size = held.size, alignment = alignment_of(held)})
                return void
            }
            for member in structure.members {
                collect(member.member_type, offset + member.offset, fields)
            }
            return void
        }
        runtime.assert(false, "a message holds plain data, handles and Relatives only: no pointers, strings, views, unions or functions")
    }

    /**
     * Check whether type is one of slop_os's handle types: Handle itself, or an alias of it, through any number of
     * aliases.
     *
     * @param type The type.
     * @return True for Handle or an alias of it; false for anything else.
     */
    is_handle :: fn(type: ptr[compiler.TypeInfo]) -> bool {
        at := type
        loop {
            if at.variant != .ALIAS {
                return false
            }
            alias :: cast[ptr[compiler.TypeInfoAlias]](at)
            if alias.name == "Handle" {
                return true
            }
            at = alias.base_type
        }
    }

    /**
     * Find the alignment a type has in a message.
     *
     * @param type The type.
     * @return A struct's own alignment; for anything else, what Hemera gives integers of its size: 1, 2, 4 or 8 bytes,
     *     never more.
     */
    alignment_of :: fn(type: ptr[compiler.TypeInfo]) -> usize {
        if type.variant == .STRUCT {
            return cast[ptr[compiler.TypeInfoStruct]](type).alignment
        }
        size :: type.size
        return if size >= 8 { cast[usize](8) } else if size >= 4 { cast[usize](4) } else if size >= 2 { cast[usize](2) } else { cast[usize](1) }
    }
}
