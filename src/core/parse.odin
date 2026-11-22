package core

import "core:mem"

// Sequence is one block of `GrappleMap.txt` (docs/original.md §1.1, `Sequence`, src/graph.hpp).
Sequence :: struct {
	description:   []string, // lines verbatim, first = name; never empty
	positions:     []Position, // ≥ 1; 1 = named position, ≥ 2 = transition (the graph decides)
	line_nr:       int, // 0-based line of the first position line
	detailed:      bool, // `detailed` in properties_in_desc (§1.2)
	bidirectional: bool, // `bidirectional` in properties_in_desc (§1.2)
}

parse_db :: proc(data: []byte, allocator := context.allocator) -> (seqs: []Sequence, err: Error) {
	return nil, nil
}

sequences_destroy :: proc(seqs: []Sequence, allocator := context.allocator) {
}

tags_in_desc :: proc(
	desc: []string,
	allocator := context.allocator,
) -> (
	[]string,
	mem.Allocator_Error,
) {
	return nil, nil
}

properties_in_desc :: proc(
	desc: []string,
	allocator := context.allocator,
) -> (
	[]string,
	mem.Allocator_Error,
) {
	return nil, nil
}
