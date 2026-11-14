package ui

import runtime from "base"
import canvas from "std"
import fonts from "std"

/** A widget's identity from frame to frame: a hash of its label, its parent's ID and its key. */
ID :: u64

/** No node: an index past every node's. */
NO_NODE : u32 : 0xffff_ffff
/** The most IDs whose state is kept from one frame to the next. */
KEPT :: 2048
/** The most nodes a frame has; past them, a widget is dropped, and the frame says so. */
MAX_NODES :: 8192

/** How a box's size along an axis is found. */
SizeKind :: enum #backed_by(u8) {
    /** Its content's, within min and max. */
    Fit = 0,
    /** What's left of its parent's, shared with its siblings that grow by weight, within min and max. */
    Grow = 1,
    /** value pixels. */
    Fixed = 2,
    /** value hundredths of its parent's content. */
    Percent = 3,
}

/** A box's size along one axis. */
Axis :: struct {
    /** How it's found. */
    kind : SizeKind = .Fit,
    /** For Fixed, pixels; for Percent, hundredths of the parent's content; for Grow, its weight, more than 0. */
    value : f32,
    /** The least it may be, in pixels. */
    min : f32,
    /** The most it may be, in pixels; 0 for no most. */
    max : f32,
}

/** Its content's size, at least min and at most max (0 for no most). */
fit :: fn(min: f32 = 0, max: f32 = 0) -> Axis {
    return Axis.{kind = .Fit, min = min, max = max}
}

/** What's left of the parent's, shared by weight with other growing siblings, at least min and at most max. */
grow :: fn(weight: f32 = 1, min: f32 = 0, max: f32 = 0) -> Axis {
    return Axis.{kind = .Grow, value = weight, min = min, max = max}
}

/** Exactly some pixels. */
fixed :: fn(pixels: f32) -> Axis {
    return Axis.{kind = .Fixed, value = pixels, min = pixels, max = pixels}
}

/** A percent of the parent's content. */
percent :: fn(hundredths: f32) -> Axis {
    return Axis.{kind = .Percent, value = hundredths}
}

/** Which way a box's children go. */
Direction :: enum #backed_by(u8) {
    /** Top to bottom. */
    Column = 0,
    /** Left to right. */
    Row = 1,
}

/** Where children sit along an axis when there's room left. */
Align :: enum #backed_by(u8) {
    /** At the start: left or top. */
    Start = 0,
    /** In the middle. */
    Center = 1,
    /** At the end: right or bottom. */
    End = 2,
}

/** What a node is, to a reader of the tree: its accessibility role. */
Role :: enum #backed_by(u8) {
    /** A box holding others. */
    Group = 0,
    /** Text. */
    Text = 1,
    /** A button, clicked. */
    Button = 2,
    /** A check box, toggled. */
    CheckBox = 3,
    /** A field of text, edited. */
    TextField = 4,
    /** A list of items. */
    List = 5,
    /** One of a list's items. */
    ListItem = 6,
    /** A box whose content scrolls. */
    ScrollArea = 7,
}

/** A colour of 8-bit channels, not premultiplied; alpha 0 is none. */
Colour :: struct {
    /** Red, 0 to 255. */
    r : u8,
    /** Green, 0 to 255. */
    g : u8,
    /** Blue, 0 to 255. */
    b : u8,
    /** Alpha: 0 transparent, 255 opaque. */
    a : u8,
}

/** An opaque colour. */
rgb :: fn(r: u8, g: u8, b: u8) -> Colour {
    return Colour.{r = r, g = g, b = b, a = 255}
}

/** A box: how it's sized and lays out its children, and how it's drawn. */
Box :: struct {
    /** Mixed into its ID, to tell apart boxes of one label under one parent, as a loop's items. */
    key : u64,
    /** Its width. */
    width : Axis,
    /** Its height. */
    height : Axis,
    /** Which way its children go. */
    direction : Direction = .Column,
    /** Room inside its edges, left and right, in pixels. */
    padding_x : f32,
    /** Room inside its edges, top and bottom, in pixels. */
    padding_y : f32,
    /** Room between its children, in pixels. */
    gap : f32,
    /** Where its children sit across, with room left. */
    align_x : Align = .Start,
    /** Where its children sit down, with room left. */
    align_y : Align = .Start,
    /** What it's filled with; alpha 0 for nothing. */
    background : Colour,
    /** Its border's colour; alpha 0 for none. */
    border : Colour,
    /** Its corners' radius, in pixels. */
    corner : f32,
    /** Whether what's outside it of its children isn't drawn. */
    clip : bool,
    /** Its role, to a reader of the tree. */
    role : Role = .Group,
}

/** How text is drawn. */
TextStyle :: struct {
    /** Its size, in pixels to the em; 0 for the theme's. */
    size : f32,
    /** Its colour; alpha 0 for the theme's. */
    colour : Colour,
    /** Whether it's the monospaced face. */
    mono : bool,
    /** Whether it wraps to its box's width; otherwise one line. */
    wrap : bool = true,
}

/** One node of a frame's tree. */
Node :: struct {
    /** Its ID. */
    id : ID,
    /** Its parent, or NO_NODE for the root. */
    parent : u32,
    /** Its first child, or NO_NODE. */
    first : u32,
    /** Its last child, or NO_NODE. */
    last : u32,
    /** Its next sibling, or NO_NODE. */
    next : u32,
    /** How it's laid out and drawn. */
    box : Box,
    /** Its text, for a Text node: where it starts in the frame's text, and how many bytes. */
    text_start : u32,
    /** How many bytes of text it has. */
    text_count : u32,
    /** How its text is drawn. */
    style : TextStyle,
    /** Whether it's text. */
    is_text : bool,
    /** Whether a press on it is its, not its parent's. */
    clickable : bool,
    /** Whether it takes focus, by a press or Tab. */
    focusable : bool,
    /** Whether it scrolls its children by its kept scroll. */
    scrolls : bool,
    /** For a check box, whether it's checked. */
    checked : bool,
    /** Whether it's the focused text field's text, drawn with its cursor and selection. */
    edited : bool,
    /** Its name to a reader of the tree, as a button's label: where in the frame's text, and how many bytes. */
    name_start : u32,
    /** How many bytes of name it has. */
    name_count : u32,
    // ---- Laid out
    /** Its content's width as Fit finds it: the widest it wants. */
    fit_w : f32,
    /** The narrowest it can be: for wrapped text, its longest word. */
    min_w : f32,
    /** Its content's height as Fit finds it. */
    fit_h : f32,
    /** Its left edge, in pixels from the frame's. */
    x : f32,
    /** Its top edge. */
    y : f32,
    /** Its width. */
    w : f32,
    /** Its height. */
    h : f32,
    /** For a scroll area, how tall its content is. */
    content_h : f32,
}

/** A key a widget reads, besides typed text. */
Key :: enum #backed_by(u8) {
    /** The cursor a character left. */
    Left = 1,
    /** The cursor a character right. */
    Right = 2,
    /** The cursor a line up. */
    Up = 3,
    /** The cursor a line down. */
    Down = 4,
    /** The cursor to the start. */
    Home = 5,
    /** The cursor to the end. */
    End = 6,
    /** The character before the cursor, or the selection, deleted. */
    Backspace = 7,
    /** The character after the cursor, or the selection, deleted. */
    Delete = 8,
    /** A field submitted. */
    Enter = 9,
    /** Focus to the next widget; with Shift, the one before. */
    Tab = 10,
    /** Focus given up. */
    Escape = 11,
    /** A list a page up. */
    PageUp = 12,
    /** A list a page down. */
    PageDown = 13,
    /** Ctrl+A. */
    SelectAll = 14,
    /** Ctrl+C. */
    Copy = 15,
    /** Ctrl+X. */
    Cut = 16,
    /** Ctrl+Z. */
    Undo = 17,
    /** Ctrl+Y or Ctrl+Shift+Z. */
    Redo = 18,
}

/** A key pressed, with whether Shift was held, which extends a selection. */
KeyPress :: struct {
    /** The key. */
    key : Key,
    /** Whether Shift was held. */
    shift : bool,
}

/** The most keys one frame's input has. */
MAX_KEYS :: 16

/** What happened since the last frame. */
Input :: struct {
    /** The pointer, across, in pixels from the frame's left; it's taken as away when outside the frame. */
    pointer_x : f32 = -1,
    /** The pointer, down. */
    pointer_y : f32 = -1,
    /** Whether the primary button is held. */
    down : bool,
    /** Whether it went down since the last frame. */
    pressed : bool,
    /** Whether it came up since the last frame. */
    released : bool,
    /** How far the wheel turned, in notches, positive away from the user. */
    wheel : f32,
    /** Text typed, UTF-8, for the focused field. */
    text : u8[],
    /** Text pasted on the user's gesture, for the focused field. */
    pasted : u8[],
    /** Keys pressed, the first key_count of them, in order. */
    keys : KeyPress[MAX_KEYS],
    /** How many keys there are. */
    key_count : usize,
}

/** Add a key to an input, if there's room. */
press_key :: fn(input: ptr[mut Input], key: Key, shift: bool = false) {
    if input.key_count < MAX_KEYS {
        input.keys[input.key_count] = KeyPress.{key = key, shift = shift}
        input.key_count += 1
    }
}

/** What an event is. */
EventKind :: enum #backed_by(u8) {
    /** A button was clicked. */
    Clicked = 1,
    /** A check box changed; value 1 if it's now checked. */
    Toggled = 2,
    /** A text field's text changed. */
    Changed = 3,
    /** Enter was pressed in a text field. */
    Submitted = 4,
    /** Text was copied or cut from a field, in the event's text, for the program to offer to be pasted. */
    Copied = 5,
    /** A widget took focus. */
    Focused = 6,
}

/** Something that happened in a frame, for the program to handle after it. */
Event :: struct {
    /** What happened. */
    kind : EventKind,
    /** The widget it happened to. */
    id : ID,
    /** For a Toggled, 1 or 0; 0 otherwise. */
    value : i64,
    /** Its text, for a Copied: where it starts in the frame's text. */
    text_start : u32,
    /** How many bytes of text it has. */
    text_count : u32,
}

/** What a widget keeps from frame to frame. */
Kept :: struct {
    /** Its ID; 0 for a free place. */
    id : ID,
    /** Where it was laid out last frame: its left edge, in pixels. */
    x : f32,
    /** Its top edge. */
    y : f32,
    /** Its width. */
    w : f32,
    /** Its height. */
    h : f32,
    /** For a scroll area or list, how far its content's scrolled, in pixels. */
    scroll : f32,
    /** For a scroll area, how tall its content was. */
    content_h : f32,
}

/** The colours and sizes widgets are drawn with. */
Theme :: struct {
    /** Behind everything. */
    background : Colour,
    /** Text. */
    text : Colour,
    /** Text that's less important, as a field's placeholder. */
    faint : Colour,
    /** A button, at rest. */
    button : Colour,
    /** A button the pointer's over. */
    button_hover : Colour,
    /** A button pressed. */
    button_pressed : Colour,
    /** What's chosen: a check, a focused field's edge, a selection's highlight. */
    accent : Colour,
    /** A selection's background. */
    selection : Colour,
    /** A field's background. */
    field : Colour,
    /** A field's or check box's edge. */
    edge : Colour,
    /** Text's size, in pixels to the em. */
    text_size : f32,
    /** Room inside buttons and fields, across. */
    padding_x : f32,
    /** Room inside buttons and fields, down. */
    padding_y : f32,
    /** Corners' radius. */
    corner : f32,
}

/** The theme widgets are drawn with unless a program sets its own: light, with Material's blue. */
default_theme :: fn() -> Theme {
    return Theme.{background = Colour.{r = 250, g = 250, b = 250, a = 255}, text = Colour.{r = 33, g = 33, b = 33, a = 255}, faint = Colour.{r = 117, g = 117, b = 117, a = 255}, button = Colour.{r = 224, g = 224, b = 224, a = 255}, button_hover = Colour.{r = 207, g = 216, b = 220, a = 255}, button_pressed = Colour.{r = 176, g = 190, b = 197, a = 255}, accent = Colour.{r = 25, g = 118, b = 210, a = 255}, selection = Colour.{r = 187, g = 222, b = 251, a = 255}, field = Colour.{r = 255, g = 255, b = 255, a = 255}, edge = Colour.{r = 158, g = 158, b = 158, a = 255}, text_size = 14, padding_x = 10, padding_y = 6, corner = 4}
}

/** One step a text field can undo: its text and cursor before an edit. */
Undo :: struct {
    /** The text. */
    text : u8[..],
    /** The cursor, in bytes. */
    cursor : usize,
}

/** The most edits a field can undo. */
MAX_UNDO :: 32

/** The focused text field's editing state: the one field that has one. */
Editing :: struct {
    /** The field's ID; 0 when no field's being edited. */
    id : ID,
    /** The cursor, in bytes into the text. */
    cursor : usize,
    /** The selection's other end, in bytes; the cursor when nothing's selected. */
    anchor : usize,
    /** What can be undone, oldest first, the first undo_count. */
    undo : Undo[MAX_UNDO],
    /** How many can be undone. */
    undo_count : usize,
    /** How many of those after undo_count can be redone. */
    redo_count : usize,
}

/** What drawing a frame needs: a rectangle, text, or a clip starting or ending. */
CommandKind :: enum #backed_by(u8) {
    /** A rectangle filled, with its corner. */
    Fill = 1,
    /** A rectangle's edge, a pixel wide. */
    Border = 2,
    /** A line of text, its baseline at y plus its ascent. */
    Text = 3,
    /** What follows is clipped to the rectangle, until its ClipEnd. */
    ClipStart = 4,
    /** The clip before the last ClipStart again. */
    ClipEnd = 5,
}

/** One command of a frame's draw list. */
Command :: struct {
    /** What it does. */
    kind : CommandKind,
    /** Its rectangle's left edge, in pixels: for Text, the line's. */
    x : f32,
    /** Its top edge. */
    y : f32,
    /** Its width. */
    w : f32,
    /** Its height. */
    h : f32,
    /** Its colour. */
    colour : Colour,
    /** For a Fill, its corners' radius. */
    corner : f32,
    /** For a Text, its size. */
    size : f32,
    /** For a Text, whether it's the monospaced face. */
    mono : bool,
    /** For a Text, where its bytes are in the frame's text. */
    text_start : u32,
    /** How many bytes. */
    text_count : u32,
}

/** A frame's result: its events, and the rectangle of the screen that changed since the last frame. */
Frame :: struct {
    /** What changed, in pixels; empty when nothing did. */
    damage : canvas.Rect,
    /** Whether the frame dropped widgets past MAX_NODES, or had two of one ID. */
    overflowed : bool,
    /** Whether two widgets had one ID, the second told apart. */
    duplicates : bool,
}

/**
 * A UI: its frame's tree, what's kept between frames, and the input being read.
 *
 * Its typefaces are bytes it's given, which have to outlive it.
 */
Ui :: struct {
    /** The proportional typeface's TrueType bytes. */
    sans : u8[],
    /** The monospaced typeface's TrueType bytes. */
    mono : u8[],
    /** The theme. */
    theme : Theme,
    /** The frame's nodes, the root first. */
    nodes : Node[..],
    /** The frame's text: labels, names and copied text. */
    text : u8[..],
    /** The frame's events. */
    events : Event[..],
    /** The frame's draw list. */
    commands : Command[..],
    /** The last frame's draw list, for the damage. */
    last_commands : Command[..],
    /** The last frame's text, which its commands' text is in. */
    last_text : u8[..],
    /** The node open, which widgets are added to. */
    open : u32,
    /** The frame's size. */
    width : f32,
    /** The frame's size. */
    height : f32,
    /** The input being read this frame, its text and pasted left empty: they're typed and pasted. */
    input : Input,
    /** The text typed this frame. */
    typed : u8[..],
    /** The text pasted this frame. */
    pasted : u8[..],
    /** What's kept from the last frame, by ID, open-addressed. */
    kept : Kept[KEPT],
    /** What this frame keeps, made as it's laid out, then swapped with kept. */
    keeping : Kept[KEPT],
    /** The widget the pointer's over, in what the last frame showed; 0 for none. */
    hover : ID,
    /** The scroll area the pointer's over, in what the last frame showed; 0 for none. */
    hover_scroll : ID,
    /** The widget a press went down on, held until it comes up; 0 for none. */
    active : ID,
    /** The focused widget; 0 for none. */
    focus : ID,
    /** The focusable widgets, in the last frame's order, for Tab. */
    focusables : ID[..],
    /** What the pointer can be over, as the last frame showed it, in the order it was drawn. */
    hits : Hit[..],
    /** The focused field's editing. */
    editing : Editing,
    /** Whether this frame dropped a widget past MAX_NODES. */
    overflowed : bool,
    /** Whether this frame had two widgets of one ID. */
    duplicates : bool,
    /** The frame's number. */
    frame : u64,
    /** How many boxes deep the widgets being added are inside one dropped past MAX_NODES. */
    dropped : u32,
    /** What a node past the frame's is read and written as, so a bad index changes nothing that matters. */
    spare : Node,
}

/**
 * Make a UI.
 *
 * @param sans The proportional typeface's TrueType bytes, kept, not copied: they have to outlive the UI.
 * @param mono The monospaced typeface's, as sans; the same bytes are fine.
 * @return The UI, before its first frame; give it back with free_ui.
 */
make :: fn(sans: u8[], mono: u8[]) -> Ui {
    return Ui.{sans = sans, mono = mono, open = NO_NODE, theme = default_theme()}
}

/** Give back a UI's arrays. */
free_ui :: fn(ui: ptr[mut Ui]) {
    runtime.array_free(&ui.nodes)
    runtime.array_free(&ui.text)
    runtime.array_free(&ui.events)
    runtime.array_free(&ui.commands)
    runtime.array_free(&ui.last_commands)
    runtime.array_free(&ui.last_text)
    runtime.array_free(&ui.focusables)
    runtime.array_free(&ui.hits)
    runtime.array_free(&ui.typed)
    runtime.array_free(&ui.pasted)
    for &undo in ui.editing.undo {
        runtime.array_free(&undo.text)
    }
}

// ---- IDs

/** A 64-bit hash's finalizer (splitmix64's), so nearby inputs land far apart. */
finalize :: fn(value: u64) -> u64 {
    z := value
    z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ~ (z >> 27)) * 0x94d049bb133111eb
    return z ~ (z >> 31)
}

/** Text hashed, FNV-1a then finalized: never 0. */
hash :: fn(text: u8[]) -> u64 {
    h := cast[u64](0xcbf29ce484222325)
    for byte in text {
        h = (h ~ cast[u64](byte)) * 0x100000001b3
    }
    made :: finalize(h)
    return if made == 0 { cast[u64](1) } else { made }
}

/**
 * A label's hash, for a widget's ID: a constant when it's run at compile time (`SAVE :: #run ui.key("Save")`), as a
 * literal label's can be.
 */
key :: fn(label: string) -> u64 {
    return hash(string_bytes(label))
}

/** Two values mixed into one, neither's order lost: a parent's ID and a child's label, or an ID and a loop's key. */
mix :: fn(a: u64, b: u64) -> u64 {
    made :: finalize(a ~ finalize(b + 0x9e3779b97f4a7c15))
    return if made == 0 { cast[u64](1) } else { made }
}

// ---- Nodes

/** A node by index; a scratch node for one past them, so a bad index reads and writes nothing that matters. */
node :: fn(ui: ptr[mut Ui], index: u32) -> ptr[mut Node] {
    at :: cast[usize](index)
    if at < ui.nodes.count {
        return &ui.nodes[at]
    }
    ui.spare = Node.{parent = NO_NODE, first = NO_NODE, last = NO_NODE, next = NO_NODE}
    return &ui.spare
}

/** Keep text in the frame's text, giving where it starts and how long it is. */
keep_text :: fn(ui: ptr[mut Ui], text: u8[]) -> (u32, u32) {
    start :: cast[u32](ui.text.count)
    for byte in text {
        runtime.array_add(&ui.text, byte)
    }
    return start, cast[u32](text.count)
}

/** A frame's text by where it starts and how long it is; empty past its end. */
text_of :: fn(text: u8[], start: u32, count: u32) -> u8[] {
    from :: cast[usize](start)
    if from <= text.count {
        rest :: text[from..<text.count]
        if cast[usize](count) <= rest.count {
            return rest[0..<cast[usize](count)]
        }
    }
    return text[0..<0]
}

/** Whether an ID was already used this frame, by a node before. */
seen :: fn(ui: ptr[Ui], id: ID) -> bool {
    for each in ui.nodes {
        if each.id == id {
            return true
        }
    }
    return false
}

/**
 * Add a node under the open one, its ID made from the open node's and its label and key.
 *
 * Two of one ID under one parent are told apart, the second's mixed with its place, and the frame says so: its state
 * can't be kept rightly, as it moves when the first does.
 *
 * @param ui The UI, whose open node gains a child.
 * @param label What tells it from its siblings, hashed: a widget's label, or a kind's name.
 * @param box How it's laid out and drawn; its key is mixed into its ID.
 * @return Its index; NO_NODE past MAX_NODES, when it's dropped.
 */
add_node :: fn(ui: ptr[mut Ui], label: u64, box: Box) -> u32 {
    if ui.nodes.count >= MAX_NODES || ui.dropped > 0 {
        ui.overflowed = true
        return NO_NODE
    }
    parent :: ui.open
    parent_id :: if parent == NO_NODE { cast[u64](0) } else { node(ui, parent).id }
    id := mix(mix(parent_id, label), box.key)
    if seen(ui, id) {
        ui.duplicates = true
        id = mix(id, cast[u64](ui.nodes.count))
    }
    index :: cast[u32](ui.nodes.count)
    runtime.array_add(&ui.nodes, Node.{id = id, parent = parent, first = NO_NODE, last = NO_NODE, next = NO_NODE, box = box})
    if parent != NO_NODE {
        above :: node(ui, parent)
        if above.last == NO_NODE {
            above.first = index
        }
        else {
            node(ui, above.last).next = index
        }
        above.last = index
    }
    return index
}

/**
 * Open a box: widgets after it go in it, until close.
 *
 * @param ui The UI.
 * @param label What tells it from its siblings; with box's key, its ID.
 * @param box How it's laid out and drawn.
 * @return Its ID.
 */
open :: fn(ui: ptr[mut Ui], label: string, box: Box = Box.{}) -> ID {
    index :: add_node(ui, key(label), box)
    if index == NO_NODE {
        // Dropped, and everything in it, until its close
        ui.dropped += 1
        return 0
    }
    ui.open = index
    return node(ui, index).id
}

/** Close the box open last, its parent open again. */
close :: fn(ui: ptr[mut Ui]) {
    if ui.dropped > 0 {
        ui.dropped -= 1
        return void
    }
    if ui.open == NO_NODE {
        return void
    }
    parent :: node(ui, ui.open).parent
    // The root stays open until the frame ends
    if parent != NO_NODE {
        ui.open = parent
    }
}

/**
 * Add text, wrapped to its box's width unless the style says not.
 *
 * @param ui The UI.
 * @param text UTF-8, copied into the frame.
 * @param style How it's drawn.
 * @param key Mixed into its ID, to tell apart texts alike under one parent.
 * @return Its ID.
 */
label :: fn(ui: ptr[mut Ui], text: string, style: TextStyle = TextStyle.{}, key: u64 = 0) -> ID {
    index :: add_node(ui, hash(string_bytes(text)), Box.{key = key, role = .Text})
    if index == NO_NODE {
        return 0
    }
    start, count :: keep_text(ui, string_bytes(text))
    made :: node(ui, index)
    made.is_text = true
    made.text_start = start
    made.text_count = count
    made.style = style
    made.name_start = start
    made.name_count = count
    return made.id
}

/** A style with the theme's size and colour where it has none. */
resolved :: fn(ui: ptr[Ui], style: TextStyle) -> TextStyle {
    made := style
    if made.size <= 0 {
        made.size = ui.theme.text_size
    }
    if made.colour.a == 0 {
        made.colour = ui.theme.text
    }
    return made
}

// ---- Kept state

/** Where an ID is in a kept table, or where it would go: open addressing, linear probing. */
slot_of :: fn(table: ptr[Kept[KEPT]], id: ID) -> usize {
    start :: cast[usize](id % KEPT)
    for probe in cast[usize](0)..<KEPT {
        at :: (start + probe) % KEPT
        found :: table[at].id
        if found == id || found == 0 {
            return at
        }
    }
    return KEPT
}

/** What's kept for an ID from the last frame; all 0 for an ID it didn't have. */
kept_of :: fn(ui: ptr[Ui], id: ID) -> Kept {
    at :: slot_of(&ui.kept, id)
    return if at < KEPT && ui.kept[at].id == id { ui.kept[at] } else { Kept.{} }
}

/** Keep state for an ID into the next frame. */
keep :: fn(ui: ptr[mut Ui], made: Kept) {
    at :: slot_of(&ui.keeping, made.id)
    if at < KEPT {
        ui.keeping[at] = made
    }
}

/** Change a kept scroll for an ID, in both tables, so it's read this frame and kept for the next. */
set_scroll :: fn(ui: ptr[mut Ui], id: ID, scroll: f32) {
    at :: slot_of(&ui.kept, id)
    if at < KEPT && ui.kept[at].id == id {
        ui.kept[at].scroll = scroll
    }
}

/** Whether a point's in what an ID was laid out at last frame. */
was_under :: fn(ui: ptr[Ui], id: ID, x: f32, y: f32) -> bool {
    place :: kept_of(ui, id)
    return place.id != 0 && x >= place.x && x < place.x + place.w && y >= place.y && y < place.y + place.h
}

// ---- Frames

/**
 * Start a frame: the input taken, the tree begun with its root, the size of the frame.
 *
 * The pointer going down on nothing takes focus away; a wheel turns the scroll area it's over; Tab and Shift+Tab move
 * focus through the last frame's focusable widgets.
 *
 * @param ui The UI.
 * @param input What happened since the last frame, copied; its text and pasted have to last until end.
 * @param width The frame's width, in pixels.
 * @param height Its height.
 */
begin :: fn(ui: ptr[mut Ui], input: Input, width: f32, height: f32) {
    ui.frame += 1
    runtime.array_reset(&ui.nodes)
    runtime.array_reset(&ui.text)
    runtime.array_reset(&ui.events)
    ui.overflowed = false
    ui.duplicates = false
    ui.dropped = 0
    // Its text copied, as the frame's own
    ui.input = Input.{pointer_x = input.pointer_x, pointer_y = input.pointer_y, down = input.down, pressed = input.pressed,
        released = input.released, wheel = input.wheel, keys = input.keys, key_count = input.key_count}
    runtime.array_reset(&ui.typed)
    for byte in input.text {
        runtime.array_add(&ui.typed, byte)
    }
    runtime.array_reset(&ui.pasted)
    for byte in input.pasted {
        runtime.array_add(&ui.pasted, byte)
    }
    ui.width = width
    ui.height = height
    ui.open = NO_NODE
    root :: add_node(ui, key("root"), Box.{width = fixed(width), height = fixed(height), background = ui.theme.background})
    ui.open = root
    // What the pointer's over, in what the last frame showed: the last drawn, over what's before it
    ui.hover = 0
    ui.hover_scroll = 0
    for hit in ui.hits {
        if input.pointer_x >= hit.x0 && input.pointer_x < hit.x1 && input.pointer_y >= hit.y0 && input.pointer_y < hit.y1 {
            if hit.pressable {
                ui.hover = hit.id
            }
            if hit.scrolls {
                ui.hover_scroll = hit.id
            }
        }
    }
    // A press focuses what it's on, if that takes focus, and takes focus away otherwise
    if input.pressed {
        ui.active = ui.hover
        set_focus(ui, if ui.hover != 0 && is_focusable(ui, ui.hover) { ui.hover } else { cast[u64](0) })
    }
    if input.wheel != 0 && ui.hover_scroll != 0 {
        place :: kept_of(ui, ui.hover_scroll)
        most :: if place.content_h > place.h { place.content_h - place.h } else { cast[f32](0) }
        scroll :: place.scroll - input.wheel * 3 * line_height(ui, ui.theme.text_size)
        set_scroll(ui, ui.hover_scroll, if scroll < 0 { cast[f32](0) } else if scroll > most { most } else { scroll })
    }
    for i in cast[usize](0)..<input.key_count {
        if i < input.keys.count && input.keys[i].key == .Tab {
            tab(ui, input.keys[i].shift)
        }
    }
}

/** Whether an ID was focusable last frame. */
is_focusable :: fn(ui: ptr[Ui], id: ID) -> bool {
    for each in ui.focusables {
        if each == id {
            return true
        }
    }
    return false
}

/** Give a widget focus, or none with 0, a Focused event for one. */
set_focus :: fn(ui: ptr[mut Ui], id: ID) {
    if ui.focus == id {
        return void
    }
    ui.focus = id
    if id != 0 {
        runtime.array_add(&ui.events, Event.{kind = .Focused, id = id})
    }
}

/** Move focus to the next focusable widget, or the one before with backwards, around the end. */
tab :: fn(ui: ptr[mut Ui], backwards: bool) {
    order :: ui.focusables[0..<ui.focusables.count]
    if order.count == 0 {
        return void
    }
    at := order.count
    for each, i in order {
        if each == ui.focus {
            at = i
        }
    }
    next :: if at == order.count { (if backwards { order.count - 1 } else { cast[usize](0) }) }
        else if backwards { (at + order.count - 1) % order.count } else { (at + 1) % order.count }
    if next < order.count {
        set_focus(ui, order[next])
    }
}

/**
 * End a frame: its tree laid out, its draw list made and compared with the last frame's, its state kept for the next,
 * and the widget the pointer's over found for it.
 *
 * @param ui The UI.
 * @return The frame's damage and whether widgets were dropped; its events are in events_of until the next begin.
 */
end :: fn(ui: ptr[mut Ui]) -> Frame {
    if ui.input.released {
        ui.active = 0
    }
    lay_out(ui)
    // What's kept: every node's place, its scroll carried over
    for &slot in ui.keeping {
        slot^ = Kept.{}
    }
    runtime.array_reset(&ui.focusables)
    runtime.array_reset(&ui.hits)
    for each, index in ui.nodes {
        if each.id == 0 {
            continue
        }
        before :: kept_of(ui, each.id)
        keep(ui, Kept.{id = each.id, x = each.x, y = each.y, w = each.w, h = each.h, scroll = before.scroll, content_h = each.content_h})
        if each.focusable {
            runtime.array_add(&ui.focusables, each.id)
        }
        // What the next frame's pointer can be over: what it's shown of, inside its clips
        if each.clickable || each.focusable || each.scrolls {
            shown :: visible(ui, cast[u32](index))
            if shown.x1 > shown.x0 && shown.y1 > shown.y0 {
                runtime.array_add(&ui.hits, Hit.{id = each.id, x0 = shown.x0, y0 = shown.y0, x1 = shown.x1, y1 = shown.y1,
                    pressable = each.clickable || each.focusable, scrolls = each.scrolls})
            }
        }
    }
    for i in cast[usize](0)..<KEPT {
        ui.kept[i] = ui.keeping[i]
    }
    // Liveness: an editing state, focus or press whose widget's gone is dropped
    if ui.focus != 0 && kept_of(ui, ui.focus).id == 0 {
        ui.focus = 0
    }
    if ui.active != 0 && kept_of(ui, ui.active).id == 0 {
        ui.active = 0
    }
    if ui.editing.id != 0 && ui.editing.id != ui.focus {
        stop_editing(ui)
    }
    make_commands(ui)
    damage :: compare_commands(ui)
    // This frame's list becomes the last
    swap_lists(ui)
    return Frame.{damage = damage, overflowed = ui.overflowed, duplicates = ui.duplicates}
}

/** A widget the pointer can be over: what of it was shown, and what it does. */
Hit :: struct {
    /** Its ID. */
    id : ID,
    /** What of it was shown, inside its clips: its left edge, in pixels. */
    x0 : f32,
    /** Its top edge. */
    y0 : f32,
    /** Its right edge, past its last pixel. */
    x1 : f32,
    /** Its bottom edge, past its last pixel. */
    y1 : f32,
    /** Whether a press on it is its. */
    pressable : bool,
    /** Whether a wheel over it scrolls it. */
    scrolls : bool,
}

/** What of a node is shown: its rectangle inside every clipping box above it; empty when none of it is. */
visible :: fn(ui: ptr[mut Ui], index: u32) -> Hit {
    made :: node(ui, index)
    shown := Hit.{x0 = made.x, y0 = made.y, x1 = made.x + made.w, y1 = made.y + made.h}
    at := made.parent
    for step in cast[usize](0)..<MAX_NODES {
        if at == NO_NODE {
            break
        }
        above :: node(ui, at)
        if above.box.clip {
            shown.x0 = max_of(shown.x0, above.x)
            shown.y0 = max_of(shown.y0, above.y)
            shown.x1 = if above.x + above.w < shown.x1 { above.x + above.w } else { shown.x1 }
            shown.y1 = if above.y + above.h < shown.y1 { above.y + above.h } else { shown.y1 }
        }
        at = above.parent
    }
    return shown
}

/** The frame's events, in order; valid until the next begin. */
events_of :: fn(ui: ptr[Ui]) -> Event[] {
    return ui.events[0..<ui.events.count]
}

/** An event's text, as a Copied's: valid until the next begin. */
event_text :: fn(ui: ptr[Ui], event: Event) -> u8[] {
    return text_of(ui.text[0..<ui.text.count], event.text_start, event.text_count)
}

/** Swap the frame's draw list and text into the last frame's, for the next comparison. */
swap_lists :: fn(ui: ptr[mut Ui]) {
    runtime.array_reset(&ui.last_commands)
    for command in ui.commands {
        runtime.array_add(&ui.last_commands, command)
    }
    runtime.array_reset(&ui.last_text)
    for byte in ui.text {
        runtime.array_add(&ui.last_text, byte)
    }
}

/** The line height of a size of the proportional face. */
line_height :: fn(ui: ptr[Ui], size: f32) -> f32 {
    font :: fonts.open(ui.sans) or_else fonts.Font.{}
    return if font.units_per_em == 0 { size * 1.4 } else { fonts.line_height(&font, size) }
}
