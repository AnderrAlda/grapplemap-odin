package fidelity

import "app:core"
import "core:encoding/json"
import "core:testing"

// Body tables of `core` (types.odin) against `body.json` (`jointDefs`, `limbs()`, `playerDefs` of the original).
// Not compared: joint names (`core` has no name table), `players[].code` and the `draw` block (rendering
// constants of the original's player drawer, not part of `core`).

@(private = "file")
Body :: struct {
	joints:   []struct {
		index:     int,
		radius:    f64,
		draggable: bool,
		mirror:    int,
	},
	segments: []struct {
		ends:       [2]int,
		length:     f64,
		mid_radius: Maybe(f64),
		visible:    bool,
	},
	players:  []struct {
		color: [3]f64,
	},
}

// json.unmarshal must round `%.17g` correctly for bit comparisons (strconv.parse_f64).
@(test)
test_json_decodes_17g_doubles_exactly :: proc(t: ^testing.T) {
	v: struct {
		a: f64,
		b: f64,
	}
	err := json.unmarshal_string(`{"a":0.025000000000000001,"b":0.14999999999999999}`, &v)
	testing.expect_value(t, err, nil)
	expect_bits(t, v.a, 0.025, "%.17g value", 1)
	expect_bits(t, v.b, 0.15, "%.17g value", 2)
}

@(test)
test_body_tables_match_oracle :: proc(t: ^testing.T) {
	body: Body
	if !read_json(t, "body.json", &body, context.temp_allocator) {
		return
	}

	if testing.expect_value(t, len(body.joints), core.JOINT_COUNT) {
		for jr, k in body.joints {
			testing.expect_value(t, jr.index, k)
			j := core.Joint(k)
			def := core.JOINT_DEFS[j]
			expect_bits(t, def.radius, jr.radius, "joint radius", k)
			testing.expectf(
				t,
				def.draggable == jr.draggable,
				"joint %v draggable: got %v, want %v",
				j,
				def.draggable,
				jr.draggable,
			)
			testing.expectf(
				t,
				int(def.mirror) == jr.mirror,
				"joint %v mirror: got %v, want %d",
				j,
				def.mirror,
				jr.mirror,
			)
		}
	}

	if testing.expect_value(t, len(body.segments), len(core.SEGMENTS)) {
		for sr, k in body.segments {
			seg := core.SEGMENTS[k]
			testing.expectf(
				t,
				int(seg.ends[0]) == sr.ends[0] && int(seg.ends[1]) == sr.ends[1],
				"segment %d ends: got %v, want %v",
				k,
				seg.ends,
				sr.ends,
			)
			expect_bits(t, seg.length, sr.length, "segment length", k)
			got_mid, got_has := seg.mid_radius.?
			want_mid, want_has := sr.mid_radius.?
			if testing.expectf(
				   t,
				   got_has == want_has,
				   "segment %d mid_radius: got %v, want %v",
				   k,
				   seg.mid_radius,
				   sr.mid_radius,
			   ) &&
			   got_has {
				expect_bits(t, got_mid, want_mid, "segment mid_radius", k)
			}
			testing.expectf(
				t,
				seg.visible == sr.visible,
				"segment %d visible: got %v, want %v",
				k,
				seg.visible,
				sr.visible,
			)
		}
	}

	if testing.expect_value(t, len(body.players), core.PLAYER_COUNT) {
		for pr, p in body.players {
			for c in 0 ..< 3 {
				expect_bits(t, core.PLAYER_COLORS[p][c], pr.color[c], "player color", p)
			}
		}
	}
}
