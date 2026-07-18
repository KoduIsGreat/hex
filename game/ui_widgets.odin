package game

// Widget layer over Clay. Clay provides layout + hit-testing only (no widget
// state), so we track press/drag/open state here, keyed by Clay element id, and
// use Clay's previous-frame layout (PointerOver / GetElementData) for hit tests.

import "core:fmt"
import clay "clay-odin"
import k2 "karl2d"

UI_State :: struct {
	active_id:      u32, // element the mouse was pressed on (0 = none)
	open_menu:      u32, // currently open dropdown (0 = none)
	tooltip_text:   string,
	tooltip_active: bool,
}

ui_state: UI_State

ui_hovered :: proc(id: clay.ElementId) -> bool {
	return clay.PointerOver(id)
}

// Press-and-release button semantics: a click fires only if the press and the
// release both land on the same element.
ui_button_behavior :: proc(id: clay.ElementId) -> (hovered, pressed, clicked: bool) {
	hovered = clay.PointerOver(id)
	if hovered && k2.mouse_button_went_down(.Left) {
		ui_state.active_id = id.id
	}
	pressed = ui_state.active_id == id.id
	if k2.mouse_button_went_up(.Left) {
		if ui_state.active_id == id.id && hovered {
			clicked = true
		}
		if ui_state.active_id == id.id {
			ui_state.active_id = 0
		}
	}
	return
}

Button_Opts :: struct {
	width:  f32, // 0 = grow to fill
	height: f32, // 0 = default 36
	accent: bool, // primary (filled accent) vs secondary (card)
}

button :: proc(id_str: string, label: string, opts := Button_Opts{}) -> bool {
	id := clay.ID(id_str)
	hovered, pressed, clicked := ui_button_behavior(id)

	bg: clay.Color
	tc := TEXT_HI
	if opts.accent {
		bg = pressed ? ACCENT_DIM : (hovered ? ACCENT : ACCENT_DIM)
		tc = TEXT_DARK
	} else {
		bg = pressed ? BG_CARD_HOVER : (hovered ? BG_CARD_HOVER : BG_CARD)
	}
	w := opts.width > 0 ? clay.SizingFixed(opts.width) : clay.SizingGrow({})
	h := opts.height > 0 ? opts.height : 36

	if clay.UI(id)(
	{
		layout = {
			sizing = {w, clay.SizingFixed(h)},
			padding = clay.PaddingAll(8),
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = bg,
		cornerRadius = clay.CornerRadiusAll(6),
	},
	) {
		clay.Text(label, text_cfg(15, tc))
	}
	return clicked
}

// Checkbox-style toggle bound to a bool. Returns true on the frame it changed.
toggle :: proc(id_str: string, label: string, value: ^bool) -> bool {
	id := clay.ID(id_str)
	hovered, _, clicked := ui_button_behavior(id)
	if clicked {
		value^ = !value^
	}
	if clay.UI(id)(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingFit({})},
			padding = clay.PaddingAll(6),
			childGap = 8,
			childAlignment = {y = .Center},
		},
		backgroundColor = hovered ? BG_CARD_HOVER : BG_CARD,
		cornerRadius = clay.CornerRadiusAll(5),
	},
	) {
		box := value^ ? ACCENT : clay.Color{80, 90, 110, 255}
		if clay.UI()(
		{
			layout = {sizing = {clay.SizingFixed(18), clay.SizingFixed(18)}},
			backgroundColor = box,
			cornerRadius = clay.CornerRadiusAll(4),
		},
		) {}
		clay.Text(label, text_cfg(14, TEXT_HI))
	}
	return clicked
}

// Horizontal slider bound to an f32 in [min,max]. Returns true while dragging
// changes the value. Uses the element's previous-frame bounds to map the mouse.
slider :: proc(id_str: string, value: ^f32, min_v, max_v: f32) -> bool {
	id := clay.ID(id_str)
	hovered := clay.PointerOver(id)
	changed := false

	if hovered && k2.mouse_button_went_down(.Left) {
		ui_state.active_id = id.id
	}
	if ui_state.active_id == id.id {
		if k2.mouse_button_is_held(.Left) {
			d := clay.GetElementData(id)
			if d.found && d.boundingBox.width > 0 {
				t := clamp((k2.get_mouse_position().x - d.boundingBox.x) / d.boundingBox.width, 0, 1)
				nv := min_v + t * (max_v - min_v)
				if nv != value^ {
					value^ = nv
					changed = true
				}
			}
		} else {
			ui_state.active_id = 0
		}
	}

	frac := clamp((value^ - min_v) / (max_v - min_v), 0, 1)
	if clay.UI(id)(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingFixed(20)},
			padding = {left = 2, right = 2, top = 4, bottom = 4},
			childAlignment = {y = .Center},
		},
		backgroundColor = BG_TRACK,
		cornerRadius = clay.CornerRadiusAll(10),
	},
	) {
		if clay.UI()(
		{
			layout = {sizing = {clay.SizingPercent(frac), clay.SizingFixed(10)}},
			backgroundColor = ACCENT,
			cornerRadius = clay.CornerRadiusAll(5),
		},
		) {}
	}
	return changed
}

// Dropdown bound to a selected index. Opens a floating menu below the header.
dropdown :: proc(id_str: string, options: []string, selected: ^int) -> bool {
	id := clay.ID(id_str)
	menu_id := clay.ID(fmt.tprintf("%s__menu", id_str))
	hovered, _, clicked := ui_button_behavior(id)
	changed := false

	if clicked {
		ui_state.open_menu = ui_state.open_menu == id.id ? 0 : id.id
	}
	is_open := ui_state.open_menu == id.id

	// Close when clicking outside the header and the menu.
	if is_open && k2.mouse_button_went_down(.Left) && !hovered && !clay.PointerOver(menu_id) {
		ui_state.open_menu = 0
		is_open = false
	}

	if clay.UI(id)(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingFixed(34)},
			padding = {left = 10, right = 10, top = 6, bottom = 6},
			childGap = 8,
			childAlignment = {y = .Center},
		},
		backgroundColor = hovered ? BG_CARD_HOVER : BG_CARD,
		cornerRadius = clay.CornerRadiusAll(5),
	},
	) {
		sel := selected^ >= 0 && selected^ < len(options) ? options[selected^] : ""
		clay.Text(sel, text_cfg(14, TEXT_HI))
		if clay.UI()({layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}}}) {}
		clay.Text(is_open ? "^" : "v", text_cfg(14, TEXT_LO))
	}

	if is_open {
		if clay.UI(menu_id)(
		{
			floating = {
				attachTo = .ElementWithId,
				parentId = id.id,
				zIndex = 100,
				attachment = {element = .LeftTop, parent = .LeftBottom},
				offset = {0, 4},
			},
			layout = {
				sizing = {clay.SizingFixed(220), clay.SizingFit({})},
				padding = clay.PaddingAll(4),
				childGap = 2,
				layoutDirection = .TopToBottom,
			},
			backgroundColor = BG_CARD_ALT,
			cornerRadius = clay.CornerRadiusAll(6),
			border = {color = BORDER_COL, width = clay.BorderOutside(1)},
		},
		) {
			for opt, i in options {
				oid := clay.ID(fmt.tprintf("%s__opt%d", id_str, i))
				oh, _, oc := ui_button_behavior(oid)
				if oc {
					selected^ = i
					changed = true
					ui_state.open_menu = 0
				}
				if clay.UI(oid)(
				{
					layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}, padding = clay.PaddingAll(8)},
					backgroundColor = oh ? BG_CARD_HOVER : BG_CARD_ALT,
					cornerRadius = clay.CornerRadiusAll(4),
				},
				) {
					clay.Text(opt, text_cfg(14, i == selected^ ? ACCENT : TEXT_HI))
				}
			}
		}
	}
	return changed
}

// Horizontal tab strip bound to an active index. Returns true on change.
tabs :: proc(id_str: string, labels: []string, active: ^int) -> bool {
	changed := false
	if clay.UI(clay.ID(id_str))(
	{layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}, childGap = 4, layoutDirection = .LeftToRight}},
	) {
		for lbl, i in labels {
			tid := clay.ID(fmt.tprintf("%s__tab%d", id_str, i))
			hovered, _, clicked := ui_button_behavior(tid)
			if clicked {
				active^ = i
				changed = true
			}
			is_active := active^ == i
			bg := is_active ? ACCENT : (hovered ? BG_CARD_HOVER : BG_CARD)
			tc := is_active ? TEXT_DARK : TEXT_HI
			if clay.UI(tid)(
			{
				layout = {padding = {left = 12, right = 12, top = 8, bottom = 8}, childAlignment = {x = .Center, y = .Center}},
				backgroundColor = bg,
				cornerRadius = clay.CornerRadiusAll(5),
			},
			) {
				clay.Text(lbl, text_cfg(14, tc))
			}
		}
	}
	return changed
}

// A read-only label/value card (label above value).
label_row :: proc(label, value: string) {
	if clay.UI()(
	{
		layout = {
			sizing = {clay.SizingGrow({}), clay.SizingFit({})},
			padding = clay.PaddingAll(10),
			childGap = 4,
			layoutDirection = .TopToBottom,
		},
		backgroundColor = BG_CARD,
		cornerRadius = clay.CornerRadiusAll(5),
	},
	) {
		clay.Text(label, text_cfg(12, TEXT_LO))
		clay.Text(value, text_cfg(16, TEXT_HI))
	}
}

// --- Tooltip --------------------------------------------------------------

// Queue a tooltip for this frame (call while hovering the trigger element).
ui_set_tooltip :: proc(text: string) {
	ui_state.tooltip_active = true
	ui_state.tooltip_text = text
}

// A small hoverable chip; returns true while hovered so the caller can queue a
// tooltip. (Demonstration helper for the gallery.)
ui_hover_help :: proc(id_str: string, label: string) -> bool {
	id := clay.ID(id_str)
	hovered := clay.PointerOver(id)
	if clay.UI(id)(
	{
		layout = {sizing = {clay.SizingFit({}), clay.SizingFit({})}, padding = clay.PaddingAll(8)},
		backgroundColor = hovered ? BG_CARD_HOVER : BG_CARD,
		cornerRadius = clay.CornerRadiusAll(5),
	},
	) {
		clay.Text(label, text_cfg(13, TEXT_LO))
	}
	return hovered
}

// Render the queued tooltip as a floating element near the cursor. Called by
// ui_end, inside the root element.
ui_tooltip_render :: proc() {
	if !ui_state.tooltip_active {
		return
	}
	m := k2.get_mouse_position()
	if clay.UI(clay.ID("__tooltip"))(
	{
		floating = {
			attachTo = .Root,
			offset = {m.x + 14, m.y + 14},
			zIndex = 1000,
			attachment = {element = .LeftTop, parent = .LeftTop},
		},
		layout = {sizing = {clay.SizingFit({max = 280}), clay.SizingFit({})}, padding = clay.PaddingAll(8)},
		backgroundColor = clay.Color{12, 16, 24, 245},
		cornerRadius = clay.CornerRadiusAll(5),
		border = {color = ACCENT, width = clay.BorderOutside(1)},
	},
	) {
		clay.Text(ui_state.tooltip_text, text_cfg(13, TEXT_HI))
	}
	ui_state.tooltip_active = false
}
