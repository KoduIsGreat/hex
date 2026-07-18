#+build js
package game

// Web builds have no filesystem: saving/loading is unsupported (the world is
// still fully playable, just not persisted across sessions).

save_read :: proc(path: string) -> ([]u8, bool) {
	return nil, false
}

save_write :: proc(path: string, data: []u8) -> bool {
	return false
}
