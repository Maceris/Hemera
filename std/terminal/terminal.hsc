package terminal

/*
 * A terminal's client (on SlopOS, the terminal protocol's, std/os/slop_os's terminal): text written, styled, and typed
 * input read one event at a time, a Read held for more whenever what came is used up. Asked to stop on its lifecycle
 * channel while it waits, it says so instead of an event.
 *
 *     console := terminal.open(given)?
 *     terminal.write_line(&console, "hello")
 *     editor := terminal.LineEditor.{}
 *     match terminal.read_line(&editor, &console, "> ") {
 *         case Line(text) => ...
 *         case _ => ...
 *     }
 */

import unicode from "std"

#if base.OS == .SlopOS {
    import runtime from "base"
    import os from "std"
    import slop_os from "std/os"
    import lifecycle from "std/os/slop_os"
    import terminal as protocol from "std/os/slop_os"

    /** The port key a stop's asked for on, beside the terminal's binding, so a wait for input wakes for a stop too. */
    STOP_KEY : u64 : 1

    /**
     * A terminal's client: its connection, the port it waits on, and the events the last Input brought, read from next.
     *
     * One thread or fiber uses it at a time; nothing in it is locked.
     */
    Terminal :: struct {
        /** The connection to the terminal, which requests go on and responses come back on. */
        end : slop_os.Channel,
        /** The port the client waits on, for responses and for a stop. */
        port : slop_os.Port,
        /** The events the last Input brought; event_count of them are filled in. */
        events : protocol.Event[protocol.MAX_EVENTS],
        /** How many of events the last Input brought, up to protocol.MAX_EVENTS; more than that are dropped. */
        event_count : usize,
        /** The index in events of the next event next_event gives. */
        next : usize,
        /** The text the last Input's events refer to, by their text_start and text_bytes. */
        text : u8[protocol.MAX_EVENT_TEXT],
        /** How many bytes of text are filled in, up to protocol.MAX_EVENT_TEXT; more than that are dropped. */
        text_count : usize,
        /** Whether a Read is held, waiting for the terminal's Input. */
        reading : bool,
        /** Whether the terminal's gone: a request failed or its connection broke. Once set, it stays. */
        hung_up : bool,
        /**
         * Packets its port's waits brought under keys other than its own, kept for next_event to give back as Other,
         * oldest first; other_count of them are filled in.
         */
        others : slop_os.Packet[OTHERS],
        /** How many of others are kept, up to OTHERS. */
        other_count : usize,
    }

    /**
     * The most packets under other keys kept between calls: one wait's worth. A wait that brings more than there's
     * room for drops the newest.
     */
    OTHERS :: 4

    /** What next_event gives: an event and its text, or why there's none. */
    Input :: union {
        /**
         * An event, and its text: the bytes it typed or pasted, empty when it has none. The text is the Terminal's,
         * good until the next call to next_event.
         */
        Event(protocol.Event, u8[]),
        /** The terminal's gone, so no more events come. */
        HangUp,
        /** The program was asked to stop on its lifecycle channel. */
        Stop,
        /**
         * A packet on the client's port under a key that isn't the client's own (0 for its connection, STOP_KEY), for a
         * program that waits for other things on the same port, like the ends of programs it watches.
         */
        Other(slop_os.Packet),
    }

    /**
     * Make a terminal client on a connection, its port made and a stop asked to wake it.
     *
     * @param connection The connection to the terminal, as a terminal service gave it; the client uses its channel end
     *     from now on, and doesn't close it.
     * @return The client, holding no Read yet; null if no port could be made for it. Failing to ask for a stop to wake
     *     it isn't an error: next_event still sees a stop the next time it wakes.
     */
    open :: fn(connection: os.Channel[protocol.Terminal]) -> Terminal? {
        made := Terminal.{end = connection.end}
        made.port = os.port_for(slop_os.startup_block().budget, connection.end) or_return null
        _ = lifecycle.on_stop(made.port, STOP_KEY)
        return made
    }

    /**
     * Write text to the terminal, styled.
     *
     * It goes in as many Writes as it takes, each ending where a grapheme cluster does.
     *
     * @param terminal A client open made, used by one thread or fiber at a time; it isn't changed, and a failed Write
     *     doesn't mark it hung up.
     * @param text The text, UTF-8, of any length. Nothing is added: no line break.
     * @param style How it's shown; the default is the terminal's plain style.
     * @return True if every Write went; false if one failed, the terminal most likely gone, with what came before it
     *     already written.
     */
    write :: fn(terminal: ptr[mut Terminal], text: string, style := protocol.Style.{}) -> bool {
        return protocol.write(terminal.end, terminal.port, text, style)
    }

    /**
     * Write text to the terminal, styled, then a line break.
     *
     * @param terminal A client open made, used by one thread or fiber at a time; it isn't changed, and a failed Write
     *     doesn't mark it hung up.
     * @param text The text, UTF-8, of any length, without the line break.
     * @param style How the text is shown; the line break is written in the plain style.
     * @return True if all of it went; false if a Write failed, the line break not written if the text wasn't.
     */
    write_line :: fn(terminal: ptr[mut Terminal], text: string, style := protocol.Style.{}) -> bool {
        return protocol.write(terminal.end, terminal.port, text, style) && protocol.write(terminal.end, terminal.port, "\n")
    }

    /**
     * Show the line being edited, below what's written, replacing the one shown before.
     *
     * @param terminal A client open made, used by one thread or fiber at a time; it isn't changed.
     * @param text The line, UTF-8, prompt included; empty to take the input line away.
     * @param cursor Where the cursor is, as a byte offset in text, from 0 to text.count.
     * @return True if it was handed to the terminal; false if the request failed.
     */
    show_input :: fn(terminal: ptr[mut Terminal], text: u8[], cursor: usize) -> bool {
        return protocol.input_line(terminal.end, terminal.port, text, cursor)
    }

    /**
     * Wait for the next event the terminal sends.
     *
     * Events left from the last Input come first; once they're used up, a Read is held for more, and the thread waits
     * on the client's port until they come. A Stop asked for wakes the wait too, and a packet under another key ends
     * it, given back as Other: the program can bind what else it waits for to the client's port, with keys of its own.
     *
     * @param terminal A client open made, used by one thread or fiber at a time. It moves on to its next event, holds a
     *     Read when its events are used up, and is marked hung up, for good, once a request or its connection fails.
     * @return The next Event, its text the client's until the next call; HangUp once the terminal's gone, and every
     *     time after; Stop once the program's been asked to stop, and every time after, unless it's hung up first; Other
     *     for a packet under another key, the oldest kept first.
     */
    next_event :: fn(terminal: ptr[mut Terminal]) -> Input {
        loop {
            if terminal.hung_up {
                return .HangUp
            }
            if lifecycle.stop_requested() {
                return .Stop
            }
            if terminal.other_count > 0 {
                other :: terminal.others[0]
                for i in 1..<terminal.other_count {
                    if i < terminal.others.count {
                        terminal.others[i - 1] = terminal.others[i]
                    }
                }
                terminal.other_count -= 1
                return .Other(other)
            }
            if terminal.next < terminal.event_count && terminal.next < terminal.events.count {
                event :: terminal.events[terminal.next]
                terminal.next += 1
                start :: cast[usize](event.text_start)
                end :: start + cast[usize](event.text_bytes)
                text :: if start <= end && end <= terminal.text_count && end <= terminal.text.count { terminal.text[start..<end] }
                    else { terminal.text[0..<0] }
                return .Event(event, text)
            }
            if !terminal.reading {
                if !protocol.read(terminal.end, terminal.port) {
                    terminal.hung_up = true
                    continue
                }
                terminal.reading = true
            }
            into := os.Incoming.{}
            match protocol.receive_response(terminal.end, terminal.port, &into, false) {
                case Received => {}
                case Empty => {
                    packets : slop_os.Packet[OTHERS]
                    taken :: cast[usize](slop_os.port_wait(terminal.port, packets, slop_os.NO_DEADLINE) or_else 0)
                    keep_others(terminal, packets, taken)
                    continue
                }
                case Failed(error) => {
                    terminal.hung_up = true
                    continue
                }
                case _ => continue
            }
            take_input(terminal, &into)
        }
    }

    /**
     * Keep the packets of a wait that aren't the client's own, for next_event to give back as Other.
     *
     * @param terminal The client, whose others grow by them; those past OTHERS are dropped.
     * @param packets What a wait on the client's port brought.
     * @param taken How many of packets the wait filled in, from the first.
     */
    keep_others :: fn(terminal: ptr[mut Terminal], packets: slop_os.Packet[], taken: usize) {
        for packet, i in packets {
            if i < taken && packet.key != 0 && packet.key != STOP_KEY && terminal.other_count < terminal.others.count {
                terminal.others[terminal.other_count] = packet
                terminal.other_count += 1
            }
        }
    }

    /**
     * Take a response the client received: an Input's events and text, which next_event gives from then on; any other
     * response is ignored.
     *
     * @param terminal The client, holding a Read that an Input answers; its events, text and next are replaced, and it
     *     holds no Read after.
     * @param into The response received, only read.
     */
    take_input :: fn(terminal: ptr[mut Terminal], into: ptr[os.Incoming]) {
        match os.message_of[protocol.Response](into)^ {
            case Input(given) => {
                terminal.reading = false
                terminal.next = 0
                terminal.event_count = 0
                terminal.text_count = 0
                for event, i in os.items(into, given.events) {
                    if i < terminal.events.count {
                        terminal.events[i] = event
                        terminal.event_count = i + 1
                    }
                }
                for byte, i in os.items(into, given.text) {
                    if i < terminal.text.count {
                        terminal.text[i] = byte
                        terminal.text_count = i + 1
                    }
                }
            }
            case _ => {}
        }
    }

    /**
     * Tell whether Ctrl-C has been pressed, without waiting: for a program busy with something else, like waiting for a
     * program it runs, that still wants to hear an Interrupt.
     *
     * A Read is held when no events are left, and an Input that's come is taken. An Interrupt among the events left is
     * taken with the events before it, as a terminal drops what's typed ahead of Ctrl-C; the events after it, and events
     * left without one, stay for next_event. While events are left no Read is held, so an Interrupt typed after them is
     * seen once they're used.
     *
     * @param terminal A client open made, used by one thread or fiber at a time; it's marked hung up if a request or its
     *     connection fails.
     * @return True if an Interrupt was taken; false if none has come, or the terminal's gone.
     */
    interrupted :: fn(terminal: ptr[mut Terminal]) -> bool {
        loop {
            if terminal.hung_up {
                return false
            }
            for i in terminal.next..<terminal.event_count {
                if i >= terminal.events.count {
                    break
                }
                match protocol.kind_of(terminal.events[i]) {
                    case Some(kind) => if kind == .Interrupt {
                        terminal.next = i + 1
                        return true
                    }
                    case None => {}
                }
            }
            if terminal.next < terminal.event_count {
                return false
            }
            if !terminal.reading {
                if !protocol.read(terminal.end, terminal.port) {
                    terminal.hung_up = true
                    return false
                }
                terminal.reading = true
            }
            into := os.Incoming.{}
            match protocol.receive_response(terminal.end, terminal.port, &into, false) {
                case Received => take_input(terminal, &into)
                case Failed(error) => {
                    terminal.hung_up = true
                    return false
                }
                case _ => return false
            }
        }
    }

    // ---- The line editor

    /* Keys, as their USB HID usages, which Key events carry */
    /** The A key's usage: Ctrl-A moves the cursor to the line's start. */
    USAGE_A : u16 : 0x04
    /** The E key's usage: Ctrl-E moves the cursor to the line's end. */
    USAGE_E : u16 : 0x08
    /** The K key's usage: Ctrl-K takes out what's after the cursor. */
    USAGE_K : u16 : 0x0e
    /** The U key's usage: Ctrl-U takes out what's before the cursor. */
    USAGE_U : u16 : 0x18
    /** The W key's usage: Ctrl-W takes out the word before the cursor. */
    USAGE_W : u16 : 0x1a
    /** The Enter key's usage, which ends the line. */
    USAGE_ENTER : u16 : 0x28
    /** The Escape key's usage, which the editor ignores. */
    USAGE_ESCAPE : u16 : 0x29
    /** The Backspace key's usage, which takes out the grapheme cluster before the cursor. */
    USAGE_BACKSPACE : u16 : 0x2a
    /** The Tab key's usage, which completes. */
    USAGE_TAB : u16 : 0x2b
    /** The Home key's usage, which moves the cursor to the line's start. */
    USAGE_HOME : u16 : 0x4a
    /** The Delete key's usage, which takes out the grapheme cluster at the cursor. */
    USAGE_DELETE : u16 : 0x4c
    /** The End key's usage, which moves the cursor to the line's end. */
    USAGE_END : u16 : 0x4d
    /** The Right Arrow key's usage, which moves the cursor a grapheme cluster on. */
    USAGE_RIGHT : u16 : 0x4f
    /** The Left Arrow key's usage, which moves the cursor a grapheme cluster back. */
    USAGE_LEFT : u16 : 0x50
    /** The Down Arrow key's usage, which goes to the next line of history. */
    USAGE_DOWN : u16 : 0x51
    /** The Up Arrow key's usage, which goes to the previous line of history. */
    USAGE_UP : u16 : 0x52

    /** The most lines history keeps; past it, the oldest is dropped. */
    MAX_HISTORY :: 200
    /** The most bytes a line has; what's typed or pasted past it is dropped. */
    MAX_LINE_BYTES :: 4096

    /**
     * A completion: the candidates for the text from start to the cursor, which it's replaced with.
     *
     * A completer fills one in for a line and its cursor; the editor frees it afterwards.
     */
    Completions :: struct {
        /** The byte offset in the line where the text being completed starts, at most the cursor. */
        start : usize,
        /**
         * What could replace the text from start to the cursor; empty when there's nothing to offer. Each string, and
         * the array, is allocated with context.allocator, and the editor frees them.
         */
        candidates : string[..],
        /**
         * What each candidate is, at its candidate's index, written beside it when they're listed; shorter than
         * candidates, or empty, for those without one. Allocated as candidates are, and freed by the editor.
         */
        descriptions : string[..],
    }

    /**
     * Fill in the completions for a line, called when Tab is pressed.
     *
     * @param data What the editor was given for it, as completer_data.
     * @param line The line being edited, UTF-8: a view of the editor's, good only during the call.
     * @param cursor The cursor, as a byte offset in line.
     * @param into The completions, empty to start with, to fill in; a start past the cursor is ignored.
     */
    Completer :: fn(data: rawptr, line: u8[], cursor: usize, into: ptr[mut Completions])

    /**
     * A line editor: the line being typed and its cursor, history, and a completer, if there's one.
     *
     * Its zero value is ready to use, with no history and no completer. free_editor gives back what it allocates, all
     * with context.allocator.
     */
    LineEditor :: struct {
        /** The line being typed, UTF-8, at most MAX_LINE_BYTES. */
        line : u8[..],
        /** The cursor, as a byte offset in line at a grapheme cluster's start, from 0 to line.count. */
        cursor : usize,
        /** Lines entered, oldest first, at most MAX_HISTORY; each one the editor's own. */
        history : string[..],
        /**
         * While Up and Down go through history, the index in history of the line shown; history.count for the typed
         * one.
         */
        browsing : usize,
        /** The line typed before Up first went into history, to come back to with Down. */
        typed : u8[..],
        /** What fills in completions when Tab is pressed; null to have Tab do nothing. set_completer sets it. */
        completer : Completer?,
        /** What the completer is given as its data. */
        completer_data : rawptr,
        /**
         * Whether a line's being typed that read_line gave back Other in the middle of, so the next read_line goes on
         * with it rather than starting a new one.
         */
        pending : bool,
    }

    /**
     * Give an editor a completer over data of its own type, so a program needn't hold its data as a rawptr.
     *
     * @tparam D The data's type.
     * @param editor The editor, whose completer and completer_data are replaced.
     * @param completer What fills in completions when Tab is pressed, given data, the line, the cursor and the
     *     completions to fill in, as Completer is.
     * @param data What completer is given, kept by the editor, so it has to live as long as the editor's used.
     */
    set_completer :: fn[D](editor: ptr[mut LineEditor], completer: (fn(data: ptr[mut D], line: u8[], cursor: usize, into: ptr[mut Completions])),
        data #escaping : ptr[mut D]) {
        editor.completer = bit_cast[Completer](completer)
        editor.completer_data = cast[rawptr](data)
    }

    /** What read_line gives. */
    LineResult :: union {
        /** A line entered, without its line break, allocated with context.allocator: the caller's to free. */
        Line(string),
        /** Ctrl-C: the line dropped. */
        Interrupted,
        /** The terminal's gone. */
        HangUp,
        /** The program was asked to stop on its lifecycle channel. */
        Stop,
        /**
         * A packet under a key of the program's own on the terminal client's port (next_event's Other), given back in
         * the middle of the line, which the next read_line goes on with.
         */
        Other(slop_os.Packet),
    }

    /**
     * Read a line, edited as it's typed: shown after prompt as the terminal's input line.
     *
     * Left and Right move a grapheme cluster, Home and End (or Ctrl-A, Ctrl-E) to the ends; Backspace and Delete take
     * one out, Ctrl-U and Ctrl-K what's before or after the cursor, Ctrl-W the word before it; Up and Down go through
     * history; Tab completes; Enter ends the line, which is written after the prompt, as typed, and kept in history;
     * Ctrl-C drops it. A paste's line breaks and tabs become spaces, so a paste never ends the line.
     *
     * @param editor The editor, whose line is emptied to start, unless the last read_line gave back Other, when it goes
     *     on with that line where it was; its history is kept from call to call.
     * @param terminal The client to read from and show the line on.
     * @param prompt What's shown before the line, UTF-8.
     * @return The line, Interrupted for Ctrl-C, HangUp once the terminal's gone, Stop once the program's asked to stop,
     *     or Other for a packet of the program's on the client's port, the line still shown, to go on with. A line that
     *     couldn't be copied for lack of memory comes back empty.
     */
    read_line :: fn(editor: ptr[mut LineEditor], terminal: ptr[mut Terminal], prompt: string) -> LineResult {
        if !editor.pending {
            runtime.array_reset(&editor.line)
            editor.cursor = 0
            editor.browsing = editor.history.count
        }
        editor.pending = false
        show(editor, terminal, prompt)
        loop {
            match next_event(terminal) {
                case HangUp => return .HangUp
                case Stop => return .Stop
                case Other(packet) => {
                    editor.pending = true
                    return .Other(packet)
                }
                case Event(event, text) => {
                    kind :: protocol.kind_of(event) or_continue
                    if kind == .Interrupt {
                        _ = show_input(terminal, u8.[], 0)
                        _ = write(terminal, prompt)
                        _ = write(terminal, as_text(editor.line))
                        _ = write_line(terminal, "^C")
                        return .Interrupted
                    }
                    if kind == .HangUp {
                        return .HangUp
                    }
                    if kind == .Paste {
                        for byte in text {
                            // A pasted line break is a space: a paste never runs a command
                            insert(editor, if byte == 0x0a || byte == 0x0d || byte == 0x09 { u8.[0x20] } else { u8.[byte] })
                        }
                    }
                    else if kind == .Key {
                        if key(editor, terminal, event, text) {
                            _ = show_input(terminal, u8.[], 0)
                            _ = write(terminal, prompt)
                            _ = write_line(terminal, as_text(editor.line))
                            remember(editor)
                            return .Line(copy_text(editor.line))
                        }
                    }
                    show(editor, terminal, prompt)
                }
            }
        }
    }

    /**
     * Act on one key: move the cursor, edit the line, go through history, complete, or type what it carries.
     *
     * @param editor An editor read_line is reading with, its cursor at a grapheme cluster's start; its line, cursor and
     *     place in history change as the key says.
     * @param terminal The client, for completion's candidates.
     * @param event The Key event. With Ctrl or Alt held, a key without a binding types nothing.
     * @param text The bytes the key types; control characters among them are dropped.
     * @return True if it was Enter, ending the line; false otherwise.
     */
    key :: fn(editor: ptr[mut LineEditor], terminal: ptr[mut Terminal], event: protocol.Event, text: u8[]) -> bool {
        control :: event.modifiers & protocol.CONTROL != 0
        code :: event.code
        if code == USAGE_ENTER {
            return true
        }
        if code == USAGE_LEFT {
            editor.cursor = previous_cluster(editor.line, editor.cursor)
        }
        else if code == USAGE_RIGHT {
            editor.cursor = next_cluster(editor.line, editor.cursor)
        }
        else if code == USAGE_HOME || (control && code == USAGE_A) {
            editor.cursor = 0
        }
        else if code == USAGE_END || (control && code == USAGE_E) {
            editor.cursor = editor.line.count
        }
        else if code == USAGE_BACKSPACE {
            start :: previous_cluster(editor.line, editor.cursor)
            remove(editor, start, editor.cursor)
            editor.cursor = start
        }
        else if code == USAGE_DELETE {
            remove(editor, editor.cursor, next_cluster(editor.line, editor.cursor))
        }
        else if control && code == USAGE_U {
            remove(editor, 0, editor.cursor)
            editor.cursor = 0
        }
        else if control && code == USAGE_K {
            remove(editor, editor.cursor, editor.line.count)
        }
        else if control && code == USAGE_W {
            start := editor.cursor
            loop {
                if start == 0 || start > editor.line.count || editor.line[start - 1] != cast[u8](' ') {
                    break
                }
                start -= 1
            }
            loop {
                if start == 0 || start > editor.line.count || editor.line[start - 1] == cast[u8](' ') {
                    break
                }
                start -= 1
            }
            remove(editor, start, editor.cursor)
            editor.cursor = start
        }
        else if code == USAGE_UP {
            through_history(editor, true)
        }
        else if code == USAGE_DOWN {
            through_history(editor, false)
        }
        else if code == USAGE_TAB {
            complete(editor, terminal)
        }
        else if !control && event.modifiers & protocol.ALT == 0 {
            // What it types, but for controls
            for byte in text {
                if byte >= 0x20 && byte != 0x7f {
                    insert(editor, u8.[byte])
                }
            }
        }
        return false
    }

    /**
     * Put bytes in at the cursor, which moves past them.
     *
     * @param editor An editor whose cursor is from 0 to its line's count; its line grows by what's put in, with
     *     context.allocator, and the cursor moves past it.
     * @param bytes The bytes; those that would take the line past MAX_LINE_BYTES are dropped.
     */
    insert :: fn(editor: ptr[mut LineEditor], bytes: u8[]) {
        for byte in bytes {
            if editor.line.count >= MAX_LINE_BYTES {
                return void
            }
            runtime.array_add(&editor.line, byte)
            // Moved along to make room at the cursor
            at := editor.line.count - 1
            loop {
                if at <= editor.cursor || at >= editor.line.count {
                    break
                }
                editor.line[at] = editor.line[at - 1]
                at -= 1
            }
            if editor.cursor < editor.line.count {
                editor.line[editor.cursor] = byte
            }
            editor.cursor += 1
        }
    }

    /**
     * Take bytes out of the line, keeping the cursor inside it.
     *
     * @param editor An editor whose line loses the bytes from start to end; its cursor isn't moved, unless it's then
     *     past the line's end, when it goes to the end.
     * @param start The byte offset of the first to take out.
     * @param end The byte offset past the last. Nothing happens when it isn't past start, or is past the line's end.
     */
    remove :: fn(editor: ptr[mut LineEditor], start: usize, end: usize) {
        if start >= end || end > editor.line.count {
            return void
        }
        gap :: end - start
        for i in start..<(editor.line.count - gap) {
            from :: i + gap
            if i < editor.line.count && from < editor.line.count {
                editor.line[i] = editor.line[from]
            }
        }
        runtime.resizable(&editor.line).count = editor.line.count - gap
        if editor.cursor > editor.line.count {
            editor.cursor = editor.line.count
        }
    }

    /**
     * Show the previous or next line of history in place of the one typed, which is kept to come back to.
     *
     * The cursor goes to the line's end. Nothing happens past either end of history.
     *
     * @param editor An editor read_line is reading with. Its line is replaced and its cursor goes to the end; the line
     *     typed is kept in typed when Up first leaves it.
     * @param back True for the previous (older) line, false for the next, ending at the line typed.
     */
    through_history :: fn(editor: ptr[mut LineEditor], back: bool) {
        if back {
            if editor.browsing == 0 {
                return void
            }
            if editor.browsing == editor.history.count {
                runtime.array_reset(&editor.typed)
                for byte in editor.line {
                    runtime.array_add(&editor.typed, byte)
                }
            }
            editor.browsing -= 1
        }
        else {
            if editor.browsing >= editor.history.count {
                return void
            }
            editor.browsing += 1
        }
        runtime.array_reset(&editor.line)
        source :: if editor.browsing < editor.history.count { string_bytes(editor.history[editor.browsing]) } else { editor.typed[0..<editor.typed.count] }
        for byte in source {
            runtime.array_add(&editor.line, byte)
        }
        editor.cursor = editor.line.count
    }

    /**
     * Complete the text before the cursor, for Tab, with the completer's candidates.
     *
     * One candidate is put in its place, with a space after it unless it ends with /, so what's typed next starts the
     * next word, and a directory's path goes on into its entries; several put in what they all start with, or if that's
     * nothing more than what's typed, are written above the line, one a line, each with its description after it, the
     * descriptions lined up two columns past the widest candidate. Without a completer, or with no candidates, nothing
     * happens.
     *
     * @param editor An editor read_line is reading with, which calls its completer, if it has one; the text from the
     *     completion's start to the cursor may be replaced, the cursor moving past what's put in.
     * @param terminal The client, where the candidates are written.
     */
    complete :: fn(editor: ptr[mut LineEditor], terminal: ptr[mut Terminal]) {
        completer :: editor.completer or_return void
        found := Completions.{}
        defer free_completions(&found)
        completer(editor.completer_data, editor.line[0..<editor.line.count], editor.cursor, &found)
        if found.candidates.count == 0 || found.start > editor.cursor {
            return void
        }
        shared := string_bytes(found.candidates[0])
        for candidate in found.candidates {
            bytes :: string_bytes(candidate)
            common : usize = 0
            loop {
                if common >= shared.count || common >= bytes.count || shared[common] != bytes[common] {
                    break
                }
                common += 1
            }
            shared = shared[0..<common]
        }
        typed :: editor.cursor - found.start
        if shared.count > typed || found.candidates.count == 1 {
            remove(editor, found.start, editor.cursor)
            editor.cursor = found.start
            insert(editor, shared)
            if found.candidates.count == 1 && (shared.count == 0 || shared[shared.count - 1] != cast[u8]('/')) {
                insert(editor, u8.[0x20])
            }
            return void
        }
        // Nothing more they share: they're shown, each with its description
        _ = show_input(terminal, u8.[], 0)
        widest : usize = 0
        for candidate in found.candidates {
            width :: unicode.text_width(string_bytes(candidate))
            widest = if width > widest { width } else { widest }
        }
        for candidate, i in found.candidates {
            description :: if i < found.descriptions.count { found.descriptions[i] } else { "" }
            if description.count == 0 {
                _ = write_line(terminal, candidate)
                continue
            }
            shown : u8[..]
            defer runtime.array_free(&shown)
            for byte in string_bytes(candidate) {
                runtime.array_add(&shown, byte)
            }
            for column in unicode.text_width(string_bytes(candidate))..<widest + 2 {
                runtime.array_add(&shown, cast[u8](' '))
            }
            for byte in string_bytes(description) {
                runtime.array_add(&shown, byte)
            }
            _ = write_line(terminal, as_text(shown))
        }
    }

    /**
     * Free a completer's candidates and descriptions, each one's text and the arrays.
     *
     * @param found The completions, filled in by a completer with context.allocator; its candidates and descriptions
     *     are empty afterwards.
     */
    free_completions :: fn(found: ptr[mut Completions]) {
        for candidate in found.candidates {
            runtime.free_array(bit_cast[u8[]](candidate))
        }
        runtime.array_free(&found.candidates)
        for description in found.descriptions {
            runtime.free_array(bit_cast[u8[]](description))
        }
        runtime.array_free(&found.descriptions)
    }

    /**
     * Keep the line just ended in history, unless it's empty or the same as the newest.
     *
     * The oldest line is dropped once there are MAX_HISTORY. The line is copied with context.allocator; if that fails,
     * an empty line is kept.
     *
     * @param editor An editor whose line was just ended; the line isn't changed, and a copy of it may be added to its
     *     history, which may drop its oldest.
     */
    remember :: fn(editor: ptr[mut LineEditor]) {
        if editor.line.count == 0 {
            return void
        }
        newest := ""
        for each in editor.history {
            newest = each
        }
        if editor.history.count > 0 && as_text(editor.line) == newest {
            return void
        }
        if editor.history.count >= MAX_HISTORY {
            runtime.free_array(bit_cast[u8[]](editor.history[0]))
            runtime.array_remove(&editor.history, 0)
        }
        runtime.array_add(&editor.history, copy_text(editor.line))
    }

    /**
     * Draw the input line: the prompt, then the line, the cursor in it.
     *
     * @param editor An editor whose line and cursor are drawn; it isn't changed.
     * @param terminal A client open made, whose input line is replaced with this one.
     * @param prompt What's shown before the line, UTF-8.
     */
    show :: fn(editor: ptr[mut LineEditor], terminal: ptr[mut Terminal], prompt: string) {
        shown : u8[..]
        defer runtime.array_free(&shown)
        for byte in string_bytes(prompt) {
            runtime.array_add(&shown, byte)
        }
        for byte in editor.line {
            runtime.array_add(&shown, byte)
        }
        _ = show_input(terminal, shown[0..<shown.count], prompt.count + editor.cursor)
    }

    /**
     * Free what an editor allocated: its line, and its history's.
     *
     * @param editor The editor, empty afterwards and ready to use again. Its completer isn't touched.
     */
    free_editor :: fn(editor: ptr[mut LineEditor]) {
        runtime.array_free(&editor.line)
        runtime.array_free(&editor.typed)
        for line in editor.history {
            runtime.free_array(bit_cast[u8[]](line))
        }
        runtime.array_free(&editor.history)
    }

    /**
     * Copy bytes into a new string.
     *
     * @param bytes The bytes to copy, UTF-8 or not; read and not kept.
     * @return The copy, allocated with context.allocator and the caller's to free; empty, allocating nothing, for no
     *     bytes or when there's no memory.
     */
    copy_text :: fn(bytes: u8[..]) -> string {
        made, error :: runtime.new_array(u8, bytes.count)
        if error != null {
            return ""
        }
        for byte, i in bytes {
            if i < made.count {
                made[i] = byte
            }
        }
        return if made.count > 0 { string_of(&made[0], made.count) } else { "" }
    }

    /**
     * View bytes as a string, without copying them.
     *
     * @param bytes The bytes to view, UTF-8 or not, which the string shares.
     * @return A string over the same bytes, good while they are and the array isn't resized; empty for no bytes.
     */
    as_text :: fn(bytes: u8[..]) -> string {
        return if bytes.count > 0 { string_of(&bytes[0], bytes.count) } else { "" }
    }
}

/**
 * Find where the grapheme cluster before an offset starts.
 *
 * @param line The text, UTF-8 or not.
 * @param at A byte offset in line at a cluster's start, or line.count.
 * @return The byte offset where the cluster ending at at starts; 0 when at is 0 or past the line's end.
 */
previous_cluster :: fn(line: u8[], at: usize) -> usize {
    if at == 0 || at > line.count {
        return 0
    }
    last : usize = 0
    position : usize = 0
    loop {
        end :: unicode.grapheme_end(line, position)
        if end <= position || end >= at {
            break
        }
        last = end
        position = end
    }
    return last
}

/**
 * Find where the grapheme cluster at an offset ends.
 *
 * @param line The text, UTF-8 or not.
 * @param at A byte offset in line at a cluster's start.
 * @return The byte offset just past the cluster; line.count when at is at or past the line's end.
 */
next_cluster :: fn(line: u8[], at: usize) -> usize {
    if at >= line.count {
        return line.count
    }
    end :: unicode.grapheme_end(line, at)
    return if end > at && end <= line.count { end } else { line.count }
}
