package os

/*
 * Indexes and queries over typed files (the SlopOS repository's decisions 0046, 0201): an index of a type's field
 * declared on a directory's volume, and predicates over a type's indexed fields, built a comparison at a time and
 * joined with and, or and not, asked beneath a directory once (query_in) or live (open_live_query), each event as a
 * commit makes it.
 *
 *     _ = os.declare_index[Task](root, "level")
 *     predicate := os.Predicate.{}
 *     defer os.free_predicate(&predicate)
 *     os.where_number[Task](root, &predicate, "level", .GreaterOrEqual, 3) or_return 1
 *     found :: os.query_in(directory, &predicate) or_return 1
 *     defer os.free_matches(&found)
 *
 * An index is declared and dropped on a connection to its volume's root, which the indexes are of; it's found, and a
 * query asked, beneath any directory of the volume.
 */
#if OS == .SlopOS {
    import runtime from "base:runtime"
    import schema from "std:schema"
    import slop_os from "std:os/slop_os"
    import dir from "std:os/slop_os/dir"
    import files from "std:os/slop_os/files"
    import query from "std:os/slop_os/query"

    /**
     * A predicate being built: its terms in postfix order, and its text constants' bytes, on context.allocator,
     * given back with free_predicate.
     */
    Predicate :: struct {
        /** The terms, in postfix order, as the query protocol has them. */
        terms : query.Term[..],
        /** The text constants' bytes, each term's at its text_offset. */
        texts : u8[..],
    }

    /** An index a directory's volume keeps: its number and what its field holds. */
    IndexFound :: struct {
        /** Its number, which a comparison names it by. */
        number : u32,
        /** What its field holds. */
        kind : files.IndexedKind,
    }

    /** A file a query found: its path beneath the directory asked, and its number in its volume. */
    QueryMatch :: struct {
        /** Its path, UTF-8, in memory from context.allocator, which free_matches gives back. */
        name : string,
        /** Its number in its volume, as a live query's events name it. */
        file : u64,
    }

    /** A live query: its connection, and whether a Next is waiting for its answer. */
    LiveQuery :: struct {
        /** The connection's end, speaking query; owned, closed by close_live_query. */
        end : slop_os.Channel,
        /** A port bound to end, owned, closed by close_live_query. */
        port : slop_os.Port,
        /** Whether a Next has been sent and not yet answered, so the next wait doesn't send another. */
        asked : bool,
    }

    /** A live query's event, its file's path in the caller's buffer. */
    LiveEvent :: struct {
        /** What happened. */
        kind : query.EventKind,
        /** The file's number in its volume; 0 for Current and Resync. */
        file : u64,
        /** How many bytes of the file's path are in the caller's buffer, cut to its size. */
        name_bytes : usize,
    }

    /**
     * Declare an index of a field of T's on the volume a directory is the root of, built from the files of T there
     * are before it's answered. A file of T's is in all of T's indexes or none, so one whose value doesn't hold the
     * field drops out of T's others.
     *
     * @tparam T The files' value's type, a struct.
     * @param directory The open directory, which stays the caller's: its volume's root, writable, not reached through
     *     a stored link.
     * @param field The name of one of T's own fields: an integer, a bool, or text (a Relative of bytes).
     * @return The index's number; the same number if it's declared already.
     * @error WrongType The field isn't one of T's, or isn't of a type an index can be of.
     * @error AccessDenied The directory isn't its volume's root (NotVolumeRoot), is read only, or was reached through a
     *     stored link.
     * @error OutOfMemory The schema couldn't be written, or the server hadn't the memory.
     * @error Other The volume keeps as many indexes as it can, keeps none, or the server didn't answer.
     */
    declare_index :: fn[T](directory : Directory, field : string) -> Result[u32, OsError] {
        bytes : u8[..]
        defer runtime.array_free(&bytes)
        if schema.try_write(type_info_of(T), &bytes) != null || bytes.count == 0 {
            return .Error(.OutOfMemory)
        }
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .DeclareIndex(
            files.IndexOf.{schema = append(&out, view_of(&bytes[0], bytes.count)), field = relative_path(&out, field)}
        )
        into := Incoming.{}
        if !ask_directory(directory_of(directory), &out, &into) {
            return .Error(.Other)
        }
        match message_of[dir.Response](&into)^ {
            case Declared(number) => return .Ok(number)
            case Failed(failure) => return .Error(error_of_file(failure))
            case _ => return .Error(.Other)
        }
    }

    /**
     * Find the index of a field of T's on a directory's volume.
     *
     * @tparam T The files' value's type.
     * @param directory The open directory, which stays the caller's: any directory of the volume.
     * @param field The field's name.
     * @return The index's number and kind.
     * @error NotFound No index of the field is declared.
     * @error Other The indexes couldn't be listed: the file system keeps none, the directory is a transaction's, or
     *     the server didn't answer.
     */
    index_of :: fn[T](directory : Directory, field : string) -> Result[IndexFound, OsError] {
        hash :: schema_hash_of[T]()
        cursor := cast[u32](0)
        loop {
            out := Outgoing.{}
            request :: begin[dir.Request](&out)
            request^ = .Indexes(cursor)
            into := Incoming.{}
            if !ask_directory(directory_of(directory), &out, &into) {
                return .Error(.Other)
            }
            match message_of[dir.Response](&into)^ {
                case IndexListed(index) => {
                    name :: items(&into, index.field)
                    if index.schema == hash && same_text(name, field) {
                        return .Ok(IndexFound.{number = index.number, kind = index.kind})
                    }
                    if index.next <= cursor {
                        return .Error(.Other)
                    }
                    cursor = index.next
                }
                case End => return .Error(.NotFound)
                case Failed(failure) => return .Error(error_of_file(failure))
                case _ => return .Error(.Other)
            }
        }
    }

    /**
     * Add a comparison of a field of T's with a number to a predicate, finding the field's index.
     *
     * @tparam T The files' value's type, whose index of field has to be declared.
     * @param directory The open directory whose volume's indexes are asked, which stays the caller's: any directory
     *     of the volume, as index_of says.
     * @param predicate The predicate, which the comparison is pushed on.
     * @param field The field's name: an integer or a bool's.
     * @param comparison How the field is compared with value.
     * @param value The constant: a signed integer's value, an unsigned one's from 0 to i64's greatest (one past it is
     *     compared with compare_number, as its bits), or 0 or 1 for a bool.
     * @return Null once it's added; NotFound if no index of the field is declared, WrongType for a text field, a
     *     negative value for an unsigned field or a bool, or a bool's past 1, or index_of's error.
     */
    where_number :: fn[T](
        directory : Directory,
        predicate : ptr[mut Predicate],
        field : string,
        comparison : query.Comparison,
        value : i64
    ) -> OsError? {
        found := IndexFound.{}
        match index_of[T](directory, field) {
            case Ok(index) => found = index
            case Error(error) => return error
        }
        if found.kind == .Text || (found.kind != .Signed && value < 0) || (found.kind == .Bool && value > 1) {
            return OsError.WrongType
        }
        compare_number(predicate, found.number, comparison, cast[u64](value))
        return null
    }

    /**
     * Add a comparison of a text field of T's with a text to a predicate, finding the field's index.
     *
     * @tparam T The files' value's type, whose index of field has to be declared.
     * @param directory The open directory whose volume's indexes are asked, which stays the caller's: any directory
     *     of the volume, as index_of says.
     * @param predicate The predicate, which the comparison is pushed on.
     * @param field The text field's name.
     * @param comparison How the field is compared with text, byte by byte, by its whole value.
     * @param text The constant, UTF-8.
     * @return Null once it's added; NotFound if no index of the field is declared, WrongType for a field that isn't
     *     text, or index_of's error.
     */
    where_text :: fn[T](
        directory : Directory,
        predicate : ptr[mut Predicate],
        field : string,
        comparison : query.Comparison,
        text : string
    ) -> OsError? {
        found := IndexFound.{}
        match index_of[T](directory, field) {
            case Ok(index) => found = index
            case Error(error) => return error
        }
        if found.kind != .Text {
            return OsError.WrongType
        }
        compare_text(predicate, found.number, comparison, text)
        return null
    }

    /**
     * Drop an index from the volume a directory is the root of: its records taken out, and the files of its type
     * indexed again by the type's other indexes. A live query naming it ends.
     *
     * @param directory The open directory, which stays the caller's: its volume's root, writable, not reached through
     *     a stored link.
     * @param index The index's number, as declare_index or index_of give it.
     * @return Null once it's dropped; NotFound for no such index, AccessDenied for a directory that isn't the root
     *     (NotVolumeRoot), is read only or was reached through a stored link, or Other if the file system keeps no
     *     indexes or the server didn't answer.
     */
    drop_index :: fn(directory : Directory, index : u32) -> OsError? {
        out := Outgoing.{}
        begin[dir.Request](&out)^ = .DropIndex(index)
        into := Incoming.{}
        if !ask_directory(directory_of(directory), &out, &into) {
            return OsError.Other
        }
        match message_of[dir.Response](&into)^ {
            case Done => return null
            case Failed(failure) => return error_of_file(failure)
            case _ => return OsError.Other
        }
    }

    /**
     * Push a comparison of an index's field with a number on a predicate.
     *
     * @param predicate The predicate.
     * @param index The index's number, as index_of finds it.
     * @param comparison How the field is compared.
     * @param value The constant: an unsigned value, a signed one's two's complement bits, or 0 or 1 for a bool.
     */
    compare_number :: fn(predicate : ptr[mut Predicate], index : u32, comparison : query.Comparison, value : u64) {
        runtime.array_add(
            &predicate.terms,
            query.Term.{
                kind = cast[u32](query.TermKind.Compare),
                comparison = cast[u32](comparison),
                index = index,
                number = value,
            }
        )
    }

    /**
     * Push a comparison of an index's text field with a text on a predicate.
     *
     * @param predicate The predicate, whose texts the constant's bytes are added to.
     * @param index The index's number, as index_of finds it.
     * @param comparison How the field is compared, byte by byte.
     * @param text The constant, UTF-8, copied.
     */
    compare_text :: fn(predicate : ptr[mut Predicate], index : u32, comparison : query.Comparison, text : string) {
        start :: predicate.texts.count
        for character in text {
            runtime.array_add(&predicate.texts, cast[u8](character))
        }
        runtime.array_add(
            &predicate.terms,
            query.Term.{
                kind = cast[u32](query.TermKind.Compare),
                comparison = cast[u32](comparison),
                index = index,
                text_offset = cast[u32](start),
                text_count = cast[u32](text.count),
            }
        )
    }

    /**
     * Join the two terms last pushed on a predicate: both have to hold.
     *
     * @param predicate The predicate, which has to have two pushed for it to hold together.
     */
    both :: fn(predicate : ptr[mut Predicate]) {
        runtime.array_add(&predicate.terms, query.Term.{kind = cast[u32](query.TermKind.And)})
    }

    /**
     * Join the two terms last pushed on a predicate: either has to hold.
     *
     * @param predicate The predicate, which has to have two pushed for it to hold together.
     */
    either :: fn(predicate : ptr[mut Predicate]) {
        runtime.array_add(&predicate.terms, query.Term.{kind = cast[u32](query.TermKind.Or)})
    }

    /**
     * Turn the term last pushed on a predicate: it has not to hold.
     *
     * @param predicate The predicate, which has to have one pushed for it to hold together.
     */
    negate :: fn(predicate : ptr[mut Predicate]) {
        runtime.array_add(&predicate.terms, query.Term.{kind = cast[u32](query.TermKind.Not)})
    }

    /**
     * Give back what a predicate holds.
     *
     * @param predicate The predicate, empty afterwards.
     */
    free_predicate :: fn(predicate : ptr[mut Predicate]) {
        runtime.array_free(&predicate.terms)
        runtime.array_free(&predicate.texts)
    }

    /**
     * Ask the files beneath a directory a predicate holds for, every one, a page at a time, going on past each page
     * that found none in what the server looked at.
     *
     * @param directory The open directory, which stays the caller's.
     * @param predicate The predicate, only read.
     * @return The files, in the server's order, each once if nothing changes meanwhile; the list and each name are
     *     from context.allocator, which the caller gives back with free_matches.
     * @error WrongType The predicate doesn't hold together, or names indexes of more than one type.
     * @error NotFound It names an index that isn't there.
     * @error OutOfMemory The server hadn't the memory, or a name couldn't be copied.
     * @error Other The file system keeps no indexes, or the server didn't answer; what was found is given back.
     */
    query_in :: fn(directory : Directory, predicate : ptr[Predicate]) -> Result[QueryMatch[..], OsError] #unrestricted {
        found : QueryMatch[..]
        cursor := query.Cursor.{}
        loop {
            out := Outgoing.{}
            request :: begin[dir.Request](&out)
            request^ = .Query(query.Ask.{predicate = predicate_of(&out, predicate), cursor = cursor})
            into := Incoming.{}
            if !ask_directory(directory_of(directory), &out, &into) {
                free_matches(&found)
                return .Error(.Other)
            }
            match message_of[dir.Response](&into)^ {
                case Matched(matched) => {
                    // None in the files the server looked at this time: on from where it got to
                    if matched.file == 0 {
                        cursor = matched.next
                        continue
                    }
                    name :: items(&into, matched.name)
                    copy, error :: runtime.new_array(u8, name.count)
                    if error != null {
                        free_matches(&found)
                        return .Error(.OutOfMemory)
                    }
                    for byte, i in name {
                        if i < copy.count {
                            copy[i] = byte
                        }
                    }
                    text :: if copy.count == 0 { "" } else { string_of(&copy[0], copy.count) }
                    runtime.array_add(&found, QueryMatch.{name = text, file = matched.file})
                    cursor = matched.next
                }
                case End => return .Ok(found)
                case Failed(failure) => {
                    free_matches(&found)
                    return .Error(error_of_file(failure))
                }
                case _ => {
                    free_matches(&found)
                    return .Error(.Other)
                }
            }
        }
    }

    /**
     * Give back what query_in found: each name, and the list, to context.allocator.
     *
     * @param matches The list, empty afterwards.
     */
    free_matches :: fn(matches : ptr[mut QueryMatch[..]]) {
        for found in matches^ {
            if found.name.count > 0 {
                runtime.free_array(string_bytes(found.name))
            }
        }
        runtime.array_free(matches)
    }

    /**
     * Open a live query beneath a directory: the files the predicate holds for, then what each commit changes.
     *
     * @param directory The open directory, which stays the caller's.
     * @param predicate The predicate, only read; the server keeps its own copy.
     * @return The live query, whose events next_live_event gives; the caller closes it with close_live_query.
     * @error WrongType The predicate doesn't hold together, or names indexes of more than one type.
     * @error NotFound It names an index that isn't there.
     * @error OutOfMemory Its port couldn't be made, or the server hadn't the memory.
     * @error Other The server keeps as many live queries as it can, keeps no indexes, or didn't answer.
     */
    open_live_query :: fn(directory : Directory, predicate : ptr[Predicate]) -> Result[LiveQuery, OsError] {
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .LiveQuery(predicate_of(&out, predicate))
        into := Incoming.{}
        if !ask_directory(directory_of(directory), &out, &into) {
            return .Error(.Other)
        }
        end := cast[slop_os.Channel](slop_os.NO_HANDLE)
        match message_of[dir.Response](&into)^ {
            case Live(connection) => end = connection.end
            case Failed(failure) => return .Error(error_of_file(failure))
            case _ => return .Error(.Other)
        }
        block :: slop_os.startup_block()
        port :: port_for(block.budget, end) or_else cast[slop_os.Port](slop_os.NO_HANDLE)
        if cast[slop_os.Handle](port) == slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](end))
            return .Error(.OutOfMemory)
        }
        return .Ok(LiveQuery.{end = end, port = port})
    }

    /**
     * Wait for a live query's next event, until a deadline.
     *
     * @param live The live query; a Next is sent unless one's waiting from a call that timed out.
     * @param name Where the event's file's path goes, as much as fits.
     * @param deadline Until when to wait, in nanoseconds of the monotonic clock; slop_os.NO_DEADLINE for ever.
     * @return The event; null if none came by the deadline, the Next left waiting for the next call.
     * @error NotFound The query ended, an index it names dropped.
     * @error Other The query ended (more matched than the server keeps), the volume couldn't be read, or the
     *     connection failed.
     */
    next_live_event :: fn(live : ptr[mut LiveQuery], name : mut u8[], deadline : u64) -> Result[LiveEvent?, OsError] {
        if !live.asked {
            out := Outgoing.{}
            begin[query.Request](&out)^ = .Next
            if query.send_request(live.end, live.port, &out) is_some {
                return .Error(.Other)
            }
            live.asked = true
        }
        into := Incoming.{}
        match query.receive_response(live.end, live.port, &into, true, deadline) {
            case Received => {}
            case Empty => return .Ok(null)
            case _ => return .Error(.Other)
        }
        live.asked = false
        match message_of[query.Response](&into)^ {
            case Event(event) => {
                bytes :: items(&into, event.name)
                count :: if bytes.count < name.count { bytes.count } else { name.count }
                for i in 0..<count {
                    if i < bytes.count && i < name.count {
                        name[i] = bytes[i]
                    }
                }
                return .Ok(LiveEvent.{kind = event.kind, file = event.file, name_bytes = count})
            }
            case Failed(failure) => return .Error(error_of_file(failure))
            case _ => return .Error(.Other)
        }
    }

    /**
     * Close a live query: its connection and port.
     *
     * @param live The live query, which isn't good afterwards.
     */
    close_live_query :: fn(live : ptr[mut LiveQuery]) {
        _ = slop_os.handle_close(cast[slop_os.Handle](live.port))
        _ = slop_os.handle_close(cast[slop_os.Handle](live.end))
        live^ = LiveQuery.{end = cast[slop_os.Channel](slop_os.NO_HANDLE), port = cast[slop_os.Port](slop_os.NO_HANDLE)}
    }

    /**
     * Append a predicate's terms and texts to a request being built.
     *
     * @param out The request, after begin.
     * @param predicate The predicate, only read.
     * @return Where its terms and texts are, for the request's Predicate.
     */
    predicate_of :: fn(out : ptr[mut Outgoing], predicate : ptr[Predicate]) -> query.Predicate {
        made := query.Predicate.{}
        terms :: predicate.terms
        if terms.count > 0 {
            made.terms = append(out, view_of(&terms[0], terms.count))
        }
        texts :: predicate.texts
        if texts.count > 0 {
            made.texts = append(out, view_of(&texts[0], texts.count))
        }
        return made
    }

    /**
     * Tell whether bytes are a text's.
     *
     * @param bytes The bytes.
     * @param text The text.
     * @return Whether they're the same length, byte for byte alike.
     */
    same_text :: fn(bytes : u8[], text : string) -> bool {
        if bytes.count != text.count {
            return false
        }
        for byte, i in bytes {
            if i < text.count && cast[u8](text[i]) != byte {
                return false
            }
        }
        return true
    }
}
