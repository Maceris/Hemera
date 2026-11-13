/*
 * std/canvas, measured: a fill's coverage summed is its shape's area, exactly for rectangles and within one per cent
 * for a circle; the fill rules; strokes' areas with each cap, and dashed; transforms, clips and damage;
 * gradients and scaled images; text from the glyph cache matching the same glyphs filled as paths; and wild paths
 * drawn without harm.
 */
package canvas_test

import runtime from "base"
import canvas from "std"
import fonts from "std"
import math from "std"
import strings from "std"
import testing from "std"

SANS :: #file_data("../../fonts/NotoSans-Regular.ttf")
SIZE :: 128

/** A canvas on a transparent image of SIZE by SIZE, its pixels on the heap. */
Board :: struct {
    pixels : u8[SIZE * SIZE * 4],
}

/** A board's canvas. */
canvas_of :: fn(board: ptr[mut Board]) -> canvas.Canvas {
    return canvas.make(canvas.Image.{pixels = board.pixels[0..<SIZE * SIZE * 4], width = SIZE, height = SIZE, stride = SIZE * 4})
}

/** How much of the board's covered: its alphas summed, in pixels. */
coverage :: fn(board: ptr[Board]) -> f32 {
    sum := cast[f32](0)
    for i in cast[usize](0)..<SIZE * SIZE {
        sum += cast[f32](board.pixels[4 * i + 3]) / 255
    }
    return sum
}

/** Whether two numbers are within a tolerance. */
near :: fn(t: ptr[mut testing.T], found: f32, expected: f32, tolerance: f32, what: string) {
    difference :: found - expected
    if difference > tolerance || difference < -tolerance {
        testing.note(t, strings.format("found %", found) or_else "")
        testing.fail(t, what)
    }
}

WHITE :: canvas.Paint.Solid(canvas.Color.{r = 1, g = 1, b = 1})

fills_exact_areas #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    board :: runtime.new(Board)
    defer runtime.free(board)
    c := canvas_of(board)
    defer canvas.free_canvas(&c)
    path := canvas.Path.{}
    defer canvas.free_path(&path)
    canvas.rect(&path, 2.25, 3.5, 10.5, 7.25)
    canvas.fill(&c, &path, WHITE)
    near(t, coverage(board), 76.125, 0.15, "a rectangle at fractions of a pixel covers its area")
    damage :: canvas.take_damage(&c)
    testing.expect(t, damage.x0 == 2 && damage.y0 == 3 && damage.x1 == 13 && damage.y1 == 11, "its damage is the pixels it touched")
    testing.expect(t, canvas.is_empty(canvas.take_damage(&c)), "and it's taken")
    // A circle
    board2 :: runtime.new(Board)
    defer runtime.free(board2)
    c2 := canvas_of(board2)
    defer canvas.free_canvas(&c2)
    canvas.reset(&path)
    canvas.circle(&path, 64.3, 60.7, 40)
    canvas.fill(&c2, &path, WHITE)
    // Its curves cut into chords within a quarter pixel of them, so a little under: within one per cent
    near(t, coverage(board2), cast[f32](math.PI) * 1600, 50, "a circle covers π r²")
    return .Ok
}

applies_fill_rules #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for rule in canvas.FillRule.[.NonZero, .EvenOdd] {
        board :: runtime.new(Board)
        defer runtime.free(board)
        c := canvas_of(board)
        defer canvas.free_canvas(&c)
        path := canvas.Path.{}
        defer canvas.free_path(&path)
        // Two squares, the same way round, one inside the other
        canvas.rect(&path, 10, 10, 40, 40)
        canvas.rect(&path, 20, 20, 20, 20)
        canvas.fill(&c, &path, WHITE, rule)
        near(t, coverage(board), if rule == .NonZero { cast[f32](1600) } else { cast[f32](1200) }, 0.1,
            if rule == .NonZero { "non-zero fills the inner square" } else { "even-odd leaves it empty" })
    }
    return .Ok
}

strokes_with_caps #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for cap in canvas.Cap.[.Butt, .Square, .Round] {
        board :: runtime.new(Board)
        defer runtime.free(board)
        c := canvas_of(board)
        defer canvas.free_canvas(&c)
        path := canvas.Path.{}
        defer canvas.free_path(&path)
        canvas.move_to(&path, 20, 30.5)
        canvas.line_to(&path, 60, 30.5)
        canvas.stroke(&c, &path, WHITE, canvas.Stroke.{width = 4, cap = cap})
        expected :: if cap == .Butt { cast[f32](160) } else if cap == .Square { cast[f32](176) } else { 160 + cast[f32](math.PI) * 4 }
        near(t, coverage(board), expected, 0.6, if cap == .Butt { "a butt-capped line is its length by its width" }
            else if cap == .Square { "square caps add half the width each end" } else { "round caps add a circle" })
    }
    // Dashed: on 10, off 10 along 100, so half of it
    board :: runtime.new(Board)
    defer runtime.free(board)
    c := canvas_of(board)
    defer canvas.free_canvas(&c)
    path := canvas.Path.{}
    defer canvas.free_path(&path)
    canvas.move_to(&path, 10, 50)
    canvas.line_to(&path, 110, 50)
    dashed := canvas.Stroke.{width = 2, dash_count = 2}
    dashed.dashes[0] = 10
    dashed.dashes[1] = 10
    canvas.stroke(&c, &path, WHITE, dashed)
    near(t, coverage(board), 100, 0.6, "a dashed line covers its dashes")
    // A closed square's outline, mitered: its outer square less its inner
    board2 :: runtime.new(Board)
    defer runtime.free(board2)
    c2 := canvas_of(board2)
    defer canvas.free_canvas(&c2)
    canvas.reset(&path)
    canvas.rect(&path, 20, 20, 40, 40)
    canvas.stroke(&c2, &path, WHITE, canvas.Stroke.{width = 4})
    near(t, coverage(board2), 44 * 44 - 36 * 36, 0.8, "a mitered square's corners are filled")
    return .Ok
}

transforms_and_clips #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    board :: runtime.new(Board)
    defer runtime.free(board)
    c := canvas_of(board)
    defer canvas.free_canvas(&c)
    canvas.save(&c)
    canvas.translate(&c, 10, 10)
    canvas.scale(&c, 2, 2)
    canvas.fill_rect(&c, 0, 0, 10, 10, WHITE)
    near(t, coverage(board), 400, 0.1, "scaled by 2, a 10 by 10 square covers 400")
    damage :: canvas.take_damage(&c)
    testing.expect(t, damage.x0 == 10 && damage.y0 == 10 && damage.x1 == 30 && damage.y1 == 30, "where it was moved to")
    canvas.restore(&c)
    // Clipped to 10 by 10, a 50 by 50 square covers 100
    board2 :: runtime.new(Board)
    defer runtime.free(board2)
    c2 := canvas_of(board2)
    defer canvas.free_canvas(&c2)
    canvas.clip_rect(&c2, 60, 60, 10, 10)
    canvas.fill_rect(&c2, 40, 40, 50, 50, WHITE)
    near(t, coverage(board2), 100, 0.01, "a clip keeps what's drawn inside it")
    // Off the image, nothing, and no damage
    canvas.fill_rect(&c2, -500, -500, 20, 20, WHITE)
    _ = canvas.take_damage(&c2)
    canvas.fill_rect(&c2, 1000, 0, 20, 20, WHITE)
    testing.expect(t, canvas.is_empty(canvas.take_damage(&c2)), "drawing off the image damages nothing")
    return .Ok
}

paints_gradients_and_images #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    board :: runtime.new(Board)
    defer runtime.free(board)
    c := canvas_of(board)
    defer canvas.free_canvas(&c)
    gradient := canvas.Gradient.{start = canvas.Point.{x = 0, y = 0}, end = canvas.Point.{x = 100, y = 0}}
    canvas.add_stop(&gradient, 0, canvas.Color.{r = 0, g = 0, b = 0})
    canvas.add_stop(&gradient, 1, canvas.Color.{r = 1, g = 1, b = 1})
    canvas.fill_rect(&c, 0, 0, 100, 1, canvas.Paint.Linear(gradient))
    // Pixel 49's centre is at 49.5: 0.495 of the way, 126.2
    red :: board.pixels[4 * 49 + 2]
    testing.expect(t, red == 126 || red == 127, "a linear gradient's colour is its centre's along it")
    testing.expect(t, board.pixels[2] < 2 && board.pixels[4 * 99 + 2] > 253, "and its ends its stops")
    // A 2 by 2 image scaled to 4 by 4, nearest: each pixel four
    texels : u8[16]
    for i in cast[usize](0)..<4 {
        texels[4 * i + 2] = cast[u8](60 * (i + 1))
        texels[4 * i + 3] = 255
    }
    image :: canvas.Image.{pixels = texels[0..<16], width = 2, height = 2, stride = 8}
    board2 :: runtime.new(Board)
    defer runtime.free(board2)
    c2 := canvas_of(board2)
    defer canvas.free_canvas(&c2)
    canvas.draw_image(&c2, image, 0, 0, 4, 4, .Nearest)
    testing.expect(t, board2.pixels[4 * (0 * SIZE + 1) + 2] == 60 && board2.pixels[4 * (0 * SIZE + 3) + 2] == 120
        && board2.pixels[4 * (3 * SIZE + 0) + 2] == 180 && board2.pixels[4 * (3 * SIZE + 3) + 2] == 240, "nearest keeps each pixel's colour")
    return .Ok
}

draws_text #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    font :: fonts.open(SANS[0..<SANS.count]) or_else fonts.Font.{}
    testing.require(t, font.units_per_em != 0, "Noto Sans opens")?
    text :: string_bytes("Hello, AVW")
    board :: runtime.new(Board)
    defer runtime.free(board)
    c := canvas_of(board)
    defer canvas.free_canvas(&c)
    end :: canvas.draw_text(&c, &font, 16, 4.25, 40, text, WHITE)
    near(t, end, 4.25 + fonts.measure(&font, 16, text), 0.001, "the pen ends where the text measures")
    cached :: coverage(board)
    testing.expect(t, cached > 50, "the text covers something")
    // Drawn again, from the cache: the same pixels
    copy : u8[SIZE * SIZE * 4]
    for byte, i in board.pixels {
        copy[i] = byte
    }
    for &byte in board.pixels {
        byte^ = 0
    }
    _ = canvas.draw_text(&c, &font, 16, 4.25, 40, text, WHITE)
    same := true
    for byte, i in board.pixels {
        if byte != copy[i] {
            same = false
        }
    }
    testing.expect(t, same, "drawn from the cache, the same pixels")
    // As paths, under a transform that isn't only a move: the same coverage, near enough
    board2 :: runtime.new(Board)
    defer runtime.free(board2)
    c2 := canvas_of(board2)
    defer canvas.free_canvas(&c2)
    canvas.scale(&c2, 1, 1.000001)
    _ = canvas.draw_text(&c2, &font, 16, 4.25, 40, text, WHITE)
    near(t, coverage(board2), cached, cached * 0.03, "as paths, about the same coverage as cached")
    return .Ok
}

/** Paths of any points, wild ones among them, filled and stroked without harm. */
draws_any_path #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    board :: runtime.new(Board)
    defer runtime.free(board)
    c := canvas_of(board)
    defer canvas.free_canvas(&c)
    path := canvas.Path.{}
    defer canvas.free_path(&path)
    count :: testing.draw_between(source, 1, 40)
    for i in 0..<count {
        kind :: testing.draw_between(source, 0, 4)
        x :: coordinate(source)
        y :: coordinate(source)
        if kind == 0 {
            canvas.move_to(&path, x, y)
        }
        else if kind == 1 {
            canvas.line_to(&path, x, y)
        }
        else if kind == 2 {
            canvas.quad_to(&path, coordinate(source), coordinate(source), x, y)
        }
        else if kind == 3 {
            canvas.cubic_to(&path, coordinate(source), coordinate(source), coordinate(source), coordinate(source), x, y)
        }
        else {
            canvas.close(&path)
        }
    }
    canvas.fill(&c, &path, WHITE, if testing.draw_between(source, 0, 1) == 0 { canvas.FillRule.NonZero } else { canvas.FillRule.EvenOdd })
    stroke := canvas.Stroke.{width = cast[f32](testing.draw_between(source, 0, 30)), join = .Round, cap = .Round, dash_count = 2}
    stroke.dashes[0] = 3
    stroke.dashes[1] = 2
    canvas.stroke(&c, &path, WHITE, stroke)
    return .Ok
}

/** A coordinate: usually on or near the board, sometimes far off, huge, or not a number. */
coordinate :: fn(source: ptr[mut testing.Source]) -> f32 {
    kind :: testing.draw_between(source, 0, 9)
    if kind == 0 {
        return 1e30
    }
    if kind == 1 {
        return cast[f32](math.nan[f64]())
    }
    if kind == 2 {
        return cast[f32](testing.draw_between(source, -100000, 100000))
    }
    return cast[f32](testing.draw_between(source, -20, 150)) + cast[f32](testing.draw_between(source, 0, 99)) / 100
}
