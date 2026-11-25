package fidelity

import "app:core"
import "core:crypto/legacy/md5"
import "core:encoding/hex"
import "core:os"
import "core:testing"

// Export of `core` (export_txt.odin) against the original's `save(loadGraph(DB), ostream)` (tools/oracle/README.md):
// `meta.json` `save_md5`/`save_equals_db` always, and `save.txt` byte for byte when the oracle dir has it (full
// dump only).

@(private = "file")
Save_Meta :: struct {
	save_md5:       Maybe(string), // null when only meta.json was written
	save_equals_db: bool,
}

// expect_same_bytes: on the first difference, the offset and the 1-based line, not the whole buffer.
@(private = "file")
expect_same_bytes :: proc(
	t: ^testing.T,
	got, want: []byte,
	what: string,
	loc := #caller_location,
) {
	n := min(len(got), len(want))
	line := 1
	for i in 0 ..< n {
		if got[i] != want[i] {
			testing.expectf(
				t,
				false,
				"%s: first difference at byte %d (line %d): got 0x%02x, want 0x%02x",
				what,
				i,
				line,
				got[i],
				want[i],
				loc = loc,
			)
			return
		}
		if got[i] == '\n' {
			line += 1
		}
	}
	testing.expectf(
		t,
		len(got) == len(want),
		"%s: lengths differ (got %d, want %d bytes; equal up to line %d)",
		what,
		len(got),
		len(want),
		line,
		loc = loc,
	)
}

@(test)
test_export_matches_oracle :: proc(t: ^testing.T) {
	g, ok := shared_graph(t)
	if !ok {
		return
	}
	out, err := core.export_txt(g)
	if !testing.expectf(t, err == nil, "export_txt: %v", err) {
		return
	}
	defer delete(out)

	meta: Save_Meta
	if !read_json(t, "meta.json", &meta, context.temp_allocator) {
		return
	}
	want_md5, has_md5 := meta.save_md5.?
	if testing.expect(t, has_md5, "meta.json: save_md5 is null") {
		ctx: md5.Context
		md5.init(&ctx)
		md5.update(&ctx, out)
		digest: [md5.DIGEST_SIZE]byte
		md5.final(&ctx, digest[:])
		got_md5 := string(hex.encode(digest[:], context.temp_allocator))
		testing.expectf(
			t,
			got_md5 == want_md5,
			"md5 %s != meta.json save_md5 %s",
			got_md5,
			want_md5,
		)
	}
	if meta.save_equals_db {
		if db, dok := load_db(t); dok {
			defer delete(db)
			expect_same_bytes(t, out, db, "export vs DB")
		}
	}
	// save.txt: full dump only (tools/oracle/README.md); absent from the committed sample.
	if save, serr := os.read_entire_file(oracle_path("save.txt"), context.allocator); serr == nil {
		defer delete(save)
		expect_same_bytes(t, out, save, "export vs save.txt")
	}
}
