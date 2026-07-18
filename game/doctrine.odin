package game

EmergencyProtocol :: enum u8 {
	SafeReturn,
	BurnTheBoats,
}

ImpasseMode :: enum u8 {
	StrictDetour,
	SmartReveal,
}

ForageMode :: enum u8 {
	StayCourse,
	ForageOpportunistic,
}

ConfidenceMode :: enum u8 {
	HighOnly,
	Moderate,
	LowAllowed,
}

ProximityRule :: enum u8 {
	Hug,
	Skirt,
	Avoid,
	Ignore,
}

RouteIntent :: enum u8 {
	ReachObjective,
}

BehaviorProfile :: struct {
	rules: [TerrainKind]ProximityRule,
}

Doctrine :: struct {
	intent:              RouteIntent,
	profile:             BehaviorProfile,
	name:                string,
	emergency:           EmergencyProtocol,
	impasse:             ImpasseMode,
	forage:              ForageMode,
	confidence:          ConfidenceMode,
	ration_danger:       f32,
	max_detour:          f32,
	min_confidence:      f32,
	max_reveal_attempts: int,
	reveal_toward_goal:  bool, // Smart Reveal only climbs vantages toward the target
}

doctrine_cautious :: proc() -> Doctrine {
	p: BehaviorProfile
	p.rules[.Plains] = .Hug
	p.rules[.Forest] = .Skirt
	p.rules[.Swamp] = .Avoid
	p.rules[.Hill] = .Ignore
	p.rules[.Mountain] = .Avoid
	p.rules[.Ocean] = .Avoid
	return Doctrine {
		intent              = .ReachObjective,
		profile             = p,
		name                = "Cautious Pathing",
		emergency           = .SafeReturn,
		impasse             = .SmartReveal,
		forage              = .ForageOpportunistic,
		confidence          = .HighOnly,
		ration_danger       = 10,
		max_detour          = 12,
		min_confidence      = 0.55,
		max_reveal_attempts = 3,
	}
}

doctrine_aggressive_surveyor :: proc() -> Doctrine {
	p: BehaviorProfile
	p.rules[.Plains] = .Ignore
	p.rules[.Forest] = .Skirt
	p.rules[.Swamp] = .Skirt
	p.rules[.Hill] = .Hug
	p.rules[.Mountain] = .Hug
	p.rules[.Ocean] = .Avoid
	return Doctrine {
		intent              = .ReachObjective,
		profile             = p,
		name                = "Aggressive Surveyor",
		emergency           = .BurnTheBoats,
		impasse             = .SmartReveal,
		forage              = .StayCourse,
		confidence          = .Moderate,
		ration_danger       = 6,
		max_detour          = 16,
		min_confidence      = 0.35,
		max_reveal_attempts = 5,
		reveal_toward_goal  = true, // survey ahead toward the objective, not behind
	}
}

doctrine_opportunistic_forager :: proc() -> Doctrine {
	p: BehaviorProfile
	p.rules[.Plains] = .Ignore
	p.rules[.Forest] = .Hug
	p.rules[.Swamp] = .Avoid
	p.rules[.Hill] = .Ignore
	p.rules[.Mountain] = .Skirt
	p.rules[.Ocean] = .Avoid
	return Doctrine {
		intent              = .ReachObjective,
		profile             = p,
		name                = "Opportunistic Forager",
		emergency           = .SafeReturn,
		impasse             = .StrictDetour,
		forage              = .ForageOpportunistic,
		confidence          = .Moderate,
		ration_danger       = 12,
		max_detour          = 14,
		min_confidence      = 0.35,
		max_reveal_attempts = 2,
	}
}

// Extra multiplier for fogged tiles below the doctrine confidence floor.
confidence_cost_factor :: proc(to: Hex, doctrine: Doctrine) -> f32 {
	if is_revealed(to) {
		return 1
	}
	if doctrine.confidence == .LowAllowed {
		return 1
	}
	b := belief_get(to)
	if b.confidence >= doctrine.min_confidence {
		return 1
	}
	switch doctrine.confidence {
	case .HighOnly:
		return 4
	case .Moderate:
		return 2
	case .LowAllowed:
		return 1
	}
	return 1
}

// Returns a multiplicative edge-cost modifier for entering `to` from `from`.
proximity_modifier :: proc(from, to: Hex, doctrine: Doctrine) -> f32 {
	to_kind, to_conf := dominant_terrain(to)
	rule := doctrine.profile.rules[to_kind]
	strength := to_conf // scale proximity by belief confidence

	mod: f32 = 1
	switch rule {
	case .Ignore:
		mod = 1
	case .Avoid:
		mod = 1 + strength * 2.0 // up to ×3
	case .Hug:
		mod = 1 - strength * 0.5 // down to ×0.5
	case .Skirt:
		// Prefer being adjacent to this terrain but not deep inside.
		on_terrain := to_kind
		adj_match := false
		deep := true
		for d in HEX_DIRS {
			n := hex_add(to, d)
			if !in_arena(n) {
				continue
			}
			nk, _ := dominant_terrain(n)
			if nk == on_terrain {
				adj_match = true
			} else {
				deep = false
			}
		}
		_ = from
		if deep && adj_match {
			mod = 1 + strength * 0.2 // up to ×1.2 deep inside
		} else if adj_match {
			edge_like := false
			for d in HEX_DIRS {
				n := hex_add(to, d)
				if !in_arena(n) {
					continue
				}
				nk, _ := dominant_terrain(n)
				if nk != on_terrain {
					edge_like = true
					break
				}
			}
			if edge_like {
				mod = 1 - strength * 0.3 // down to ×0.7 on border
			} else {
				mod = 1
			}
		} else {
			mod = 1
		}
	}

	return max(mod, 0.1)
}

edge_cost :: proc(from, to: Hex, doctrine: Doctrine) -> f32 {
	base := expected_day_cost(to)
	return base * proximity_modifier(from, to, doctrine) * confidence_cost_factor(to, doctrine)
}
