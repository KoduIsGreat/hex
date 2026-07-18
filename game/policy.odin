package game

MissionMode :: enum u8 {
	ToGoal,
	Foraging,
	Revealing,
	Returning,
}

FORAGE_RATION_GAIN :: f32(6)
REVEAL_SEARCH_RADIUS :: i32(8)

// Estimate days to return home via A* (belief + doctrine). Returns a large
// number if unreachable so Safe Return does not falsely trigger.
estimated_return_cost :: proc(from, home: Hex, doctrine: Doctrine) -> f32 {
	if from == home {
		return 0
	}
	res := pathfind_astar(from, home, doctrine, context.temp_allocator)
	if !res.found {
		return 1e9
	}
	return res.cost
}

// Find nearest passable Forest (revealed true forest, or believed forest argmax)
// within max hex distance. Prefer closer tiles.
find_forage_target :: proc(from: Hex, max_dist: i32) -> (Hex, bool) {
	best: Hex
	best_d := max_dist + 1
	found := false

	for dq in -max_dist ..= max_dist {
		r1 := max(-max_dist, -dq - max_dist)
		r2 := min(max_dist, -dq + max_dist)
		for dr in r1 ..= r2 {
			h := Hex{from[0] + dq, from[1] + dr, -from[0] - dq - from[1] - dr}
			if h == from || !in_arena(h) {
				continue
			}
			d := hex_distance(from, h)
			if d >= best_d {
				continue
			}
			kind, _ := dominant_terrain(h)
			if kind != .Forest {
				continue
			}
			if is_revealed(h) && !is_passable(terrain_at(h)) {
				continue
			}
			best = h
			best_d = d
			found = true
		}
	}
	return best, found
}

// How strongly a vantage's progress toward the goal weighs in its reveal score.
REVEAL_ALIGN_WEIGHT :: f32(8)

// Prefer revealed Hills, else believed Hill/Mountain, within search radius.
// When `toward_only` is set, only vantages that lie closer to `goal` than the
// current position are considered, and progress toward `goal` dominates the
// score — so the surveyor climbs to see ahead rather than re-scouting behind it.
find_reveal_target :: proc(from: Hex, radius: i32, goal: Hex, toward_only: bool) -> (Hex, bool) {
	best: Hex
	best_score: f32 = -1
	found := false
	goal_dist := hex_distance(from, goal)

	for dq in -radius ..= radius {
		r1 := max(-radius, -dq - radius)
		r2 := min(radius, -dq + radius)
		for dr in r1 ..= r2 {
			h := Hex{from[0] + dq, from[1] + dr, -from[0] - dq - from[1] - dr}
			if h == from || !in_arena(h) {
				continue
			}
			// Progress toward the goal: positive means this vantage is ahead.
			align := f32(goal_dist - hex_distance(h, goal))
			if toward_only && align <= 0 {
				continue // not in the direction of the target — skip it
			}
			kind, conf := dominant_terrain(h)
			vision: i32
			score: f32
			if is_revealed(h) {
				if !is_passable(terrain_at(h)) {
					continue
				}
				k := terrain_at(h)
				if k != .Hill && k != .Mountain {
					continue
				}
				// Mountains are impassable in PoC — only hills for standing on.
				if k == .Mountain {
					continue
				}
				vision = vision_radius(k)
				score = f32(vision) * 10 - f32(hex_distance(from, h))
			} else {
				if kind != .Hill && kind != .Mountain {
					continue
				}
				// Only path onto believed hills (passable); mountains stay penalty tiles.
				if kind == .Mountain {
					continue
				}
				vision = vision_radius(kind)
				score = f32(vision) * 10 * conf - f32(hex_distance(from, h))
			}
			if toward_only {
				score += align * REVEAL_ALIGN_WEIGHT
			}
			if score > best_score {
				best_score = score
				best = h
				found = true
			}
		}
	}
	return best, found
}

// True when primary path is unusable (missing or next tile known impassable).
path_is_blocked :: proc() -> bool {
	if !expedition.has_primary {
		return false
	}
	if !expedition.path.found || len(expedition.path.path) < 2 {
		return true
	}
	if expedition.path_index >= len(expedition.path.path) - 1 {
		return false // already at end of this path segment
	}
	next := expedition.path.path[expedition.path_index + 1]
	if is_revealed(next) && !is_passable(terrain_at(next)) {
		return true
	}
	return false
}

// Evaluate and possibly switch mission mode / temp goal. Returns true if mode changed.
policy_evaluate :: proc() -> bool {
	d := expedition.doctrine
	cur := expedition.explorer.hex
	prev_mode := expedition.mode

	// Already on a temp mission: don't interrupt until complete (except Safe Return).
	if expedition.mode == .Returning {
		return false
	}

	// 1) Safe Return — highest priority (can interrupt forage/reveal).
	if d.emergency == .SafeReturn && expedition.mode != .Returning {
		ret := estimated_return_cost(cur, expedition.home, d)
		if expedition.rations <= ret && ret < 1e8 {
			expedition.mode = .Returning
			expedition.temp_goal = expedition.home
			expedition.has_temp = true
			trace_append(
				expedition.days_elapsed,
				.Returning,
				"SafeReturn: rations %.1f <= return %.1f",
				expedition.rations,
				ret,
			)
			return true
		}
	}

	// Don't interrupt an active forage/reveal with a new forage/reveal.
	if expedition.mode == .Foraging || expedition.mode == .Revealing {
		return false
	}

	// 2) Opportunistic forage.
	if d.forage == .ForageOpportunistic && expedition.rations < d.ration_danger {
		max_d := i32(d.max_detour)
		if target, ok := find_forage_target(cur, max_d); ok {
			expedition.mode = .Foraging
			expedition.temp_goal = target
			expedition.has_temp = true
			trace_append(
				expedition.days_elapsed,
				.Foraging,
				"Forage: rations %.1f < danger %.1f -> forest",
				expedition.rations,
				d.ration_danger,
			)
			return true
		}
	}

	// 3) Smart Reveal on impasse / missing path.
	if d.impasse == .SmartReveal && expedition.reveal_attempts < d.max_reveal_attempts {
		need_reveal := path_is_blocked()
		// Also trigger if primary path cost is huge vs hex distance (detour smell).
		if !need_reveal && expedition.path.found && expedition.has_primary {
			straight := f32(hex_distance(cur, expedition.primary_goal))
			if straight > 0 && expedition.path.cost > d.max_detour && expedition.path.cost > straight * 3 {
				need_reveal = true
			}
		}
		if need_reveal {
			if target, ok := find_reveal_target(cur, REVEAL_SEARCH_RADIUS, expedition.primary_goal, d.reveal_toward_goal); ok {
				expedition.mode = .Revealing
				expedition.temp_goal = target
				expedition.has_temp = true
				expedition.reveal_attempts += 1
				trace_append(
					expedition.days_elapsed,
					.Revealing,
					"SmartReveal: climb hill (attempt %v/%v)",
					expedition.reveal_attempts,
					d.max_reveal_attempts,
				)
				_ = prev_mode
				return true
			}
		}
	}

	_ = prev_mode
	return false
}

// Called when explorer reaches the active (temp or primary) goal.
policy_on_arrived :: proc() -> (continue_run: bool) {
	switch expedition.mode {
	case .Returning:
		expedition_set_status("Safe return after %v days. Rations: %.1f", expedition.days_elapsed, expedition.rations)
		trace_append(expedition.days_elapsed, .Returning, "Arrived home — run ended")
		expedition.playing = false
		expedition.run_over = true
		expedition.has_temp = false
		expedition.mode = .ToGoal
		path_clear(&expedition.path)
		return false

	case .Foraging:
		expedition.rations += FORAGE_RATION_GAIN
		trace_append(
			expedition.days_elapsed,
			.Foraging,
			"Foraged +%.0f rations (now %.1f)",
			FORAGE_RATION_GAIN,
			expedition.rations,
		)
		expedition.mode = .ToGoal
		expedition.has_temp = false
		expedition_set_status("Foraged. Resuming goal. Rations: %.1f", expedition.rations)
		expedition_repath()
		return true

	case .Revealing:
		trace_append(expedition.days_elapsed, .Revealing, "Reveal climb done — repathing")
		expedition.mode = .ToGoal
		expedition.has_temp = false
		expedition_set_status("Revealed from high ground. Resuming goal.")
		expedition_repath()
		return true

	case .ToGoal:
		expedition_set_status("Arrived in %v days. Rations left: %.1f", expedition.days_elapsed, expedition.rations)
		trace_append(expedition.days_elapsed, .ToGoal, "Reached primary goal")
		expedition.playing = false
		expedition.run_over = true
		return false
	}
	return false
}

active_goal :: proc() -> (Hex, bool) {
	if expedition.has_temp {
		return expedition.temp_goal, true
	}
	if expedition.has_primary {
		return expedition.primary_goal, true
	}
	return {}, false
}
