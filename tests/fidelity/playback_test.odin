package fidelity

import "app:core"
import "core:bytes"
import "core:encoding/json"
import "core:log"
import "core:testing"

// `frames` and `smoothen` of `core` (playback.odin) against `playback.ndjson` (tools/oracle/README.md, "Playback"):
// every `transition` line is `frames(g, {Step{seq, false}}, 11)` (caption, `segment_frames_per_pos`, raw frames) and
// then `smoothen` of that step alone, bit for bit; the `chain` line is a 2-step path smoothed in one call, which proves
// the filter state crosses the step boundary. Lines are streamed (389 MB in the full dump). Captions are decoded from
// the `keep_negative_zero` copy of the line: a caption holding a `-0` token would come out changed and fail the
// comparison, never pass it.

@(private = "file")
FRAMES_PER_POS :: 11 // the dumper's, src/makevideo.cpp:34

@(private = "file")
Transition_Line :: struct {
	block:                  int,
	seq:                    int,
	frames_per_pos:         int,
	segment_frames_per_pos: int,
	caption:                string,
	raw:                    []Oracle_Position,
	smooth:                 []Oracle_Position,
}

@(private = "file")
Chain_Line :: struct {
	seqs:                   []int,
	frames_per_pos:         int,
	segment_frames_per_pos: []int,
	captions:               []string,
	raw:                    [][]Oracle_Position,
	smooth:                 [][]Oracle_Position,
}

@(private = "file")
Playback_State :: struct {
	t:           ^testing.T,
	g:           ^core.Graph,
	seqs:        []core.Sequence,
	transitions: int, // transition lines read
	chains:      int, // chain lines read
	compared:    int, // lines that matched
}

@(test)
test_playback_matches_oracle :: proc(t: ^testing.T) {
	seqs, ok := parse_real_db(t)
	if !ok {
		return
	}
	defer core.sequences_destroy(seqs)
	g, gok := shared_graph(t)
	if !gok {
		return
	}

	state := Playback_State {
		t    = t,
		g    = g,
		seqs = seqs,
	}
	path := oracle_path("playback.ndjson")
	lines, _, nerr := ndjson_each(path, &state, check_playback_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(t, state.transitions > 0, "%s: no transition lines", path)
	testing.expect_value(t, state.chains, 1)
	testing.expect_value(t, state.transitions + state.chains, lines)
	testing.expect_value(t, state.compared, lines)
	// Outside the sample (the full dump), every transition has a line.
	if oracle_dir() != DEFAULT_ORACLE_DIR {
		testing.expect_value(t, state.transitions, len(g.edges))
	}
	log.infof("%s: %d transitions and %d chain checked", path, state.transitions, state.chains)
}

@(private = "file")
check_playback_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Playback_State)(ctx)
	if bytes.has_prefix(line, transmute([]byte)string(`{"type":"transition",`)) {
		state.transitions += 1
		ok := check_transition(state, line)
		state.compared += int(ok)
		return ok
	}
	if bytes.has_prefix(line, transmute([]byte)string(`{"type":"chain",`)) {
		state.chains += 1
		ok := check_chain(state, line)
		state.compared += int(ok)
		return ok
	}
	return testing.expectf(
		state.t,
		false,
		"playback.ndjson: unknown line type: %.40s",
		string(line),
	)
}

// edge_of: the edge `seq`, checked against the parsed `block` (same `line_nr`, as compose_test.odin does).
@(private = "file")
edge_of :: proc(state: ^Playback_State, seq, block: int) -> bool {
	t, g := state.t, state.g
	if !testing.expectf(
		t,
		seq >= 0 && seq < len(g.edges) && block >= 0 && block < len(state.seqs),
		"playback: transition %d (block %d) out of range",
		seq,
		block,
	) {
		return false
	}
	return testing.expectf(
		t,
		g.edges[seq].sequence.line_nr == state.seqs[block].line_nr,
		"playback: edge %d has line_nr %d, block %d has %d",
		seq,
		g.edges[seq].sequence.line_nr,
		block,
		state.seqs[block].line_nr,
	)
}

// expect_frames compares one step's frames, count first.
@(private = "file")
expect_frames :: proc(
	t: ^testing.T,
	got: []core.Position,
	want: []Oracle_Position,
	what: string,
	block: int,
) -> bool {
	if !testing.expectf(
		t,
		len(got) == len(want),
		"%s, block %d: %d frames, want %d",
		what,
		block,
		len(got),
		len(want),
	) {
		return false
	}
	for f, i in got {
		if !expect_position(t, f, want[i], what, block, i) {
			return false
		}
	}
	return true
}

@(private = "file")
check_transition :: proc(state: ^Playback_State, line: []byte) -> bool {
	t := state.t
	tl: Transition_Line
	if jerr := json.unmarshal(keep_negative_zero(line), &tl); jerr != nil {
		return testing.expectf(t, false, "playback.ndjson transition: %v", jerr)
	}
	b := tl.block
	edge_of(state, tl.seq, b) or_return
	testing.expect_value(t, tl.frames_per_pos, FRAMES_PER_POS) or_return
	detailed := state.g.edges[tl.seq].sequence.detailed
	testing.expect_value(
		t,
		tl.segment_frames_per_pos,
		FRAMES_PER_POS / (2 if detailed else 1),
	) or_return

	steps, err := core.frames(state.g, {{seq = tl.seq}}, FRAMES_PER_POS)
	if !testing.expectf(t, err == nil && len(steps) == 1, "frames, block %d: %v", b, err) {
		return false
	}
	testing.expectf(
		t,
		steps[0].caption == tl.caption,
		"caption, block %d: %q, want %q",
		b,
		steps[0].caption,
		tl.caption,
	) or_return
	expect_frames(t, steps[0].frames, tl.raw, "raw frame, block", b) or_return
	core.smoothen(steps)
	return expect_frames(t, steps[0].frames, tl.smooth, "smooth frame, block", b)
}

@(private = "file")
check_chain :: proc(state: ^Playback_State, line: []byte) -> bool {
	t := state.t
	cl: Chain_Line
	if jerr := json.unmarshal(keep_negative_zero(line), &cl); jerr != nil {
		return testing.expectf(t, false, "playback.ndjson chain: %v", jerr)
	}
	n := len(cl.seqs)
	if !testing.expectf(
		t,
		n == 2 &&
		len(cl.segment_frames_per_pos) == n &&
		len(cl.captions) == n &&
		len(cl.raw) == n &&
		len(cl.smooth) == n,
		"chain: %d seqs, %d fpp, %d captions, %d raw, %d smooth",
		n,
		len(cl.segment_frames_per_pos),
		len(cl.captions),
		len(cl.raw),
		len(cl.smooth),
	) {
		return false
	}
	testing.expect_value(t, cl.frames_per_pos, FRAMES_PER_POS) or_return
	path := make([]core.Step, n)
	for s, i in cl.seqs {
		if !testing.expectf(t, s >= 0 && s < len(state.g.edges), "chain: seq %d out of range", s) {
			return false
		}
		path[i] = {
			seq = s,
		}
		detailed := state.g.edges[s].sequence.detailed
		testing.expect_value(
			t,
			cl.segment_frames_per_pos[i],
			FRAMES_PER_POS / (2 if detailed else 1),
		) or_return
	}

	steps, err := core.frames(state.g, path, FRAMES_PER_POS)
	if !testing.expectf(t, err == nil && len(steps) == n, "chain frames: %v", err) {
		return false
	}
	for s, i in steps {
		testing.expectf(
			t,
			s.caption == cl.captions[i],
			"chain caption %d: %q, want %q",
			i,
			s.caption,
			cl.captions[i],
		) or_return
		expect_frames(t, s.frames, cl.raw[i], "chain raw frame, step", i) or_return
	}
	core.smoothen(steps) // one call over both steps: the state crosses the boundary
	for s, i in steps {
		expect_frames(t, s.frames, cl.smooth[i], "chain smooth frame, step", i) or_return
	}
	return true
}
