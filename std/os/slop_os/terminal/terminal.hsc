package terminal

import os from "std"
import slop_os from "std/os"
import unicode from "std"

/*
 * The protocol's plain types, on every OS, so code that turns them into something else can be tested hosted (as the
 * SlopOS repository's VT adapter is).
 */

/** The most bytes of text one Text has; write splits longer text into several. */
MAX_TEXT_BYTES :: 2048
/**
 * The ring every terminal connection is made with, 8 KiB, so a Write of MAX_TEXT_BYTES, with its runs and links, fits
 * a message, which is at most half the ring; the default ring's 1 KiB takes under 500 bytes, and a longer Write isn't
 * sent at all.
 */
RING_BYTES : u32 : 8192
/** The most runs one Text has. */
MAX_RUNS :: 64
/** The most events one Events has, and read's default for how many to ask for. */
MAX_EVENTS :: 32
/** The most bytes of text, for all its events together, one Events has. */
MAX_EVENT_TEXT :: 1024

/** What a Color is, as its kind says. */
ColorKind :: enum #backed_by(u8) {
    /** The terminal's own foreground or background, whichever the Color is used as. */
    Default = 0,
    /** The Color's index into the terminal's palette: 0 to 7 the ANSI colours, 8 to 15 their bright ones, up to 255. */
    Palette = 1,
    /** The Color's red, green and blue. */
    Rgb = 2,
}

/**
 * A colour of text or of its background.
 *
 * It's plain data, as a Relative's elements are, so its kind is a ColorKind's value as a u8; palette, rgb and
 * color_kind make and read them. The zero Color is the default.
 */
Color :: struct {
    /** A ColorKind's value; one this version doesn't know is read as Default. */
    kind : u8,
    /** The palette's index, 0 to 255, for a Palette colour; unused otherwise. */
    index : u8,
    /** The red component, 0 to 255, for an Rgb colour; unused otherwise. */
    red : u8,
    /** The green component, 0 to 255, for an Rgb colour; unused otherwise. */
    green : u8,
    /** The blue component, 0 to 255, for an Rgb colour; unused otherwise. */
    blue : u8,
}

/**
 * Make a colour from the terminal's palette.
 *
 * @param index The palette's index: 0 to 7 the ANSI colours, 8 to 15 their bright ones, up to 255; how many a
 *     terminal shows, its Features.colors says.
 * @return A Palette colour.
 */
palette :: fn(index: u8) -> Color {
    return Color.{kind = cast[u8](ColorKind.Palette), index = index}
}

/**
 * Make a colour from its red, green and blue.
 *
 * @param red The red component, 0 to 255.
 * @param green The green component, 0 to 255.
 * @param blue The blue component, 0 to 255.
 * @return An Rgb colour.
 */
rgb :: fn(red: u8, green: u8, blue: u8) -> Color {
    return Color.{kind = cast[u8](ColorKind.Rgb), red = red, green = green, blue = blue}
}

/**
 * Tell what kind of colour a colour is.
 *
 * @param color The colour, as it came, from any version of the protocol.
 * @return Its kind; Default for a kind this version doesn't know, so a newer kind is shown as the default colour.
 */
color_kind :: fn(color: Color) -> ColorKind {
    return match color.kind {
        case 1 => ColorKind.Palette
        case 2 => ColorKind.Rgb
        case _ => ColorKind.Default
    }
}

/** A Style's attribute bit: bold text. */
BOLD : u8 : 1
/** A Style's attribute bit: dim, or faint, text. */
DIM : u8 : 2
/** A Style's attribute bit: italic text. */
ITALIC : u8 : 4
/** A Style's attribute bit: underlined text. */
UNDERLINE : u8 : 8
/** A Style's attribute bit: the foreground and background colours swapped. */
INVERSE : u8 : 16
/** A Style's attribute bit: text struck through. */
STRIKETHROUGH : u8 : 32

/** How text looks: its colours and attributes. The zero Style is the terminal's default, plain. */
Style :: struct {
    /** The text's colour. */
    foreground : Color,
    /** The colour behind the text. */
    background : Color,
    /**
     * The attribute bits, BOLD to STRIKETHROUGH, ORed together; 0 for none. A terminal shows those its
     * Features.attributes has, and ignores the rest.
     */
    attributes : u8,
}

/**
 * A run of a Text: its next bytes, in style, and a link's target, a range of the Text's links bytes (none where
 * link_bytes is 0).
 */
Run :: struct {
    /** How many bytes of the Text's text the run covers, from where the run before it ended. */
    bytes : u32,
    /** How the run's text looks. */
    style : Style,
    /** Where the run's link's target starts, in bytes from the start of the Text's links. */
    link_start : u32,
    /** How many bytes the link's target has, UTF-8; 0 for a run that isn't a link. */
    link_bytes : u32,
}

/** A place on the screen, from 0, in columns and rows. */
Position :: struct {
    /** The column, from 0 at the left. */
    column : u16,
    /** The row, from 0 at the top. */
    row : u16,
}

/** A rectangle of the screen, in columns and rows. */
Area :: struct {
    /** Its leftmost column, from 0. */
    column : u16,
    /** Its top row, from 0. */
    row : u16,
    /** How many columns wide it is. */
    columns : u16,
    /** How many rows high it is. */
    rows : u16,
}

/** An area's rows moved up by lines, or down when lines is negative, the rows left behind cleared. */
ScrollArea :: struct {
    /** The area that scrolls; nothing outside it moves. */
    area : Area,
    /** How many rows it moves: up when positive, down when negative, not at all when 0. */
    lines : i16,
}

/** How many colours a terminal shows. */
ColorSupport :: enum #backed_by(u8) {
    /** None: only its default colours. */
    None = 0,
    /** The palette's first 16. */
    Palette16 = 1,
    /** The whole palette of 256. */
    Palette256 = 2,
    /** Any red, green and blue. */
    Rgb = 3,
}

/** What a terminal can show, in place of terminfo, as Describe answers. */
Features :: struct {
    /** How many columns wide the terminal is now. */
    columns : u16,
    /** How many rows high the terminal is now. */
    rows : u16,
    /** How many colours it shows. */
    colors : ColorSupport,
    /** The Style attribute bits it shows, ORed together. */
    attributes : u8,
    /** Whether it shows runs' links. */
    links : bool,
    /** The Unicode version its widths come from, as major * 256 + minor. */
    unicode : u16,
}

/** A key event's modifier bit: Shift held. */
SHIFT : u8 : 1
/** A key event's modifier bit: Control held. */
CONTROL : u8 : 2
/** A key event's modifier bit: Alt held. */
ALT : u8 : 4
/** A key event's modifier bit: Meta held. */
META : u8 : 8

/** What an Event is, and which of its fields mean something. */
EventKind :: enum #backed_by(u8) {
    /**
     * A key pressed. code: the key's USB HID usage (page 7), 0 where only its text is known; modifiers; the text it
     * types, if any.
     */
    Key = 1,
    /** Text was pasted, given as text: one event, never as keys. */
    Paste = 2,
    /** The terminal was resized, to its columns and rows. */
    Resize = 3,
    /** The terminal's focus changed: focused says whether it's now the one being looked at. */
    Focus = 4,
    /** Ctrl-C, for the terminal's owner to decide what to stop. */
    Interrupt = 5,
    /** The terminal is gone: nothing more will be shown or typed. */
    HangUp = 6,
}

/**
 * One event; its text is a range of its Events's text. Plain data, as a Relative's elements are: kind an EventKind's
 * value and focused 1 or 0 (event_of and kind_of make and read them).
 */
Event :: struct {
    /** An EventKind's value; one this version doesn't know is null to kind_of, and is best skipped. */
    kind : u8,
    /** A Key's modifier bits, SHIFT to META, ORed together; 0 for none, and for other kinds. */
    modifiers : u8,
    /** A Focus's: 1 if the terminal is now the one being looked at, 0 if not. */
    focused : u8,
    /** A Key's USB HID usage, on page 7; 0 where only its text is known. */
    code : u16,
    /** A Resize's new width, in columns. */
    columns : u16,
    /** A Resize's new height, in rows. */
    rows : u16,
    /** Where the event's text starts, in bytes from the start of its Events's text. */
    text_start : u32,
    /** How many bytes the event's text has, UTF-8: a Key's typed text or a Paste's; 0 for none. */
    text_bytes : u32,
}

/**
 * Make an event of a kind, its other fields to fill in.
 *
 * @param kind What the event is.
 * @return The event, every field but kind zero.
 */
event_of :: fn(kind: EventKind) -> Event {
    return Event.{kind = cast[u8](kind)}
}

/**
 * Tell what an event is.
 *
 * @param event The event, as it came, from any version of the protocol.
 * @return Its kind; null for a kind this version doesn't know.
 */
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

/**
 * The terminal protocol, for os.Channel[Terminal]: a terminal (the SlopOS repository's decisions 0136).
 *
 * Text and operations are separate messages, so text is never read for control sequences, and input comes as typed
 * events. Text goes where the cursor is, in styled runs, and a line break is the only character in it that does
 * anything: anything else that doesn't show is shown as a visible substitute. A program that draws its whole
 * screen asks for one with Screen, and moves the cursor and clears in it.
 *
 * The program reading input can hand the terminal the line it's editing (InputLine), which the terminal keeps below
 * everything written, by any client, and draws again after it, with the cursor where the program says: output that
 * comes while a line's being typed goes above it, as a shell's line editor does. An empty one takes it away; the
 * program writes the line itself once it's done with it, if it wants it kept.
 *
 * Output isn't answered. Describe is answered with Described; Read is held until there's input, then answered with
 * Events. Connections arrive on the terminal service's listener as Connects.
 *
 * The first client to read owns the input until its connection goes, or it gives it up with ReleaseInput, as a
 * shell does while a program it started on the terminal runs: the next client to read owns it then.
 */
Terminal :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * terminal pays for its work from its own budget.
 */
PROTOCOL :: slop_os.Protocol.{name = "terminal", major_version = 1, lending = .Server}

/** UTF-8 text in runs, which cover it from its start; bytes the runs don't reach take the last run's style. */
Text :: struct {
    /**
     * The text, UTF-8, at most MAX_TEXT_BYTES bytes: a line break moves to the next line, and anything else that
     * doesn't show is shown as a visible substitute.
     */
    text : slop_os.Relative[u8],
    /** The runs, at most MAX_RUNS, in order from the text's start. */
    runs : slop_os.Relative[Run],
    /** The links' targets, UTF-8, one after another, which the runs name ranges of; empty for none. */
    links : slop_os.Relative[u8],
}

/** Input, as Read answers it: events, and the text they name ranges of. */
Events :: struct {
    /** The events, oldest first, at most as many as the Read asked for and MAX_EVENTS. */
    events : slop_os.Relative[Event],
    /** The events' text, UTF-8, one after another, at most MAX_EVENT_TEXT bytes. */
    text : slop_os.Relative[u8],
}

/** The line being edited, UTF-8, shown plain, and the cursor in it, as a byte offset at a cluster's start. */
InputLine :: struct {
    /** The line's text, UTF-8, shown plain; empty takes the line away. */
    text : slop_os.Relative[u8],
    /** Where the cursor is, in bytes from the line's start, at a grapheme cluster's start: 0 to text's count. */
    cursor : u32,
}

/** What a client asks of a terminal. */
Request :: union {
    /** Text written where the cursor is, in its runs' styles. Not answered. */
    Write(Text),
    /**
     * The cursor moved, in the screen Screen gave; in lines, its column on the line being written. Not answered.
     */
    MoveCursor(Position),
    /** The cursor shown (true) or hidden (false). Not answered. */
    ShowCursor(bool),
    /** The area made blank, in the default style. Not answered. */
    Clear(Area),
    /** An area's rows scrolled. Not answered. */
    Scroll(ScrollArea),
    /**
     * A screen of the program's own, the terminal's size and blank, for a program that draws everything (true), or
     * back to lines that scroll, as they were (false). Not answered.
     */
    Screen(bool),
    /** The terminal's bell rung, however it rings it. Not answered. */
    Bell,
    /** What the terminal can show. Answered with Described. */
    Describe,
    /**
     * Input, as many events as this at most. Held until there's some, then answered with Input.
     */
    Read(u32),
    /**
     * The line the reader's editing, kept below what's written; ignored from a client that isn't reading input.
     * Not answered.
     */
    InputLine(InputLine),
    /** Serve another client, on the end given, which moves to the terminal. Not answered. */
    Connect(os.Channel[Terminal]),
    /**
     * Give up the input, from the client that owns it, so the next client to read owns it; its line is taken
     * away, and a Read it holds is answered with an Input of no events. Ignored from a client that doesn't own it.
     * Not answered otherwise.
     */
    ReleaseInput,
}

/** What a terminal answers. */
Response :: union {
    /** The answer to Describe: what the terminal can show, and its size now. */
    Described(Features),
    /** The answer to Read, once there's input: the events, and their text. */
    Input(Events),
    /** The answer to a request the terminal doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * Output shown again is shown twice; a Describe or a Connect asked again changes nothing more.
 *
 * @param request The request, which isn't changed.
 * @return False for Write, Scroll, Bell and Read; true for the rest, which set something to what it was set to.
 */
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
        case ReleaseInput => true
    }
}

#insert os.protocol_code(Request, Response)

/**
 * Make a new connection to the terminal a connection reaches, with a Connect.
 *
 * The Connect isn't answered, so a terminal that won't take the connection is learned of only when the new end
 * finds its other end closed.
 *
 * @param end A connection to the terminal, or its service's listening end, kept by the caller; only the Connect
 *     is sent on it.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param budget The memory budget that pays for the new channel.
 * @return The new connection's end, which the caller owns and closes; null if the channel couldn't be made or the
 *     Connect couldn't be sent, and then nothing is left open.
 */
connect :: fn(end: slop_os.Channel, port: slop_os.Port, budget: slop_os.MemoryBudget) -> os.Channel[Terminal]? {
    pair :: os.channel_for[Terminal](budget, RING_BYTES) or_return null
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

/**
 * Write text in one style on a terminal, in as many Writes as it takes.
 *
 * Each Write has at most MAX_TEXT_BYTES bytes and ends where a grapheme cluster does, unless one cluster is longer
 * than that, which is then cut. Nothing is answered, so this doesn't wait for the text to be shown; it waits only
 * while the ring is full.
 *
 * @param end A connection to the terminal, kept by the caller.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param text The text, UTF-8; a line break moves to the next line. Empty sends one empty Write.
 * @param style How the text looks; the default, plain.
 * @return True if every Write went; false at the first that didn't, with what's before it sent.
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

/**
 * Send bytes as one Write, of one run in one style and no link.
 *
 * @param end A connection to the terminal, kept by the caller.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param bytes The text, UTF-8, at most MAX_TEXT_BYTES bytes; more makes a message too big to send.
 * @param style How the text looks.
 * @return True if the Write went; false if it couldn't be sent.
 */
write_run :: fn(end: slop_os.Channel, port: slop_os.Port, bytes: u8[], style: Style) -> bool {
    out := os.Outgoing.{}
    request :: os.begin[Request](&out)
    run :: Run.[Run.{bytes = cast[u32](bytes.count), style = style}]
    empty : u8[0]
    request^ = .Write(Text.{text = os.append(&out, bytes), runs = os.append(&out, run), links = os.append(&out, empty)})
    return send_request(end, port, &out) == null
}

/**
 * Write text in one style on a terminal, then a line break, as write does.
 *
 * @param end A connection to the terminal, kept by the caller.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param text The text, UTF-8, without its line break.
 * @param style How the text, and the line break, look; the default, plain.
 * @return True if everything went; false at the first Write that didn't, and the line break isn't sent then.
 */
write_line :: fn(end: slop_os.Channel, port: slop_os.Port, text: string, style := Style.{}) -> bool {
    return write(end, port, text, style) && write(end, port, "\n", style)
}

/**
 * Send one request that has no variable-size data: anything but Write and InputLine, which write and input_line
 * send.
 *
 * @param end A connection to the terminal, kept by the caller.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param request The request; a Connect's end moves to the terminal with it.
 * @return True if it went; false if it couldn't be sent. A request that's answered still has to be answered:
 *     this doesn't wait for it.
 */
send :: fn(end: slop_os.Channel, port: slop_os.Port, request: Request) -> bool {
    out := os.Outgoing.{}
    os.begin[Request](&out)^ = request
    return send_request(end, port, &out) == null
}

/**
 * Hand the terminal the line being edited, which it keeps below what's written, with the cursor in it.
 *
 * @param end A connection to the terminal, kept by the caller; it has to be the one reading input, or the line
 *     is ignored.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param text The line, UTF-8, shown plain; empty takes the line away.
 * @param cursor Where the cursor is, in bytes from the line's start, at a grapheme cluster's start: 0 to
 *     text.count. It's sent as a u32.
 * @return True if it went; false if it couldn't be sent.
 */
input_line :: fn(end: slop_os.Channel, port: slop_os.Port, text: u8[], cursor: usize) -> bool {
    out := os.Outgoing.{}
    request :: os.begin[Request](&out)
    request^ = .InputLine(InputLine.{text = os.append(&out, text), cursor = cast[u32](cursor)})
    return send_request(end, port, &out) == null
}

/**
 * Ask for input: send a Read, which the terminal holds until there's some, then answers with Input.
 *
 * It doesn't wait for the answer, which comes to receive_response.
 *
 * @param end A connection to the terminal, kept by the caller.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param most The most events the answer may have; MAX_EVENTS, the most an Events holds, by default.
 * @return True if the Read went; false if it couldn't be sent.
 */
read :: fn(end: slop_os.Channel, port: slop_os.Port, most: u32 = MAX_EVENTS) -> bool {
    return send(end, port, .Read(most))
}
