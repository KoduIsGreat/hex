package game
import "core:math"
import k2 "karl2d"

// Cube coordinates: h[0]=q, h[1]=r, h[2]=s, with the invariant q + r + s == 0.
Hex :: [3]i32
Vec2 :: k2.Vec2


Orientation :: enum {
	PointyTop,
	FlatTop,
}

hex_sub :: proc(a, b: Hex) -> Hex {
	return Hex{a[0] - b[0], a[1] - b[1], a[2] - b[2]}
}

hex_add :: proc(a, b: Hex) -> Hex {
	return Hex{a[0] + b[0], a[1] + b[1], a[2] + b[2]}
}

// Hex grid distance between two cube coords.
hex_distance :: proc(a, b: Hex) -> i32 {
	return (abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])) / 2
}

// The six cube-coordinate neighbor offsets.
HEX_DIRS :: [6]Hex {
	{+1, -1, 0},
	{+1, 0, -1},
	{0, +1, -1},
	{-1, +1, 0},
	{-1, 0, +1},
	{0, -1, +1},
}

SQRT3 :: 1.7320508075688772935274463415059


// Pixel/world point -> hex coord.
world_to_hex :: proc(p: Vec2, size: f32, orient: Orientation) -> Hex {
	fq, fr: f32
	switch orient {
	case .PointyTop:
		fq = (SQRT3 / 3 * p.x - 1.0 / 3 * p.y) / size
		fr = (2.0 / 3 * p.y) / size
	case .FlatTop:
		fq = (2.0 / 3 * p.x) / size
		fr = (-1.0 / 3 * p.x + SQRT3 / 3 * p.y) / size
	}
	return axial_round(fq, fr)
}

// Round fractional axial coords to the nearest hex via cube rounding.
axial_round :: proc(q, r: f32) -> Hex {
	s := -q - r // cube constraint: q + r + s == 0

	rq := math.round_f32(q)
	rr := math.round_f32(r)
	rs := math.round_f32(s)

	dq := abs(rq - q)
	dr := abs(rr - r)
	ds := abs(rs - s)

	// Whichever component drifted most gets recomputed from the other two,
	// preserving q + r + s == 0.
	if dq > dr && dq > ds {
		rq = -rr - rs
	} else if dr > ds {
		rr = -rq - rs
	} else {
		rs = -rq - rr
	}

	return Hex{i32(rq), i32(rr), i32(rs)}
}

// Hex coord -> pixel/world center.
hex_to_world :: proc(h: Hex, size: f32, orient: Orientation) -> Vec2 {
	q := f32(h[0])
	r := f32(h[1])
	switch orient {
	case .PointyTop:
		return Vec2{size * (SQRT3 * q + SQRT3 / 2 * r), size * (3.0 / 2 * r)}
	case .FlatTop:
		return Vec2{size * (3.0 / 2 * q), size * (SQRT3 / 2 * q + SQRT3 * r)}
	}
	return {}
}
