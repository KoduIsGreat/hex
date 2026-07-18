package game

// Persistence (GDD §2, §10.3): "all cleared fog remains cleared across runs".
//
// world_revealed is the persistent, accumulated known world - the source of
// truth for what has ever been discovered. It is distinct from `revealed`, which
// is the live display/gameplay buffer (rewound during playback). Terrain is a
// pure function of (seed, coords), so only non-derivable state is saved: the
// seed, the revealed set, and the society meta. Belief is recomputed on load.

import "core:encoding/json"

SAVE_PATH :: "wayfinder_save.json"

// On-disk save shape. Hex is [3]i32; JSON stores each as a 3-element array.
Society :: struct {
	seed:       i64,
	noise_freq: f64,
	revealed:   [][3]i32,
	prestige:   int,
	funding:    int,
}

prestige: int
funding: int
world_revealed: map[Hex]bool // persistent accumulated known world

society_save :: proc() {
	soc: Society
	soc.seed = world_seed
	soc.noise_freq = noise_freq
	soc.prestige = prestige
	soc.funding = funding

	rev := make([][3]i32, len(world_revealed), context.temp_allocator)
	i := 0
	for h in world_revealed {
		rev[i] = {h[0], h[1], h[2]}
		i += 1
	}
	soc.revealed = rev

	data, err := json.marshal(soc, {pretty = true}, context.temp_allocator)
	if err != nil {
		return
	}
	save_write(SAVE_PATH, data)
}

// Load a save if present. Returns the parsed society and whether it loaded.
// The caller applies it (seed/noise_freq/revealed) before baking the world.
society_load :: proc() -> (Society, bool) {
	data, ok := save_read(SAVE_PATH)
	if !ok {
		return {}, false
	}
	defer delete(data)
	soc: Society
	if json.unmarshal(data, &soc) != nil {
		return {}, false
	}
	return soc, true
}

// Reset the persistent known world to mirror the current display revealed set
// (used on a fresh world / reseed).
world_revealed_reset :: proc() {
	clear(&world_revealed)
	for h in revealed {
		world_revealed[h] = true
	}
}

// Fold a completed run's discoveries into the persistent known world.
world_revealed_commit :: proc(r: ^RunResult) {
	for d in r.days {
		for h in d.revealed_delta {
			world_revealed[h] = true
		}
	}
}
