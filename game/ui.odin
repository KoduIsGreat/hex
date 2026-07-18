package game

// Clay-based UI foundation: core frame lifecycle, renderer, and theme.
//
// Clay computes layout + hit-testing and emits render commands; this module
// draws those commands with karl2d and provides a widget layer (ui_widgets.odin)
// and a dockable panel grammar (ui_panels.odin) on top. See docs/ui_design.md.
//
// A widget gallery behind [U] exercises the toolkit. It is a dev aid, not a
// game screen - the four-phase screens (issue #9) build on the same primitives.

import "base:runtime"
import "core:c"
import "core:fmt"
import clay "clay-odin"
import k2 "karl2d"

ui_show: bool
ui_ctx: runtime.Context
ui_memory: []u8

// --- Theme ----------------------------------------------------------------

BG_PANEL :: clay.Color{20, 26, 40, 240}
BG_CARD :: clay.Color{30, 38, 56, 255}
BG_CARD_HOVER :: clay.Color{48, 62, 92, 255}
BG_CARD_ALT :: clay.Color{26, 33, 49, 255}
BG_TRACK :: clay.Color{40, 48, 66, 255}
ACCENT :: clay.Color{235, 205, 120, 255}
ACCENT_DIM :: clay.Color{200, 170, 90, 255}
TEXT_HI :: clay.Color{235, 235, 220, 255}
TEXT_LO :: clay.Color{170, 180, 195, 255}
TEXT_DARK :: clay.Color{20, 20, 20, 255}
BORDER_COL :: clay.Color{60, 72, 96, 255}

text_cfg :: proc(size: u16, color: clay.Color) -> clay.TextElementConfig {
	return {fontSize = size, textColor = color, wrapMode = .Words}
}

// Clay Color is RGBA floats in 0..255; karl2d Color is [4]u8.
clay_color :: proc "contextless" (col: clay.Color) -> k2.Color {
	return {u8(col[0]), u8(col[1]), u8(col[2]), u8(col[3])}
}

// --- Lifecycle ------------------------------------------------------------

clay_error_handler :: proc "c" (err: clay.ErrorData) {
	context = ui_ctx
	s := string(err.errorText.chars[:err.errorText.length])
	fmt.eprintfln("clay error: %s", s)
}

// Clay hands us text + a font config and expects pixel dimensions back. It must
// measure with the same font/size the renderer draws with, or wrapping drifts.
clay_measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	userData: rawptr,
) -> clay.Dimensions {
	context = ui_ctx
	str := string(text.chars[:text.length])
	sz := k2.measure_text(str, f32(config.fontSize))
	return {sz.x, sz.y}
}

ui_init :: proc() {
	ui_ctx = context
	min_size := clay.MinMemorySize()
	ui_memory = make([]u8, int(min_size))
	arena := clay.CreateArenaWithCapacityAndMemory(c.size_t(min_size), raw_data(ui_memory))
	ss := k2.get_screen_size()
	clay.Initialize(arena, {ss.x, ss.y}, {handler = clay_error_handler})
	clay.SetMeasureTextFunction(clay_measure_text, nil)
}

ui_shutdown :: proc() {
	delete(ui_memory)
}

// Begin a UI frame: feed Clay the viewport + pointer + scroll, start the layout,
// and open a full-screen root so floating elements (tooltips, menus) have a
// parent. Widgets/panels are declared between ui_begin and ui_end.
ui_begin :: proc() {
	ss := k2.get_screen_size()
	mouse := k2.get_mouse_position()
	clay.SetLayoutDimensions({ss.x, ss.y})
	clay.SetPointerState({mouse.x, mouse.y}, k2.mouse_button_is_held(.Left))
	clay.UpdateScrollContainers(true, {0, k2.get_mouse_wheel_delta() * 40}, k2.get_frame_time())

	clay.BeginLayout()
	clay._OpenElementWithId(clay.ID("__root"))
	clay.ConfigureOpenElement(
		{layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}}},
	)
}

// End a UI frame: render any queued tooltip inside the root, close the root, and
// draw the resulting render commands (screen space; caller has camera off).
ui_end :: proc() {
	ui_tooltip_render()
	clay._CloseElement()
	cmds := clay.EndLayout(k2.get_frame_time())
	ui_render(cmds)
}

// --- Gallery (behind [U]) -------------------------------------------------

gal_tab: int
gal_toggle: bool
gal_slider: f32 = 0.5
gal_dropdown: int

ui_draw :: proc() {
	if !ui_show {
		return
	}
	ui_begin()
	ui_gallery()
	ui_end()
}

ui_gallery :: proc() {
	// Root row: left controls panel + center scroll panel.
	panel_begin(
		"gal_row",
		{sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, padding = 16, gap = 16, row = true, transparent = true},
	)
	defer panel_end()

	// Left: widget controls.
	panel_begin("gal_left", {sizing = {clay.SizingFixed(320), clay.SizingGrow({})}, padding = 16, gap = 12})
	{
		clay.Text("UI FOUNDATION", text_cfg(22, ACCENT))
		clay.Text("Clay widgets + panel grammar", text_cfg(13, TEXT_LO))

		@(static) tab_labels := []string{"Widgets", "About"}
		tabs("gal_tabs", tab_labels, &gal_tab)

		if gal_tab == 0 {
			if button("gal_btn", "Primary Button", {accent = true}) {
				fmt.println("gallery: primary button clicked")
			}
			if button("gal_btn2", "Secondary Button") {
				fmt.println("gallery: secondary button clicked")
			}
			toggle("gal_tog", "Belief overlay", &gal_toggle)
			label_row("Slider", fmt.tprintf("%.2f", gal_slider))
			slider("gal_slider", &gal_slider, 0, 1)
			label_row("Dropdown", "route intent")
			@(static) intents := []string{"Reach Objective", "Survey Region", "Artifact Hunt", "Resource Forage"}
			dropdown("gal_dd", intents, &gal_dropdown)
			if ui_hover_help("gal_help", "Hover me") {
				ui_set_tooltip("Tooltips render as a floating element near the cursor.")
			}
		} else {
			clay.Text(
				"This gallery exercises the reusable widget layer over Clay: buttons, toggle, slider, dropdown, tabs, tooltip, and a scissor-clipped scroll list. The four-phase game screens reuse these same primitives.",
				text_cfg(13, TEXT_LO),
			)
		}
	}
	panel_end()

	// Center: scrollable list (proves clipping + scroll wheel).
	panel_begin("gal_center", {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, padding = 16, gap = 10})
	{
		clay.Text("SCROLL LIST", text_cfg(22, ACCENT))
		scroll_begin("gal_scroll")
		for i in 0 ..< 40 {
			row_id := fmt.tprintf("gal_item_%d", i)
			if clay.UI(clay.ID(row_id))(
			{
				layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}, padding = clay.PaddingAll(8)},
				backgroundColor = clay.Hovered() ? BG_CARD_HOVER : (i % 2 == 0 ? BG_CARD : BG_CARD_ALT),
				cornerRadius = clay.CornerRadiusAll(4),
			},
			) {
				clay.Text(fmt.tprintf("Item %d - hover to highlight, wheel to scroll", i), text_cfg(13, TEXT_HI))
			}
		}
		scroll_end()
	}
	panel_end()
}

// --- Render ---------------------------------------------------------------

// karl2d draws sharp rects; approximate Clay's rounded corners with an inset
// cross of rects plus a filled circle at each corner.
draw_round_rect :: proc(r: k2.Rect, radius: f32, color: k2.Color) {
	rad := min(radius, min(r.w, r.h) * 0.5)
	if rad <= 1 {
		k2.draw_rect(r, color)
		return
	}
	k2.draw_rect({r.x + rad, r.y, r.w - 2 * rad, r.h}, color)
	k2.draw_rect({r.x, r.y + rad, r.w, r.h - 2 * rad}, color)
	SEG :: 10
	k2.draw_circle({r.x + rad, r.y + rad}, rad, color, SEG)
	k2.draw_circle({r.x + r.w - rad, r.y + rad}, rad, color, SEG)
	k2.draw_circle({r.x + rad, r.y + r.h - rad}, rad, color, SEG)
	k2.draw_circle({r.x + r.w - rad, r.y + r.h - rad}, rad, color, SEG)
}

ui_render :: proc(cmds: clay.ClayArray(clay.RenderCommand)) {
	cmds := cmds
	for i in 0 ..< cmds.length {
		cmd := clay.RenderCommandArray_Get(&cmds, i)
		bb := cmd.boundingBox
		rect := k2.Rect{bb.x, bb.y, bb.width, bb.height}

		#partial switch cmd.commandType {
		case .Rectangle:
			rd := cmd.renderData.rectangle
			draw_round_rect(rect, rd.cornerRadius.topLeft, clay_color(rd.backgroundColor))
		case .Border:
			b := cmd.renderData.border
			k2.draw_rect_outline(rect, f32(max(b.width.left, 1)), clay_color(b.color))
		case .Text:
			t := cmd.renderData.text
			str := string(t.stringContents.chars[:t.stringContents.length])
			k2.draw_text(str, {bb.x, bb.y}, f32(t.fontSize), clay_color(t.textColor))
		case .ScissorStart:
			k2.set_scissor_rect(rect)
		case .ScissorEnd:
			k2.set_scissor_rect(nil)
		}
	}
}
