package game

import "core:container/priority_queue"
import "core:slice"

PathResult :: struct {
	path:  [dynamic]Hex,
	cost:  f32,
	found: bool,
}

path_clear :: proc(res: ^PathResult) {
	clear(&res.path)
	res.cost = 0
	res.found = false
}

path_destroy :: proc(res: ^PathResult) {
	delete(res.path)
	res^ = {}
}

AStarNode :: struct {
	hex:  Hex,
	f:    f32,
	g:    f32,
}

astar_less :: proc(a, b: AStarNode) -> bool {
	return a.f < b.f
}

// A* from start to goal over the bounded arena.
pathfind_astar :: proc(start, goal: Hex, doctrine: Doctrine, allocator := context.allocator) -> PathResult {
	res: PathResult
	res.path = make([dynamic]Hex, allocator)

	if !in_arena(start) || !in_arena(goal) {
		return res
	}
	// Don't path onto known impassable revealed tiles as the goal.
	if is_revealed(goal) && !is_passable(terrain_at(goal)) {
		return res
	}
	if start == goal {
		append(&res.path, start)
		res.found = true
		return res
	}

	came_from := make(map[Hex]Hex, allocator)
	defer delete(came_from)
	g_score := make(map[Hex]f32, allocator)
	defer delete(g_score)

	open: priority_queue.Priority_Queue(AStarNode)
	priority_queue.init(&open, astar_less, priority_queue.default_swap_proc(AStarNode), 256, allocator)
	defer priority_queue.destroy(&open)

	g_score[start] = 0
	h0 := f32(hex_distance(start, goal))
	priority_queue.push(&open, AStarNode{hex = start, g = 0, f = h0})

	closed := make(map[Hex]bool, allocator)
	defer delete(closed)

	MAX_ITERS :: 20000
	iters := 0

	for priority_queue.len(open) > 0 {
		iters += 1
		if iters > MAX_ITERS {
			break
		}
		cur := priority_queue.pop(&open)
		if cur.hex in closed {
			continue
		}
		closed[cur.hex] = true

		if cur.hex == goal {
			// Reconstruct path.
			path_rev := make([dynamic]Hex, context.temp_allocator)
			n := goal
			for {
				append(&path_rev, n)
				if n == start {
					break
				}
				prev, ok := came_from[n]
				if !ok {
					return res
				}
				n = prev
			}
			slice.reverse(path_rev[:])
			for h in path_rev {
				append(&res.path, h)
			}
			res.cost = g_score[goal]
			res.found = true
			return res
		}

		for d in HEX_DIRS {
			nb := hex_add(cur.hex, d)
			if !in_arena(nb) || nb in closed {
				continue
			}
			// Hard-block revealed impassable tiles.
			if is_revealed(nb) && !is_passable(terrain_at(nb)) {
				continue
			}

			tentative := g_score[cur.hex] + edge_cost(cur.hex, nb, doctrine)
			old, has := g_score[nb]
			if has && tentative >= old {
				continue
			}
			came_from[nb] = cur.hex
			g_score[nb] = tentative
			f := tentative + f32(hex_distance(nb, goal))
			priority_queue.push(&open, AStarNode{hex = nb, g = tentative, f = f})
		}
	}

	return res
}
