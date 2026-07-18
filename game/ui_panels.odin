package game

// Panel grammar: dockable begin/end panels and scroll containers. Odin has no
// closures, so instead of passing a build proc we open/close Clay elements
// explicitly (clay.UI's `if` scope is equivalent but can't span a begin/end
// API). Content declared between _begin and _end becomes the panel's children.

import clay "clay-odin"

Panel_Cfg :: struct {
	sizing:      clay.Sizing,
	padding:     u16,
	gap:         u16,
	row:         bool, // false = TopToBottom column (default), true = LeftToRight
	transparent: bool, // no background / rounding (e.g. layout-only containers)
	bg:          clay.Color, // background override; {} = BG_PANEL
}

panel_begin :: proc(id_str: string, cfg: Panel_Cfg) {
	dir := cfg.row ? clay.LayoutDirection.LeftToRight : .TopToBottom
	bg := clay.Color{}
	radius := f32(0)
	if !cfg.transparent {
		bg = cfg.bg == {} ? BG_PANEL : cfg.bg
		radius = 8
	}
	clay._OpenElementWithId(clay.ID(id_str))
	clay.ConfigureOpenElement(
		{
			layout = {
				sizing = cfg.sizing,
				padding = clay.PaddingAll(cfg.padding),
				childGap = cfg.gap,
				layoutDirection = dir,
			},
			backgroundColor = bg,
			cornerRadius = clay.CornerRadiusAll(radius),
		},
	)
}

panel_end :: proc() {
	clay._CloseElement()
}

// A vertical, scissor-clipped scroll container that grows to fill its parent.
// Wheel scrolling is driven by clay.UpdateScrollContainers (see ui_begin).
scroll_begin :: proc(id_str: string) {
	clay._OpenElementWithId(clay.ID(id_str))
	clay.ConfigureOpenElement(
		{
			layout = {
				sizing = {clay.SizingGrow({}), clay.SizingGrow({})},
				childGap = 4,
				layoutDirection = .TopToBottom,
			},
			clip = {vertical = true, childOffset = clay.GetScrollOffset()},
		},
	)
}

scroll_end :: proc() {
	clay._CloseElement()
}

// A flexible spacer that pushes following siblings to the far edge.
ui_spacer :: proc() {
	if clay.UI()({layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}}}) {}
}
