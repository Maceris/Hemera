package ui

import runtime from "base"
import canvas from "std"
import fonts from "std"

/** How deep boxes nest that the draw list goes into; deeper ones aren't drawn. */
MAX_DEPTH :: 256
/** The cursor's width, in pixels. */
CURSOR_WIDTH : f32 : 2

/** Make the frame's draw list from its laid-out tree, from the root down, each node before its children. */
make_commands :: fn(ui: ptr[mut Ui]) {
    runtime.array_reset(&ui.commands)
    if ui.nodes.count == 0 {
        return void
    }
    faces :: faces_of(ui)
    lines : fonts.Line[..]
    defer runtime.array_free(&lines)
    emit(ui, &faces, &lines, 0, 0)
}

/** Add a command to the frame's draw list. */
add_command :: fn(ui: ptr[mut Ui], command: Command) {
    runtime.array_add(&ui.commands, command)
}

/** Add a node's commands and its children's: its fill, its edge, its text, and a clip around its children. */
emit :: fn(ui: ptr[mut Ui], faces: ptr[Faces], lines: ptr[mut fonts.Line[..]], index: u32, depth: usize) {
    if depth >= MAX_DEPTH {
        return void
    }
    made :: node(ui, index)
    box :: made.box
    if box.background.a > 0 {
        add_command(ui, Command.{kind = .Fill, x = made.x, y = made.y, w = made.w, h = made.h, colour = box.background, corner = box.corner})
    }
    if box.border.a > 0 {
        add_command(ui, Command.{kind = .Border, x = made.x, y = made.y, w = made.w, h = made.h, colour = box.border, corner = box.corner})
    }
    if made.is_text {
        emit_text(ui, faces, lines, index)
    }
    if box.clip {
        add_command(ui, Command.{kind = .ClipStart, x = made.x, y = made.y, w = made.w, h = made.h})
    }
    child := made.first
    for step in cast[usize](0)..<MAX_NODES {
        if child == NO_NODE {
            break
        }
        emit(ui, faces, lines, child, depth + 1)
        child = node(ui, child).next
    }
    if box.clip {
        add_command(ui, Command.{kind = .ClipEnd})
    }
}

/**
 * Add a text node's lines, wrapped as it was laid out, and, for a text field's, its selection behind them and its
 * cursor after.
 */
emit_text :: fn(ui: ptr[mut Ui], faces: ptr[Faces], lines: ptr[mut fonts.Line[..]], index: u32) {
    made :: node(ui, index)
    style :: resolved(ui, made.style)
    font :: face(faces, style)
    text :: text_of(ui.text[0..<ui.text.count], made.text_start, made.text_count)
    runtime.array_reset(lines)
    fonts.wrap(font, style.size, text, if style.wrap { made.w + 0.5 } else { cast[f32](1.0e9) }, lines)
    height :: if font.units_per_em == 0 { style.size * 1.4 } else { fonts.line_height(font, style.size) }
    editing :: made.edited
    low :: if ui.editing.cursor < ui.editing.anchor { ui.editing.cursor } else { ui.editing.anchor }
    high :: if ui.editing.cursor < ui.editing.anchor { ui.editing.anchor } else { ui.editing.cursor }
    cursor_drawn := false
    for line, i in lines^ {
        top :: made.y + cast[f32](i) * height
        if editing && high > low && low < line.end && high > line.start {
            from :: if low > line.start { low } else { line.start }
            to :: if high < line.end { high } else { line.end }
            left :: made.x + fonts.measure(font, style.size, slice(text, line.start, from))
            right :: made.x + fonts.measure(font, style.size, slice(text, line.start, to))
            add_command(ui, Command.{kind = .Fill, x = left, y = top, w = right - left, h = height, colour = ui.theme.selection})
        }
        add_command(ui, Command.{kind = .Text, x = made.x, y = top, w = line.width, h = height, colour = style.colour, size = style.size,
            mono = style.mono, text_start = made.text_start + cast[u32](line.start), text_count = cast[u32](line.end - line.start)})
        // The cursor on the line it's in, or at the end of the last
        last :: i + 1 == lines.count
        if editing && !cursor_drawn && ui.editing.cursor >= line.start && (ui.editing.cursor <= line.end || last) {
            at :: if ui.editing.cursor < line.end { ui.editing.cursor } else { line.end }
            x :: made.x + fonts.measure(font, style.size, slice(text, line.start, at))
            add_command(ui, Command.{kind = .Fill, x = x, y = top, w = CURSOR_WIDTH, h = height, colour = ui.theme.accent})
            cursor_drawn = true
        }
    }
    if editing && !cursor_drawn {
        add_command(ui, Command.{kind = .Fill, x = made.x, y = made.y, w = CURSOR_WIDTH, h = height, colour = ui.theme.accent})
    }
}

/** Bytes from start to end of text; empty where they're not within it. */
slice :: fn(text: u8[], start: usize, end: usize) -> u8[] {
    if start <= end && end <= text.count {
        return text[start..<end]
    }
    return text[0..<0]
}

/** Whether two commands draw the same, their text compared by its bytes. */
same_command :: fn(ui: ptr[Ui], now: Command, before: Command) -> bool {
    if now.kind != before.kind || now.x != before.x || now.y != before.y || now.w != before.w || now.h != before.h
        || now.colour.r != before.colour.r || now.colour.g != before.colour.g || now.colour.b != before.colour.b
        || now.colour.a != before.colour.a || now.corner != before.corner || now.size != before.size || now.mono != before.mono
        || now.text_count != before.text_count {
        return false
    }
    a :: text_of(ui.text[0..<ui.text.count], now.text_start, now.text_count)
    b :: text_of(ui.last_text[0..<ui.last_text.count], before.text_start, before.text_count)
    if a.count != b.count {
        return false
    }
    for byte, i in a {
        if i < b.count && b[i] != byte {
            return false
        }
    }
    return true
}

/** A command's rectangle, in whole pixels covering it. */
rect_of :: fn(command: Command) -> canvas.Rect {
    return canvas.Rect.{x0 = cast[i32](floor_of(command.x)), y0 = cast[i32](floor_of(command.y)),
        x1 = cast[i32](ceil_of(command.x + command.w)), y1 = cast[i32](ceil_of(command.y + command.h))}
}

/** The largest whole number at most a value. */
floor_of :: fn(value: f32) -> f32 {
    whole :: cast[f32](cast[i64](value))
    return if whole > value { whole - 1 } else { whole }
}

/** The smallest whole number at least a value. */
ceil_of :: fn(value: f32) -> f32 {
    whole :: cast[f32](cast[i64](value))
    return if whole < value { whole + 1 } else { whole }
}

/**
 * Compare the frame's draw list with the last's: the damage is every command that differs, where it is now and where
 * it was; from the first place the lists differ in length, all of both after it.
 *
 * @return What changed on the screen, cut to the frame; empty when the lists are the same.
 */
compare_commands :: fn(ui: ptr[mut Ui]) -> canvas.Rect {
    now :: ui.commands[0..<ui.commands.count]
    before :: ui.last_commands[0..<ui.last_commands.count]
    damage := canvas.Rect.{}
    same_length :: now.count == before.count
    first_different := now.count
    for command, i in now {
        if i < before.count && same_command(ui, command, before[i]) {
            continue
        }
        if i < first_different {
            first_different = i
        }
        if same_length {
            damage = grown(damage, rect_of(command))
            if i < before.count {
                damage = grown(damage, rect_of(before[i]))
            }
        }
    }
    if !same_length {
        start :: if first_different < before.count { first_different } else { before.count }
        for command, i in now {
            if i >= start {
                damage = grown(damage, rect_of(command))
            }
        }
        for command, i in before {
            if i >= start {
                damage = grown(damage, rect_of(command))
            }
        }
    }
    frame :: canvas.Rect.{x1 = cast[i32](ceil_of(ui.width)), y1 = cast[i32](ceil_of(ui.height))}
    return canvas.intersect(damage, frame)
}

/** A rectangle grown to take in another; a clip's end, which has none, adds nothing. */
grown :: fn(damage: canvas.Rect, rect: canvas.Rect) -> canvas.Rect {
    if canvas.is_empty(rect) {
        return damage
    }
    return if canvas.is_empty(damage) { rect } else { canvas.union_of(damage, rect) }
}

/** A colour as the canvas's. */
colour_of :: fn(colour: Colour) -> canvas.Color {
    return canvas.rgba(colour.r, colour.g, colour.b, colour.a)
}

/**
 * Paint the last frame's draw list on a canvas, within a region: what's outside it isn't touched.
 *
 * A double-buffered target's region is the union of this frame's damage and the last's, as its buffer missed both.
 *
 * @param ui The UI, after end.
 * @param painter The canvas, the frame's size; its clip and transform are restored after.
 * @param region What to paint, in pixels.
 */
paint :: fn(ui: ptr[Ui], painter: ptr[mut canvas.Canvas], region: canvas.Rect) {
    if canvas.is_empty(region) {
        return void
    }
    faces :: faces_of(ui)
    canvas.save(painter)
    canvas.clip_rect(painter, cast[f32](region.x0), cast[f32](region.y0), cast[f32](region.x1 - region.x0), cast[f32](region.y1 - region.y0))
    // The draw list's swapped into last_commands as a frame ends
    path := canvas.Path.{}
    defer canvas.free_path(&path)
    depth := cast[usize](0)
    for command in ui.last_commands {
        match command.kind {
            case .ClipStart => {
                canvas.save(painter)
                canvas.clip_rect(painter, command.x, command.y, command.w, command.h)
                depth += 1
            }
            case .ClipEnd => {
                if depth > 0 {
                    canvas.restore(painter)
                    depth -= 1
                }
            }
            case .Fill => {
                if !canvas.is_empty(canvas.intersect(rect_of(command), region)) {
                    if command.corner > 0 {
                        canvas.reset(&path)
                        canvas.rounded_rect(&path, command.x, command.y, command.w, command.h, command.corner)
                        canvas.fill(painter, &path, canvas.Paint.Solid(colour_of(command.colour)))
                    }
                    else {
                        canvas.fill_rect(painter, command.x, command.y, command.w, command.h, canvas.Paint.Solid(colour_of(command.colour)))
                    }
                }
            }
            case .Border => {
                if !canvas.is_empty(canvas.intersect(rect_of(command), region)) {
                    canvas.reset(&path)
                    canvas.rounded_rect(&path, command.x + 0.5, command.y + 0.5, command.w - 1, command.h - 1, command.corner)
                    canvas.stroke(painter, &path, canvas.Paint.Solid(colour_of(command.colour)), canvas.Stroke.{width = 1})
                }
            }
            case .Text => {
                if !canvas.is_empty(canvas.intersect(rect_of(command), region)) {
                    font :: if command.mono { &faces.mono } else { &faces.sans }
                    ascent :: cast[f32](font.ascender) * fonts.scale_of(font, command.size)
                    text :: text_of(ui.last_text[0..<ui.last_text.count], command.text_start, command.text_count)
                    _ = canvas.draw_text(painter, font, command.size, command.x, command.y + ascent, text, canvas.Paint.Solid(colour_of(command.colour)))
                }
            }
        }
    }
    for i in cast[usize](0)..<depth {
        canvas.restore(painter)
    }
    canvas.restore(painter)
}
