package game

// Clay -> karl2d integration spike.
//
// Proves the layout library can drive this game's menus: it wires Clay's text
// measurement to karl2d, renders Clay's output commands with karl2d primitives,
// and builds a small three-panel mock (prep list + scrollable log + inspector)
// exercising flex layout, text wrapping, scissor-clipped scrolling, and hover
// hit-testing. Toggle with [U].
//
// This is a throwaway proof-of-concept, not the final UI framework (see the
// "UI foundation" issue). Nothing here is wired into gameplay yet.

import "base:runtime"
import "core:c"
import "core:fmt"
import clay "clay-odin"
import k2 "karl2d"

ui_show: bool
ui_ctx: runtime.Context
ui_memory: []u8

// Clay Color is RGBA floats in 0..255; karl2d Color is [4]u8.
clay_color :: proc "contextless" (col: clay.Color) -> k2.Color {
	return {u8(col[0]), u8(col[1]), u8(col[2]), u8(col[3])}
}

clay_error_handler :: proc "c" (err: clay.ErrorData) {
	context = ui_ctx
	s := string(err.errorText.chars[:err.errorText.length])
	fmt.eprintfln("clay error: %s", s)
}

// Clay hands us text + a font config and expects pixel dimensions back.
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

// Feed Clay this frame's viewport + pointer + scroll, build the layout, and
// draw the resulting render commands. Called in screen space (camera off).
ui_draw :: proc() {
	if !ui_show {
		return
	}
	ss := k2.get_screen_size()
	mouse := k2.get_mouse_position()
	dt := k2.get_frame_time()

	clay.SetLayoutDimensions({ss.x, ss.y})
	clay.SetPointerState({mouse.x, mouse.y}, k2.mouse_button_is_held(.Left))
	clay.UpdateScrollContainers(true, {0, k2.get_mouse_wheel_delta() * 40}, dt)

	cmds := ui_build()
	ui_render(cmds)
}

// --- Layout ---------------------------------------------------------------

BG_PANEL :: clay.Color{20, 26, 40, 240}
BG_CARD :: clay.Color{30, 38, 56, 255}
BG_CARD_HOVER :: clay.Color{48, 62, 92, 255}
ACCENT :: clay.Color{235, 205, 120, 255}
TEXT_HI :: clay.Color{235, 235, 220, 255}
TEXT_LO :: clay.Color{170, 180, 195, 255}

text_cfg :: proc(size: u16, color: clay.Color) -> clay.TextElementConfig {
	return {fontSize = size, textColor = color, wrapMode = .Words}
}

ui_build :: proc() -> clay.ClayArray(clay.RenderCommand) {
	clay.BeginLayout()

	// Root: full-screen row, transparent so the map shows through the gaps.
	if clay.UI(clay.ID("Root"))(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingGrow({})},
			padding = clay.PaddingAll(16),
			childGap = 16,
			layoutDirection = .LeftToRight,
		},
	},
	) {
		ui_prep_panel()
		ui_log_panel()
		ui_inspector_panel()
	}

	return clay.EndLayout(k2.get_frame_time())
}

// Left: doctrine sections + a hover-highlighted Launch button.
ui_prep_panel :: proc() {
	if clay.UI(clay.ID("Prep"))(
	{
		layout = {
			sizing = {clay.SizingFixed(300), clay.SizingGrow({})},
			padding = clay.PaddingAll(16),
			childGap = 10,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = BG_PANEL,
		cornerRadius = clay.CornerRadiusAll(8),
	},
	) {
		clay.Text("THE PREP TABLE", text_cfg(22, ACCENT))
		clay.Text("Expedition programming", text_cfg(14, TEXT_LO))
		ui_row("Route Intent", "Reach Objective")
		ui_row("Terrain Profile", "Cautious Pathing")
		ui_row("Risk Appetite", "Low Risk")
		ui_row("Emergency", "Safe Return")
		ui_row("Party", "Navigator, Surveyor")

		// Spacer pushes the button to the bottom.
		if clay.UI()({layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}}}) {}

		launch_id := clay.ID("Launch")
		hot := clay.PointerOver(launch_id)
		if clay.UI(launch_id)(
		{
			layout = {
				sizing = {clay.SizingGrow({}), clay.SizingFixed(44)},
				childAlignment = {x = .Center, y = .Center},
			},
			backgroundColor = hot ? ACCENT : clay.Color{200, 170, 90, 255},
			cornerRadius = clay.CornerRadiusAll(6),
		},
		) {
			clay.Text("LAUNCH EXPEDITION", text_cfg(16, clay.Color{20, 20, 20, 255}))
		}
	}
}

// A label/value row that highlights on hover (proves per-element hit-testing).
ui_row :: proc(label, value: string) {
	if clay.UI()(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingFit({})},
			padding = clay.PaddingAll(10),
			childGap = 8,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = clay.Hovered() ? BG_CARD_HOVER : BG_CARD,
		cornerRadius = clay.CornerRadiusAll(5),
	},
	) {
		clay.Text(label, text_cfg(12, TEXT_LO))
		clay.Text(value, text_cfg(16, TEXT_HI))
	}
}

// Center: a scrollable, scissor-clipped decision log (proves clipping + scroll).
ui_log_panel :: proc() {
	if clay.UI(clay.ID("LogPanel"))(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingGrow({})},
			padding = clay.PaddingAll(16),
			childGap = 10,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = BG_PANEL,
		cornerRadius = clay.CornerRadiusAll(8),
	},
	) {
		clay.Text("EXPEDITION LOG", text_cfg(22, ACCENT))
		if clay.UI(clay.ID("LogScroll"))(
		{
			layout = {
				sizing = {clay.SizingGrow({}), clay.SizingGrow({})},
				childGap = 6,
				layoutDirection = .TopToBottom,
			},
			clip = {vertical = true, childOffset = clay.GetScrollOffset()},
		},
		) {
			lines := []string {
				"Day 1  ToGoal      chose Plains over Forest (cost 1.0 < 2.0)",
				"Day 2  ToGoal      revealed 7 tiles, belief updated",
				"Day 3  ToGoal      P(Mountain) 0.62 ahead - skirting",
				"Day 4  Revealing   SmartReveal: climb hill (attempt 1/3)",
				"Day 5  ToGoal      resumed, path 8.4 days",
				"Day 6  Foraging    rations 9.0 < danger 10 -> forest",
				"Day 7  Foraging    foraged +6 rations (now 14.0)",
				"Day 8  ToGoal      belief confidence 0.71, low-risk OK",
				"Day 9  ToGoal      impasse: swamp basin, detour 4 days",
				"Day 10 Returning   SafeReturn: rations 12.0 <= return 11.4",
				"Day 11 Returning   crossing known territory",
				"Day 12 Returning   arrived home - run ended",
			}
			for line, i in lines {
				if clay.UI()(
				{
					layout = {
						sizing = {clay.SizingGrow({}), clay.SizingFit({})},
						padding = clay.PaddingAll(8),
					},
					backgroundColor = clay.Hovered() ? BG_CARD_HOVER : (i % 2 == 0 ? BG_CARD : clay.Color{26, 33, 49, 255}),
					cornerRadius = clay.CornerRadiusAll(4),
				},
				) {
					clay.Text(line, text_cfg(13, TEXT_HI))
				}
			}
		}
	}
}

// Right: a fixed inspector with a wrapped paragraph (proves text wrapping).
ui_inspector_panel :: proc() {
	if clay.UI(clay.ID("Inspector"))(
	{
		layout = {
			sizing = {clay.SizingFixed(280), clay.SizingGrow({})},
			padding = clay.PaddingAll(16),
			childGap = 10,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = BG_PANEL,
		cornerRadius = clay.CornerRadiusAll(8),
	},
	) {
		clay.Text("TILE INSPECTOR", text_cfg(22, ACCENT))
		ui_row("Terrain", "Fog")
		ui_row("Belief (argmax)", "Desert 62%")
		ui_row("Confidence", "71%")
		clay.Text(
			"Contribution: local neighbours raise P(Desert); regional density and shape continuity extend the basin north-east. Directional alignment is weak here.",
			text_cfg(13, TEXT_LO),
		)
	}
}

// --- Render ---------------------------------------------------------------

ui_render :: proc(cmds: clay.ClayArray(clay.RenderCommand)) {
	cmds := cmds
	for i in 0 ..< cmds.length {
		cmd := clay.RenderCommandArray_Get(&cmds, i)
		bb := cmd.boundingBox
		rect := k2.Rect{bb.x, bb.y, bb.width, bb.height}

		#partial switch cmd.commandType {
		case .Rectangle:
			k2.draw_rect(rect, clay_color(cmd.renderData.rectangle.backgroundColor))
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
