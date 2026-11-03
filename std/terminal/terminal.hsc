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

    /** The port key a stop's asked for on, beside the terminal's binding */
    STOP_KEY : u64 : 1

    Terminal :: struct {
        end : slop_os.Channel,
        port : slop_os.Port,
        // The events the last Input brought, and their text, read from next
        events : protocol.Event[protocol.MAX_EVENTS],
        event_count : usize,
        next : usize,
        text : u8[protocol.MAX_EVENT_TEXT],
        text_count : usize,
        /** Whether a Read is held */
        reading : bool,
        /** Whether it's gone, or asked to stop */
        hung_up : bool,
    }

    /** What next_event gives: an event and its text, or why there's none. */
    Input :: union {
        Event(protocol.Event, u8[]),
        /** The terminal's gone */
        HangUp,
        /** The program was asked to stop on its lifecycle channel */
        Stop,
    }

    /** A terminal client on a connection, its port made and a stop asked to wake it. */
    open :: fn(connection: os.Channel[protocol.Terminal]) -> Terminal? {
        made := Terminal.{end = connection.end}
        made.port = os.port_for(slop_os.startup_block().budget, connection.end) or_return null
        _ = lifecycle.on_stop(made.port, STOP_KEY)
        return made
    }

    write :: fn(terminal: ptr[mut Terminal], text: string, style := protocol.Style.{}) -> bool {
        return protocol.write(terminal.end, terminal.port, text, style)
    }

    write_line :: fn(terminal: ptr[mut Terminal], text: string, style := protocol.Style.{}) -> bool {
        return protocol.write(terminal.end, terminal.port, text, style) && protocol.write(terminal.end, terminal.port, "\n")
    }

    /** The line being edited, below what's written, the cursor a byte offset in it. */
    show_input :: fn(terminal: ptr[mut Terminal], text: u8[], cursor: usize) -> bool {
        return protocol.input_line(terminal.end, terminal.port, text, cursor)
    }

    /**
     * The next event, waited for: its text is the terminal's until the next call. A Read is held for more once what came
     * is used up; HangUp once the terminal's gone, Stop once the program's asked to stop.
     */
    next_event :: fn(terminal: ptr[mut Terminal]) -> Input {
        loop {
            if terminal.hung_up {
                return .HangUp
            }
            if lifecycle.stop_requested() {
                return .Stop
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
                    packets : slop_os.Packet[4]
                    _ = slop_os.port_wait(terminal.port, packets, slop_os.NO_DEADLINE)
                    continue
                }
                case Failed(error) => {
                    terminal.hung_up = true
                    continue
                }
                case _ => continue
            }
            match os.message_of[protocol.Response](&into)^ {
                case Input(given) => {
                    terminal.reading = false
                    terminal.next = 0
                    terminal.event_count = 0
                    terminal.text_count = 0
                    for event, i in os.items(&into, given.events) {
                        if i < terminal.events.count {
                            terminal.events[i] = event
                            terminal.event_count = i + 1
                        }
                    }
                    for byte, i in os.items(&into, given.text) {
                        if i < terminal.text.count {
                            terminal.text[i] = byte
                            terminal.text_count = i + 1
                        }
                    }
                }
                case _ => {}
            }
        }
    }

    // ---- The line editor

    // Keys, as their USB HID usages, which Key events carry
    USAGE_A : u16 : 0x04
    USAGE_E : u16 : 0x08
    USAGE_K : u16 : 0x0e
    USAGE_U : u16 : 0x18
    USAGE_W : u16 : 0x1a
    USAGE_ENTER : u16 : 0x28
    USAGE_ESCAPE : u16 : 0x29
    USAGE_BACKSPACE : u16 : 0x2a
    USAGE_TAB : u16 : 0x2b
    USAGE_HOME : u16 : 0x4a
    USAGE_DELETE : u16 : 0x4c
    USAGE_END : u16 : 0x4d
    USAGE_RIGHT : u16 : 0x4f
    USAGE_LEFT : u16 : 0x50
    USAGE_DOWN : u16 : 0x51
    USAGE_UP : u16 : 0x52

    // The most lines history keeps, and the most bytes a line has
    MAX_HISTORY :: 200
    MAX_LINE_BYTES :: 4096

    /**
     * A completion: the candidates for the text from start to the cursor, which it's replaced with. A completer fills
     * one in for a line and its cursor; data is what the editor was given for it.
     */
    Completions :: struct {
        start : usize,
        candidates : string[..],
    }

    Completer :: fn(data: rawptr, line: u8[], cursor: usize, into: ptr[mut Completions])

    /**
     * A line editor: the line being typed and the cursor in it, as a byte offset at a grapheme cluster's start; history,
     * oldest first, its lines the editor's own; and a completer, if there's one.
     */
    LineEditor :: struct {
        line : u8[..],
        cursor : usize,
        history : string[..],
        // While Up and Down go through history: the line it's at, and the line typed before them
        browsing : usize,
        typed : u8[..],
        completer : Completer?,
        completer_data : rawptr,
    }

    /** What read_line gives. */
    LineResult :: union {
        /** A line, the caller's to free */
        Line(string),
        /** Ctrl-C: the line dropped */
        Interrupted,
        HangUp,
        Stop,
    }

    /**
     * A line read, edited as it's typed: shown after prompt as the terminal's input line. Left and Right move a grapheme
     * cluster, Home and End (or Ctrl-A, Ctrl-E) to the ends; Backspace and Delete take one out, Ctrl-U and Ctrl-K what's
     * before or after the cursor, Ctrl-W the word before it; Up and Down go through history; Tab completes; Enter ends
     * the line, which is written after the prompt, as typed, and kept in history; Ctrl-C drops it.
     */
    read_line :: fn(editor: ptr[mut LineEditor], terminal: ptr[mut Terminal], prompt: string) -> LineResult {
        runtime.array_reset(&editor.line)
        editor.cursor = 0
        editor.browsing = editor.history.count
        show(editor, terminal, prompt)
        loop {
            match next_event(terminal) {
                case HangUp => return .HangUp
                case Stop => return .Stop
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

    /** One key: whether it ended the line. */
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

    /** bytes put in at the cursor, which moves past them. */
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

    /** The bytes from start to end taken out. */
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

    /** The previous or next line of history in place of the one typed, which is kept to come back to. */
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
     * Tab: the completer's candidates for the text before the cursor; one is put in its place, several put in what they
     * all start with, or if that's nothing more, are written above the line.
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
            return void
        }
        // Nothing more they share: they're shown
        _ = show_input(terminal, u8.[], 0)
        for candidate in found.candidates {
            _ = write_line(terminal, candidate)
        }
    }

    free_completions :: fn(found: ptr[mut Completions]) {
        for candidate in found.candidates {
            runtime.free_array(bit_cast[u8[]](candidate))
        }
        runtime.array_free(&found.candidates)
    }

    /** A line ended kept in history, unless it's empty or the same as the last; the oldest dropped past MAX_HISTORY. */
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

    /** The input line drawn: the prompt, then the line, the cursor in it. */
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

    /** The line's free, and its history's. */
    free_editor :: fn(editor: ptr[mut LineEditor]) {
        runtime.array_free(&editor.line)
        runtime.array_free(&editor.typed)
        for line in editor.history {
            runtime.free_array(bit_cast[u8[]](line))
        }
        runtime.array_free(&editor.history)
    }

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

    as_text :: fn(bytes: u8[..]) -> string {
        return if bytes.count > 0 { string_of(&bytes[0], bytes.count) } else { "" }
    }
}

/** Where the grapheme cluster before at starts, or 0. */
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

/** Where the grapheme cluster at at ends, or at at the line's end. */
next_cluster :: fn(line: u8[], at: usize) -> usize {
    if at >= line.count {
        return line.count
    }
    end :: unicode.grapheme_end(line, at)
    return if end > at && end <= line.count { end } else { line.count }
}
