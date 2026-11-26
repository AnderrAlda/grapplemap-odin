package core

import "core:math"

// Time-based playback of the original (docs/original.md §6.4, §6.6): `Playback` (src/playback.hpp:24-60,
// src/playback.cpp:96-176) walks an oriented path by elapsed seconds instead of a fixed frame count. Same operation
// order as the original (ADR 0003 d4), so after the same `progress` calls the state has the original's bits.

// PAUSE_BEFORE and PAUSE_AFTER are `Playback::pause_before`/`pause_after` (src/playback.hpp:27-29), in seconds.
PAUSE_BEFORE :: 0.8
PAUSE_AFTER :: 0.8

// SEGMENTS_PER_SECOND and SEGMENTS_PER_SECOND_DETAILED are the `speed` of `progress` (src/playback.cpp:129-131): a
// normal sequence plays 5 segments per second, a `detailed` one 10.
SEGMENTS_PER_SECOND :: 5
SEGMENTS_PER_SECOND_DETAILED :: 10

// Reoriented_Step is `Reoriented<Reversible<SeqNum>>` (an element of `OrientedPath`, src/paths.hpp): a step and the
// reorientation its stored positions are shown with.
Reoriented_Step :: struct {
	step:          Step,
	reorientation: Position_Reorientation,
}

// connect is `gp_connect(n, s, g)` (src/graph_util.cpp:232-245): the step's own start end (`from(s)`: the edge's
// `to` if `s.reverse`, else its `from`) is tested first, then its exit end (`to(s)`); on the first whose node is
// `n.node`, the reorientation is `compose(inverse(E), n.reorientation)`, `E` that end's stored reorientation. The step
// keeps its direction either way. Neither end on `n.node`, or `seq` out of range, is
// `Graph_Error{.Step_Not_Connected, block = seq}` (the original asserts).
connect :: proc(g: ^Graph, n: Reoriented_Node, s: Step) -> (r: Reoriented_Step, err: Error) {
	if s.seq < 0 || s.seq >= len(g.edges) {
		return {}, Graph_Error{kind = .Step_Not_Connected, line = 0, block = s.seq}
	}
	start, exit := step_ends(g, s)
	e: Position_Reorientation
	if start.node == n.node {
		e = start.reorientation
	} else if exit.node == n.node {
		e = exit.reorientation
	} else {
		return {}, Graph_Error{kind = .Step_Not_Connected, line = 0, block = s.seq}
	}
	return {step = s, reorientation = compose(inverse(e), n.reorientation)}, nil
}

// step_exit is where `r` arrives: the step's exit end's node (`to(s)`) with `compose(X, r.reorientation)`, `X` that
// end's stored reorientation (as `follow`'s `next`, playback.odin).
step_exit :: proc(g: ^Graph, r: Reoriented_Step) -> Reoriented_Node {
	_, exit := step_ends(g, r.step)
	return {node = exit.node, reorientation = compose(exit.reorientation, r.reorientation)}
}

// step_ends is `from(s, g)`, `to(s, g)` for a `Reversible<SeqNum>` (src/locations.hpp:166-178).
@(private = "file")
step_ends :: proc(g: ^Graph, s: Step) -> (start, exit: Reoriented_Node) {
	e := &g.edges[s.seq]
	if s.reverse {
		return e.to, e.from
	}
	return e.from, e.to
}

// Timed_Playback is the original's `Playback` minus its chaser (chaser.odin): the location is step `path[i]`,
// segment `segment` (`positions[segment] → positions[segment + 1]`) at `how_far` ∈ [0, 1], always in stored order (a
// reversed step runs `how_far` down from 1 and `segment` down to 0). `wait` is the pause left (seconds); `at_end`
// holds the end. `loop` (default true, the original) restarts after the end pause; false holds the end forever.
// `path` is borrowed: the caller owns it and keeps it alive; every step comes from `connect` (valid `seq`).
Timed_Playback :: struct {
	path:       []Reoriented_Step,
	i, segment: int,
	how_far:    f64,
	wait:       f64,
	at_end:     bool,
	loop:       bool,
}

// timed_init is the `Playback` constructor (src/playback.cpp:96-100) minus the chaser: `timed_reset`. An empty path
// is `Graph_Error{.Empty_Path}` (the original reads `path.front()`).
timed_init :: proc(
	g: ^Graph,
	path: []Reoriented_Step,
	loop := true,
) -> (
	p: Timed_Playback,
	err: Error,
) {
	if len(path) == 0 {
		return {}, Graph_Error{kind = .Empty_Path, line = 0, block = NO_BLOCK}
	}
	p = {
		path = path,
		loop = loop,
	}
	timed_reset(&p, g)
	return p, nil
}

// timed_reset is `Playback::reset` (src/playback.cpp:102-112): back to the first segment of the first step (its last
// segment at `how_far = 1` if reversed, else segment 0 at 0), no pause, not at the end.
timed_reset :: proc(p: ^Timed_Playback, g: ^Graph) {
	p.i = 0
	start_step(p, g)
	p.wait = 0
	p.at_end = false
}

// start_step puts `segment`/`how_far` at the start of `path[i]` (`first_segment`, src/graph_util.hpp:95-98).
@(private = "file")
start_step :: proc(p: ^Timed_Playback, g: ^Graph) {
	s := p.path[p.i].step
	if s.reverse {
		p.segment, p.how_far = segment_count(g, s.seq) - 1, 1
	} else {
		p.segment, p.how_far = 0, 0
	}
}

@(private = "file")
segment_count :: proc(g: ^Graph, seq: int) -> int {
	n := len(g.edges[seq].sequence.positions) - 1
	assert(n >= 1, "an edge has at least two positions")
	return n
}

// speed is `progress`'s `speed`, in segments per second.
@(private = "file")
speed :: proc(g: ^Graph, seq: int) -> f64 {
	return SEGMENTS_PER_SECOND_DETAILED if g.edges[seq].sequence.detailed else SEGMENTS_PER_SECOND
}

// timed_progress is `Playback::progress(seconds)` (src/playback.cpp:114-176), its tail recursion written as a loop:
// the pause is consumed first; at the end (pause over) it resets and pauses `PAUSE_BEFORE` with `loop`, discarding the
// rest, or holds without it. Forwards `how_far += seconds·speed`; below 1 it stays, else the leftover
// `(how_far − 1) / speed` goes to the next segment (`how_far = 0`) or, past the last one, the step is finished
// (`how_far = 1`). Reversed mirrors it (`how_far −= …`, stays above 0, leftover `−how_far / speed`). A finished last
// step sets `at_end` and `wait = PAUSE_AFTER` (the leftover discarded); another one moves to the next step's start and
// carries the leftover at that step's speed.
timed_progress :: proc(p: ^Timed_Playback, g: ^Graph, seconds: f64) {
	seconds := seconds
	for {
		if p.wait > seconds {
			p.wait -= seconds
			return
		}
		seconds -= p.wait
		p.wait = 0

		if p.at_end {
			if p.loop {
				timed_reset(p, g)
				p.wait = PAUSE_BEFORE
			}
			return
		}

		s := p.path[p.i].step
		v := speed(g, s.seq)
		last := segment_count(g, s.seq) - 1
		finished := false
		if !s.reverse {
			p.how_far += seconds * v
			if p.how_far < 1 {
				return
			}
			seconds = (p.how_far - 1) / v
			if p.segment != last {
				p.segment += 1
				p.how_far = 0
			} else {
				p.how_far = 1
				finished = true
			}
		} else {
			p.how_far -= seconds * v
			if p.how_far > 0 {
				return
			}
			seconds = (-p.how_far) / v
			if p.segment != 0 {
				p.segment -= 1
				p.how_far = 1
			} else {
				p.how_far = 0
				finished = true
			}
		}

		if finished {
			if p.i + 1 == len(p.path) {
				p.at_end = true
				p.wait = PAUSE_AFTER
				return
			}
			p.i += 1
			start_step(p, g)
		}
	}
}

// timed_at is `at(location(), graph)` (src/playback.hpp:44-51, src/graph_util.hpp:260-268): interpolate the stored
// keyframes, **then** reorient: `reorient(path[i].reorientation, between(positions[segment], positions[segment + 1],
// how_far))`.
timed_at :: proc(p: ^Timed_Playback, g: ^Graph) -> Position {
	r := p.path[p.i]
	ps := g.edges[r.step.seq].sequence.positions
	return reorient(r.reorientation, between(ps[p.segment], ps[p.segment + 1], p.how_far))
}

// timed_duration is the playing time of `path` without pauses: Σ segments / speed per step, in path order (§6.6; a
// `f64`, not the original's truncating integer `duration`). An empty path is 0.
timed_duration :: proc(path: []Reoriented_Step, g: ^Graph) -> f64 {
	t: f64 = 0
	for r in path {
		t += step_duration(g, r.step.seq)
	}
	return t
}

@(private = "file")
step_duration :: proc(g: ^Graph, seq: int) -> f64 {
	return f64(segment_count(g, seq)) / speed(g, seq)
}

// timed_elapsed is the playing time up to the current location (the inverse of `timed_seek`, for the scrub bar):
// the durations of the steps before `i`, then `local / speed` with `local = segment + how_far` forwards and
// `(segments − 1 − segment) + (1 − how_far)` reversed. Pauses do not count.
timed_elapsed :: proc(p: ^Timed_Playback, g: ^Graph) -> f64 {
	t: f64 = 0
	for k in 0 ..< p.i {
		t += step_duration(g, p.path[k].step.seq)
	}
	s := p.path[p.i].step
	local: f64
	if s.reverse {
		local = f64(segment_count(g, s.seq) - 1 - p.segment) + (1 - p.how_far)
	} else {
		local = f64(p.segment) + p.how_far
	}
	return t + local / speed(g, s.seq)
}

// timed_seek jumps to playing time `t` (clamped to [0, duration]; no pause, not at the end): the step where `t`
// falls, `local = (t − start)·speed`, `k = min(floor(local), segments − 1)`, `f = min(local − k, 1)`; forwards
// `segment = k`, `how_far = f`; reversed `segment = segments − 1 − k`, `how_far = 1 − f`. `t ≥ duration` is the end
// of the last step (`how_far` 1 forwards, 0 reversed). Not exact for every `t`: `timed_elapsed(seek(t))` can differ
// from `t` by rounding.
timed_seek :: proc(p: ^Timed_Playback, g: ^Graph, t: f64) {
	p.wait = 0
	p.at_end = false
	t := t
	t = max(t, 0)
	start: f64 = 0
	for r, k in p.path {
		d := step_duration(g, r.step.seq)
		if t < start + d {
			p.i = k
			n := segment_count(g, r.step.seq)
			local := (t - start) * speed(g, r.step.seq)
			seg := min(int(math.floor(local)), n - 1)
			f := min(local - f64(seg), 1)
			if r.step.reverse {
				p.segment, p.how_far = n - 1 - seg, 1 - f
			} else {
				p.segment, p.how_far = seg, f
			}
			return
		}
		start += d
	}
	// At or past the end.
	p.i = len(p.path) - 1
	s := p.path[p.i].step
	if s.reverse {
		p.segment, p.how_far = 0, 0
	} else {
		p.segment, p.how_far = segment_count(g, s.seq) - 1, 1
	}
}
