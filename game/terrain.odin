package game

import k2 "karl2d"

// Logical terrain kinds used by belief, doctrine, and pathfinding.
// Atlas TILE_TYPEs collapse into this smaller design set.
TerrainKind :: enum u8 {
	Plains,
	Forest,
	Swamp,
	Hill,
	Mountain,
	Ocean,
}

TERRAIN_KIND_COUNT :: len(TerrainKind)

// Large but finite penalty so A* can still explore around believed mountains/ocean.
IMPASSABLE_PENALTY :: f32(20)

tile_to_terrain :: proc(t: TILE_TYPE) -> TerrainKind {
	#partial switch t {
	case .Ocean, .DeepOcean, .Ice, .Port, .Port2, .Lighthouse:
		return .Ocean
	case .Mountain:
		return .Mountain
	case .RockyHills, .RockyUplands, .SnowRocky, .Mesa, .DesertRocky, .SandRocky:
		return .Hill
	case .Swamp:
		return .Swamp
	case .LightForest, .DenseForest, .Jungle, .SnowForest, .SnowDense, .SnowPines:
		return .Forest
	case:
		// Grass, Plains, Savanna, Sand, Dunes, Snow, settlements, caves, ruins, oasis, etc.
		return .Plains
	}
}

terrain_at :: proc(h: Hex) -> TerrainKind {
	return tile_to_terrain(world_tile(h))
}

base_day_cost :: proc(k: TerrainKind) -> f32 {
	switch k {
	case .Plains:
		return 1
	case .Forest:
		return 2
	case .Swamp:
		return 3
	case .Hill:
		return 2
	case .Mountain:
		return IMPASSABLE_PENALTY
	case .Ocean:
		return IMPASSABLE_PENALTY
	}
	return 1
}

vision_radius :: proc(k: TerrainKind) -> i32 {
	switch k {
	case .Plains, .Forest, .Swamp, .Ocean:
		return 1
	case .Hill:
		return 2
	case .Mountain:
		return 3
	}
	return 1
}

is_passable :: proc(k: TerrainKind) -> bool {
	return k != .Mountain && k != .Ocean
}

// Cost used when the true terrain is known (revealed).
true_day_cost :: proc(h: Hex) -> f32 {
	return base_day_cost(terrain_at(h))
}

terrain_color :: proc(k: TerrainKind) -> k2.Color {
	switch k {
	case .Plains:
		return {140, 180, 90, 255}
	case .Forest:
		return {40, 110, 50, 255}
	case .Swamp:
		return {70, 100, 70, 255}
	case .Hill:
		return {150, 120, 80, 255}
	case .Mountain:
		return {160, 160, 170, 255}
	case .Ocean:
		return {40, 80, 160, 255}
	}
	return {128, 128, 128, 255}
}

terrain_name :: proc(k: TerrainKind) -> string {
	switch k {
	case .Plains:
		return "Plains"
	case .Forest:
		return "Forest"
	case .Swamp:
		return "Swamp"
	case .Hill:
		return "Hill"
	case .Mountain:
		return "Mountain"
	case .Ocean:
		return "Ocean"
	}
	return "?"
}
