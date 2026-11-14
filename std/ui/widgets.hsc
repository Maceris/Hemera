package ui

import runtime from "base"
import fonts from "std"

/** A check box's side, in pixels. */
CHECK : f32 : 16

/** Which of a list's items are made this frame: from first, up to but not including last. */
Range :: struct {
    /** The first item made. */
    first : usize,
    /** One past the last item made. */
    last : usize,
}

/** Open a node by its label's hash, for a widget; its index, or NO_NODE when it's dropped. */
open_node :: fn(ui: ptr[mut Ui], label: u64, box: Box) -> u32 {
    index :: add_node(ui, label, box)
    if index == NO_NODE {
        ui.dropped += 1
        return NO_NODE
    }
    ui.open = index
    return index
}

/** Name a node, for a reader of the tree and for selectors, with text kept in the frame. */
name_node :: fn(ui: ptr[mut Ui], index: u32, name: u8[]) {
    start, count :: keep_text(ui, name)
    made :: node(ui, index)
    made.name_start = start
    made.name_count = count
}

/** Whether a press on a widget came up over it this frame: a click. */
clicked_now :: fn(ui: ptr[Ui], id: ID) -> bool {
    return ui.input.released && ui.active == id && ui.hover == id
}

/** Whether a key was pressed this frame. */
key_pressed :: fn(ui: ptr[Ui], key: Key) -> bool {
    for i in cast[usize](0)..<ui.input.key_count {
        if i < ui.input.keys.count && ui.input.keys[i].key == key {
            return true
        }
    }
    return false
}

/**
 * A button: its label in a box, drawn as it's hovered or pressed, and focusable.
 *
 * @param ui The UI.
 * @param label Its text, which with key is its ID.
 * @param key Mixed into its ID, to tell apart buttons of one label under one parent.
 * @return Whether it was clicked this frame, by the pointer or by Enter while it's focused; a Clicked event too.
 */
button :: fn(ui: ptr[mut Ui], label: string, key: u64 = 0) -> bool {
    theme :: ui.theme
    index :: open_node(ui, hash(string_bytes(label)), Box.{key = key, direction = .Row, padding_x = theme.padding_x,
        padding_y = theme.padding_y, corner = theme.corner, align_x = .Center, align_y = .Center, role = .Button})
    if index == NO_NODE {
        close(ui)
        return false
    }
    made :: node(ui, index)
    id :: made.id
    made.clickable = true
    made.focusable = true
    pressed :: ui.active == id && ui.input.down && ui.hover == id
    made.box.background = if pressed { theme.button_pressed } else if ui.hover == id { theme.button_hover } else { theme.button }
    made.box.border = if ui.focus == id { theme.accent } else { Colour.{} }
    name_node(ui, index, string_bytes(label))
    _ = label_text(ui, string_bytes(label), TextStyle.{wrap = false})
    close(ui)
    clicked :: clicked_now(ui, id) || (ui.focus == id && key_pressed(ui, .Enter))
    if clicked {
        runtime.array_add(&ui.events, Event.{kind = .Clicked, id = id})
    }
    return clicked
}

/** Add text under the open node, its ID from its bytes. */
label_text :: fn(ui: ptr[mut Ui], text: u8[], style: TextStyle) -> u32 {
    index :: add_node(ui, hash(text), Box.{role = .Text})
    if index == NO_NODE {
        return NO_NODE
    }
    start, count :: keep_text(ui, text)
    made :: node(ui, index)
    made.is_text = true
    made.text_start = start
    made.text_count = count
    made.style = style
    made.name_start = start
    made.name_count = count
    return index
}

/**
 * A check box with its label, toggled by a click or Enter.
 *
 * @param ui The UI.
 * @param label Its text, which with key is its ID.
 * @param value Whether it's checked, the program's, changed when it's toggled.
 * @param key Mixed into its ID.
 * @return Whether it was toggled this frame; a Toggled event too.
 */
checkbox :: fn(ui: ptr[mut Ui], label: string, value: ptr[mut bool], key: u64 = 0) -> bool {
    theme :: ui.theme
    index :: open_node(ui, hash(string_bytes(label)), Box.{key = key, direction = .Row, gap = 8, align_y = .Center, role = .CheckBox})
    if index == NO_NODE {
        close(ui)
        return false
    }
    made :: node(ui, index)
    id :: made.id
    made.clickable = true
    made.focusable = true
    toggled :: clicked_now(ui, id) || (ui.focus == id && key_pressed(ui, .Enter))
    if toggled {
        value^ = !value^
        runtime.array_add(&ui.events, Event.{kind = .Toggled, id = id, value = if value^ { cast[i64](1) } else { cast[i64](0) }})
    }
    made.checked = value^
    name_node(ui, index, string_bytes(label))
    _ = open_node(ui, hash(string_bytes("mark")), Box.{width = fixed(CHECK), height = fixed(CHECK), corner = 3,
        background = if value^ { theme.accent } else { theme.field }, border = if ui.focus == id { theme.accent } else { theme.edge }})
    close(ui)
    _ = label_text(ui, string_bytes(label), TextStyle.{wrap = false})
    close(ui)
    return toggled
}

/**
 * A scroll area: a box whose children scroll down within it, by the wheel over it; widgets after it go in it, until
 * close.
 *
 * @param ui The UI.
 * @param label What tells it from its siblings; with box's key, its ID.
 * @param box How it's laid out; it's clipped, and its height is what it shows, not its content's.
 * @return Its ID.
 */
scroll_area :: fn(ui: ptr[mut Ui], label: string, box: Box) -> ID {
    made := box
    made.clip = true
    made.role = if box.role == .Group { Role.ScrollArea } else { box.role }
    index :: open_node(ui, key(label), made)
    if index == NO_NODE {
        return 0
    }
    node(ui, index).scrolls = true
    return node(ui, index).id
}

/**
 * A list of many items, virtualized: of count items row_height tall, only those it shows are made, the rest stood in
 * for by space above and below them. The program makes items first to last, each row_height tall (list_item), then
 * calls end_list.
 *
 * @param ui The UI.
 * @param label What tells it from its siblings, its ID.
 * @param count How many items there are.
 * @param row_height Each item's height, in pixels, more than 0.
 * @param box How it's laid out: its height is what it shows.
 * @return Which items to make this frame.
 */
list :: fn(ui: ptr[mut Ui], label: string, count: usize, row_height: f32, box: Box) -> Range {
    made := box
    made.role = .List
    id :: scroll_area(ui, label, made)
    if id == 0 || row_height <= 0 {
        return Range.{}
    }
    place :: kept_of(ui, id)
    // Its first frame shows what its height says, or nothing until it's laid out
    shown :: if place.id != 0 { place.h } else if box.height.kind == .Fixed { box.height.value } else { cast[f32](0) }
    first := cast[usize](floor_of(place.scroll / row_height))
    first = if first > count { count } else { first }
    after :: cast[usize](ceil_of((place.scroll + shown) / row_height)) + 1
    last :: if after > count { count } else { after }
    if first > 0 {
        _ = open_node(ui, key("above"), Box.{height = fixed(cast[f32](first) * row_height)})
        close(ui)
    }
    return Range.{first = first, last = last}
}

/** One of a list's items, row_height tall and as wide as the list; widgets after it go in it, until close. */
list_item :: fn(ui: ptr[mut Ui], item: usize, row_height: f32, box: Box = Box.{}) -> ID {
    made := box
    made.key = cast[u64](item)
    made.height = fixed(row_height)
    made.width = grow()
    made.role = .ListItem
    index :: open_node(ui, key("item"), made)
    return if index == NO_NODE { cast[u64](0) } else { node(ui, index).id }
}

/** End a list: the space for the items after those made, and the list closed. */
end_list :: fn(ui: ptr[mut Ui], range: Range, count: usize, row_height: f32) {
    if range.last < count {
        _ = open_node(ui, key("below"), Box.{height = fixed(cast[f32](count - range.last) * row_height)})
        close(ui)
    }
    close(ui)
}

// ---- Text fields

/**
 * A field of text, one line, edited while it's focused: typed and pasted text inserted, the cursor moved with the
 * arrows, Home and End, Shift selecting; Backspace and Delete; Ctrl+A, C, X, Z and Y. Only the focused field keeps an
 * editing state: its cursor, selection and what it can undo.
 *
 * @param ui The UI.
 * @param name What it's for, which with key is its ID, and its name to a reader of the tree.
 * @param text Its text, the program's, UTF-8, changed as it's edited.
 * @param width Its width.
 * @param key Mixed into its ID.
 * @param secret Whether it's a password's: shown as a star a byte, its cursor kept at its end, and nothing copied or
 *     cut from it.
 * @return Whether its text changed this frame; Changed, Submitted (Enter) and Copied (Ctrl+C or X) events too.
 */
text_field :: fn(ui: ptr[mut Ui], name: string, text: ptr[mut u8[..]], width: Axis = grow(), key: u64 = 0, secret: bool = false) -> bool {
    theme :: ui.theme
    index :: open_node(ui, hash(string_bytes(name)), Box.{key = key, width = width, padding_x = theme.padding_x / 2, padding_y = theme.padding_y,
        corner = theme.corner, clip = true, role = .TextField, background = theme.field})
    if index == NO_NODE {
        close(ui)
        return false
    }
    made :: node(ui, index)
    id :: made.id
    made.clickable = true
    made.focusable = true
    made.box.border = if ui.focus == id { theme.accent } else { theme.edge }
    name_node(ui, index, string_bytes(name))
    // A press on it focuses it, its cursor where it was pressed
    pressed_on :: ui.input.pressed && ui.hover == id
    if pressed_on {
        set_focus(ui, id)
    }
    changed := false
    if ui.focus == id {
        if ui.editing.id != id {
            stop_editing(ui)
            ui.editing.id = id
            ui.editing.cursor = text.count
            ui.editing.anchor = text.count
        }
        if pressed_on {
            at :: offset_at(ui, id, contents(text), ui.input.pointer_x)
            ui.editing.cursor = at
            ui.editing.anchor = at
        }
        if secret {
            // Typed at its end, and only its end: what's typed can't be read back through a selection
            ui.editing.cursor = text.count
            ui.editing.anchor = text.count
            changed = edit(ui, id, text, true)
            ui.editing.cursor = text.count
            ui.editing.anchor = text.count
        }
        else {
            changed = edit(ui, id, text, false)
        }
    }
    // Its text, as it is after the edits, with its cursor if it's focused
    stars : u8[..]
    defer runtime.array_free(&stars)
    if secret {
        for byte in contents(text) {
            runtime.array_add(&stars, cast[u8]('*'))
        }
    }
    shown :: label_text(ui, if secret { stars[0..<stars.count] } else { contents(text) }, TextStyle.{wrap = false})
    if shown != NO_NODE {
        node(ui, shown).edited = ui.focus == id
        // An empty field's text is still a line tall
        node(ui, shown).box.height = fit(line_height(ui, theme.text_size))
    }
    close(ui)
    if changed {
        runtime.array_add(&ui.events, Event.{kind = .Changed, id = id})
    }
    return changed
}

/** Where in text a point across a field falls, by the field's place last frame: the nearest gap between characters. */
offset_at :: fn(ui: ptr[Ui], id: ID, text: u8[], x: f32) -> usize {
    place :: kept_of(ui, id)
    font :: fonts.open(ui.sans) or_else fonts.Font.{}
    across :: x - place.x - ui.theme.padding_x / 2
    best := cast[usize](0)
    best_distance := cast[f32](1.0e9)
    for at in cast[usize](0)..<text.count + 1 {
        if at < text.count && is_continuation(text[at % text.count]) {
            continue
        }
        width :: fonts.measure(&font, ui.theme.text_size, slice(text, 0, at))
        distance :: if width > across { width - across } else { across - width }
        if distance < best_distance {
            best = at
            best_distance = distance
        }
    }
    return best
}

/** Whether a byte continues a UTF-8 character, not starting one. */
is_continuation :: fn(byte: u8) -> bool {
    return byte & 0xc0 == 0x80
}

/** The start of the character before an offset in text. */
before :: fn(text: u8[], at: usize) -> usize {
    place := if at > text.count { text.count } else { at }
    if place == 0 {
        return 0
    }
    place -= 1
    for step in cast[usize](0)..<4 {
        if place == 0 || place >= text.count || !is_continuation(text[place]) {
            break
        }
        place -= 1
    }
    return place
}

/** The end of the character after an offset in text. */
after :: fn(text: u8[], at: usize) -> usize {
    if at >= text.count {
        return text.count
    }
    place := at + 1
    for step in cast[usize](0)..<4 {
        if place >= text.count || !is_continuation(text[place % text.count]) {
            break
        }
        place += 1
    }
    return place
}

/** Apply the frame's input to the field being edited: its keys in order, then what's typed and pasted; a secret one's never copied. */
edit :: fn(ui: ptr[mut Ui], id: ID, text: ptr[mut u8[..]], secret: bool) -> bool {
    changed := false
    editing :: &ui.editing
    editing.cursor = if editing.cursor > text.count { text.count } else { editing.cursor }
    editing.anchor = if editing.anchor > text.count { text.count } else { editing.anchor }
    for i in cast[usize](0)..<ui.input.key_count {
        if i >= ui.input.keys.count {
            break
        }
        press :: ui.input.keys[i]
        current :: contents(text)
        match press.key {
            case .Left => move_cursor(editing, if editing.cursor != editing.anchor && !press.shift { low_end(editing) } else { before(current, editing.cursor) }, press.shift)
            case .Right => move_cursor(editing, if editing.cursor != editing.anchor && !press.shift { high_end(editing) } else { after(current, editing.cursor) }, press.shift)
            case .Home => move_cursor(editing, 0, press.shift)
            case .End => move_cursor(editing, text.count, press.shift)
            case .Backspace => {
                if editing.cursor == editing.anchor {
                    editing.anchor = before(current, editing.cursor)
                }
                changed = replace(ui, text, "") || changed
            }
            case .Delete => {
                if editing.cursor == editing.anchor {
                    editing.anchor = after(current, editing.cursor)
                }
                changed = replace(ui, text, "") || changed
            }
            case .SelectAll => {
                editing.anchor = 0
                editing.cursor = text.count
            }
            case .Copy => {
                if !secret {
                    copied(ui, id, contents(text))
                }
            }
            case .Cut => {
                if !secret {
                    copied(ui, id, contents(text))
                    changed = replace(ui, text, "") || changed
                }
            }
            case .Undo => changed = undo(ui, text, false) || changed
            case .Redo => changed = undo(ui, text, true) || changed
            case .Enter => runtime.array_add(&ui.events, Event.{kind = .Submitted, id = id})
            case .Escape => set_focus(ui, 0)
            case _ => {}
        }
    }
    if ui.typed.count > 0 {
        changed = replace(ui, text, string_of_bytes(ui.typed[0..<ui.typed.count])) || changed
    }
    if ui.pasted.count > 0 {
        changed = replace(ui, text, string_of_bytes(ui.pasted[0..<ui.pasted.count])) || changed
    }
    return changed
}

/** A field's text as it is, a view onto the program's array. */
contents :: fn(text: ptr[u8[..]]) -> u8[] {
    held :: text^
    return held[0..<held.count]
}

/** Bytes as a string, for an insertion. */
string_of_bytes :: fn(bytes: u8[]) -> string {
    return if bytes.count > 0 { string_of(&bytes[0], bytes.count) } else { "" }
}

/** The selection's start. */
low_end :: fn(editing: ptr[Editing]) -> usize {
    return if editing.cursor < editing.anchor { editing.cursor } else { editing.anchor }
}

/** The selection's end. */
high_end :: fn(editing: ptr[Editing]) -> usize {
    return if editing.cursor < editing.anchor { editing.anchor } else { editing.cursor }
}

/** Move the cursor, the selection's other end staying with Shift, or coming with it. */
move_cursor :: fn(editing: ptr[mut Editing], to: usize, extending: bool) {
    editing.cursor = to
    if !extending {
        editing.anchor = to
    }
}

/** A Copied event with the selection's text, if there's a selection. */
copied :: fn(ui: ptr[mut Ui], id: ID, text: u8[]) {
    low :: low_end(&ui.editing)
    high :: high_end(&ui.editing)
    if high <= low {
        return void
    }
    start, count :: keep_text(ui, slice(text, low, high))
    runtime.array_add(&ui.events, Event.{kind = .Copied, id = id, text_start = start, text_count = count})
}

/**
 * Replace the selection, or insert at the cursor, with text: what can be undone kept first, what could be redone
 * dropped.
 *
 * @return Whether the text changed.
 */
replace :: fn(ui: ptr[mut Ui], text: ptr[mut u8[..]], replacement: string) -> bool {
    low :: low_end(&ui.editing)
    high :: high_end(&ui.editing)
    inserted :: string_bytes(replacement)
    if low == high && inserted.count == 0 {
        return false
    }
    remember(ui, contents(text))
    made : u8[..]
    defer runtime.array_free(&made)
    for byte in slice(contents(text), 0, low) {
        runtime.array_add(&made, byte)
    }
    for byte in inserted {
        runtime.array_add(&made, byte)
    }
    for byte in slice(contents(text), high, text.count) {
        runtime.array_add(&made, byte)
    }
    runtime.array_reset(text)
    for byte in made {
        runtime.array_add(text, byte)
    }
    ui.editing.cursor = low + inserted.count
    ui.editing.anchor = ui.editing.cursor
    ui.editing.redo_count = 0
    return true
}

/** Keep text and the cursor as what an undo goes back to; past MAX_UNDO, the oldest is dropped. */
remember :: fn(ui: ptr[mut Ui], text: u8[]) {
    editing :: &ui.editing
    if editing.undo_count >= MAX_UNDO {
        // The oldest dropped, the rest moved down
        for i in cast[usize](1)..<MAX_UNDO {
            first :: editing.undo[i - 1].text
            editing.undo[i - 1].text = editing.undo[i].text
            editing.undo[i - 1].cursor = editing.undo[i].cursor
            editing.undo[i].text = first
        }
        editing.undo_count = MAX_UNDO - 1
    }
    at :: editing.undo_count
    if at < MAX_UNDO {
        runtime.array_reset(&editing.undo[at].text)
        for byte in text {
            runtime.array_add(&editing.undo[at].text, byte)
        }
        editing.undo[at].cursor = editing.cursor
        editing.undo_count += 1
    }
}

/**
 * Undo the last edit, or redo the last undone: the text swapped with what was kept, so the swap is what's redone or
 * undone next.
 *
 * @return Whether the text changed.
 */
undo :: fn(ui: ptr[mut Ui], text: ptr[mut u8[..]], again: bool) -> bool {
    editing :: &ui.editing
    if again {
        if editing.redo_count == 0 || editing.undo_count >= MAX_UNDO {
            return false
        }
        editing.redo_count -= 1
        editing.undo_count += 1
    }
    else {
        if editing.undo_count == 0 {
            return false
        }
        editing.undo_count -= 1
        editing.redo_count += 1
    }
    at :: if again { editing.undo_count - 1 } else { editing.undo_count }
    if at >= MAX_UNDO {
        return false
    }
    // What's there now goes where what's restored was, for the way back
    kept : u8[..]
    defer runtime.array_free(&kept)
    for byte in text^ {
        runtime.array_add(&kept, byte)
    }
    cursor :: editing.cursor
    runtime.array_reset(text)
    for byte in editing.undo[at].text {
        runtime.array_add(text, byte)
    }
    editing.cursor = if editing.undo[at].cursor > text.count { text.count } else { editing.undo[at].cursor }
    editing.anchor = editing.cursor
    runtime.array_reset(&editing.undo[at].text)
    for byte in kept {
        runtime.array_add(&editing.undo[at].text, byte)
    }
    editing.undo[at].cursor = cursor
    return true
}

/** Drop the editing state, as its field lost focus or went: its cursor, selection and undo. */
stop_editing :: fn(ui: ptr[mut Ui]) {
    ui.editing.id = 0
    ui.editing.cursor = 0
    ui.editing.anchor = 0
    ui.editing.undo_count = 0
    ui.editing.redo_count = 0
}
