package query

import os from "std:os"
import slop_os from "std:os/slop_os"
import files from "std:os/slop_os/files"

/**
 * The query protocol, for os.Channel[Query]: a live query (the SlopOS repository's decisions 0201), and the predicate
 * a directory's Query and LiveQuery are asked with.
 *
 * A predicate is a list of terms in postfix order: each comparison of an index's field with a constant pushes
 * whether it holds, each And and Or pops two and pushes both or either, each Not pops one and pushes its opposite,
 * and one is left at the end. Every index a predicate names has to be of the same type, whose files it's asked of.
 *
 * A live query answers the files beneath its directory that match, each Matched, then Current, then, as each
 * transaction that changes what matches is committed, Added, Changed or Gone for each file, one for each Next. A
 * Next with nothing to answer yet is answered when there is something.
 */
Query :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "query", major_version = 1, lending = .PerConnection}

/** The most terms a predicate has; a longer one is refused (WrongType). */
MAX_TERMS :: 32

/** What a term is, as its kind holds it. */
TermKind :: enum #backed_by(u32) {
    /** A comparison of an index's field with a constant. */
    Compare = 1,
    /** Both of the two terms before. */
    And = 2,
    /** Either of the two terms before. */
    Or = 3,
    /** Not the term before. */
    Not = 4,
}

/** How a comparison compares its field with its constant, as its comparison holds it. */
Comparison :: enum #backed_by(u32) {
    /** The field is the constant. */
    Equal = 1,
    /** The field isn't the constant. */
    NotEqual = 2,
    /** The field is less than the constant. */
    Less = 3,
    /** The field is at most the constant. */
    LessOrEqual = 4,
    /** The field is more than the constant. */
    Greater = 5,
    /** The field is at least the constant. */
    GreaterOrEqual = 6,
}

/** One term of a predicate. It holds plain numbers only, as a Relative's items do; the server checks them. */
Term :: struct {
    /** Its TermKind's value. */
    kind : u32,
    /** A comparison's Comparison's value; 0 for another kind. */
    comparison : u32,
    /** A comparison's index, by number, as Indexes lists it; 0 for another kind. */
    index : u32,
    /** A comparison of a text field: how many bytes of the predicate's texts its constant is; 0 otherwise. */
    text_count : u32,
    /**
     * A comparison's constant for an integer or a bool field: an unsigned value as it is, a signed one's two's
     * complement bits, a bool 0 or 1.
     */
    number : u64,
    /** A comparison of a text field: where its constant starts among the predicate's texts, in bytes. */
    text_offset : u32,
    /** Reserved; zero. */
    reserved : u32,
}

/** A predicate: its terms, and the bytes its text constants are among. */
Predicate :: struct {
    /** The terms, in postfix order, 1 to MAX_TERMS. */
    terms : slop_os.Relative[Term],
    /**
     * The text constants' bytes, UTF-8, each term's at its text_offset; a server may compare only a text's first
     * bytes, as many as its index keeps.
     */
    texts : slop_os.Relative[u8],
}

/** Where a query is in what it answers: opaque, only given back; all zeros for its start. */
Cursor :: struct {
    /** Where its walk is. */
    phase : u32,
    /** Reserved; zero. */
    reserved : u32,
    /** Where its walk is, within the phase. */
    key : u64,
    /** Where its walk is, within the key. */
    skip : u64,
}

/** What a directory's Query asks: a predicate, and where to go on from. */
Ask :: struct {
    /** The predicate. */
    predicate : Predicate,
    /** All zeros for the first file, then each Matched's next. */
    cursor : Cursor,
}

/** A file a directory's Query answers, and where to go on from. */
Match :: struct {
    /** The file's path, UTF-8, beneath the directory asked. */
    name : slop_os.Relative[u8],
    /** The file's number in its volume, the same for as long as it's there, which a live query's events name too. */
    file : u64,
    /** The cursor to give the next Query, for the file after this one. */
    next : Cursor,
}

/** What happened, as a live query's event says it. */
EventKind :: enum #backed_by(u32) {
    /** A file that matched when the query was opened, or when it was begun again after Resync. */
    Matched = 1,
    /** Every file that matched then has been answered; what follows is what changes. */
    Current = 2,
    /** A file matches that didn't. */
    Added = 3,
    /** A file that matches was changed, or moved, and still matches. */
    Changed = 4,
    /** A file that matched doesn't any more, or is gone. */
    Gone = 5,
    /**
     * More changed at once than the query could keep track of, so it begins again: each file that matches now is
     * Matched once more, then Current.
     */
    Resync = 6,
}

/** One event of a live query's. */
Event :: struct {
    /** What happened. */
    kind : EventKind,
    /** The file's number in its volume; 0 for Current and Resync. */
    file : u64,
    /**
     * The file's path, UTF-8, beneath the query's directory, as it is now; empty for Current and Resync, and for a
     * file that's Gone from beneath the directory or from the volume.
     */
    name : slop_os.Relative[u8],
}

/** What a client asks of a live query. */
Request :: union {
    /**
     * The next event. Answered with Event, at once if there's one, or once a commit makes one; Failed with NoSpace if
     * more files match than the query can keep, and then it ends; Failed with another error if the volume couldn't
     * be read.
     */
    Next,
}

/** What a live query's server answers. */
Response :: union {
    /** The answer to Next: an event, its file's path in the message's variable-size data. */
    Event(Event),
    /** The answer to a request that failed, and why. */
    Failed(files.FileError),
    /** The answer to a request the server doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True: Next only reads, though an event answered to the first is lost.
 */
is_idempotent :: fn(request : ptr[Request]) -> bool {
    return match request^ {
        case Next => true
    }
}

#insert os.protocol_code(Request, Response)
