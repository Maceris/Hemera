package terminal

// The protocol's plain types, on every OS, so code that turns them into something else can be tested hosted (as the SlopOS repository's VT adapter is)

// The most bytes of text, and runs, one Text has.
MAX_TEXT_BYTES :: 2048
MAX_RUNS :: 64
// The most events, and bytes of their text, one Events has.
MAX_EVENTS :: 32
MAX_EVENT_TEXT :: 1024

ColorKind :: enum #backed_by(u8) {
    // The terminal's own foreground or background
    Default = 0,
    // index into the terminal's palette: 0 to 7 the ANSI colours, 8 to 15 their bright ones, up to 255
    Palette = 1,
    // red, green and blue
    Rgb = 2,
}

// Plain data, as a Relative's elements are: kind a ColorKind's value (palette, rgb and color_kind make and read them)
Color :: struct {
    kind : u8,
    index : u8,
    red : u8,
    green : u8,
    blue : u8,
}

// The palette's colour index.
palette :: fn(index: u8) -> Color {
    return Color.{kind = cast[u8](ColorKind.Palette), index = index}
}

rgb :: fn(red: u8, green: u8, blue: u8) -> Color {
    return Color.{kind = cast[u8](ColorKind.Rgb), red = red, green = green, blue = blue}
}

// What a colour is; a kind this version hasn't is the default.
color_kind :: fn(color: Color) -> ColorKind {
    return match color.kind {
        case 1 => ColorKind.Palette
        case 2 => ColorKind.Rgb
        case _ => ColorKind.Default
    }
}

// A Style's attributes, as bits.
BOLD : u8 : 1
DIM : u8 : 2
ITALIC : u8 : 4
UNDERLINE : u8 : 8
INVERSE : u8 : 16
STRIKETHROUGH : u8 : 32

Style :: struct {
    foreground : Color,
    background : Color,
    attributes : u8,
}

/*
 * A run of a Text: its next bytes, in style, and a link's target, a range of the Text's links bytes (none where
 * link_bytes is 0).
 */
Run :: struct {
    bytes : u32,
    style : Style,
    link_start : u32,
    link_bytes : u32,
}

// A place on the screen, from 0, in columns and rows.
Position :: struct {
    column : u16,
    row : u16,
}

// A rectangle of the screen.
Area :: struct {
    column : u16,
    row : u16,
    columns : u16,
    rows : u16,
}

// An area's rows moved up by lines, or down when lines is negative, the rows left behind cleared.
ScrollArea :: struct {
    area : Area,
    lines : i16,
}

ColorSupport :: enum #backed_by(u8) {
    None = 0,
    Palette16 = 1,
    Palette256 = 2,
    Rgb = 3,
}

// What a terminal can show, in place of terminfo.
Features :: struct {
    columns : u16,
    rows : u16,
    colors : ColorSupport,
    // The Style attributes it shows
    attributes : u8,
    links : bool,
    // The Unicode version its widths come from, as major * 256 + minor
    unicode : u16,
}

// A key's modifiers, as bits.
SHIFT : u8 : 1
CONTROL : u8 : 2
ALT : u8 : 4
META : u8 : 8

EventKind :: enum #backed_by(u8) {
    // code: the key's USB HID usage (page 7), 0 where only its text is known; modifiers; the text it types, if any
    Key = 1,
    // text: what was pasted, as one event, never as keys
    Paste = 2,
    // columns and rows: the terminal's new size
    Resize = 3,
    // focused: whether the terminal is now the one being looked at
    Focus = 4,
    // Ctrl-C, for the terminal's owner to decide what to stop
    Interrupt = 5,
    // The terminal is gone: nothing more will be shown or typed
    HangUp = 6,
}

/*
 * One event; its text is a range of its Events's text. Plain data, as a Relative's elements are: kind an EventKind's
 * value and focused 1 or 0 (event_of and kind_of make and read them).
 */
Event :: struct {
    kind : u8,
    modifiers : u8,
    focused : u8,
    code : u16,
    columns : u16,
    rows : u16,
    text_start : u32,
    text_bytes : u32,
}

// An event of kind, with nothing else set.
event_of :: fn(kind: EventKind) -> Event {
    return Event.{kind = cast[u8](kind)}
}

// What an event is, or null for a kind this version hasn't.
kind_of :: fn(event: Event) -> EventKind? {
    return match event.kind {
        case 1 => EventKind.Key
        case 2 => EventKind.Paste
        case 3 => EventKind.Resize
        case 4 => EventKind.Focus
        case 5 => EventKind.Interrupt
        case 6 => EventKind.HangUp
        case _ => null
    }
}

// Only for SlopOS, where std/os has what its generated code needs, as std/os/slop_os's file does
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import unicode from "std"

    /*
     * A terminal (the SlopOS repository's decisions 0136): text and operations as separate messages, so text is never
     * read for control sequences, and input as typed events. Text goes where the cursor is, in styled runs, and a line
     * break is the only character in it that does anything: anything else that doesn't show is shown as a visible
     * substitute. A program that draws its whole screen asks for one with Screen, and moves the cursor and clears in it.
     *
     * The program reading input can hand the terminal the line it's editing (InputLine), which the terminal keeps below
     * everything written, by any client, and draws again after it, with the cursor where the program says: output that
     * comes while a line's being typed goes above it, as a shell's line editor does. An empty one takes it away; the
     * program writes the line itself once it's done with it, if it wants it kept.
     *
     * Output isn't answered. Describe is answered with Described; Read is held until there's input, then answered with
     * Events. Connections arrive on the terminal service's listener as Connects.
     */
    Terminal :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "terminal", major_version = 1, lending = .Server}

    // UTF-8 text in runs, which cover it from its start; bytes the runs don't reach take the last run's style.
    Text :: struct {
        text : slop_os.Relative[u8],
        runs : slop_os.Relative[Run],
        links : slop_os.Relative[u8],
    }

    Events :: struct {
        events : slop_os.Relative[Event],
        text : slop_os.Relative[u8],
    }

    // The line being edited, UTF-8, shown plain, and the cursor in it, as a byte offset at a cluster's start.
    InputLine :: struct {
        text : slop_os.Relative[u8],
        cursor : u32,
    }

    Request :: union {
        Write(Text),
        // The cursor, in the screen Screen gave; in lines, its column on the line being written
        MoveCursor(Position),
        ShowCursor(bool),
        // The area made blank, in the default style
        Clear(Area),
        Scroll(ScrollArea),
        /*
         * A screen of the program's own, the terminal's size and blank, for a program that draws everything (true), or
         * back to lines that scroll, as they were (false)
         */
        Screen(bool),
        Bell,
        Describe,
        // Input, as many events as this at most; held until there's some
        Read(u32),
        // The line the reader's editing, kept below what's written; ignored from a client that isn't reading input
        InputLine(InputLine),
        // Serve another client, on its end
        Connect(os.Channel[Terminal]),
    }

    Response :: union {
        Described(Features),
        Input(Events),
        Unsupported,
    }

    // Output shown again is shown twice; a Describe or a Connect asked again changes nothing more.
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case Write(_) => false
            case MoveCursor(_) => true
            case ShowCursor(_) => true
            case Clear(_) => true
            case Scroll(_) => false
            case Screen(_) => true
            case Bell => false
            case Describe => true
            case Read(_) => false
            case InputLine(_) => true
            case Connect(_) => true
        }
    }

    #insert os.protocol_code(Request, Response)

    // A new connection to the terminal service listening on end, or null (as std/os/slop_os's others).
    connect :: fn(end: slop_os.Channel, port: slop_os.Port, budget: slop_os.MemoryBudget) -> os.Channel[Terminal]? {
        pair :: os.channel_for[Terminal](budget, 0) or_return null
        out := os.Outgoing.{}
        request :: os.begin[Request](&out)
        request^ = .Connect(os.Channel[Terminal].{end = pair.a})
        match send_request(end, port, &out) {
            case Some(error) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.a))
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.b))
                return null
            }
            case None => return os.Channel[Terminal].{end = pair.b}
        }
    }

    /*
     * text, in style, on the terminal at end, in as many Writes as it takes, each ending where a grapheme cluster does;
     * whether every one went.
     */
    write :: fn(end: slop_os.Channel, port: slop_os.Port, text: string, style := Style.{}) -> bool {
        bytes :: string_bytes(text)
        at : usize = 0
        loop {
            // As much as fits, cut back to a cluster's end, unless one cluster is longer than a message
            last := if bytes.count - at > MAX_TEXT_BYTES { at + MAX_TEXT_BYTES } else { bytes.count }
            if last < bytes.count {
                fitting := at
                loop {
                    next :: unicode.grapheme_end(bytes, fitting)
                    if next > last || next <= fitting {
                        break
                    }
                    fitting = next
                }
                if fitting > at {
                    last = fitting
                }
            }
            if last < at || last > bytes.count {
                return false
            }
            if !write_run(end, port, bytes[at..<last], style) {
                return false
            }
            at = last
        }
        while at < bytes.count
        return true
    }

    // bytes, one run in style, as one Write.
    write_run :: fn(end: slop_os.Channel, port: slop_os.Port, bytes: u8[], style: Style) -> bool {
        out := os.Outgoing.{}
        request :: os.begin[Request](&out)
        run :: Run.[Run.{bytes = cast[u32](bytes.count), style = style}]
        empty : u8[0]
        request^ = .Write(Text.{text = os.append(&out, bytes), runs = os.append(&out, run), links = os.append(&out, empty)})
        return send_request(end, port, &out) == null
    }

    // text then a line break, as write.
    write_line :: fn(end: slop_os.Channel, port: slop_os.Port, text: string, style := Style.{}) -> bool {
        return write(end, port, text, style) && write(end, port, "\n", style)
    }

    // One request with no data, sent; whether it went.
    send :: fn(end: slop_os.Channel, port: slop_os.Port, request: Request) -> bool {
        out := os.Outgoing.{}
        os.begin[Request](&out)^ = request
        return send_request(end, port, &out) == null
    }

    // The line being edited, with the cursor at a byte offset in it, handed to the terminal; whether it went.
    input_line :: fn(end: slop_os.Channel, port: slop_os.Port, text: u8[], cursor: usize) -> bool {
        out := os.Outgoing.{}
        request :: os.begin[Request](&out)
        request^ = .InputLine(InputLine.{text = os.append(&out, text), cursor = cast[u32](cursor)})
        return send_request(end, port, &out) == null
    }

    // A Read held for up to most events.
    read :: fn(end: slop_os.Channel, port: slop_os.Port, most: u32 = MAX_EVENTS) -> bool {
        return send(end, port, .Read(most))
    }
}
