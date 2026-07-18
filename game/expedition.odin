package game

import "core:fmt"
import k2 "karl2d"

STARTING_RATIONS :: f32(80)
START_VISION :: i32(2)

Expedition :: struct {
	explorer:        Entity,
	home:            Hex,
	primary_goal:    Hex,
	has_primary:     bool,
	temp_goal:       Hex,
	has_temp:        bool,
	mode:            MissionMode,
	path:            PathResult,
	path_index:      int,
	doctrine:        Doctrine,
	rations:         f32,
	show_belief:     bool,
	status_buf:      [256]u8,
	status_len:      int,
	playing:         bool,
	step_timer:      f32,
	days_elapsed:    int,
	reveal_attempts: int,
	run_over:        bool,
}

expedition_status :: proc() -> string {
	return string(expedition.status_buf[:expedition.status_len])
}

expedition_set_status :: proc(fmt_str: string, args: ..any) {
	s := fmt.bprintf(expedition.status_buf[:], fmt_str, ..args)
	expedition.status_len = len(s)
}

expedition: Expedition

expedition_init :: proc() {
	fog_init()
	belief_init()
	trace_clear()

	expedition = {}
	expedition.home = Hex{0, 0, 0}
	expedition.explorer.hex = expedition.home
	expedition.explorer.pos = hex_to_world(expedition.explorer.hex, HEX_SIZE, ORIENT)
	expedition.doctrine = doctrine_cautious()
	expedition.rations = STARTING_RATIONS
	expedition.mode = .ToGoal
	expedition.path = PathResult{path = make([dynamic]Hex)}
	expedition_set_status("Click a tile to set goal. [Space] step. [Enter] play. [1/2/3] doctrine. [B] belief.")

	reveal_begin()
	reveal_around(expedition.explorer.hex, START_VISION)
	reveal_from_tile(expedition.explorer.hex)
	belief_recompute()
}

expedition_reset_world :: proc() {
	clear(&revealed)
	clear(&beliefs)
	trace_clear()
	path_clear(&expedition.path)
	expedition.has_primary = false
	expedition.has_temp = false
	expedition.path_index = 0
	expedition.playing = false
	expedition.run_over = false
	expedition.days_elapsed = 0
	expedition.reveal_attempts = 0
	expedition.mode = .ToGoal
	expedition.rations = STARTING_RATIONS
	expedition.home = Hex{0, 0, 0}
	expedition.explorer.hex = expedition.home
	expedition.explorer.pos = hex_to_world(expedition.explorer.hex, HEX_SIZE, ORIENT)
	reveal_begin()
	reveal_around(expedition.explorer.hex, START_VISION)
	reveal_from_tile(expedition.explorer.hex)
	belief_recompute()
	world_revealed_reset() // new world -> persistent known world resets to the home area
	expedition_set_status("World regenerated. Click a goal.")
}

expedition_shutdown :: proc() {
	path_destroy(&expedition.path)
	belief_shutdown()
	fog_shutdown()
}

expedition_set_doctrine :: proc(d: Doctrine) {
	expedition.doctrine = d
	expedition.reveal_attempts = 0
	if expedition.mode != .Returning {
		expedition.mode = .ToGoal
		expedition.has_temp = false
	}
	expedition_repath()
	if !expedition.has_primary {
		expedition_set_status("Doctrine: %s", d.name)
	}
}

expedition_set_goal :: proc(goal: Hex) {
	if !in_arena(goal) {
		expedition_set_status("Goal outside arena.")
		return
	}
	if expedition.run_over {
		expedition.run_over = false
	}
	expedition.primary_goal = goal
	expedition.has_primary = true
	// New primary goal cancels temp missions (except mid-return).
	if expedition.mode != .Returning {
		expedition.mode = .ToGoal
		expedition.has_temp = false
	}
	expedition_repath()
}

expedition_active_goal :: proc() -> (Hex, bool) {
	return active_goal()
}

expedition_repath :: proc() {
	path_clear(&expedition.path)
	expedition.path_index = 0
	goal, ok := active_goal()
	if !ok {
		return
	}
	res := pathfind_astar(expedition.explorer.hex, goal, expedition.doctrine)
	delete(expedition.path.path)
	expedition.path = res
	if res.found {
		expedition.path_index = 0
		expedition_set_status(
			"[%s] path %.1f days (%v steps)",
			mission_mode_name(expedition.mode),
			res.cost,
			max(0, len(res.path) - 1),
		)
	} else {
		expedition_set_status("[%s] No path found.", mission_mode_name(expedition.mode))
	}
}

// A short rationale for stepping onto `next`: the chosen tile's expected cost
// versus the cheapest alternative neighbor (the "chose A over B" of GDD §7.5).
movement_reason :: proc(cur, next: Hex, doctrine: Doctrine) -> string {
	ka, conf_a := dominant_terrain(next)
	cost_a := edge_cost(cur, next, doctrine)

	// Cheapest alternative neighbor we could have stepped to instead.
	best_alt: Hex
	best_cost: f32 = 1e18
	have_alt := false
	for d in HEX_DIRS {
		n := hex_add(cur, d)
		if n == next || !in_arena(n) {
			continue
		}
		if is_revealed(n) && !is_passable(terrain_at(n)) {
			continue
		}
		c := edge_cost(cur, n, doctrine)
		if c < best_cost {
			best_cost = c
			best_alt = n
			have_alt = true
		}
	}

	// If stepping onto a fogged tile, the decision rests on belief confidence.
	conf := is_revealed(next) ? "" : fmt.tprintf(" [belief %.0f%%]", conf_a * 100)

	if have_alt {
		kb, _ := dominant_terrain(best_alt)
		if cost_a > best_cost + 0.1 {
			// Chose a locally costlier tile because it lies on the better route.
			return fmt.tprintf(
				"Took %s (cost %.1f) over cheaper %s (cost %.1f) for a better route%s",
				terrain_name(ka),
				cost_a,
				terrain_name(kb),
				best_cost,
				conf,
			)
		}
		if kb != ka {
			return fmt.tprintf(
				"Chose %s (cost %.1f) over %s (cost %.1f)%s",
				terrain_name(ka),
				cost_a,
				terrain_name(kb),
				best_cost,
				conf,
			)
		}
	}
	return fmt.tprintf("Advanced to %s (cost %.1f) on the lowest-cost path%s", terrain_name(ka), cost_a, conf)
}

// Advance one day along the current path, evaluating policies first.
expedition_step :: proc() -> bool {
	if expedition.run_over {
		expedition.playing = false
		return false
	}
	if expedition.rations <= 0 {
		expedition_set_status("Out of rations!")
		trace_append(expedition.days_elapsed, expedition.mode, "Out of rations — run ended")
		expedition.playing = false
		expedition.run_over = true
		return false
	}

	_, has := active_goal()
	if !has {
		expedition_set_status("No goal set.")
		expedition.playing = false
		return false
	}

	// Policy may switch mode / temp goal before we move.
	if policy_evaluate() {
		expedition_repath()
	}

	if !expedition.path.found || len(expedition.path.path) < 2 {
		// One more policy pass for Smart Reveal when no path exists.
		if expedition.mode == .ToGoal {
			if policy_evaluate() {
				expedition_repath()
			}
		}
		if !expedition.path.found || len(expedition.path.path) < 2 {
			// Already standing on active goal?
			active, ok := active_goal()
			if ok && expedition.explorer.hex == active {
				return policy_on_arrived()
			}
			expedition_set_status("[%s] No path to follow.", mission_mode_name(expedition.mode))
			expedition.playing = false
			return false
		}
	}

	if expedition.path_index >= len(expedition.path.path) - 1 {
		return policy_on_arrived()
	}

	next := expedition.path.path[expedition.path_index + 1]
	// Log why we step here (using belief as it stands before revealing `next`).
	cur := expedition.explorer.hex
	move_reason := movement_reason(cur, next, expedition.doctrine)
	expedition.explorer.hex = next
	expedition.explorer.pos = hex_to_world(next, HEX_SIZE, ORIENT)
	expedition.path_index += 1
	expedition.days_elapsed += 1

	reveal_begin()
	reveal_from_tile(next)
	belief_update(newly_revealed[:])

	pay := true_day_cost(next)
	expedition.rations -= pay
	trace_append(expedition.days_elapsed, expedition.mode, "%s", move_reason)

	active, _ := active_goal()
	if expedition.explorer.hex == active {
		return policy_on_arrived()
	}

	// Always repath after reveal; policy may also divert (Safe Return).
	_ = policy_evaluate()
	expedition_repath()
	return true
}

STEP_INTERVAL :: f32(0.25)

// Live stepping is now driven by playback of a precomputed run (see run.odin).
expedition_update :: proc(dt: f32) {
	playback_update(dt)
}

draw_hex_overlay :: proc(h: Hex, color: k2.Color, radius_scale: f32 = 0.85) {
	center := hex_to_world(h, HEX_SIZE, ORIENT)
	k2.draw_circle(center, HEX_SIZE * radius_scale, color, 6)
}

expedition_draw_overlays :: proc() {
	if expedition.path.found && len(expedition.path.path) > 1 {
		line_col: k2.Color = {255, 220, 80, 220}
		switch expedition.mode {
		case .Foraging:
			line_col = {80, 220, 100, 220}
		case .Revealing:
			line_col = {80, 220, 255, 220}
		case .Returning:
			line_col = {255, 160, 60, 220}
		case .ToGoal:
			line_col = {255, 220, 80, 220}
		}
		for i in 0 ..< len(expedition.path.path) - 1 {
			a := hex_to_world(expedition.path.path[i], HEX_SIZE, ORIENT)
			b := hex_to_world(expedition.path.path[i + 1], HEX_SIZE, ORIENT)
			k2.draw_line(a, b, 3, line_col)
		}
	}

	// Primary goal (red) always if set.
	if expedition.has_primary {
		draw_hex_overlay(expedition.primary_goal, {255, 80, 80, 180}, 0.55)
	}

	// Temp goal color by mode.
	if expedition.has_temp {
		col: k2.Color
		switch expedition.mode {
		case .Foraging:
			col = {80, 220, 100, 200}
		case .Revealing:
			col = {80, 220, 255, 200}
		case .Returning:
			col = {255, 160, 60, 200}
		case .ToGoal:
			col = {255, 255, 255, 180}
		}
		draw_hex_overlay(expedition.temp_goal, col, 0.5)
	}

	// Home marker (small).
	draw_hex_overlay(expedition.home, {200, 200, 200, 120}, 0.3)

	draw_hex_overlay(expedition.explorer.hex, {255, 255, 255, 230}, 0.45)
	k2.draw_circle(expedition.explorer.pos, HEX_SIZE * 0.28, {40, 180, 255, 255}, 12)
}
