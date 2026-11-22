package fidelity

import "core:encoding/json"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

// Fidelity tests: our `core` against the oracle dump of the original (ADR 0002, docs/specs/phase-2-core.md
// deliverable 2). The oracle directory is `GM_ORACLE_DIR` (the full dump, CI) or the committed sample.

ORACLE_DIR_ENV :: "GM_ORACLE_DIR"
DEFAULT_ORACLE_DIR :: #directory + "/../fixtures/oracle"
DB_PATH :: #directory + "/../../reference/GrappleMap/GrappleMap.txt"

// oracle_dir: `GM_ORACLE_DIR` when set and non-empty, else the committed sample.
oracle_dir :: proc(allocator := context.temp_allocator) -> string {
	dir := os.get_env(ORACLE_DIR_ENV, allocator)
	return dir if dir != "" else DEFAULT_ORACLE_DIR
}

// oracle_path: `<oracle_dir>/<name>`.
oracle_path :: proc(name: string, allocator := context.temp_allocator) -> string {
	return strings.concatenate({oracle_dir(allocator), "/", name}, allocator)
}

db_path :: proc() -> string {
	return DB_PATH
}

// load_db reads the real DB of the submodule. A missing DB fails the test (never a skip, spec deliverable 2).
load_db :: proc(t: ^testing.T, allocator := context.allocator) -> (data: []byte, ok: bool) {
	err: os.Error
	data, err = os.read_entire_file(db_path(), allocator)
	if err != nil {
		testing.expectf(
			t,
			false,
			"missing reference/GrappleMap (%s: %v): run `git submodule update --init`",
			db_path(),
			err,
		)
		return nil, false
	}
	return data, true
}

// read_json reads a whole (small) oracle JSON file into `v` (a pointer); strings and slices go to `allocator`. A missing or
// malformed file fails the test.
read_json :: proc(t: ^testing.T, name: string, v: any, allocator: mem.Allocator) -> bool {
	path := oracle_path(name)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if !testing.expectf(t, err == nil, "cannot read %s: %v", path, err) {
		return false
	}
	jerr := json.unmarshal_any(data, v, allocator = allocator)
	return testing.expectf(t, jerr == nil, "cannot decode %s: %v", path, jerr)
}

// expect_bits: `got` and `want` have the same IEEE-754 bits (ADR 0003: no tolerance unless Ander agrees). The
// message reads "<what> <index>" (e.g. "coordinate, block 12", "joint radius 3").
expect_bits :: proc(
	t: ^testing.T,
	got, want: f64,
	what: string,
	index: int,
	loc := #caller_location,
) -> bool {
	g := transmute(u64)got
	w := transmute(u64)want
	return testing.expectf(
		t,
		g == w,
		"%s %d: got %.17g (0x%016x), want %.17g (0x%016x)",
		what,
		index,
		got,
		g,
		want,
		w,
		loc = loc,
	)
}
