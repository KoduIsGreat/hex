#+build !js
package game

// Native file I/O for save/load. Split from the web build because core:os
// compile-errors on wasm (mirrors karl2d's file_system split).

import "core:os"

save_read :: proc(path: string) -> ([]u8, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	return data, err == nil
}

save_write :: proc(path: string, data: []u8) -> bool {
	return os.write_entire_file(path, data) == nil
}
