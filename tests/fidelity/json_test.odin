package fidelity

import "app:core"
import "core:encoding/json"
import "core:log"
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
