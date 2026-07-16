package game

import "core:fmt"
import "core:math"
import "core:math/noise"
import "core:math/rand"
import k2 "karl2d"


hex_tex: k2.Texture
cloud_shader: k2.Shader
camera: k2.Camera

// Mutable worldgen params (tweakable at runtime).
world_seed := i64(447198347)
// Noise frequency in world (pixel) space. Lower = larger, smoother biomes.
noise_freq := f64(0.0008)


// Hex geometry "radius" (center to corner). Distinct from the sprite size below;
// tune this so neighboring sprites tessellate against your art.
HEX_SIZE :: f32(16)
ORIENT :: Orientation.FlatTop

// Sprite cells in hex.png are 32 wide x 48 tall (the extra height is the
// stacked "depth" of each tile).
SPRITE_W :: f32(32)
SPRITE_H :: f32(48)

TILE_TYPE :: enum u8 {
	// Row 0: temperate terrain
	Grass,
	LightForest,
	DenseForest,
	RockyHills,
	RockyUplands,
	Mountain,
	Ocean,
	DeepOcean,
	// Row 1: settlements + warm terrain
	Village,
	Town,
	Capital,
	DesertOrange,
	Jungle,
	Savanna,
	Plains,
	Swamp,
	// Row 2: snow / tundra
	Snow,
	SnowForest,
	SnowDense,
	SnowRocky,
	SnowPines,
	Ice,
	SnowVillage,
	SnowCapital,
	// Row 3: desert
	Sand,
	SandRocky,
	Dunes,
	Mesa,
	Oasis,
	DesertRocky,
	DesertVillage,
	DesertCapital,
	// Row 4-5: features
	Port,
	Port2,
	Lighthouse,
	Cave,
	Ruins,
}


init :: proc() {
	k2.init(1280, 720, "Wayfinder PoC")
	hex_tex = k2.load_texture_from_bytes(#load("../assets/hex.png"))
	cloud_shader = k2.load_shader_from_bytes(#load("clouds.vert"), #load("clouds.frag"))
	fmt.printfln("hex h=%v w=%v", hex_tex.height, hex_tex.width)
	camera = k2.Camera {
		target = {0, 0},
		offset = k2.get_screen_size() * 0.5,
		zoom   = 1,
	}
	world_cache = make(map[ChunkCoord]^Chunk)
	river_tiles = make(map[Hex]bool)
	lake_tiles = make(map[Hex]bool)
	traced_sources = make(map[ChunkCoord]bool)
	prev_world_seed = world_seed
	prev_noise_freq = noise_freq
	expedition_init()
}


// Atlas cell (col, row) -> source rect. Cells are 32 wide x 48 tall.
cell :: proc "contextless" (col, row: int) -> k2.Rect {
	return k2.Rect{f32(col) * SPRITE_W, f32(row) * SPRITE_H, SPRITE_W, SPRITE_H}
}

// Source rect in the atlas for each tile type, laid out to match hex.png.
tile_rects := [TILE_TYPE]k2.Rect {
	.Grass         = cell(0, 0),
	.LightForest   = cell(1, 0),
	.DenseForest   = cell(2, 0),
	.RockyHills    = cell(3, 0),
	.RockyUplands  = cell(4, 0),
	.Mountain      = cell(5, 0),
	.Ocean         = cell(6, 0),
	.DeepOcean     = cell(7, 0),
	.Village       = cell(0, 1),
	.Town          = cell(1, 1),
	.Capital       = cell(2, 1),
	.DesertOrange  = cell(3, 1),
	.Jungle        = cell(4, 1),
	.Savanna       = cell(5, 1),
	.Plains        = cell(6, 1),
	.Swamp         = cell(7, 1),
	.Snow          = cell(0, 2),
	.SnowForest    = cell(1, 2),
	.SnowDense     = cell(2, 2),
	.SnowRocky     = cell(3, 2),
	.SnowPines     = cell(4, 2),
	.Ice           = cell(5, 2),
	.SnowVillage   = cell(6, 2),
	.SnowCapital   = cell(7, 2),
	.Sand          = cell(0, 3),
	.SandRocky     = cell(1, 3),
	.Dunes         = cell(2, 3),
	.Mesa          = cell(3, 3),
	.Oasis         = cell(4, 3),
	.DesertRocky   = cell(5, 3),
	.DesertVillage = cell(6, 3),
	.DesertCapital = cell(7, 3),
	.Port          = cell(4, 4),
	.Port2         = cell(5, 4),
	.Lighthouse    = cell(6, 4),
	.Cave          = cell(7, 4),
	.Ruins         = cell(0, 5),
}

tile_rect :: proc(t: TILE_TYPE) -> k2.Rect {
	return tile_rects[t]
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
// River hexes are stored globally; a chunk converts its land river-hexes to water.

RIVER_SRC_CELL :: i32(18) // one candidate source per this many hexes
RIVER_MAX_LEN :: i32(80) // max hexes a single river is traced
RIVER_SOURCE_ELEV :: f64(0.45) // min elevation (raw fbm) for a source to spawn

LAKE_MAX_TILES :: 500 // cap on a single lake/inland sea
LAKE_REACH :: i32(24) // max hex distance a lake spreads from its terminus
LAKE_DEPTH :: f64(0.05) // water rises this much above the terminus elevation

// A river that could affect this chunk may start up to RIVER_MAX_LEN away and
// then pool a lake reaching LAKE_REACH further, so search sources in that span.
RIVER_REACH :: RIVER_MAX_LEN + LAKE_REACH

river_tiles: map[Hex]bool // hexes that carry a river
lake_tiles: map[Hex]bool // hexes that are lake/inland-sea water
traced_sources: map[ChunkCoord]bool // source cells already evaluated

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
// Bounded by tile count and reach so it stays deterministic and chunk-safe.
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
			continue // keep extent bounded for chunk completeness
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

// Trace every source whose river could possibly reach this chunk, so a chunk's
// rivers are complete no matter what order chunks are generated in.
ensure_rivers_near :: proc(cc: ChunkCoord) {
	cx_lo := floor_div(cc.x * CHUNK_SIZE - RIVER_REACH, RIVER_SRC_CELL)
	cx_hi := floor_div(cc.x * CHUNK_SIZE + CHUNK_SIZE - 1 + RIVER_REACH, RIVER_SRC_CELL)
	cy_lo := floor_div(cc.y * CHUNK_SIZE - RIVER_REACH, RIVER_SRC_CELL)
	cy_hi := floor_div(cc.y * CHUNK_SIZE + CHUNK_SIZE - 1 + RIVER_REACH, RIVER_SRC_CELL)
	for cy in cy_lo ..= cy_hi {
		for cx in cx_lo ..= cx_hi {
			key := ChunkCoord{cx, cy}
			if key in traced_sources {
				continue
			}
			traced_sources[key] = true
			src := source_for_cell(cx, cy)
			if elevation_at(hex_to_world(src, HEX_SIZE, ORIENT)) > RIVER_SOURCE_ELEV {
				trace_river(src)
			}
		}
	}
}


// --- Chunk cache ----------------------------------------------------------
// biome_at does ~17 noise samples per tile, so we memoize results in chunks.
// Each chunk is generated once on first touch and evicted after going unused.

CHUNK_SIZE :: 16
CHUNK_EVICT_AGE :: u64(180) // frames a chunk may go unused before eviction

ChunkCoord :: [2]i32

Chunk :: struct {
	tiles:     [CHUNK_SIZE * CHUNK_SIZE]TILE_TYPE,
	last_used: u64,
}

world_cache: map[ChunkCoord]^Chunk
frame_counter: u64

// Worldgen params last frame; a change invalidates the whole cache.
prev_world_seed: i64
prev_noise_freq: f64

// Floored division/modulo so negative coords map correctly into chunks.
floor_div :: proc(a, b: i32) -> i32 {
	q := a / b
	if a % b != 0 && (a < 0) != (b < 0) {
		q -= 1
	}
	return q
}
floor_mod :: proc(a, b: i32) -> i32 {
	m := a % b
	if m != 0 && (m < 0) != (b < 0) {
		m += b
	}
	return m
}

// Biome for a hex, served from the chunk cache (generating the chunk if needed).
biome_cached :: proc(h: Hex) -> TILE_TYPE {
	cc := ChunkCoord{floor_div(h[0], CHUNK_SIZE), floor_div(h[1], CHUNK_SIZE)}
	chunk := world_cache[cc]
	if chunk == nil {
		chunk = new(Chunk)
		ensure_rivers_near(cc) // make sure rivers crossing this chunk are traced
		base_q := cc.x * CHUNK_SIZE
		base_r := cc.y * CHUNK_SIZE
		for ly in 0 ..< CHUNK_SIZE {
			for lx in 0 ..< CHUNK_SIZE {
				q := base_q + i32(lx)
				r := base_r + i32(ly)
				hh := Hex{q, r, -q - r}
				b := biome_at(hex_to_world(hh, HEX_SIZE, ORIENT))
				// Rivers and lakes turn land into water (not mountains or existing sea).
				if hh in river_tiles || hh in lake_tiles {
					#partial switch b {
					case .DeepOcean, .Ocean, .Mountain:
					// leave as-is
					case:
						b = .Ocean
					}
				}
				chunk.tiles[ly * CHUNK_SIZE + lx] = b
			}
		}
		world_cache[cc] = chunk
	}
	chunk.last_used = frame_counter
	lx := floor_mod(h[0], CHUNK_SIZE)
	ly := floor_mod(h[1], CHUNK_SIZE)
	return chunk.tiles[ly * CHUNK_SIZE + lx]
}

// Drop everything (called when worldgen params change).
world_cache_clear :: proc() {
	for _, c in world_cache {
		free(c)
	}
	clear(&world_cache)
	clear(&river_tiles)
	clear(&lake_tiles)
	clear(&traced_sources)
}

// Free chunks that haven't been touched recently.
world_cache_evict :: proc() {
	stale := make([dynamic]ChunkCoord, context.temp_allocator)
	for cc, c in world_cache {
		if frame_counter - c.last_used > CHUNK_EVICT_AGE {
			append(&stale, cc)
		}
	}
	for cc in stale {
		free(world_cache[cc])
		delete_key(&world_cache, cc)
	}
}
// --------------------------------------------------------------------------


HexBounds :: struct {
	q_min, q_max, r_min, r_max: i32,
}

// Loose axial bounding box of every hex that could touch the viewport.
visible_hex_bounds :: proc(c: k2.Camera, size: f32, orient: Orientation) -> HexBounds {
	ss := k2.get_screen_size()
	corners := [4]Vec2 {
		k2.screen_to_world({0, 0}, c),
		k2.screen_to_world({ss.x, 0}, c),
		k2.screen_to_world({0, ss.y}, c),
		k2.screen_to_world({ss.x, ss.y}, c),
	}
	b := HexBounds{max(i32), min(i32), max(i32), min(i32)}
	for corner in corners {
		h := world_to_hex(corner, size, orient)
		b.q_min = min(b.q_min, h[0]);b.q_max = max(b.q_max, h[0])
		b.r_min = min(b.r_min, h[1]);b.r_max = max(b.r_max, h[1])
	}
	// The sheared grid plus tall sprites mean cover spills past the corner hexes.
	MARGIN :: i32(2)
	b.q_min -= MARGIN;b.q_max += MARGIN
	b.r_min -= MARGIN;b.r_max += MARGIN
	return b
}


main :: proc() {
	init()
	for step() {}
	expedition_shutdown()
	k2.shutdown()
}

// --- Globe mode -----------------------------------------------------------
// When zoomed far out, the flat hex plane is warped into an orthographic
// "planet from orbit" illusion. It is purely cosmetic: an infinite plane can't
// truly wrap into a sphere, so we show a circular cap and fade past the horizon.

GLOBE_START :: f32(0.6) // zoom at which the globe begins forming
GLOBE_FULL :: f32(0.3) // zoom at which it is a full sphere
SPACE_COLOR :: k2.Color{3, 5, 12, 255}
ATMOSPHERE :: k2.Color{40, 90, 140, 255}

// 0 = flat grid, 1 = full globe.
globe_blend :: proc() -> f32 {
	return clamp((GLOBE_START - camera.zoom) / (GLOBE_START - GLOBE_FULL), 0, 1)
}

// On-screen pixel radius of the globe disc.
globe_radius_px :: proc() -> f32 {
	return 0.45 * k2.get_screen_size().y
}

// Project a world point to screen, morphing flat->sphere by blend t in [0,1].
globe_project :: proc(
	world: Vec2,
	t: f32,
) -> (
	screen: Vec2,
	scale: f32,
	shade: f32,
	visible: bool,
) {
	ss := k2.get_screen_size()
	center := ss * 0.5
	d := world - camera.target
	flat_screen := center + d * camera.zoom

	if t <= 0 {
		return flat_screen, camera.zoom, 1, true
	}

	R := globe_radius_px()
	r := math.sqrt_f32(d.x * d.x + d.y * d.y)
	dir := r > 0.0001 ? d / r : Vec2{0, 0}
	theta := r * camera.zoom / R // arc angle from the sub-viewer point

	on_far_side := theta > f32(math.PI) * 0.5
	theta = min(theta, f32(math.PI) * 0.5) // clamp at the horizon

	globe_screen := center + dir * (R * math.sin_f32(theta))
	globe_scale := camera.zoom * math.cos_f32(theta)
	globe_shade := 0.35 + 0.65 * math.cos_f32(theta) // limb darkening

	// Day/night terminator: light the sphere surface by the sun direction.
	st := math.sin_f32(theta)
	n := [3]f32{dir.x * st, dir.y * st, math.cos_f32(theta)}
	ndl := max(0, n.x * sun_dir.x + n.y * sun_dir.y + n.z * sun_dir.z)
	globe_shade *= 0.15 + 0.85 * ndl // ambient + diffuse

	screen = flat_screen + (globe_screen - flat_screen) * t
	scale = camera.zoom + (globe_scale - camera.zoom) * t
	shade = 1 + (globe_shade - 1) * t
	visible = !(on_far_side && t > 0.5)
	return
}

color_lerp :: proc(a, b: k2.Color, t: f32) -> k2.Color {
	lerp_u8 :: proc(x, y: u8, t: f32) -> u8 {
		return u8(f32(x) + (f32(y) - f32(x)) * t)
	}
	return k2.Color {
		lerp_u8(a[0], b[0], t),
		lerp_u8(a[1], b[1], t),
		lerp_u8(a[2], b[2], t),
		lerp_u8(a[3], b[3], t),
	}
}

shade_color :: proc(s: f32) -> k2.Color {
	v := u8(clamp(s, 0, 1) * 255)
	return k2.Color{v, v, v, 255}
}
// --------------------------------------------------------------------------

// --- Day / night ----------------------------------------------------------
DAY_LENGTH :: f32(120) // real seconds per full day/night cycle

// Recomputed each frame in draw().
sun_dir: [3]f32 // globe lighting direction (sub-viewer point is +z)
day_amount: f32 // 0 = night .. 1 = day (flat-mode brightness)
sky_tint: k2.Color
land_tint: k2.Color

smoothstep_f :: proc(e0, e1, x: f32) -> f32 {
	t := clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
}

norm3 :: proc(v: [3]f32) -> [3]f32 {
	l := math.sqrt_f32(v.x * v.x + v.y * v.y + v.z * v.z)
	return l < 1e-6 ? [3]f32{0, 0, 1} : v / l
}

update_daynight :: proc() {
	ft := f32(k2.get_time()) / DAY_LENGTH
	tod := ft - math.floor_f32(ft) // 0..1, 0 = midnight, 0.5 = noon
	a := tod * 2 * f32(math.PI)
	sh := -math.cos_f32(a) // sun height: -1 midnight .. +1 noon

	// Sun sweeps in longitude with a slight northward tilt.
	sun_dir = norm3({math.sin_f32(a), 0.35, -math.cos_f32(a)})

	day_amount = smoothstep_f(-0.15, 0.25, sh)
	horizon := math.exp_f32(-sh * sh * 6) // dawn/dusk glow, peaks at the horizon

	// Sky color: night -> day blue, warm at the horizon.
	sky := color_lerp(k2.Color{20, 24, 48, 255}, k2.LIGHT_BLUE, day_amount)
	sky_tint = color_lerp(sky, k2.Color{240, 140, 80, 255}, horizon * 0.55)

	// Land tint mirrors it but keeps some ambient floor at night.
	land := color_lerp(k2.Color{60, 70, 120, 255}, k2.WHITE, day_amount)
	land_tint = color_lerp(land, k2.Color{255, 170, 110, 255}, horizon * 0.35)
}

draw :: proc() {
	camera.offset = k2.get_screen_size() * 0.5 // keep target centered on resize
	t := globe_blend()
	update_daynight()

	k2.clear(color_lerp(sky_tint, SPACE_COLOR, t))

	b := visible_hex_bounds(camera, HEX_SIZE, ORIENT)

	if t <= 0 {
		// Fast flat path: let the camera transform handle world->screen.
		k2.set_camera(camera)
		origin := Vec2{SPRITE_W * 0.5, SPRITE_H * 0.5}
		for r in b.r_min ..= b.r_max {
			for q in b.q_min ..= b.q_max {
				h := Hex{q, r, -q - r}
				center := hex_to_world(h, HEX_SIZE, ORIENT)
				if in_arena(h) && !is_revealed(h) {
					// Fogged tile: hide true biome.
					k2.draw_circle(center, HEX_SIZE * 0.92, FOG_COLOR, 6)
					if expedition.show_belief {
						bc := belief_overlay_color(h)
						k2.draw_circle(center, HEX_SIZE * 0.7, bc, 6)
					}
				} else {
					k2.draw_texture_rect(hex_tex, tile_rect(biome_cached(h)), center, origin, 0, land_tint)
				}
			}
		}
		expedition_draw_overlays()
		k2.set_camera(nil)
		draw_clouds(1, 1) // drifting cloud shadows on the terrain
	} else {
		// Globe / blended path: project each tile manually in screen space.
		sc := k2.get_screen_size() * 0.5
		R := globe_radius_px()
		k2.draw_circle(sc, R * t * 1.04, ATMOSPHERE, 64) // atmosphere halo
		k2.draw_circle(sc, R * t, k2.DARK_BLUE, 64) // ocean backdrop fills limb gaps
		for r in b.r_min ..= b.r_max {
			for q in b.q_min ..= b.q_max {
				h := Hex{q, r, -q - r}
				center := hex_to_world(h, HEX_SIZE, ORIENT)
				screen, scale, shade, vis := globe_project(center, t)
				if !vis || scale <= 0 do continue
				src := tile_rect(biome_cached(h))
				dst := k2.Rect{screen.x, screen.y, SPRITE_W * scale, SPRITE_H * scale}
				org := Vec2{SPRITE_W * scale * 0.5, SPRITE_H * scale * 0.5}
				k2.draw_texture_fit(hex_tex, src, dst, org, 0, shade_color(shade))
			}
		}
		draw_clouds(0, t)
	}

	draw_hud()
	k2.present()
}

// Animated clouds: mode 0 wraps them onto the globe, mode 1 casts drifting
// shadows on the flat map. Driven by a full-screen quad through the shader.
draw_clouds :: proc(mode, blend: f32) {
	ss := k2.get_screen_size()
	center := ss * 0.5
	seed := f32(u32(world_seed) & 0xffff) / 6553.6 // 0..10, varies per world
	tm := f32(k2.get_time())
	radius := globe_radius_px()
	zoom := camera.zoom
	target := camera.target

	k2.set_shader(cloud_shader)
	set := proc(name: string, v: any) {
		k2.set_shader_constant(cloud_shader, cloud_shader.constant_lookup[name], v)
	}
	set("u_resolution", ss)
	set("u_center", center)
	set("u_radius", radius)
	set("u_time", tm)
	set("u_blend", blend)
	set("u_seed", seed)
	set("u_mode", mode)
	set("u_zoom", zoom)
	set("u_cam_target", target)
	set("u_day", day_amount)
	set("u_sun", sun_dir)

	k2.draw_rect({0, 0, ss.x, ss.y}, k2.YELLOW)
	k2.set_shader(nil)
}

draw_hud :: proc() {
	chunks := len(world_cache)
	hover := world_to_hex(k2.screen_to_world(k2.get_mouse_position(), camera), HEX_SIZE, ORIENT)
	belief_line := ""
	if in_arena(hover) && !is_revealed(hover) {
		b := belief_get(hover)
		belief_line = fmt.tprintf(
			"\nhover fog: %s %.0f%% conf %.0f%%",
			terrain_name(belief_argmax(b)),
			b.p[belief_argmax(b)] * 100,
			b.confidence * 100,
		)
	} else if in_arena(hover) && is_revealed(hover) {
		belief_line = fmt.tprintf("\nhover: %s", terrain_name(terrain_at(hover)))
	}

	mode_line := fmt.tprintf(
		"mode: %s  danger: %.0f  reveals: %v/%v",
		mission_mode_name(expedition.mode),
		expedition.doctrine.ration_danger,
		expedition.reveal_attempts,
		expedition.doctrine.max_reveal_attempts,
	)

	info := fmt.tprintf(
		"WAYFINDER PoC\n%s\n%s\ndays: %v  rations: %.1f\npath: %s\nbelief: %s\nseed: %v  zoom: %.2f  chunks: %v%s\n\n[click] goal  [Space] step  [Enter] play/pause\n[1/2/3] doctrine  [B] belief  [WASD] pan  [R] seed",
		expedition.doctrine.name,
		mode_line,
		expedition.days_elapsed,
		expedition.rations,
		expedition.path.found ? fmt.tprintf("%.1f days", expedition.path.cost) : "none",
		expedition.show_belief ? "ON" : "OFF",
		world_seed,
		camera.zoom,
		chunks,
		belief_line,
	)
	k2.draw_text(info, {9, 9}, 16, k2.BLACK)
	k2.draw_text(info, {8, 8}, 16, k2.WHITE)

	ss := k2.get_screen_size()
	status := expedition_status()
	k2.draw_text(status, {9, ss.y - 27}, 16, k2.BLACK)
	k2.draw_text(status, {8, ss.y - 28}, 16, k2.YELLOW)

	// Decision trace strip (last 4 entries) above status.
	recent := trace_recent(4)
	y := ss.y - 28 - f32(len(recent) + 1) * 18
	k2.draw_text("Trace:", {9, y + 1}, 14, k2.BLACK)
	k2.draw_text("Trace:", {8, y}, 14, k2.LIGHT_GRAY)
	for e, i in recent {
		line := fmt.tprintf("D%v [%s] %s", e.day, mission_mode_name(e.mode), trace_reason(&recent[i]))
		yy := y + f32(i + 1) * 18
		k2.draw_text(line, {9, yy + 1}, 14, k2.BLACK)
		k2.draw_text(line, {8, yy}, 14, k2.Color{200, 220, 180, 255})
	}
}

ZOOM_MIN :: f32(0.25)
ZOOM_MAX :: f32(8)
ZOOM_STEP :: f32(1.1) // multiplier per wheel click

handle_input :: proc() {
	dt := k2.get_frame_time()
	// Pan speed in world units; divide by zoom so it feels constant on screen.
	speed := f32(400) * dt / camera.zoom
	if k2.key_is_held(.W) do camera.target.y -= speed
	if k2.key_is_held(.S) do camera.target.y += speed
	if k2.key_is_held(.A) do camera.target.x -= speed
	if k2.key_is_held(.D) do camera.target.x += speed

	if wheel := k2.get_mouse_wheel_delta(); wheel != 0 {
		mouse := k2.get_mouse_position()
		// World point under the cursor before zooming.
		before := k2.screen_to_world(mouse, camera)

		new_zoom := camera.zoom * math.pow(ZOOM_STEP, wheel)
		camera.zoom = clamp(new_zoom, ZOOM_MIN, ZOOM_MAX)

		// Shift target so that same world point stays under the cursor.
		after := k2.screen_to_world(mouse, camera)
		camera.target += before - after
	}

	// R: roll a new world seed.
	if k2.key_went_down(.R) {
		world_seed = rand.int63()
	}

	// - / = : shrink / grow biome scale (multiplicative while held).
	FREQ_RATE :: f64(1.5) // factor per second
	NOISE_FREQ_MIN :: f64(0.0001)
	NOISE_FREQ_MAX :: f64(0.2)
	if k2.key_is_held(.Minus) {
		noise_freq *= math.pow(FREQ_RATE, f64(dt))
	}
	if k2.key_is_held(.Equal) {
		noise_freq /= math.pow(FREQ_RATE, f64(dt))
	}
	noise_freq = clamp(noise_freq, NOISE_FREQ_MIN, NOISE_FREQ_MAX)

	// Doctrine presets.
	if k2.key_went_down(.N1) {
		expedition_set_doctrine(doctrine_cautious())
	}
	if k2.key_went_down(.N2) {
		expedition_set_doctrine(doctrine_aggressive_surveyor())
	}
	if k2.key_went_down(.N3) {
		expedition_set_doctrine(doctrine_opportunistic_forager())
	}

	// Belief overlay toggle.
	if k2.key_went_down(.B) {
		expedition.show_belief = !expedition.show_belief
	}

	// Single step / play-pause.
	if k2.key_went_down(.Space) {
		expedition.playing = false
		expedition_step()
	}
	if k2.key_went_down(.Enter) {
		expedition.playing = !expedition.playing
		expedition.step_timer = 0
	}

	// Left click: set pathfinding goal.
	if k2.mouse_button_went_down(.Left) && globe_blend() <= 0 {
		goal := world_to_hex(k2.screen_to_world(k2.get_mouse_position(), camera), HEX_SIZE, ORIENT)
		expedition_set_goal(goal)
	}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}
	frame_counter += 1
	handle_input()
	expedition_update(k2.get_frame_time())

	// Worldgen params changed -> the cached tiles are stale.
	if world_seed != prev_world_seed || noise_freq != prev_noise_freq {
		world_cache_clear()
		prev_world_seed = world_seed
		prev_noise_freq = noise_freq
		expedition_reset_world()
	}

	draw()
	world_cache_evict()

	free_all(context.temp_allocator)
	return true
}
