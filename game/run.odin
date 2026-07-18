package game

// Precomputed run + playback (GDD §6.1). At Launch the whole expedition is
// simulated to completion in one pass, producing an ordered list of per-day
// results. Playback then scrubs that list without re-simulating: it rebuilds the
// revealed/belief state as of the selected day so all existing rendering works.
//
// The simulation is deterministic given (world, doctrine, start, goal): the world
// is fixed and stepping has no RNG, so the same inputs reproduce the same run.

import "core:strings"
import k2 "karl2d"

MAX_RUN_DAYS :: 600 // hard cap on expedition length (a stuck run ends here)
NO_PROGRESS_LIMIT :: 60 // ToGoal days without getting closer -> give up (stuck)

RunOutcome :: enum {
	Incomplete,
	ReachedGoal,
	SafeReturned,
	OutOfRations,
	NoPath,
}

DayResult :: struct {
	day:            int,
	pos:            Hex,
	mode:           MissionMode,
	rations:        f32,
	revealed_delta: []Hex, // tiles first revealed on this day
	reason:         string, // decision-trace summary for this day
}

RunResult :: struct {
	days:           [dynamic]DayResult,
	outcome:        RunOutcome,
	start:          Hex,
	goal:           Hex,
	start_revealed: []Hex, // revealed set before the run, for playback reconstruction
}

Playback :: struct {
	cursor:  int,
	playing: bool,
	timer:   f32,
}

run_result: RunResult
run_active: bool
playback: Playback

run_free :: proc(r: ^RunResult) {
	for d in r.days {
		delete(d.revealed_delta)
		delete(d.reason)
	}
	delete(r.days)
	delete(r.start_revealed)
	r^ = {}
}

run_clear :: proc() {
	if run_active {
		run_free(&run_result)
		run_active = false
	}
	playback = {}
}

// --- Precompute -----------------------------------------------------------

@(private = "file")
clone_hexes :: proc(s: []Hex) -> []Hex {
	out := make([]Hex, len(s))
	copy(out, s)
	return out
}

// Run a whole expedition from start to goal to completion, capturing a per-day
// result each day. Mutates the global revealed/belief/expedition state to the
// run's final state (playback rewinds it). Deterministic given the inputs.
simulate_run :: proc(start, goal: Hex, doctrine: Doctrine) -> RunResult {
	r: RunResult
	r.days = make([dynamic]DayResult)
	r.start = start
	r.goal = goal

	// Base the run on the persistent known world (playback may have left the
	// display buffer `revealed` rewound to a cursor), and snapshot it so
	// playback can reconstruct any day's fog.
	clear(&revealed)
	sr := make([dynamic]Hex)
	for h in world_revealed {
		revealed[h] = true
		append(&sr, h)
	}
	r.start_revealed = sr[:]
	belief_recompute()

	// Reset run state to a fresh expedition from `start`.
	expedition.doctrine = doctrine
	expedition.explorer.hex = start
	expedition.explorer.pos = hex_to_world(start, HEX_SIZE, ORIENT)
	expedition.primary_goal = goal
	expedition.has_primary = true
	expedition.has_temp = false
	expedition.mode = .ToGoal
	expedition.rations = STARTING_RATIONS
	expedition.days_elapsed = 0
	expedition.reveal_attempts = 0
	expedition.run_over = false
	path_clear(&expedition.path)
	trace_clear()

	// Day 0: reveal around the start and record it.
	reveal_begin()
	reveal_from_tile(start)
	belief_update(newly_revealed[:])
	expedition_repath()
	append(
		&r.days,
		DayResult {
			day = 0,
			pos = start,
			mode = .ToGoal,
			rations = expedition.rations,
			revealed_delta = clone_hexes(newly_revealed[:]),
			reason = strings.clone("Launch"),
		},
	)

	// Iteration-bounded (not day-bounded): a step can do policy work without
	// advancing the day. We guarantee termination three ways: a hard day cap, a
	// stall guard (no day advanced), and a no-progress guard (the explorer keeps
	// moving in ToGoal mode but never gets closer to the goal - i.e. stuck /
	// oscillating). Record a DayResult only when the day advances.
	stall := 0
	best_dist := max(i32)
	no_progress := 0
	stuck := false
	for _ in 0 ..< MAX_RUN_DAYS {
		reveal_begin() // empty delta on days that reveal nothing
		prev_day := expedition.days_elapsed
		c0 := decision_trace.count
		cont := expedition_step()
		if expedition.days_elapsed > prev_day {
			reason := decision_trace.count > c0 ? trace_latest_reason() : ""
			append(
				&r.days,
				DayResult {
					day = expedition.days_elapsed,
					pos = expedition.explorer.hex,
					mode = expedition.mode,
					rations = expedition.rations,
					revealed_delta = clone_hexes(newly_revealed[:]),
					reason = strings.clone(reason),
				},
			)
			stall = 0
			// Track progress toward the goal (only while actually heading there).
			if expedition.mode == .ToGoal {
				d := hex_distance(expedition.explorer.hex, goal)
				if d < best_dist {
					best_dist = d
					no_progress = 0
				} else {
					no_progress += 1
					if no_progress >= NO_PROGRESS_LIMIT {
						stuck = true
						break
					}
				}
			}
		} else {
			stall += 1
			if stall >= 64 {
				break // policy churn without forward progress -> stop
			}
		}
		if !cont || expedition.run_over {
			break
		}
	}

	r.outcome = run_classify(stuck)

	// Discoveries are permanent: fold them into the persistent known world and
	// save (GDD §2). Playback afterward only rewinds the display buffer.
	world_revealed_commit(&r)
	society_save()
	return r
}

@(private = "file")
run_classify :: proc(stuck: bool) -> RunOutcome {
	if expedition.explorer.hex == expedition.primary_goal {
		return .ReachedGoal
	}
	if expedition.rations <= 0 {
		return .OutOfRations
	}
	if expedition.explorer.hex == expedition.home {
		return .SafeReturned
	}
	return stuck ? .Incomplete : .NoPath
}

run_outcome_name :: proc(o: RunOutcome) -> string {
	switch o {
	case .Incomplete:
		return "Stuck (no progress)"
	case .ReachedGoal:
		return "Reached goal"
	case .SafeReturned:
		return "Safe return"
	case .OutOfRations:
		return "Out of rations"
	case .NoPath:
		return "No path"
	}
	return "?"
}

// --- Launch + playback ----------------------------------------------------

// Precompute a fresh run from home to the current primary goal, then play it.
launch_run :: proc() {
	if !expedition.has_primary {
		expedition_set_status("Set a goal before launching.")
		return
	}
	run_clear()
	run_result = simulate_run(expedition.home, expedition.primary_goal, expedition.doctrine)
	run_active = true
	playback = {playing = true}
	playback_seek(0)
	expedition_set_status(
		"Launched: %v days, %s",
		len(run_result.days) - 1,
		run_outcome_name(run_result.outcome),
	)
}

// Rebuild the global revealed/belief state and explorer to show day `day`.
playback_seek :: proc(day: int) {
	if !run_active || len(run_result.days) == 0 {
		return
	}
	d := clamp(day, 0, len(run_result.days) - 1)
	playback.cursor = d

	clear(&revealed)
	for h in run_result.start_revealed {
		revealed[h] = true
	}
	for i in 0 ..= d {
		for h in run_result.days[i].revealed_delta {
			revealed[h] = true
		}
	}
	belief_recompute()

	dr := run_result.days[d]
	expedition.explorer.hex = dr.pos
	expedition.explorer.pos = hex_to_world(dr.pos, HEX_SIZE, ORIENT)
	expedition.days_elapsed = dr.day
	expedition.rations = dr.rations
	expedition.mode = dr.mode
}

playback_step :: proc(delta: int) {
	playback.playing = false
	playback_seek(playback.cursor + delta)
}

playback_update :: proc(dt: f32) {
	if !run_active || !playback.playing {
		return
	}
	playback.timer -= dt
	if playback.timer <= 0 {
		playback.timer = STEP_INTERVAL
		if playback.cursor >= len(run_result.days) - 1 {
			playback.playing = false
		} else {
			playback_seek(playback.cursor + 1)
		}
	}
}

playback_toggle :: proc() {
	if playback.cursor >= len(run_result.days) - 1 {
		playback_seek(0) // restart from the beginning if at the end
	}
	playback.playing = !playback.playing
	playback.timer = 0
}

// Traveled route up to the cursor, plus goal and explorer, drawn in world space.
playback_draw_overlays :: proc() {
	col := k2.Color{255, 220, 80, 220}
	for i in 1 ..= playback.cursor {
		a := hex_to_world(run_result.days[i - 1].pos, HEX_SIZE, ORIENT)
		b := hex_to_world(run_result.days[i].pos, HEX_SIZE, ORIENT)
		k2.draw_line(a, b, 3, col)
	}
	draw_hex_overlay(run_result.goal, {255, 80, 80, 180}, 0.55)
	draw_hex_overlay(expedition.home, {200, 200, 200, 120}, 0.3)
	draw_hex_overlay(expedition.explorer.hex, {255, 255, 255, 230}, 0.45)
	k2.draw_circle(expedition.explorer.pos, HEX_SIZE * 0.28, {40, 180, 255, 255}, 12)
}
