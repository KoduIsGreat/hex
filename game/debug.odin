package game

// Debug / test entry harness. Instead of hand-editing temp code into init() to
// probe a specific part of the run loop, pass flags on the command line:
//
//   Headless (no window) - simulate a run and print its per-day decision trace:
//     odin run . -define:KARL2D_RENDER_BACKEND=gl -- --headless
//     ... -- --headless --doctrine=surveyor --goal=40,-20 --seed=123
//
//   Interactive - boot straight into a phase of the state machine:
//     ... -- --phase=simulation --doctrine=surveyor --goal=40,-20
//     ... -- --phase=prep
//     ... -- --phase=analysis --goal=30,-15
//
// Flags (all optional):
//   --headless          run with no window, print the trace, then exit
//   --phase=NAME        boot the interactive app into maproom|prep|simulation|analysis
//   --doctrine=NAME     cautious | surveyor | forager        (default cautious)
//   --goal=Q,R[,S]      objective hex, S derived if omitted  (default 40,-20)
//   --start=Q,R[,S]     start/home hex                       (default 0,0)
//   --seed=N            world seed (i64)
//   --freq=F            noise frequency (f64)
//   --fresh             ignore any on-disk save (fresh world)
//
// Both --headless and --phase boots are non-destructive: they never write the
// on-disk save, so probing the state machine can't clobber a real playthrough.

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Set from --fresh before init() so the interactive boot skips loading the save.
debug_fresh: bool

DebugConfig :: struct {
	headless:     bool,
	phase_set:    bool,
	phase:        GamePhase,
	doctrine:     Doctrine,
	goal:         Hex,
	start:        Hex,
	seed:         i64,
	freq:         f64,
	seed_set:     bool,
	freq_set:     bool,
	fresh:        bool,
}

// Parse the "q,r" / "q,r,s" form of a hex argument.
@(private = "file")
parse_hex_arg :: proc(s: string) -> (Hex, bool) {
	parts := strings.split(s, ",", context.temp_allocator)
	if len(parts) < 2 {
		return {}, false
	}
	q, ok_q := strconv.parse_int(strings.trim_space(parts[0]))
	r, ok_r := strconv.parse_int(strings.trim_space(parts[1]))
	if !ok_q || !ok_r {
		return {}, false
	}
	if len(parts) >= 3 {
		s3, ok_s := strconv.parse_int(strings.trim_space(parts[2]))
		if ok_s {
			return Hex{i32(q), i32(r), i32(s3)}, true
		}
	}
	return Hex{i32(q), i32(r), i32(-q - r)}, true
}

@(private = "file")
parse_doctrine_arg :: proc(name: string) -> (Doctrine, bool) {
	switch strings.to_lower(name, context.temp_allocator) {
	case "cautious":
		return doctrine_cautious(), true
	case "surveyor", "aggressive_surveyor":
		return doctrine_aggressive_surveyor(), true
	case "forager", "opportunistic_forager":
		return doctrine_opportunistic_forager(), true
	}
	return {}, false
}

@(private = "file")
parse_phase_arg :: proc(name: string) -> (GamePhase, bool) {
	switch strings.to_lower(name, context.temp_allocator) {
	case "maproom", "map_room", "map":
		return .MapRoom, true
	case "prep":
		return .Prep, true
	case "simulation", "sim":
		return .Simulation, true
	case "analysis":
		return .Analysis, true
	}
	return {}, false
}

// Build a DebugConfig from the command line. Unknown flags warn but are ignored.
debug_parse_args :: proc() -> DebugConfig {
	cfg := DebugConfig {
		doctrine = doctrine_cautious(),
		goal     = Hex{40, -20, -20},
		start    = Hex{0, 0, 0},
	}

	for arg in os.args[1:] {
		if !strings.has_prefix(arg, "--") {
			continue
		}
		body := arg[2:]
		key := body
		val := ""
		if eq := strings.index_byte(body, '='); eq >= 0 {
			key = body[:eq]
			val = body[eq + 1:]
		}

		switch key {
		case "headless":
			cfg.headless = true
		case "fresh":
			cfg.fresh = true
		case "phase":
			if p, ok := parse_phase_arg(val); ok {
				cfg.phase = p
				cfg.phase_set = true
			} else {
				fmt.eprintfln("debug: unknown --phase=%q", val)
			}
		case "doctrine":
			if d, ok := parse_doctrine_arg(val); ok {
				cfg.doctrine = d
			} else {
				fmt.eprintfln("debug: unknown --doctrine=%q", val)
			}
		case "goal":
			if h, ok := parse_hex_arg(val); ok {
				cfg.goal = h
			} else {
				fmt.eprintfln("debug: bad --goal=%q (want q,r or q,r,s)", val)
			}
		case "start":
			if h, ok := parse_hex_arg(val); ok {
				cfg.start = h
			} else {
				fmt.eprintfln("debug: bad --start=%q (want q,r or q,r,s)", val)
			}
		case "seed":
			if n, ok := strconv.parse_i64(val); ok {
				cfg.seed = n
				cfg.seed_set = true
			} else {
				fmt.eprintfln("debug: bad --seed=%q", val)
			}
		case "freq":
			if f, ok := strconv.parse_f64(val); ok {
				cfg.freq = f
				cfg.freq_set = true
			} else {
				fmt.eprintfln("debug: bad --freq=%q", val)
			}
		case:
			fmt.eprintfln("debug: ignoring unknown flag --%s", key)
		}
	}
	return cfg
}

// Headless: set up the world with no renderer, simulate one run, print the
// full per-day decision trace, then return. Never writes the save file.
debug_run_headless :: proc(cfg: DebugConfig) {
	persist_enabled = false // never touch the on-disk save from a headless run
	if cfg.seed_set {
		world_seed = cfg.seed
	}
	if cfg.freq_set {
		noise_freq = cfg.freq
	}

	world_init()
	expedition_init() // allocates fog/belief state, reveals the home area
	expedition.home = cfg.start
	world_revealed_reset()

	fmt.printfln(
		"headless run: seed=%v freq=%v doctrine=%q start=%v goal=%v",
		world_seed,
		noise_freq,
		cfg.doctrine.name,
		cfg.start,
		cfg.goal,
	)

	r := simulate_run(cfg.start, cfg.goal, cfg.doctrine)
	for d in r.days {
		fmt.printfln(
			"D%v [%s] pos=%v rations=%.1f  %s",
			d.day,
			mission_mode_name(d.mode),
			d.pos,
			d.rations,
			d.reason,
		)
	}
	last := max(0, len(r.days) - 1)
	fmt.printfln("OUTCOME: %s in %d days (goal %v)", run_outcome_name(r.outcome), last, r.goal)

	run_free(&r)
	expedition_shutdown()
	world_shutdown()
}

// Interactive: after the normal init(), jump straight into a phase so a visual
// check does not require clicking through the whole loop. For Simulation and
// Analysis this launches a run to the configured goal first.
debug_enter_phase :: proc(cfg: DebugConfig) {
	// A debug boot is a throwaway session: never overwrite the real save (a run
	// launch and the on-quit save both call society_save otherwise).
	persist_enabled = false
	expedition_set_doctrine(cfg.doctrine)

	switch cfg.phase {
	case .MapRoom:
		show_known_world()
		game_phase = .MapRoom
	case .Prep:
		do_plan()
	case .Simulation:
		expedition_set_goal(cfg.goal)
		do_launch()
	case .Analysis:
		expedition_set_goal(cfg.goal)
		do_launch()
		do_skip_to_analysis()
	}
	fmt.eprintfln("debug: booted into phase %v", game_phase)
}
