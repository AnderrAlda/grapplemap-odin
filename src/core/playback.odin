package core

import "core:mem"
import "core:strings"

// Playback of the original (docs/original.md §6.1-§6.3): `follow` walks one step into frames, `frames` walks a path
// with captions, `smoothen` applies the lag filter. Same operation order as the original (ADR 0003 d4: no FMA, no
// reassociation), so the frames are bit-identical to `frames()`/`smoothen()` (tests/fidelity/playback_test.odin).

// Frame_Step is one entry of the original's `Frames` (`vector<pair<string, vector<Position>>>`, src/paths.hpp:9): the
// caption of a step and its frames.
Frame_Step :: struct {
	caption: string,
	frames:  []Position,
}

// follow is `follow(g, n, s, frames_per_pos)` (src/graph_util.cpp:60-108). The direction is decided by node equality,
// `from` first: forwards if the edge's `from` node is `n.node`, else backwards if its `to` node is (a self-loop is
// walked forwards). `r = compose(inverse(E), n.reorientation)`, `E` the entry end's stored reorientation; for each
// consecutive pair `A`, `B` in walking order and `k = 0 … fpp`, `between(reorient(r, A), reorient(r, B), k / fpp)`:
// the keyframes are reoriented first, then interpolated, and segment boundaries repeat. `fpp = 0` gives
// `0 / 0.0 = NaN`, as the original. `next` is the exit end's node with `compose(X, r)`, `X` its stored reorientation.
// Allocates exactly `segments · (fpp + 1)` positions on `allocator`. A step that does not touch `n.node`, or a `seq`
// out of range (the original indexes out of bounds), is `Graph_Error{.Step_Not_Connected, block = seq}`, allocating
// nothing. The original's `basicallySame` asserts are not ported (compiled out, §1.7).
follow :: proc(
	g: ^Graph,
	n: Reoriented_Node,
	seq: int,
	fpp: int,
	allocator := context.allocator,
) -> (
	out: []Position,
	next: Reoriented_Node,
	err: Error,
) {
	assert(fpp >= 0, "frames per position must not be negative")
	w := enter(g, n, seq) or_return
	out = make([]Position, w.segments * (fpp + 1), allocator) or_return
	fill(w, fpp, out)
	return out, w.next, nil
}

// Walk is one step of `follow` once its direction is known: the keyframes in walking order are
// `positions[segments − s]` backwards, `positions[s]` forwards; `r` reorients them; `next` is where it ends.
@(private = "file")
Walk :: struct {
	positions: []Position,
	segments:  int,
	forwards:  bool,
	r:         Position_Reorientation,
	next:      Reoriented_Node,
}

// enter is the part of `follow` before the frames: the direction (node equality, `from` first), `r` and `next`.
@(private = "file")
enter :: proc(g: ^Graph, n: Reoriented_Node, seq: int) -> (w: Walk, err: Error) {
	if seq < 0 || seq >= len(g.edges) {
		return {}, Graph_Error{kind = .Step_Not_Connected, line = 0, block = seq}
	}
	e := &g.edges[seq]
	entry, exit: Reoriented_Node
	if e.from.node == n.node {
		w.forwards, entry, exit = true, e.from, e.to
	} else if e.to.node == n.node {
		w.forwards, entry, exit = false, e.to, e.from
	} else {
		return {}, Graph_Error{kind = .Step_Not_Connected, line = 0, block = seq}
	}
	w.positions = e.sequence.positions
	assert(len(w.positions) >= 2, "an edge has at least two positions")
	w.segments = len(w.positions) - 1
	w.r = compose(inverse(entry.reorientation), n.reorientation)
	w.next = {exit.node, compose(exit.reorientation, w.r)}
	return w, nil
}

// fill writes the first `len(out)` frames of `w` at `fpp` frames per position (`len(out) ≤ segments · (fpp + 1)`):
// `frames` passes one less, the original's `pop_back`, so it never computes the dropped frame.
@(private = "file")
fill :: proc(w: Walk, fpp: int, out: []Position) {
	assert(len(out) <= w.segments * (fpp + 1))
	ps, last := w.positions, w.segments
	i := 0
	for s in 0 ..< w.segments {
		a, b := ps[s], ps[s + 1]
		if !w.forwards {
			a, b = ps[last - s], ps[last - s - 1]
		}
		ra, rb := reorient(w.r, a), reorient(w.r, b)
		for k in 0 ..= fpp {
			if i == len(out) {
				return
			}
			out[i] = between(ra, rb, f64(k) / f64(fpp))
			i += 1
		}
	}
}

// frames is `frames(g, path, frames_per_pos)` (src/paths.cpp:23-52). Starts at `from(path[0])`: the first edge's own
// endpoint (`to` if `reverse`, else `from`) with its stored reorientation (src/locations.hpp:166-172). Each step is
// `follow(g, n, step.seq, fpp / (detailed ? 2 : 1))` (integer division; `step.reverse` only picks the start node, the
// direction is `follow`'s), minus its last frame (`pop_back`). The caption is the edge's first description line, or,
// when that is exactly `...` and the stored `to` node (whatever the direction) is named, that node's first line;
// then every literal `\n` (backslash, `n`) becomes a space. An empty path gives `nil`. Every caption and frame list is
// a fresh allocation on `allocator`, nothing else is allocated (no temp): free the result with `frames_destroy`. On
// error nothing is left allocated.
frames :: proc(
	g: ^Graph,
	path: []Step,
	fpp: int,
	allocator := context.allocator,
) -> (
	out: []Frame_Step,
	err: Error,
) {
	assert(fpp >= 0, "frames per position must not be negative")
	if len(path) == 0 {
		return nil, nil
	}
	for step in path {
		if step.seq < 0 || step.seq >= len(g.edges) {
			return nil, Graph_Error{kind = .Step_Not_Connected, line = 0, block = step.seq}
		}
	}
	first := &g.edges[path[0].seq]
	n := first.to if path[0].reverse else first.from

	out = make([]Frame_Step, len(path), allocator) or_return
	if err = walk(g, path, n, fpp, out, allocator); err != nil {
		frames_destroy(out, allocator)
		return nil, err
	}
	return out, nil
}

// walk fills `out` (one entry per step of `path`, starting at `n`) for `frames`; on error, what it filled is left for
// the caller to free.
@(private = "file")
walk :: proc(
	g: ^Graph,
	path: []Step,
	n: Reoriented_Node,
	fpp: int,
	out: []Frame_Step,
	allocator: mem.Allocator,
) -> Error {
	n := n
	for step, i in path {
		div := 2 if g.edges[step.seq].sequence.detailed else 1
		step_fpp := fpp / div
		w := enter(g, n, step.seq) or_return
		// `follow` minus its last frame (`pop_back`): exactly what is kept is allocated.
		out[i].frames = make([]Position, w.segments * (step_fpp + 1) - 1, allocator) or_return
		fill(w, step_fpp, out[i].frames)
		out[i].caption = caption(g, step.seq, allocator) or_return
		n = w.next
	}
	return nil
}

// frames_destroy frees a result of `frames` (`allocator` is the one given to it).
frames_destroy :: proc(steps: []Frame_Step, allocator := context.allocator) {
	for s in steps {
		delete(s.caption, allocator)
		delete(s.frames, allocator)
	}
	delete(steps, allocator)
}

// caption is the lambda `d` of `frames` (src/paths.cpp:27-34), always a fresh string on `allocator`. Public for the
// HUD; a `seq` out of range is `Graph_Error{.Step_Not_Connected, block = seq}`, allocating nothing.
caption :: proc(g: ^Graph, seq: int, allocator := context.allocator) -> (s: string, err: Error) {
	if seq < 0 || seq >= len(g.edges) {
		return "", Graph_Error{kind = .Step_Not_Connected, line = 0, block = seq}
	}
	e := &g.edges[seq]
	assert(len(e.sequence.description) > 0, "a sequence has a description")
	desc := e.sequence.description[0]
	to_desc := g.nodes[e.to.node].description
	if desc == "..." && len(to_desc) > 0 {
		desc = to_desc[0]
	}
	if !strings.contains(desc, `\n`) {
		return strings.clone(desc, allocator) or_return, nil
	}
	// `replace_all` reports a failed allocation only as `was_allocation = false` (and an empty string).
	replaced, was_allocation := strings.replace_all(desc, `\n`, " ", allocator)
	if !was_allocation {
		return "", mem.Allocator_Error.Out_Of_Memory
	}
	return replaced, nil
}

// SMOOTHEN_LAG_MAX and SMOOTHEN_LAG_BASE are the constants of `smoothen` (src/paths.cpp:16):
// `lag = min(0.83, 0.6 + y)`.
@(private = "file")
SMOOTHEN_LAG_MAX :: 0.83
@(private = "file")
SMOOTHEN_LAG_BASE :: 0.6

// smoothen is `smoothen(Frames)` (src/paths.cpp:8-21), in place (the original filters a copy: clone the frames first
// to keep the raw ones). One pass over every frame of every step, the state crossing step boundaries: starting from
// the first frame of the first step, per frame, player and joint, `lag = 0.6 + y` if that is below 0.83, else 0.83
// (`std::min(0.83, x)`: a NaN gives 0.83; written out to mirror it, although Odin's `min` also gives 0.83), and
// `p = last = last·lag + p·(1 − lag)` per component. The first frame is computed too, not copied (it can move by
// 1 ulp, §6.3). If there is no step or the first step has no frame, nothing happens (the original reads
// `f[0].second[0]`: UB); later empty steps are skipped.
smoothen :: proc(steps: []Frame_Step) {
	if len(steps) == 0 || len(steps[0].frames) == 0 {
		return
	}
	last := steps[0].frames[0]
	for s in steps {
		for &p in s.frames {
			for pl in 0 ..< PLAYER_COUNT {
				for j in Joint {
					x := SMOOTHEN_LAG_BASE + p[pl][j].y
					lag := x if x < SMOOTHEN_LAG_MAX else SMOOTHEN_LAG_MAX
					one_minus := 1 - lag
					last[pl][j] = last[pl][j] * lag + p[pl][j] * one_minus
					p[pl][j] = last[pl][j]
				}
			}
		}
	}
}
