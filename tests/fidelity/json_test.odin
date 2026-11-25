package fidelity

import "app:core"
import "core:crypto/legacy/md5"
import "core:encoding/hex"
import "core:encoding/json"
import "core:log"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

// JSON writer of `core` (json.odin) on the whole DB: counts from `meta.json`, ids = block numbers (the DB is in
// writer order, ADR 0005), valid JSON per `core:encoding/json` (a syntax check; `core` never uses it).

@(private = "file")
Json_Meta :: struct {
	counts: struct {
		named_positions: int,
		transitions:     int,
	},
}

@(private = "file")
Json_Doc :: struct {
	schema_version: int,
	next_id:        int,
	positions:      []struct {
		id: int,
	},
	transitions:    []struct {
		id: int,
	},
}

@(test)
test_export_json_db :: proc(t: ^testing.T) {
	g, ok := shared_graph(t)
	if !ok {
		return
	}
	start := time.now()
	out, err := core.export_json(g)
	elapsed := time.since(start)
	if !testing.expectf(t, err == nil, "export_json: %v", err) {
		return
	}
	defer delete(out)
	log.infof("export_json: %d bytes in %v", len(out), elapsed)

	meta: Json_Meta
	if !read_json(t, "meta.json", &meta, context.temp_allocator) {
		return
	}
	c := meta.counts
	testing.expect(t, c.named_positions > 0 && c.transitions > 0, "meta.json: counts missing")
	if !testing.expect(t, json.is_valid(out, .JSON), "output is not valid JSON") {
		return
	}
	doc: Json_Doc
	if uerr := json.unmarshal(out, &doc, .JSON, context.temp_allocator);
	   !testing.expectf(t, uerr == nil, "unmarshal: %v", uerr) {
		return
	}
	testing.expect_value(t, doc.schema_version, 1)
	testing.expect_value(t, len(doc.positions), c.named_positions)
	testing.expect_value(t, len(doc.transitions), c.transitions)
	testing.expect_value(t, doc.next_id, c.named_positions + c.transitions + 1)
	// Writer order: positions are blocks 1…P, then transitions P+1….
	for p, i in doc.positions {
		if p.id != i + 1 {
			testing.expectf(t, false, "position %d has id %d", i, p.id)
			return
		}
	}
	for e, i in doc.transitions {
		if e.id != c.named_positions + i + 1 {
			testing.expectf(t, false, "transition %d has id %d", i, e.id)
			return
		}
	}
	testing.expect(t, strings.has_suffix(string(out), "]\n}\n"), "ending")
}

// JSON reader (json_read.odin) on the whole DB: `txt → JSON → txt` is `save(loadGraph(DB))` byte for byte
// (`save_md5`, the DB when `save_equals_db`, `save.txt` in the full dump), and `JSON → JSON` is the identity.
@(test)
test_json_round_trip_db :: proc(t: ^testing.T) {
	g, ok := shared_graph(t)
	if !ok {
		return
	}
	j1, err := core.export_json(g)
	if !testing.expectf(t, err == nil, "export_json: %v", err) {
		return
	}
	defer delete(j1)

	start := time.now()
	h, lerr := core.load_graph_json(j1)
	elapsed := time.since(start)
	if !testing.expectf(t, lerr == nil, "load_graph_json: %v", lerr) {
		return
	}
	defer core.graph_destroy(&h)
	log.infof("load_graph_json: %d bytes in %v", len(j1), elapsed)

	testing.expect_value(t, len(h.nodes), len(g.nodes))
	testing.expect_value(t, h.named_count, g.named_count)
	testing.expect_value(t, len(h.edges), len(g.edges))
	testing.expect_value(t, h.next_id, g.next_id)
	if len(h.edges) == len(g.edges) {
		for e, i in g.edges {
			if h.edges[i].from.node != e.from.node || h.edges[i].to.node != e.to.node {
				testing.expectf(t, false, "edge %d: from/to differ", i)
				break
			}
		}
	}

	txt, terr := core.export_txt(&h)
	if !testing.expectf(t, terr == nil, "export_txt: %v", terr) {
		return
	}
	defer delete(txt)
	meta: Save_Meta
	if !read_json(t, "meta.json", &meta, context.temp_allocator) {
		return
	}
	if want_md5, has := meta.save_md5.?; testing.expect(t, has, "meta.json: save_md5 is null") {
		ctx: md5.Context
		md5.init(&ctx)
		md5.update(&ctx, txt)
		digest: [md5.DIGEST_SIZE]byte
		md5.final(&ctx, digest[:])
		got := string(hex.encode(digest[:], context.temp_allocator))
		testing.expectf(t, got == want_md5, "md5 %s != meta.json save_md5 %s", got, want_md5)
	}
	if meta.save_equals_db {
		if db, dok := load_db(t); dok {
			defer delete(db)
			expect_same_bytes(t, txt, db, "txt → JSON → txt vs DB")
		}
	}
	if save, serr := os.read_entire_file(oracle_path("save.txt"), context.allocator); serr == nil {
		defer delete(save)
		expect_same_bytes(t, txt, save, "txt → JSON → txt vs save.txt")
	}

	j2, jerr := core.export_json(&h)
	if !testing.expectf(t, jerr == nil, "export_json (reloaded): %v", jerr) {
		return
	}
	defer delete(j2)
	expect_same_bytes(t, j2, j1, "JSON → JSON")
}
