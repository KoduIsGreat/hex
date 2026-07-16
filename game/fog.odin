package game

import k2 "karl2d"

ARENA_RADIUS :: i32(40)
FOG_COLOR :: k2.Color{18, 22, 32, 220}

revealed: map[Hex]bool

fog_init :: proc() {
	if revealed == nil {
		revealed = make(map[Hex]bool)
	} else {
		clear(&revealed)
	}
}

fog_shutdown :: proc() {
	delete(revealed)
	revealed = {}
}

in_arena :: proc(h: Hex) -> bool {
	origin := Hex{0, 0, 0}
	return hex_distance(h, origin) <= ARENA_RADIUS
}

is_revealed :: proc(h: Hex) -> bool {
	return h in revealed
}

reveal_hex :: proc(h: Hex) {
	if in_arena(h) {
		revealed[h] = true
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
