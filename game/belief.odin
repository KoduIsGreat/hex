package game

import k2 "karl2d"

BELIEF_ALPHA :: f32(0.6)
BELIEF_REGIONAL_R :: i32(5)
BELIEF_LOCAL_W :: f32(0.6)
BELIEF_REGIONAL_W :: f32(0.4)

BeliefTile :: struct {
	p:          [TerrainKind]f32,
	confidence: f32,
}

beliefs: map[Hex]BeliefTile

belief_init :: proc() {
	if beliefs == nil {
		beliefs = make(map[Hex]BeliefTile)
	} else {
		clear(&beliefs)
	}
}

belief_shutdown :: proc() {
	delete(beliefs)
	beliefs = {}
}

// Uniform prior for a fogged tile with no nearby evidence: every terrain kind
// equally likely, minimal confidence. Returned by belief_get for tiles outside
// the computed frontier so expected-cost pathing stays sensible.
belief_uniform :: proc() -> BeliefTile {
	b: BeliefTile
	u := f32(1) / f32(TERRAIN_KIND_COUNT)
	for k in TerrainKind {
		b.p[k] = u
	}
	b.confidence = 0.05
	return b
}

belief_get :: proc(h: Hex) -> BeliefTile {
	if b, ok := beliefs[h]; ok {
		return b
	}
	return belief_uniform()
}

normalize_probs :: proc(p: ^[TerrainKind]f32) {
	sum: f32 = 0
	for k in TerrainKind {
		sum += p[k]
	}
	if sum <= 1e-6 {
		// Uniform prior when no evidence.
		u := 1.0 / f32(TERRAIN_KIND_COUNT)
		for k in TerrainKind {
			p[k] = u
		}
		return
	}
	for k in TerrainKind {
		p[k] /= sum
	}
}

// Recompute beliefs for every fogged tile within the regional radius of a
// revealed tile - the explored "frontier". Fogged tiles with no revealed
// evidence nearby fall back to the uniform prior (belief_get), so there's no
// point storing them. This keeps cost proportional to explored area rather than
// world size, which matters now that the world is large. (#10 will make this
// fully incremental via a dirty set seeded by each reveal.)
belief_recompute :: proc() {
	clear(&beliefs)
	R := BELIEF_REGIONAL_R
	for rev in revealed {
		for dq in -R ..= R {
			r1 := max(-R, -dq - R)
			r2 := min(R, -dq + R)
			for dr in r1 ..= r2 {
				h := Hex{rev[0] + dq, rev[1] + dr, -rev[0] - dq - rev[1] - dr}
				if !in_arena(h) || is_revealed(h) || h in beliefs {
					continue
				}
				beliefs[h] = infer_belief(h)
			}
		}
	}
}

infer_belief :: proc(h: Hex) -> BeliefTile {
	local: [TerrainKind]f32
	regional: [TerrainKind]f32
	local_votes: f32 = 0
	regional_weight: f32 = 0
	neighbor_revealed: f32 = 0

	// Local: adjacent revealed tiles.
	for d in HEX_DIRS {
		n := hex_add(h, d)
		if !in_arena(n) || !is_revealed(n) {
			continue
		}
		k := terrain_at(n)
		local[k] += 1
		local_votes += 1
		neighbor_revealed += 1
	}

	// Regional: distance-weighted votes within R.
	R := BELIEF_REGIONAL_R
	for dq in -R ..= R {
		rr1 := max(-R, -dq - R)
		rr2 := min(R, -dq + R)
		for dr in rr1 ..= rr2 {
			if dq == 0 && dr == 0 {
				continue
			}
			n := Hex{h[0] + dq, h[1] + dr, -h[0] - dq - h[1] - dr}
			if !in_arena(n) || !is_revealed(n) {
				continue
			}
			dist := f32(hex_distance(h, n))
			w := 1.0 / (dist * dist)
			k := terrain_at(n)
			regional[k] += w
			regional_weight += w
		}
	}

	normalize_probs(&local)
	normalize_probs(&regional)

	combined: [TerrainKind]f32
	for k in TerrainKind {
		combined[k] = BELIEF_LOCAL_W * local[k] + BELIEF_REGIONAL_W * regional[k]
	}
	normalize_probs(&combined)

	// Confidence from local neighbor density + regional evidence strength.
	local_conf := neighbor_revealed / 6.0
	reg_conf := clamp(regional_weight / 4.0, 0, 1)
	confidence := clamp(0.55 * local_conf + 0.45 * reg_conf, 0.05, 1)

	return BeliefTile{p = combined, confidence = confidence}
}

belief_argmax :: proc(b: BeliefTile) -> TerrainKind {
	best := TerrainKind.Plains
	best_p: f32 = -1
	for k in TerrainKind {
		if b.p[k] > best_p {
			best_p = b.p[k]
			best = k
		}
	}
	return best
}

expected_day_cost :: proc(h: Hex) -> f32 {
	if is_revealed(h) {
		return true_day_cost(h)
	}
	b := belief_get(h)
	cost: f32 = 0
	for k in TerrainKind {
		cost += b.p[k] * base_day_cost(k)
	}
	return cost
}

// Dominant terrain for doctrine rules: true if revealed, else belief argmax.
dominant_terrain :: proc(h: Hex) -> (kind: TerrainKind, confidence: f32) {
	if is_revealed(h) {
		return terrain_at(h), 1
	}
	b := belief_get(h)
	return belief_argmax(b), b.confidence
}

belief_overlay_color :: proc(h: Hex) -> k2.Color {
	b := belief_get(h)
	k := belief_argmax(b)
	c := terrain_color(k)
	a := u8(clamp(b.confidence, 0.15, 1) * BELIEF_ALPHA * 255)
	return {c[0], c[1], c[2], a}
}
