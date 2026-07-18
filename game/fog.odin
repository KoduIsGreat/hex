package game

import k2 "karl2d"

// The playable arena is the whole finite world (see world.odin). in_arena is
// therefore also the "inside the baked world" test used by world_tile.
ARENA_RADIUS :: WORLD_RADIUS
FOG_COLOR :: k2.Color{18, 22, 32, 220}

revealed: map[Hex]bool

// Hexes revealed since the last reveal_begin. Consumed by belief_update so
// belief only recomputes near freshly-revealed ground (see belief.odin).
newly_revealed: [dynamic]Hex

fog_init :: proc() {
	if revealed == nil {
		revealed = make(map[Hex]bool)
		newly_revealed = make([dynamic]Hex)
		world_revealed = make(map[Hex]bool)
	} else {
		clear(&revealed)
		clear(&newly_revealed)
		clear(&world_revealed)
	}
}

fog_shutdown :: proc() {
	delete(revealed)
	delete(newly_revealed)
	delete(world_revealed)
	revealed = {}
	newly_revealed = {}
	world_revealed = {}
}

// Begin a reveal batch: clears the newly-revealed accumulator.
reveal_begin :: proc() {
	clear(&newly_revealed)
}

in_arena :: proc(h: Hex) -> bool {
	origin := Hex{0, 0, 0}
	return hex_distance(h, origin) <= ARENA_RADIUS
}

is_revealed :: proc(h: Hex) -> bool {
	return h in revealed
}

reveal_hex :: proc(h: Hex) {
	if in_arena(h) && !(h in revealed) {
		revealed[h] = true
		append(&newly_revealed, h)
	}
}

// Reveal every hex within `radius` of center (cube distance).
reveal_around :: proc(center: Hex, radius: i32) {
	for dq in -radius ..= radius {
		r1 := max(-radius, -dq - radius)
		r2 := min(radius, -dq + radius)
		for dr in r1 ..= r2 {
			h := Hex{center[0] + dq, center[1] + dr, -center[0] - dq - center[1] - dr}
			reveal_hex(h)
		}
	}
}

// Reveal using the vision radius of the terrain under `center`.
reveal_from_tile :: proc(center: Hex) {
	reveal_around(center, vision_radius(terrain_at(center)))
}
