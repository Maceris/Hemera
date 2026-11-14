/**
 * An immediate-mode UI library: a program describes its UI from its state each frame (`if ui.button(&u, "Save") {
 * save() }`), and the calls build the frame's tree, which is then laid out, turned into a draw list, and painted on a
 * canvas (std/canvas). No callbacks and no widget objects: what a widget keeps between frames (focus, scroll, the text
 * being edited) is the library's, by the widget's ID, dropped once a frame doesn't have that ID.
 *
 * Layout is Clay's: each axis Fixed, Fit, Grow or a percent of the parent, children in a row or a column with padding,
 * gaps and alignment, laid out one axis at a time, widths first, so text wraps to its width before heights are known.
 * IDs are a label's hash mixed with the parent's and an explicit key, hashed at compile time where the label's a
 * constant (key). Input is the previous frame's layout's: a widget knows it's hovered or clicked from where it was
 * drawn. A frame returns its events, for the program to handle after it, and its damage: the draw list compared with
 * the last frame's, for a compositor's partial redraw. The tree is also what tests drive, through selectors over IDs,
 * roles and text, and what an accessibility protocol is given.
 *
 * Freestanding: it draws on a canvas its caller gives, and keeps its frame's nodes, text and commands in arrays from
 * the context's allocator, reused from frame to frame.
 */
package ui

import tiers from "std"

/** The package's tier, Freestanding: it needs only base and std's canvas, fonts and unicode. */
PACKAGE_TIER :: tiers.Tier.Freestanding
