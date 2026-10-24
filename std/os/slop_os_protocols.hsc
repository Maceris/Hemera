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

    // The most bytes a message has, and the most handles, here: what fits a ring of 8 KiB or more.
    MESSAGE_WORDS :: 512
    MESSAGE_BYTES :: MESSAGE_WORDS * 8

    // A message being built: its bytes so far, and the handles it moves, gathered as it's sent.
    Outgoing :: struct {
        words : u64[MESSAGE_WORDS],
        used : u32,
        handles : slop_os.Handle[slop_os.MAX_HANDLES_PER_BATCH],
        handle_count : u32,
    }

    // A message received: its bytes, zeros past its size up to its type's, and the handles that came with it.
    Incoming :: struct {
        words : u64[MESSAGE_WORDS],
        size : u32,
        handles : slop_os.Handle[slop_os.MAX_HANDLES_PER_BATCH],
        handle_count : u32,
    }

    // What receiving a message gave.
    Arrival :: union {
        // A valid message, which message_of reads
        Received,
        // None yet, without waiting
        Empty,
        // A request whose variant this side doesn't know, which answer_unsupported answers
        Unsupported,
        // A message that breaks its type's rules: out of bounds, an impossible tag or value, a missing handle
        Invalid,
        // A channel in it, or arriving where one was expected, speaks another protocol
        WrongProtocol,
        Failed(slop_os.ChannelError),
    }

    // What a message's validator found.
    Validity :: enum {
        Valid,
        Unknown,
        Invalid,
    }

    // A message of T started in out, zeroed: where to write it. Its variable-size data goes after it (append).
    begin :: fn[T](out: ptr[mut Outgoing]) -> ptr[mut T] {
        out^ = Outgoing.{}
        out.used = cast[u32]((size_of(T) + 7) & ~cast[usize](7))
        return cast[ptr[mut T]](&out.words[0])
    }

    // items, after what out has so far, aligned for E: where they are, for a Relative field.
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

    // The message received, as its type: only once its receive function said Received.
    message_of :: fn[T](into: ptr[Incoming]) -> ptr[T] {
        return cast[ptr[T]](&into.words[0])
    }

    // A Relative's items, in a message received and validated.
    items :: fn[E](into: ptr[Incoming], relative: slop_os.Relative[E]) -> E[] {
        return view_of(cast[ptr[E]](cast[u64](&into.words[0]) + cast[u64](relative.offset)), cast[usize](relative.count))
    }

    // ---- What the generated code calls

    // A message's bytes, for its validator.
    bytes_of_incoming :: fn(into: ptr[Incoming]) -> u8[] {
        return view_of(cast[ptr[u8]](&into.words[0]), MESSAGE_BYTES)
    }

    // A little-endian integer of size bytes at offset in message, 0 past its end.
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

    // Whether a Relative at offset in a message of size bytes, of element_size and alignment, is after its fixed part and inside it.
    relative_fits :: fn(message: u8[], size: u32, offset: usize, fixed: usize, element_size: usize, alignment: usize) -> bool {
        start :: read_message(message, offset, 4)
        count :: read_message(message, offset + 4, 4)
        if count == 0 {
            return true
        }
        end :: start + count * cast[u64](element_size)
        return start >= cast[u64](fixed) && start % cast[u64](alignment) == 0 && count <= cast[u64](MESSAGE_BYTES) && end <= cast[u64](size)
    }

    // Whether a handle's index at offset is in the batch, or none.
    index_fits :: fn(message: u8[], offset: usize, handle_count: u32) -> bool {
        index :: cast[u32](read_message(message, offset, 4))
        return index == slop_os.NO_HANDLE_INDEX || index < handle_count
    }

    // Sending: the handle at offset in out goes in its batch, and its index takes its place.
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

    // Receiving: the handle whose index is at offset in into takes its place, and whether it speaks tag, if not 0.
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

    // A message read into into, zeroed past its size, with its handles taken (Received), or Empty without waiting if none's there.
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

    // The handles a refused message brought, closed.
    refuse :: fn(into: ptr[mut Incoming]) {
        for handle, i in into.handles {
            if i < cast[usize](into.handle_count) {
                _ = slop_os.handle_close(handle)
            }
        }
        into.handle_count = 0
    }

    // out's message, with its handles, through end.
    send_outgoing :: fn(end: slop_os.Channel, port: slop_os.Port, out: ptr[mut Outgoing]) -> slop_os.ChannelError? {
        bytes :: view_of(cast[ptr[u8]](&out.words[0]), cast[usize](out.used))
        return send(end, port, bytes, view_of(&out.handles[0], cast[usize](out.handle_count)))
    }

    // ---- The generator

    // What a message's type needs checked, and its handles: one per field that needs either.
    FieldKind :: enum {
        Bool,
        Enum,
        Handle,
        Relative,
    }

    FieldCheck :: struct {
        kind : FieldKind,
        offset : usize,
        // An enum's size and members' values; a Relative's element's size and alignment
        size : usize,
        alignment : usize,
        values : u128[],
        // A typed channel's protocol tag, 0 for a plain handle
        tag : u64,
    }

    /*
     * The code a protocol package inserts at its top level: its validators, send and receive functions for
     * Request and Response, unions of its messages, and answer_unsupported, from Response's Unsupported variant,
     * which every Response needs (decisions/0040).
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

    union_of :: fn(T: type) -> ptr[compiler.TypeInfoUnion] {
        info :: type_info_of(T)
        runtime.assert(info.variant == .UNION, "a protocol's Request and Response are unions")
        return cast[ptr[compiler.TypeInfoUnion]](info)
    }

    // validate_<side>, send_<side> and receive_<side> for one of the unions.
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

    // The checks a variant's fields need, in a message whose fixed part is fixed bytes.
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

    // Each handle field's encoding into out's batch when sending, or decoding from into's when receiving.
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

    // What type, at offset in a message, needs: added to fields. Anything a message can't hold stops the build.
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

    // Whether type is one of slop_os's handle types: a distinct alias of Handle, or Handle itself.
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

    // The alignment a type has in a message, from its size: what Hemera gives integers of that size, up to 8.
    alignment_of :: fn(type: ptr[compiler.TypeInfo]) -> usize {
        if type.variant == .STRUCT {
            return cast[ptr[compiler.TypeInfoStruct]](type).alignment
        }
        size :: type.size
        return if size >= 8 { cast[usize](8) } else if size >= 4 { cast[usize](4) } else if size >= 2 { cast[usize](2) } else { cast[usize](1) }
    }
}
