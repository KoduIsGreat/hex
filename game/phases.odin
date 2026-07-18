package game

// The four-phase run loop (GDD §2): Map Room -> Prep -> Simulation -> Analysis.
// This is the integrator that ties the finite world, persistence, precomputed
// runs, and the Clay UI together. Each phase docks a left panel around the
// shared center map (which is drawn separately); a top bar shows the loop.

import "core:fmt"
import clay "clay-odin"

GamePhase :: enum {
	MapRoom,
	Prep,
	Simulation,
	Analysis,
}

game_phase: GamePhase // zero value = MapRoom
prep_profile: int // selected terrain-profile preset (0..2)

// --- Transitions ----------------------------------------------------------

// Show the full persistent known world (not a playback cursor) on the map.
show_known_world :: proc() {
	clear(&revealed)
	for h in world_revealed {
		revealed[h] = true
	}
	belief_recompute()
}

do_plan :: proc() {
	run_clear()
	show_known_world()
	expedition.has_primary = false
	expedition_set_status("Prep: pick a doctrine and click a tile to set your goal.")
	game_phase = .Prep
}

do_launch :: proc() {
	if !expedition.has_primary {
		expedition_set_status("Click a tile to set a goal first.")
		return
	}
	launch_run() // precompute + start playback
	expedition.show_belief = true // show what the explorer believed each day
	game_phase = .Simulation
}

do_skip_to_analysis :: proc() {
	if run_active {
		playback.playing = false
		playback_seek(len(run_result.days) - 1)
	}
	game_phase = .Analysis
}

do_replay :: proc() {
	if run_active {
		playback_seek(0)
		playback.playing = true
	}
	game_phase = .Simulation
}

do_return_hq :: proc() {
	society_save()
	run_clear()
	show_known_world() // now includes the run's committed discoveries
	game_phase = .MapRoom
}

apply_profile :: proc(i: int) {
	switch i {
	case 0:
		expedition_set_doctrine(doctrine_cautious())
	case 1:
		expedition_set_doctrine(doctrine_aggressive_surveyor())
	case 2:
		expedition_set_doctrine(doctrine_opportunistic_forager())
	}
	prep_profile = i
}

// True when the pointer is over a docked UI panel (so map clicks are ignored).
// Uses Clay's previous-frame layout, which is fine for a one-frame lag.
ui_over_panel :: proc() -> bool {
	return clay.PointerOver(clay.ID("phase_bar")) || clay.PointerOver(clay.ID("phase_panel"))
}

// --- UI -------------------------------------------------------------------

game_ui :: proc() {
	// Full-screen column: top phase bar, then a row with the left dock panel and
	// a transparent remainder where the map shows through.
	panel_begin("phase_root", {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, transparent = true})
	phase_bar()
	panel_begin("phase_content", {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, row = true, transparent = true})
	phase_panel()
	panel_end()
	panel_end()
}

phase_bar :: proc() {
	panel_begin(
		"phase_bar",
		{sizing = {clay.SizingGrow({}), clay.SizingFixed(46)}, row = true, padding = 8, gap = 6, bg = {14, 18, 28, 240}},
	)
	names := []string{"Map Room", "Prep", "Simulation", "Analysis"}
	for n, i in names {
		active := int(game_phase) == i
		if clay.UI(clay.ID(fmt.tprintf("pbc%d", i)))(
		{
			layout = {padding = {left = 12, right = 12, top = 8, bottom = 8}, childAlignment = {y = .Center}},
			backgroundColor = active ? ACCENT : BG_CARD,
			cornerRadius = clay.CornerRadiusAll(5),
		},
		) {
			clay.Text(n, text_cfg(14, active ? TEXT_DARK : TEXT_LO))
		}
		if i < len(names) - 1 {
			if clay.UI()({layout = {padding = clay.PaddingAll(4), childAlignment = {y = .Center}}}) {
				clay.Text("->", text_cfg(14, TEXT_LO))
			}
		}
	}
	ui_spacer()
	if clay.UI()({layout = {padding = clay.PaddingAll(6), childAlignment = {y = .Center}}}) {
		clay.Text(fmt.tprintf("Prestige %v    Funding %v", prestige, funding), text_cfg(14, TEXT_LO))
	}
	panel_end()
}

phase_panel :: proc() {
	panel_begin("phase_panel", {sizing = {clay.SizingFixed(330), clay.SizingGrow({})}, padding = 16, gap = 12})
	switch game_phase {
	case .MapRoom:
		panel_map_room()
	case .Prep:
		panel_prep()
	case .Simulation:
		panel_sim()
	case .Analysis:
		panel_analysis()
	}
	panel_end()
}

panel_map_room :: proc() {
	clay.Text("THE MAP ROOM", text_cfg(22, ACCENT))
	clay.Text("Review the known world, then plan your next expedition.", text_cfg(13, TEXT_LO))
	label_row("Known tiles", fmt.tprintf("%v", len(world_revealed)))
	label_row("Prestige", fmt.tprintf("%v", prestige))
	label_row("Funding", fmt.tprintf("%v", funding))
	toggle("mr_belief", "Belief overlay", &expedition.show_belief)
	ui_spacer()
	if button("mr_plan", "Plan Expedition  ->", {accent = true}) {
		do_plan()
	}
}

panel_prep :: proc() {
	clay.Text("THE PREP TABLE", text_cfg(22, ACCENT))
	clay.Text("Configure doctrine, then click a tile to set your goal.", text_cfg(13, TEXT_LO))

	clay.Text("Route intent", text_cfg(12, TEXT_LO))
	@(static) intents := []string{"Reach Objective"}
	@(static) intent_sel := 0
	dropdown("pr_intent", intents, &intent_sel)

	clay.Text("Terrain profile", text_cfg(12, TEXT_LO))
	@(static) profiles := []string{"Cautious", "Surveyor", "Forager"}
	if tabs("pr_profile", profiles, &prep_profile) {
		apply_profile(prep_profile)
	}

	label_row("Doctrine", expedition.doctrine.name)
	label_row("Goal", expedition.has_primary ? fmt.tprintf("%v", expedition.primary_goal) : "click a tile")

	ui_spacer()
	if button("pr_back", "<  Map Room") {
		show_known_world()
		game_phase = .MapRoom
	}
	if button("pr_launch", "Launch Expedition  ->", {accent = true}) {
		do_launch()
	}
}

panel_sim :: proc() {
	clay.Text("SIMULATION", text_cfg(22, ACCENT))
	last := max(0, len(run_result.days) - 1)
	label_row("Day", fmt.tprintf("%v / %v", playback.cursor, last))
	label_row("Rations", fmt.tprintf("%.1f", expedition.rations))

	// Compact transport controls: play/pause + step.
	panel_begin(
		"sim_ctrl",
		{sizing = {clay.SizingGrow({}), clay.SizingFit({})}, row = true, gap = 8, transparent = true},
	)
	if button("sim_play", playback.playing ? "Pause" : "Play") {
		playback_toggle()
	}
	if button("sim_prev", "<", {width = 44}) {
		playback_step(-1)
	}
	if button("sim_next", ">", {width = 44}) {
		playback_step(1)
	}
	panel_end()

	// Belief overlay reflects what the explorer believed as of the shown day.
	toggle("sim_belief", "Belief overlay (this day)", &expedition.show_belief)

	// This day's decision - updates as playback advances so you can follow why
	// the explorer moved where it did, day by day.
	clay.Text("This day's decision", text_cfg(12, TEXT_LO))
	cur_reason := ""
	if playback.cursor >= 0 && playback.cursor < len(run_result.days) {
		cur_reason = run_result.days[playback.cursor].reason
	}
	if clay.UI(clay.ID("sim_today"))(
	{
		layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}, padding = clay.PaddingAll(10)},
		backgroundColor = BG_CARD,
		cornerRadius = clay.CornerRadiusAll(5),
	},
	) {
		clay.Text(cur_reason == "" ? "(moved without a logged decision)" : cur_reason, text_cfg(14, TEXT_HI))
	}

	// Running decision log up to the current day, newest first (so the latest
	// decision is always at the top without scrolling); the current day is highlighted.
	clay.Text("Decision log", text_cfg(12, TEXT_LO))
	scroll_begin("sim_log")
	hi := min(playback.cursor, len(run_result.days) - 1)
	for i := hi; i >= 0; i -= 1 {
		d := run_result.days[i]
		if d.reason == "" {
			continue
		}
		cur := i == playback.cursor
		if clay.UI(clay.ID(fmt.tprintf("sl%d", i)))(
		{
			layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}, padding = clay.PaddingAll(6)},
			backgroundColor = cur ? ACCENT_DIM : (i % 2 == 0 ? BG_CARD : BG_CARD_ALT),
			cornerRadius = clay.CornerRadiusAll(4),
		},
		) {
			clay.Text(
				fmt.tprintf("D%v [%s] %s", d.day, mission_mode_name(d.mode), d.reason),
				text_cfg(12, cur ? TEXT_DARK : TEXT_HI),
			)
		}
	}
	scroll_end()

	if button("sim_analyze", "Skip to Analysis  ->", {accent = true}) {
		do_skip_to_analysis()
	}
}

panel_analysis :: proc() {
	clay.Text("EXPEDITION LOG", text_cfg(22, ACCENT))
	last := max(0, len(run_result.days) - 1)
	label_row("Outcome", run_outcome_name(run_result.outcome))
	label_row("Days", fmt.tprintf("%v", last))
	if last >= 0 && len(run_result.days) > 0 {
		label_row("Rations left", fmt.tprintf("%.1f", run_result.days[last].rations))
	}

	// Newest day first so the latest decisions are at the top of the feed.
	clay.Text("Decision trace", text_cfg(12, TEXT_LO))
	scroll_begin("an_log")
	#reverse for d, i in run_result.days {
		if d.reason == "" {
			continue
		}
		if clay.UI(clay.ID(fmt.tprintf("an_row%d", i)))(
		{
			layout = {sizing = {clay.SizingGrow({}), clay.SizingFit({})}, padding = clay.PaddingAll(6)},
			backgroundColor = i % 2 == 0 ? BG_CARD : BG_CARD_ALT,
			cornerRadius = clay.CornerRadiusAll(4),
		},
		) {
			clay.Text(fmt.tprintf("D%v [%s] %s", d.day, mission_mode_name(d.mode), d.reason), text_cfg(12, TEXT_HI))
		}
	}
	scroll_end()

	if button("an_replay", "Replay") {
		do_replay()
	}
	if button("an_return", "Return to HQ  ->", {accent = true}) {
		do_return_hq()
	}
}
