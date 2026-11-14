/*
 * std/ui, driven by frames of synthetic input: rows and columns sized Fixed, Grow, Percent and Fit; text wrapped to its
 * width; buttons clicked, check boxes toggled and focus moved with Tab; a text field edited, its selection copied and
 * its edits undone and redone; a list of a thousand items made ten at a time and scrolled; the draw list compared, so
 * a frame that changes nothing has no damage; state dropped with its widget; frames painted; duplicate IDs told
 * apart; selectors; and any input taken without harm.
 */
package ui_test

import runtime from "base"
import canvas from "std"
import strings from "std"
import testing from "std"
import ui from "std"

SANS :: #file_data("../../fonts/NotoSans-Regular.ttf")
MONO :: #file_data("../../fonts/NotoSansMono-Regular.ttf")
/** The frame's size, in pixels. */
WIDTH :: 400
HEIGHT :: 300

/** A frame's pixels, on the heap. */
Board :: struct {
    /** BGRA, WIDTH by HEIGHT. */
    pixels : u8[WIDTH * HEIGHT * 4],
}

/** A UI on the heap, its typefaces the test's. */
new_ui :: fn() -> ptr[mut ui.Ui] {
    made :: runtime.new(ui.Ui)
    made^ = ui.make(SANS[0..<SANS.count], MONO[0..<MONO.count])
    return made
}

/** Give a UI back. */
free :: fn(u: ptr[mut ui.Ui]) {
    ui.free_ui(u)
    runtime.free(u)
}

/** Whether two numbers are within a tolerance, noted if they're not. */
near :: fn(t: ptr[mut testing.T], found: f32, expected: f32, tolerance: f32, what: string) {
    difference :: found - expected
    if difference > tolerance || difference < -tolerance {
        testing.note(t, strings.format("found %, expected %", found, expected) or_else "")
        testing.fail(t, what)
    }
}

/** An input with the pointer at a place. */
at :: fn(x: f32, y: f32) -> ui.Input {
    return ui.Input.{pointer_x = x, pointer_y = y}
}

/** Where a widget was laid out. */
place :: fn(u: ptr[ui.Ui], id: ui.ID) -> ui.Kept {
    return ui.kept_of(u, id)
}

lays_out_rows_and_columns #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    row :: ui.open(u, "row", ui.Box.{direction = .Row, width = ui.grow(), padding_x = 10, padding_y = 4, gap = 5})
    first :: ui.open(u, "first", ui.Box.{width = ui.fixed(50), height = ui.fixed(20)})
    ui.close(u)
    middle :: ui.open(u, "middle", ui.Box.{width = ui.grow(), height = ui.fixed(20)})
    ui.close(u)
    last :: ui.open(u, "last", ui.Box.{width = ui.fixed(30), height = ui.grow()})
    ui.close(u)
    ui.close(u)
    half :: ui.open(u, "half", ui.Box.{width = ui.percent(50), height = ui.fixed(10)})
    ui.close(u)
    wide :: ui.open(u, "wide", ui.Box.{width = ui.grow(max = 120), height = ui.fixed(10), align_x = .Center})
    ui.close(u)
    _ = ui.end(u)
    near(t, place(u, row).w, WIDTH, 0.01, "a growing row is as wide as its column")
    near(t, place(u, row).h, 28, 0.01, "and as tall as its tallest child and its padding")
    near(t, place(u, first).x, 10, 0.01, "its first child starts after its padding")
    near(t, place(u, middle).w, WIDTH - 20 - 50 - 30 - 10, 0.01, "a growing child takes what's left after the others and the gaps")
    near(t, place(u, middle).x, 65, 0.01, "after the first and a gap")
    near(t, place(u, last).h, 20, 0.01, "a child growing across a row is as tall as the row's inside")
    near(t, place(u, half).w, WIDTH / 2, 0.01, "a percent is of the parent's content")
    near(t, place(u, wide).w, 120, 0.01, "growing stops at its most")
    near(t, place(u, half).y, 28, 0.01, "a column's children go down, one after another")
    return .Ok
}

wraps_text #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.open(u, "narrow", ui.Box.{width = ui.fixed(100)})
    long :: ui.label(u, "the quick brown fox jumps over the lazy dog")
    ui.close(u)
    short :: ui.label(u, "one line")
    _ = ui.end(u)
    line :: place(u, short).h
    testing.expect(t, line > 14 && line < 30, "a line's as tall as the face says")
    testing.expect(t, place(u, long).h > 2.5 * line, "text wraps to its box's width, line after line")
    testing.expect(t, place(u, long).w <= 100, "and is no wider than it")
    testing.expect(t, place(u, short).w < 100 && place(u, short).w > 30, "text that fits is as wide as it is")
    return .Ok
}

/** Run a frame with one button, giving whether it was clicked. */
button_frame :: fn(u: ptr[mut ui.Ui], input: ui.Input) -> bool {
    ui.begin(u, input, WIDTH, HEIGHT)
    clicked :: ui.button(u, "Save")
    _ = ui.end(u)
    return clicked
}

clicks_buttons #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    _ = button_frame(u, ui.Input.{})
    id :: ui.find(u, "//text=Save") or_else 0
    testing.require(t, id != 0, "a selector finds the button by its label")?
    spot :: ui.middle_of(u, id) or_else ui.Spot.{x = -1, y = -1}
    x :: spot.x
    y :: spot.y
    _ = button_frame(u, at(x, y))
    down := at(x, y)
    down.pressed = true
    down.down = true
    testing.expect(t, !button_frame(u, down), "a press isn't a click")
    up := at(x, y)
    up.released = true
    testing.expect(t, button_frame(u, up), "a press and release over it is")
    events :: ui.events_of(u)
    testing.expect(t, events.count == 1 && events[0].kind == .Clicked && events[0].id == id, "and a Clicked event")
    // Pressed on it, let go elsewhere: not a click
    down.pointer_x = x
    _ = button_frame(u, down)
    away := at(WIDTH - 1, HEIGHT - 1)
    away.released = true
    _ = button_frame(u, at(WIDTH - 1, HEIGHT - 1))
    testing.expect(t, !button_frame(u, away), "a press let go away from it isn't a click")
    return .Ok
}

/** Run a frame with two check boxes. */
checks_frame :: fn(u: ptr[mut ui.Ui], input: ui.Input, a: ptr[mut bool], b: ptr[mut bool]) {
    ui.begin(u, input, WIDTH, HEIGHT)
    _ = ui.checkbox(u, "Wrap lines", a)
    _ = ui.checkbox(u, "Show hidden", b)
    _ = ui.end(u)
}

toggles_and_moves_focus #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    a := false
    b := true
    checks_frame(u, ui.Input.{}, &a, &b)
    first :: ui.find(u, "//role=checkbox") or_else 0
    spot :: ui.middle_of(u, first) or_else ui.Spot.{x = -1, y = -1}
    x :: spot.x
    y :: spot.y
    checks_frame(u, at(x, y), &a, &b)
    down := at(x, y)
    down.pressed = true
    down.down = true
    checks_frame(u, down, &a, &b)
    up := at(x, y)
    up.released = true
    checks_frame(u, up, &a, &b)
    testing.expect(t, a && b, "a click toggles the box it's on, and only it")
    // Tab from the first, focused by its press, to the second; Enter toggles it
    tabbed := ui.Input.{}
    ui.press_key(&tabbed, .Tab)
    checks_frame(u, tabbed, &a, &b)
    second :: ui.find(u, "//text=Show hidden") or_else 0
    testing.expect(t, u.focus == second && second != 0, "Tab moves focus to the next")
    entered := ui.Input.{}
    ui.press_key(&entered, .Enter)
    checks_frame(u, entered, &a, &b)
    testing.expect(t, !b && a, "Enter toggles the focused box")
    back := ui.Input.{}
    ui.press_key(&back, .Tab, true)
    checks_frame(u, back, &a, &b)
    testing.expect(t, u.focus == first, "Shift+Tab moves it back")
    nodes : ui.Accessible[..]
    defer runtime.array_free(&nodes)
    ui.accessible(u, &nodes)
    found := 0
    for each in nodes {
        if each.role == .CheckBox {
            found += 1
            testing.expect(t, each.checked == (each.id == first), "the tree says which box is checked")
        }
    }
    testing.expect(t, found == 2, "the tree has both boxes")
    return .Ok
}

/** Run a frame with a text field over text, giving whether it changed. */
field_frame :: fn(u: ptr[mut ui.Ui], input: ui.Input, text: ptr[mut u8[..]]) -> bool {
    ui.begin(u, input, WIDTH, HEIGHT)
    changed :: ui.text_field(u, "Name", text)
    _ = ui.end(u)
    return changed
}

/** Text as a string, to compare. */
as_text :: fn(text: ptr[u8[..]]) -> string {
    held :: text^
    bytes :: held[0..<held.count]
    return if bytes.count > 0 { string_of(&bytes[0], bytes.count) } else { "" }
}

/** An input with keys pressed. */
keys :: fn(pressed: ui.Key[], shift: bool = false) -> ui.Input {
    made := ui.Input.{}
    for key in pressed {
        ui.press_key(&made, key, shift)
    }
    return made
}

edits_text #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    text : u8[..]
    defer runtime.array_free(&text)
    _ = field_frame(u, ui.Input.{}, &text)
    field :: ui.find(u, "//role=textfield") or_else 0
    spot :: ui.middle_of(u, field) or_else ui.Spot.{x = -1, y = -1}
    x :: spot.x
    y :: spot.y
    _ = field_frame(u, at(x, y), &text)
    press := at(x, y)
    press.pressed = true
    press.down = true
    _ = field_frame(u, press, &text)
    testing.expect(t, u.focus == field && field != 0, "a press focuses the field")
    typed := ui.Input.{text = string_bytes("hello")}
    testing.expect(t, field_frame(u, typed, &text) && as_text(&text) == "hello", "typing goes into it")
    _ = field_frame(u, keys(ui.Key.[ui.Key.Left, ui.Key.Left, ui.Key.Backspace]), &text)
    testing.expect(t, as_text(&text) == "helo", "the cursor moves back, and Backspace deletes before it")
    _ = field_frame(u, keys(ui.Key.[ui.Key.SelectAll, ui.Key.Copy]), &text)
    copied := false
    for event in ui.events_of(u) {
        if event.kind == .Copied {
            bytes :: ui.event_text(u, event)
            copied = bytes.count == 4 && string_of(&bytes[0], 4) == "helo"
        }
    }
    testing.expect(t, copied, "Ctrl+A and Ctrl+C copy it all, for the program to offer")
    _ = field_frame(u, keys(ui.Key.[ui.Key.Undo]), &text)
    testing.expect(t, as_text(&text) == "hello", "Ctrl+Z undoes the deletion")
    _ = field_frame(u, keys(ui.Key.[ui.Key.Redo]), &text)
    testing.expect(t, as_text(&text) == "helo", "and Ctrl+Y redoes it")
    _ = field_frame(u, keys(ui.Key.[ui.Key.End]), &text)
    _ = field_frame(u, keys(ui.Key.[ui.Key.Left, ui.Key.Left], true), &text)
    _ = field_frame(u, ui.Input.{text = string_bytes("p!")}, &text)
    testing.expect(t, as_text(&text) == "hep!", "Shift selects, and typing replaces the selection")
    pasted := ui.Input.{pasted = string_bytes(" pasted")}
    _ = field_frame(u, pasted, &text)
    testing.expect(t, as_text(&text) == "hep! pasted", "a paste goes in at the cursor")
    _ = field_frame(u, keys(ui.Key.[ui.Key.Enter]), &text)
    submitted := false
    for event in ui.events_of(u) {
        submitted = submitted || (event.kind == .Submitted && event.id == field)
    }
    testing.expect(t, submitted, "Enter submits it")
    // UTF-8: Backspace takes a whole character
    _ = field_frame(u, ui.Input.{text = string_bytes("é")}, &text)
    _ = field_frame(u, keys(ui.Key.[ui.Key.Backspace]), &text)
    testing.expect(t, as_text(&text) == "hep! pasted", "Backspace deletes a character's every byte")
    return .Ok
}

drops_state_with_its_widget #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    text : u8[..]
    defer runtime.array_free(&text)
    _ = field_frame(u, ui.Input.{}, &text)
    field :: ui.find(u, "//role=textfield") or_else 0
    u.focus = field
    _ = field_frame(u, ui.Input.{text = string_bytes("x")}, &text)
    testing.expect(t, u.editing.id == field, "the focused field has the editing state")
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.label(u, "the field's gone")
    _ = ui.end(u)
    testing.expect(t, u.focus == 0 && u.editing.id == 0, "a frame without it drops its focus and editing")
    testing.expect(t, ui.kept_of(u, field).id == 0, "and what was kept for it")
    return .Ok
}

/** Run a frame with a list of a thousand items, giving which were made. */
list_frame :: fn(u: ptr[mut ui.Ui], input: ui.Input) -> ui.Range {
    ui.begin(u, input, WIDTH, HEIGHT)
    range :: ui.list(u, "items", 1000, 20, ui.Box.{width = ui.grow(), height = ui.fixed(200)})
    for item in range.first..<range.last {
        _ = ui.list_item(u, item, 20)
        _ = ui.label(u, strings.format("Item %", item) or_else "", key = cast[u64](item))
        ui.close(u)
    }
    ui.end_list(u, range, 1000, 20)
    _ = ui.end(u)
    return range
}

virtualizes_lists #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    first :: list_frame(u, ui.Input.{})
    testing.expect(t, first.first == 0 && first.last <= 12, "only the items it shows are made")
    testing.expect(t, (ui.find(u, "//text=Item 3") is_some) && (ui.find(u, "//text=Item 40") is_none), "the rest aren't in the tree")
    list :: ui.find(u, "//role=list") or_else 0
    testing.expect(t, place(u, list).h == 200 && ui.kept_of(u, list).content_h >= 20000, "it shows 200 pixels of 20000")
    spot :: ui.middle_of(u, list) or_else ui.Spot.{x = -1, y = -1}
    x :: spot.x
    y :: spot.y
    _ = list_frame(u, at(x, y))
    wheel := at(x, y)
    wheel.wheel = -10
    _ = list_frame(u, wheel)
    scrolled :: list_frame(u, at(x, y))
    testing.expect(t, scrolled.first > 0, "the wheel over it scrolls it down")
    shown :: ui.find(u, strings.format("//text=Item %", scrolled.first + 2) or_else "") or_else 0
    testing.expect(t, shown != 0, "and the items it shows now are made")
    item :: place(u, shown)
    testing.expect(t, item.y >= place(u, list).y - 20 && item.y < place(u, list).y + 200, "where it shows them")
    return .Ok
}

compares_draw_lists #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.button(u, "Save")
    first :: ui.end(u)
    testing.expect(t, first.damage.x1 - first.damage.x0 == WIDTH && first.damage.y1 - first.damage.y0 == HEIGHT, "the first frame's damage is all of it")
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.button(u, "Save")
    same :: ui.end(u)
    testing.expect(t, canvas.is_empty(same.damage), "a frame that changes nothing has no damage")
    button :: place(u, ui.find(u, "//role=button") or_else 0)
    ui.begin(u, at(button.x + 2, button.y + 2), WIDTH, HEIGHT)
    _ = ui.button(u, "Save")
    hovered :: ui.end(u)
    testing.expect(t, !canvas.is_empty(hovered.damage) && hovered.damage.x1 <= cast[i32](button.x + button.w) + 1
        && hovered.damage.y1 <= cast[i32](button.y + button.h) + 1, "a button the pointer comes over is its own damage, at once")
    ui.begin(u, at(button.x + 3, button.y + 2), WIDTH, HEIGHT)
    _ = ui.button(u, "Save")
    still :: ui.end(u)
    testing.expect(t, canvas.is_empty(still.damage), "and moving over it changes nothing more")
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.button(u, "Save")
    away :: ui.end(u)
    testing.expect(t, !canvas.is_empty(away.damage), "nor does it stay hovered once the pointer's gone")
    return .Ok
}

paints_frames #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    board :: runtime.new(Board)
    defer runtime.free(board)
    pixels :: &board.pixels
    painter := canvas.make(canvas.Image.{pixels = board.pixels[0..<WIDTH * HEIGHT * 4], width = WIDTH, height = HEIGHT, stride = WIDTH * 4})
    defer canvas.free_canvas(&painter)
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.open(u, "body", ui.Box.{width = ui.grow(), padding_x = 20, padding_y = 20})
    _ = ui.button(u, "A rather wide button")
    ui.close(u)
    frame :: ui.end(u)
    ui.paint(u, &painter, frame.damage)
    pixel :: fn(pixels: ptr[u8[WIDTH * HEIGHT * 4]], x: usize, y: usize) -> (u8, u8, u8) {
        at :: 4 * (y * WIDTH + x)
        return pixels[at % (WIDTH * HEIGHT * 4)], pixels[(at + 1) % (WIDTH * HEIGHT * 4)], pixels[(at + 2) % (WIDTH * HEIGHT * 4)]
    }
    b, g, r :: pixel(pixels, WIDTH - 2, HEIGHT - 2)
    theme :: u.theme
    testing.expect(t, r == theme.background.r && g == theme.background.g && b == theme.background.b, "the background's the theme's")
    button :: place(u, ui.find(u, "//role=button") or_else 0)
    // Inside the button, left of its text
    bb, bg, br :: pixel(pixels, cast[usize](button.x + 3), cast[usize](button.y + button.h / 2))
    testing.expect(t, br == theme.button.r && bg == theme.button.g && bb == theme.button.b, "a button's its colour")
    dark := 0
    for x in cast[usize](button.x)..<cast[usize](button.x + button.w) {
        cb, cg, cr :: pixel(pixels, x, cast[usize](button.y + button.h / 2))
        if cr < 100 {
            dark += 1
        }
    }
    testing.expect(t, dark > 10, "and its label's drawn across it")
    return .Ok
}

tells_duplicates_apart #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    ui.begin(u, ui.Input.{}, WIDTH, HEIGHT)
    _ = ui.button(u, "Same")
    _ = ui.button(u, "Same")
    _ = ui.button(u, "Same", key = 7)
    frame :: ui.end(u)
    testing.expect(t, frame.duplicates, "two of one label under one parent are reported")
    ids := 0
    for each in u.nodes {
        if each.box.role == .Button {
            ids += 1
        }
    }
    testing.expect(t, ids == 3, "and each is still made")
    testing.expect(t, ui.mix(ui.mix(1, 2), 0) != ui.mix(ui.mix(1, 3), 0) && ui.mix(1, 2) != ui.mix(2, 1), "mixing keeps order and values apart")
    KEY :: #run ui.key("Save")
    testing.expect(t, KEY == ui.key("Save"), "a label's key is the same made at compile time")
    return .Ok
}

takes_any_input #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    u :: new_ui()
    defer free(u)
    text : u8[..]
    defer runtime.array_free(&text)
    on := false
    bytes : u8[16]
    for frame in 0..<testing.draw_between(source, 1, 12) {
        input := ui.Input.{pointer_x = cast[f32](testing.draw_between(source, 0, WIDTH + 20)) - 10,
            pointer_y = cast[f32](testing.draw_between(source, 0, HEIGHT + 20)) - 10, wheel = cast[f32](testing.draw_between(source, 0, 20)) - 10}
        input.pressed = testing.draw_between(source, 0, 1) == 1
        input.released = testing.draw_between(source, 0, 1) == 1
        input.down = input.pressed
        pressed :: cast[usize](testing.draw_between(source, 0, 6))
        for k in cast[usize](0)..<ui.MAX_KEYS {
            if k < pressed {
                input.keys[k] = ui.KeyPress.{key = cast[ui.Key](cast[u8](testing.draw_between(source, 1, 18))), shift = testing.draw_between(source, 0, 1) == 1}
                input.key_count = k + 1
            }
        }
        count :: cast[usize](testing.draw_between(source, 0, 16))
        for i in cast[usize](0)..<16 {
            bytes[i] = cast[u8](testing.draw_between(source, 0, 255))
        }
        input.text = if count <= bytes.count { bytes[0..<count] } else { bytes[0..<0] }
        ui.begin(u, input, WIDTH, HEIGHT)
        _ = ui.text_field(u, "field", &text)
        _ = ui.checkbox(u, "box", &on)
        range :: ui.list(u, "list", 50, 18, ui.Box.{height = ui.fixed(90)})
        for item in range.first..<range.last {
            _ = ui.list_item(u, item, 18)
            _ = ui.button(u, "row")
            ui.close(u)
        }
        ui.end_list(u, range, 50, 18)
        _ = ui.end(u)
        testing.expect(t, u.editing.cursor <= text.count && u.editing.anchor <= text.count, "the cursor stays within the text")
    }
    return .Ok
}
