package game

import "core:math/noise"

// The world is a fixed hex disc of radius WORLD_RADIUS, generated once at start
// (and on seed/param change) into a flat array. Terrain is a pure function of
// (seed, coords), so at runtime only this baked array plus the persistent
// revealed set need to exist - nothing streams. ARENA_RADIUS (fog.odin) aliases
// WORLD_RADIUS, so in_arena is also the "inside the finite world" test.

WORLD_RADIUS :: i32(160)
WORLD_SPAN :: int(2 * WORLD_RADIUS + 1)

world_tiles: []TILE_TYPE

world_init :: proc() {
	world_tiles = make([]TILE_TYPE, WORLD_SPAN * WORLD_SPAN)
	river_tiles = make(map[Hex]bool)
	lake_tiles = make(map[Hex]bool)
	bake_world()
}

world_shutdown :: proc() {
	delete(world_tiles)
	delete(river_tiles)
	delete(lake_tiles)
}

// Flat index for a hex within the world disc. Valid only when in_arena(h): the
// disc guarantees |q| <= R and |r| <= R, so the index is always in range.
world_index :: proc "contextless" (h: Hex) -> int {
	return int(h[0] + WORLD_RADIUS) * WORLD_SPAN + int(h[1] + WORLD_RADIUS)
}

// Baked terrain for a hex; ocean sentinel outside the finite world.
world_tile :: proc(h: Hex) -> TILE_TYPE {
	if !in_arena(h) {
		return .DeepOcean
	}
	return world_tiles[world_index(h)]
}

// Generate the whole world once: trace all rivers, then fill every disc tile
// from the biome model, converting land river/lake hexes to water.
bake_world :: proc() {
	clear(&river_tiles)
	clear(&lake_tiles)
	trace_all_rivers()

	R := WORLD_RADIUS
	for q in -R ..= R {
		r1 := max(-R, -q - R)
		r2 := min(R, -q + R)
		for r in r1 ..= r2 {
			h := Hex{q, r, -q - r}
			b := biome_at(hex_to_world(h, HEX_SIZE, ORIENT))
			if h in river_tiles || h in lake_tiles {
				#partial switch b {
				case .DeepOcean, .Ocean, .Mountain:
				// leave as-is
				case:
					b = .Ocean
				}
			}
			world_tiles[world_index(h)] = b
		}
	}
}

// Trace every river source whose reach could touch the world disc, once. The
// disc fits inside the [-R,R] axial box; sources may sit RIVER_REACH beyond it.
trace_all_rivers :: proc() {
	R := WORLD_RADIUS
	lo := floor_div(-R - RIVER_REACH, RIVER_SRC_CELL)
	hi := floor_div(R + RIVER_REACH, RIVER_SRC_CELL)
	for cy in lo ..= hi {
		for cx in lo ..= hi {
			src := source_for_cell(cx, cy)
			if elevation_at(hex_to_world(src, HEX_SIZE, ORIENT)) > RIVER_SOURCE_ELEV {
				trace_river(src)
			}
		}
	}
}


// --- Worldgen noise -------------------------------------------------------

NOISE_OCTAVES :: 4
WARP_STRENGTH :: f64(0.6) // how much domain warping distorts features

// Elevation thresholds (on fbm, ~[-1,1]).
SEA_DEEP :: f64(-0.35)
SEA :: f64(-0.12)
COAST :: f64(-0.02)
// Mountain thresholds (on the ridged mountain factor, [0,1]).
MTN_PEAK :: f64(0.62)
MTN_HIGH :: f64(0.52)
MTN_HILL :: f64(0.44)
// Moisture thresholds (on fbm remapped to [0,1]).
FOREST_DENSE :: f64(0.62)
FOREST_LIGHT :: f64(0.42)

// Fractal Brownian motion: layered octaves of simplex noise. Returns ~[-1,1].
fbm :: proc(p: [2]f64, seed: i64, octaves: int) -> f64 {
	v, amp, freq, norm := 0.0, 1.0, 1.0, 0.0
	for _ in 0 ..< octaves {
		v += amp * f64(noise.noise_2d(seed, {p.x * freq, p.y * freq}))
		norm += amp
		amp *= 0.5
		freq *= 2.0
	}
	return v / norm
}

// Ridged multifractal: produces sharp ridge lines (mountain ranges). [0,1].
ridged :: proc(p: [2]f64, seed: i64, octaves: int) -> f64 {
	v, amp, freq, norm := 0.0, 0.5, 1.0, 0.0
	for _ in 0 ..< octaves {
		n := f64(noise.noise_2d(seed, {p.x * freq, p.y * freq}))
		n = 1.0 - abs(n) // fold into ridges
		n *= n // sharpen
		v += amp * n
		norm += amp
		amp *= 0.5
		freq *= 2.0
	}
	return v / norm
}

// Offset the sample point by another noise field -> organic, non-grid features.
warp :: proc(p: [2]f64, seed: i64) -> [2]f64 {
	wx := fbm({p.x, p.y}, seed + 101, 3)
	wy := fbm({p.x + 5.2, p.y + 1.3}, seed + 202, 3)
	return {p.x + WARP_STRENGTH * wx, p.y + WARP_STRENGTH * wy}
}

// Domain-warped elevation field, ~[-1,1]. Shared by biomes and river tracing.
elevation_at :: proc(center: Vec2) -> f64 {
	p := [2]f64{f64(center.x) * noise_freq, f64(center.y) * noise_freq}
	return fbm(warp(p, world_seed), world_seed, NOISE_OCTAVES)
}

TEMP_FREQ :: f64(0.35) // temperature varies more slowly than elevation
TEMP_LAPSE :: f64(0.7) // how strongly altitude cools the climate
COLD :: f64(0.30) // temperature below this is cold/tundra
HOT :: f64(0.65) // temperature above this is hot/arid

// Moisture field, [0,1]. Larger, slower regions than elevation.
moisture_at :: proc(p: [2]f64) -> f64 {
	return (fbm({p.x * 0.6 + 100, p.y * 0.6 + 100}, world_seed + 303, 3) + 1) * 0.5
}

// Temperature field, [0,1]. A slow noise field, cooled by altitude.
temperature_at :: proc(p: [2]f64, e01: f64) -> f64 {
	base := (fbm({p.x * TEMP_FREQ + 50, p.y * TEMP_FREQ - 70}, world_seed + 555, 3) + 1) * 0.5
	return clamp(base - TEMP_LAPSE * max(0, e01 - 0.5), 0, 1)
}

// Stateless biome via a Whittaker-style model: elevation picks water/coast/
// mountain; on land, temperature x moisture select the biome.
biome_at :: proc(center: Vec2) -> TILE_TYPE {
	p := [2]f64{f64(center.x) * noise_freq, f64(center.y) * noise_freq}
	e := elevation_at(center)
	e01 := (e + 1) * 0.5
	t := temperature_at(p, e01)

	// Water (cold seas freeze into ice).
	if e < SEA_DEEP {
		return .DeepOcean
	}
	if e < SEA {
		return .Ice if t < COLD - 0.08 else .Ocean
	}

	m := moisture_at(p)

	// Coastal lowland just above sea level, flavored by climate.
	if e < COAST {
		switch {
		case t < COLD:
			return .Snow
		case t > HOT && m > 0.6:
			return .Swamp
		case:
			return .Grass
		}
	}

	// Mountain ranges -> ridged noise, amplified at altitude.
	ridge := ridged({p.x * 1.3, p.y * 1.3}, world_seed + 404, NOISE_OCTAVES)
	mtn := ridge * (0.45 + 0.55 * e01)
	if mtn > MTN_PEAK {
		return .Mountain
	}
	if mtn > MTN_HIGH {
		switch {
		case t < COLD:
			return .SnowPines
		case t > HOT && m < 0.4:
			return .Mesa
		case:
			return .RockyUplands
		}
	}
	if mtn > MTN_HILL {
		switch {
		case t < COLD:
			return .SnowRocky
		case t > HOT && m < 0.4:
			return .Mesa
		case:
			return .RockyHills
		}
	}

	// Lowlands: temperature band, then moisture.
	switch {
	case t < COLD: // cold
		switch {
		case m > 0.60:
			return .SnowDense
		case m > 0.35:
			return .SnowForest
		case:
			return .Snow
		}
	case t < HOT: // temperate
		switch {
		case m > 0.60:
			return .DenseForest
		case m > 0.40:
			return .LightForest
		case m > 0.22:
			return .Grass
		case:
			return .Plains
		}
	case: // hot
		switch {
		case m > 0.62:
			return .Jungle
		case m > 0.45:
			return .Savanna
		case m > 0.28:
			return .Grass
		case m > 0.15:
			return .Sand
		case:
			return .Dunes
		}
	}
}


// --- Rivers ---------------------------------------------------------------
// Sources spawn on a coarse grid wherever elevation is high enough, then flow
// downhill (steepest neighbor) until they hit the sea or a local minimum.
// River hexes are stored globally; bake_world converts land river-hexes to water.

RIVER_SRC_CELL :: i32(18) // one candidate source per this many hexes
RIVER_MAX_LEN :: i32(80) // max hexes a single river is traced
RIVER_SOURCE_ELEV :: f64(0.45) // min elevation (raw fbm) for a source to spawn

LAKE_MAX_TILES :: 500 // cap on a single lake/inland sea
LAKE_REACH :: i32(24) // max hex distance a lake spreads from its terminus
LAKE_DEPTH :: f64(0.05) // water rises this much above the terminus elevation

// A river that could affect the world may start up to RIVER_MAX_LEN away and
// then pool a lake reaching LAKE_REACH further, so search sources in that span.
RIVER_REACH :: RIVER_MAX_LEN + LAKE_REACH

river_tiles: map[Hex]bool // hexes that carry a river
lake_tiles: map[Hex]bool // hexes that are lake/inland-sea water

// Integer hash (splitmix-ish) for deterministic source placement.
hash_coord :: proc(x, y: i32, seed: i64) -> u64 {
	h := u64(seed) * 0x9E3779B97F4A7C15
	h ~= u64(u32(x)) * 0xFF51AFD7ED558CCD
	h = (h << 31) | (h >> 33)
	h ~= u64(u32(y)) * 0xC4CEB9FE1A85EC53
	h ~= h >> 29
	h *= 0xBF58476D1CE4E5B9
	h ~= h >> 32
	return h
}

source_for_cell :: proc(cx, cy: i32) -> Hex {
	hsh := hash_coord(cx, cy, world_seed + 909)
	q := cx * RIVER_SRC_CELL + i32(hsh % u64(RIVER_SRC_CELL))
	r := cy * RIVER_SRC_CELL + i32((hsh / u64(RIVER_SRC_CELL)) % u64(RIVER_SRC_CELL))
	return Hex{q, r, -q - r}
}

trace_river :: proc(source: Hex) {
	h := source
	for _ in 0 ..< RIVER_MAX_LEN {
		e := elevation_at(hex_to_world(h, HEX_SIZE, ORIENT))
		if e < SEA {
			return // reached the sea
		}
		river_tiles[h] = true

		best := h
		best_e := e
		for d in HEX_DIRS {
			n := hex_add(h, d)
			ne := elevation_at(hex_to_world(n, HEX_SIZE, ORIENT))
			if ne < best_e {
				best_e = ne
				best = n
			}
		}
		if best == h {
			fill_lake(h, e) // local minimum: water pools into a lake
			return
		}
		h = best
	}
}

// Flood-fill a depression from its lowest point up to a fixed water level.
// Bounded by tile count and reach so it stays deterministic and complete.
fill_lake :: proc(start: Hex, terminus_e: f64) {
	level := terminus_e + LAKE_DEPTH
	frontier := make([dynamic]Hex, context.temp_allocator)
	append(&frontier, start)
	count := 0
	for len(frontier) > 0 && count < LAKE_MAX_TILES {
		h := pop(&frontier)
		if h in lake_tiles {
			continue
		}
		if hex_distance(h, start) > LAKE_REACH {
			continue // keep extent bounded
		}
		e := elevation_at(hex_to_world(h, HEX_SIZE, ORIENT))
		if e < SEA || e > level {
			continue // below: it's the ocean; above: it's the shore
		}
		lake_tiles[h] = true
		count += 1
		for d in HEX_DIRS {
			append(&frontier, hex_add(h, d))
		}
	}
}

// Floored division so negative coords map correctly into source cells.
floor_div :: proc(a, b: i32) -> i32 {
	q := a / b
	if a % b != 0 && (a < 0) != (b < 0) {
		q -= 1
	}
	return q
}
