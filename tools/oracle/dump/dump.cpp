// Oracle dumper (#34): loads GrappleMap.txt with the original loader and writes the files of
// docs/specs/phase-1-original-research.md ("Dump format") to --out. Linked against the original's
// `common` objects (reference/GrappleMap/src/SConstruct:33); nothing of the original is modified.
//
// Usage: grapplemap-dump --db FILE --index FILE --out DIR [--versions FILE] [--commit SHA] [--sample TSV]
//   --index: the .index written by grapplemap-indexer on a copy of the DB (only read, never used to load).
//   --sample: tools/oracle/sample.tsv (#35); the same files, filtered to the listed blocks (see Sample).
//
// Files (fixed order, no timestamps): meta.json, sequences.ndjson, graph.ndjson, ops.ndjson, between.ndjson,
// compose.ndjson, playback.ndjson, body.json, spring.ndjson, inventory.ndjson, and save.txt (full dump only).
#include "json.hpp"

#include "graph_util.hpp"
#include "md5.hpp"
#include "metadata.hpp"
#include "paths.hpp"
#include "persistence.hpp"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <sstream>

namespace {

using namespace GrappleMap;
using dump::Json;

char const DUMPER_VERSION[] = "4";

// frames-per-pos of frames() (default of src/makevideo.cpp:34); halved for `detailed` by integer division
// (src/paths.cpp:42: 11 / 2 = 5).
unsigned const FRAMES_PER_POS = 11;

// Values of s for between(a, b, s) over every consecutive pair.
double const BETWEEN_S[] = {0.25, 0.5, 0.75};
double const BETWEEN_S_SAMPLE = 0.5; // the s every sampled transition keeps

struct Args
{
	string db, index, out, versions, commit, sample;
};

[[noreturn]] void usage()
{
	std::cerr << "usage: grapplemap-dump --db FILE --index FILE --out DIR [--versions FILE] [--commit SHA] [--sample TSV]\n";
	std::exit(2);
}

Args parse_args(int argc, char const * const * argv)
{
	Args a;
	for (int i = 1; i != argc; ++i)
	{
		string const k = argv[i];
		if (i + 1 == argc) usage();
		string const v = argv[++i];
		if (k == "--db") a.db = v;
		else if (k == "--index") a.index = v;
		else if (k == "--out") a.out = v;
		else if (k == "--versions") a.versions = v;
		else if (k == "--commit") a.commit = v;
		else if (k == "--sample") a.sample = v;
		else usage();
	}
	if (a.db.empty() || a.index.empty() || a.out.empty()) usage();
	return a;
}

string read_file(string const & path)
{
	std::ifstream f(path, std::ios::binary);
	if (!f) throw std::runtime_error(path + ": cannot open");
	return string(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
}

void write_file(string const & path, string const & content)
{
	std::ofstream f(path, std::ios::binary);
	f << content;
	if (!f) throw std::runtime_error(path + ": cannot write");
}

vector<string> split_lines(string const & s)
{
	vector<string> v;
	std::istringstream iss(s);
	string line;
	while (std::getline(iss, line)) v.push_back(line);
	return v;
}

// The full dump is ~0.5 GB, so no file is held in memory (save.txt, ~2.7 MB, is the one exception): each one is streamed record by record to
// "<name>.tmp" and only renamed to its final name once every file is complete (meta.json last). A failure
// therefore never leaves a partial dump: the temporaries are removed and only meta.json, with the error, is written.
class Staged_Files
{
	string dir_;
	vector<string> names_;
	bool committed_ = false;

	string tmp(string const & name) const { return dir_ + "/" + name + ".tmp"; }

public:
	explicit Staged_Files(string dir) : dir_(std::move(dir)) {}
	Staged_Files(Staged_Files const &) = delete;
	Staged_Files & operator=(Staged_Files const &) = delete;

	template<typename F>
	void write(string const & name, F f)
	{
		names_.push_back(name);
		std::ofstream o(tmp(name), std::ios::binary);
		if (!o) throw std::runtime_error(tmp(name) + ": cannot open");
		f(o);
		o.close();
		if (!o) throw std::runtime_error(tmp(name) + ": cannot write");
	}

	// If a rename fails, the files already renamed are removed too, so only fail()'s meta.json remains.
	void commit()
	{
		for (size_t i = 0; i != names_.size(); ++i)
			if (std::rename(tmp(names_[i]).c_str(), (dir_ + "/" + names_[i]).c_str()) != 0)
			{
				for (size_t k = 0; k != i; ++k) std::remove((dir_ + "/" + names_[k]).c_str());
				throw std::runtime_error(dir_ + "/" + names_[i] + ": cannot rename");
			}
		committed_ = true;
	}

	~Staged_Files()
	{
		if (!committed_) foreach (n : names_) std::remove(tmp(n).c_str());
	}
};

struct Index
{
	string md5;
	vector<pair<unsigned, unsigned>> pairs;
};

// Format written by writeIndex (src/persistence.cpp:178-184): "<md5>\n" then "from to " per sequence.
Index read_index(string const & path)
{
	std::istringstream f(read_file(path));
	Index ix;
	std::getline(f, ix.md5);
	unsigned from, to;
	while (f >> from >> to) ix.pairs.emplace_back(from, to);
	return ix;
}

int const Q_MAX = 61 * 62 + 61; // largest 2-digit base62 value (src/persistence.cpp:33-61)

// Inverse of decodePosition (src/persistence.cpp:33-61): x = q/1000 - off. Exact or it throws.
int quantize(double const x, double const off)
{
	long const q = std::lround((x + off) * 1000);
	if (q < 0 || q > Q_MAX || double(q) / 1000 - off != x)
	{
		char buf[64];
		std::snprintf(buf, sizeof buf, "coordinate not on the base62 grid: %.17g", x);
		throw std::runtime_error(buf);
	}
	return int(q);
}

void position_q(Json & j, Position const & p)
{
	j.begin_array();
	foreach (pl : playerNums())
	{
		j.begin_array();
		foreach (jt : joints)
		{
			V3 const v = p[pl][jt];
			j.begin_array().integer(quantize(v.x, 2)).integer(quantize(v.y, 0)).integer(quantize(v.z, 2)).end_array();
		}
		j.end_array();
	}
	j.end_array();
}

void v3(Json & j, V3 const v) { j.begin_array().num(v.x).num(v.y).num(v.z).end_array(); }

// A computed position as doubles: [player][joint] = [x, y, z].
void position_d(Json & j, Position const & p)
{
	j.begin_array();
	foreach (pl : playerNums())
	{
		j.begin_array();
		foreach (jt : joints) v3(j, p[pl][jt]);
		j.end_array();
	}
	j.end_array();
}

void positions_d(Json & j, vector<Position> const & v)
{
	j.begin_array();
	foreach (p : v) position_d(j, p);
	j.end_array();
}

void reorientation(Json & j, PositionReorientation const & r)
{
	j.begin_object();
	j.key("translation"); v3(j, r.reorientation.offset);
	j.key("angle").num(r.reorientation.angle);
	j.key("swap").boolean(r.swap_players);
	j.key("mirror").boolean(r.mirror);
	j.end_object();
}

vector<string> set_to_vector(set<string> const & s) { return vector<string>(s.begin(), s.end()); }

vector<string> lines_with_prefix(vector<string> const & desc, std::initializer_list<char const *> prefixes)
{
	vector<string> r;
	foreach (line : desc)
		foreach (p : prefixes)
			if (line.compare(0, std::strlen(p), p) == 0) { r.push_back(line); break; }
	return r;
}

// A block of GrappleMap.txt: a named position (graph node) or a transition (graph edge), in file order.
struct Block
{
	unsigned line_nr;
	bool is_node;
	size_t index; // NodeNum or SeqNum
};

vector<Block> blocks_in_file_order(Graph const & g)
{
	// Nodes and edges each keep file order (src/persistence.cpp:160-166); merge them by line number.
	vector<Block> v;
	foreach (n : nodenums(g))
		if (g[n].line_nr) v.push_back({*g[n].line_nr, true, size_t(n.index)});
	foreach (s : seqnums(g)) v.push_back({*g[s].line_nr, false, s.index});
	std::stable_sort(v.begin(), v.end(), [](Block const & a, Block const & b) { return a.line_nr < b.line_nr; });
	for (size_t i = 1; i < v.size(); ++i)
		if (v[i].line_nr == v[i - 1].line_nr)
			throw std::runtime_error("two blocks at line " + std::to_string(v[i].line_nr));
	return v;
}

// --sample: the blocks listed in sample.tsv, and the subset of each file the spec gives for them
// (docs/specs/phase-1-original-research.md, "Representative sample"). Every dump_* function takes a
// `Sample const *` and filters by block index (nullptr: the full dump), so the sample and the full dump share one
// code path.
struct Sample
{
	vector<char> in;       // listed in sample.tsv
	vector<char> all_s;    // between: also s = 0.25 and 0.75 (first BETWEEN_ALL_S transitions)
	vector<char> playback; // the PLAYBACK_SHORT shortest non-bidirectional transitions and the shortest bidirectional
	vector<char> spring;   // SPRING_POSITIONS positions: those listed under `named` first, in block order
};

size_t const BETWEEN_ALL_S = 10, PLAYBACK_SHORT = 2, SPRING_POSITIONS = 10;

bool keep(Sample const * s, size_t const b) { return !s || s->in[b]; }

// The one position of a transition that ops.ndjson keeps in the sample, and the one pair (its first index) that
// between.ndjson keeps: the middle ones.
size_t sample_pos(size_t const n) { return n / 2; }
size_t sample_pair(size_t const n) { return (n - 2) / 2; }

void dump_sequences(std::ostream & out, Graph const & g, vector<Block> const & blocks, Sample const * smp)
{
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (!keep(smp, b)) continue;
		auto const & blk = blocks[b];
		vector<string> const & desc = blk.is_node ? g[NodeNum{uint16_t(blk.index)}].description
		                                          : g[SeqNum{blk.index}].description;
		auto const props = properties_in_desc(desc);

		j.begin_object();
		j.key("index").integer(long(b));
		j.key("kind").str(blk.is_node ? "position" : "transition");
		j.key("line_nr").integer(blk.line_nr);
		j.key("description").strings(desc);
		j.key("tags").strings(set_to_vector(tags_in_desc(desc)));
		j.key("properties").strings(set_to_vector(props));
		j.key("refs").strings(lines_with_prefix(desc, {"ref:"}));
		j.key("notes").strings(lines_with_prefix(desc, {"note:", "todo:"}));
		j.key("detailed").boolean(props.count("detailed") != 0);
		j.key("bidirectional").boolean(props.count("bidirectional") != 0);
		j.key("positions_q").begin_array();
		if (blk.is_node) position_q(j, g[NodeNum{uint16_t(blk.index)}].position);
		else foreach (p : g[SeqNum{blk.index}].positions) position_q(j, p);
		j.end_array();
		j.end_object();
		out << j.take();
	}
}

// In the sample: the listed transitions, and the listed nodes plus the endpoints of the listed transitions.
void dump_graph(std::ostream & out, Graph const & g, vector<Block> const & blocks, Index const & ix, Sample const * smp)
{
	vector<long> node_block(g.num_nodes(), -1), seq_block(g.num_sequences(), -1);
	for (size_t b = 0; b != blocks.size(); ++b)
		(blocks[b].is_node ? node_block : seq_block)[blocks[b].index] = long(b);
	vector<char> node_kept(g.num_nodes(), !smp);
	foreach (n : nodenums(g))
		if (node_block[n.index] >= 0 && keep(smp, size_t(node_block[n.index]))) node_kept[n.index] = true;
	foreach (s : seqnums(g))
		if (keep(smp, size_t(seq_block[s.index]))) node_kept[g[s].from->index] = node_kept[g[s].to->index] = true;

	Json j;
	foreach (n : nodenums(g))
	{
		if (!node_kept[n.index]) continue;
		j.begin_object();
		j.key("type").str("node");
		j.key("index").integer(n.index);
		j.key("block");
		if (node_block[n.index] < 0) j.null(); else j.integer(node_block[n.index]);
		j.key("description").strings(g[n].description);
		j.key("tags").strings(set_to_vector(tags_in_desc(g[n].description)));
		j.key("position_q"); position_q(j, g[n].position);
		j.end_object();
		out << j.take();
	}
	foreach (s : seqnums(g))
	{
		if (!keep(smp, size_t(seq_block[s.index]))) continue;
		auto const & e = g[s];
		j.begin_object();
		j.key("type").str("transition");
		j.key("index").integer(s.index);
		j.key("block").integer(seq_block[s.index]);
		j.key("from").integer(e.from->index);
		j.key("to").integer(e.to->index);
		j.key("reorientation_from"); reorientation(j, e.from.reorientation);
		j.key("reorientation_to"); reorientation(j, e.to.reorientation);
		j.end_object();
		out << j.take();
	}
	j.begin_object();
	j.key("type").str("index");
	j.key("md5").str(ix.md5);
	j.key("pairs").begin_array();
	foreach (p : ix.pairs) j.begin_array().integer(p.first).integer(p.second).end_array();
	j.end_array();
	j.end_object();
	out << j.take();
}

// Calls f(pos, position) for every position of a block: pos 0 for a named position, the sequence for a transition.
template<typename F>
void each_position(Graph const & g, Block const & blk, F f)
{
	if (blk.is_node) f(size_t(0), g[NodeNum{uint16_t(blk.index)}].position);
	else
	{
		auto const & ps = g[SeqNum{blk.index}].positions;
		for (size_t k = 0; k != ps.size(); ++k) f(k, ps[k]);
	}
}

// src/positions.hpp:37,68,132-184; src/positions.cpp:261-291.
// In the sample: one position per transition (sample_pos) and every named position.
void dump_ops(std::ostream & out, Graph const & g, vector<Block> const & blocks, Sample const * smp)
{
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (!keep(smp, b)) continue;
		size_t const n = blocks[b].is_node ? 1 : g[SeqNum{blocks[b].index}].positions.size();
		each_position(g, blocks[b], [&](size_t const pos, Position const & p)
			{
				if (smp && pos != sample_pos(n) && !blocks[b].is_node) return;
				Position swapped = p;
				swap_players(swapped); // in place in the original
				V2 const h = heading(p);

				j.begin_object();
				j.key("block").integer(long(b));
				j.key("pos").integer(long(pos));
				j.key("mirror"); position_d(j, mirror(p));
				j.key("swap_players"); position_d(j, swapped);
				j.key("orient_canonically_with_mirror"); position_d(j, orient_canonically_with_mirror(p));
				j.key("orient_canonically_without_mirror"); position_d(j, orient_canonically_without_mirror(p));
				j.key("heading").begin_array().num(h.x).num(h.y).end_array();
				j.key("center"); v3(j, center(p));
				j.end_object();
				out << j.take();
			});
	}
}

// between(a, b, s) (src/positions.hpp:42) for every consecutive pair of every transition; pos is a's index.
// In the sample: the middle pair (sample_pair) of each transition at BETWEEN_S_SAMPLE, and at every s for `all_s`.
void dump_between(std::ostream & out, Graph const & g, vector<Block> const & blocks, Sample const * smp)
{
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (blocks[b].is_node || !keep(smp, b)) continue;
		auto const & ps = g[SeqNum{blocks[b].index}].positions;
		for (size_t k = 0; k + 1 < ps.size(); ++k)
			for (double const s : BETWEEN_S)
			{
				if (smp && (k != sample_pair(ps.size()) || (s != BETWEEN_S_SAMPLE && !smp->all_s[b]))) continue;
				j.begin_object();
				j.key("block").integer(long(b));
				j.key("seq").integer(long(blocks[b].index));
				j.key("pos").integer(long(k));
				j.key("s").num(s);
				j.key("position"); position_d(j, between(ps[k], ps[k + 1], s));
				j.end_object();
				out << j.take();
			}
	}
}

// inverse and compose (src/positions.cpp:97-128) on the endpoint reorientations of every transition, in file order;
// compose_inverse_from_to is the form follow() uses (docs/original.md §6.2). In the sample: the listed transitions.
void dump_compose(std::ostream & out, Graph const & g, vector<Block> const & blocks, Sample const * smp)
{
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (blocks[b].is_node || !keep(smp, b)) continue;
		auto const & e = g[SeqNum{blocks[b].index}];
		PositionReorientation const & from = e.from.reorientation, & to = e.to.reorientation;
		j.begin_object();
		j.key("block").integer(long(b));
		j.key("seq").integer(long(blocks[b].index));
		j.key("inverse_from"); reorientation(j, inverse(from));
		j.key("inverse_to"); reorientation(j, inverse(to));
		j.key("compose_from_to"); reorientation(j, compose(from, to));
		j.key("compose_inverse_from_to"); reorientation(j, compose(inverse(from), to));
		j.end_object();
		out << j.take();
	}
}

void frames_d(Json & j, Frames const & f, size_t const step) { positions_d(j, f.at(step).second); }

// frames() (src/paths.cpp:23-52, one Frames entry per step, the last frame of each step dropped) raw and after
// smoothen() (src/paths.cpp:8-21). Each transition is played alone, forwards, and smoothed alone: smoothing per
// transition is the dumper's choice (the original's callers smooth a whole script, src/makevideo.cpp:93,105), so a
// "chain" record follows with the first pair a -> b (index order, b starts at a's end node) smoothed in one call.
// In the sample: the `playback` transitions, and as chain the pair of listed transitions with the fewest positions
// (ties in index order). That chain line is the one sample line that is not a line of the full dump.
void dump_playback(std::ostream & out, Graph const & g, vector<Block> const & blocks, Sample const * smp)
{
	vector<long> seq_block(g.num_sequences(), -1);
	for (size_t b = 0; b != blocks.size(); ++b)
		if (!blocks[b].is_node) seq_block[blocks[b].index] = long(b);

	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (blocks[b].is_node || (smp && !smp->playback[b])) continue;
		SeqNum const s{blocks[b].index};
		Frames const raw = frames(g, Path{Step{s, false}}, FRAMES_PER_POS);
		Frames const smooth = smoothen(raw);

		j.begin_object();
		j.key("type").str("transition");
		j.key("block").integer(long(b));
		j.key("seq").integer(long(s.index));
		j.key("frames_per_pos").integer(FRAMES_PER_POS);
		j.key("segment_frames_per_pos").integer(FRAMES_PER_POS / (g[s].detailed ? 2 : 1));
		j.key("caption").str(raw.at(0).first);
		j.key("raw"); frames_d(j, raw, 0);
		j.key("smooth"); frames_d(j, smooth, 0);
		j.end_object();
		out << j.take();
	}

	optional<pair<SeqNum, SeqNum>> chain;
	size_t chain_positions = 0;
	foreach (a : seqnums(g))
	{
		if (!keep(smp, size_t(seq_block[a.index]))) continue;
		foreach (c : seqnums(g))
			if (keep(smp, size_t(seq_block[c.index])) && *g[c].from == *g[a].to)
			{
				size_t const n = g[a].positions.size() + g[c].positions.size();
				if (!chain || n < chain_positions) { chain = std::make_pair(a, c); chain_positions = n; }
				if (!smp) break; // full dump: the first pair
			}
		if (chain && !smp) break;
	}
	if (!chain) return;

	vector<Path> const script{Path{Step{chain->first, false}, Step{chain->second, false}}};
	Frames const raw = frames(g, script, FRAMES_PER_POS); // paths.cpp:54
	Frames const smooth = smoothen(raw);

	j.begin_object();
	j.key("type").str("chain");
	j.key("seqs").begin_array().integer(long(chain->first.index)).integer(long(chain->second.index)).end_array();
	j.key("frames_per_pos").integer(FRAMES_PER_POS);
	j.key("segment_frames_per_pos").begin_array();
	for (SeqNum const s : {chain->first, chain->second}) j.integer(FRAMES_PER_POS / (g[s].detailed ? 2 : 1));
	j.end_array();
	j.key("captions").begin_array().str(raw.at(0).first).str(raw.at(1).first).end_array();
	j.key("raw").begin_array(); frames_d(j, raw, 0); frames_d(j, raw, 1); j.end_array();
	j.key("smooth").begin_array(); frames_d(j, smooth, 0); frames_d(j, smooth, 1); j.end_array();
	j.end_object();
	out << j.take();
}

// spring(Position&) (src/positions.cpp:183-194, apply_limits then spring per player, no fixed joint) on a copy of
// every named position, in block order.
// In the sample: the `spring` positions.
void dump_spring(std::ostream & out, Graph const & g, vector<Block> const & blocks, Sample const * smp)
{
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (!blocks[b].is_node || (smp && !smp->spring[b])) continue;
		NodeNum const n{uint16_t(blocks[b].index)};
		Position p = g[n].position;
		spring(p);

		j.begin_object();
		j.key("block").integer(long(b));
		j.key("node").integer(n.index);
		j.key("position"); position_d(j, p);
		j.end_object();
		out << j.take();
	}
}

// Inventory (#35): the closed list of classes of docs/specs/phase-1-original-research.md ("Representative
// sample"), in output order. `normal` is a transition in no structural class (STRUCTURAL below); the text classes
// (duplicate_description, description_*, has_ref, has_note) do not exclude it: 96% of blocks have one of them.
char const * const CLASSES[] = {"normal", "named", "bidirectional", "detailed", "long", "endpoint_mirror",
	"endpoint_swap", "endpoint_mirror_swap", "duplicate_description", "edge_coordinate", "description_newline",
	"description_utf8", "description_quote", "has_ref", "has_note", "error_or_unmatched"};
size_t const NUM_CLASSES = sizeof CLASSES / sizeof *CLASSES;
enum Class_Id : unsigned
{
	C_NORMAL, C_NAMED, C_BIDIRECTIONAL, C_DETAILED, C_LONG, C_ENDPOINT_MIRROR, C_ENDPOINT_SWAP,
	C_ENDPOINT_MIRROR_SWAP, C_DUPLICATE_DESCRIPTION, C_EDGE_COORDINATE, C_DESCRIPTION_NEWLINE, C_DESCRIPTION_UTF8,
	C_DESCRIPTION_QUOTE, C_HAS_REF, C_HAS_NOTE, C_ERROR_OR_UNMATCHED
};
static_assert(NUM_CLASSES == C_ERROR_OR_UNMATCHED + 1 && NUM_CLASSES <= 32, "CLASSES and Class_Id disagree");

unsigned const STRUCTURAL = 1u << C_BIDIRECTIONAL | 1u << C_DETAILED | 1u << C_LONG | 1u << C_ENDPOINT_MIRROR
	| 1u << C_ENDPOINT_SWAP | 1u << C_ENDPOINT_MIRROR_SWAP | 1u << C_EDGE_COORDINATE | 1u << C_ERROR_OR_UNMATCHED;

size_t const LONG_LENGTH = 15; // spec: "length >= 15"
// Tag families, first match in table order wins; a block whose tags match none is "other". A transition's tags
// are the original's is_tagged() (src/metadata.hpp:32-37): its own, plus every tag that both endpoints have.
struct Family
{
	char const * name;
	std::initializer_list<char const *> tags;
};
Family const FAMILIES[] = {
	{"leg_locks", {"heel_hook", "knee_bar", "toehold", "ashi_waza", "ashi", "50_50", "slx"}},
	{"back", {"back", "seatbelt", "rear_naked_choke", "crab_ride"}},
	{"mount", {"mount", "s_mount", "three_quarter_mount", "top_mounted"}},
	{"side_control", {"side_control", "side_ctrl", "judo_side", "twister_side", "north_south", "knee_on_belly"}},
	{"turtle", {"turtle"}},
	{"guard", {"guard", "full_guard", "closed_guard", "half_guard", "butterfly", "engaged_butterfly",
		"reverse_butterfly", "rubber_guard", "lockdown", "quarter_guard", "deep_half", "z_guard", "x_guard",
		"spider_guard", "three_quarter_guard", "reverse_half", "knee_shield", "inverted_guard", "guard_pull",
		"guard_jump"}},
	{"standing", {"standing", "single_leg_takedown", "double_leg_takedown", "takedown", "collar_tie", "ankle_pick",
		"throw", "te_waza", "koshi_waza", "sutemi_waza", "sacrifice_throw", "inside_trip"}},
};

char const * family_of(set<string> const & tags)
{
	foreach (f : FAMILIES)
		foreach (t : f.tags)
			if (tags.count(t)) return f.name;
	return "other";
}

// spec: 2 / 3-5 / 6-10 / >10 positions.
char const * length_bucket(size_t const n) { return n <= 2 ? "2" : n <= 5 ? "3-5" : n <= 10 ? "6-10" : ">10"; }

struct Block_Info
{
	size_t length;
	char const * family;
	unsigned classes; // bit set of Class_Id
};

vector<string> const & description(Graph const & g, Block const & blk)
{
	return blk.is_node ? g[NodeNum{uint16_t(blk.index)}].description : g[SeqNum{blk.index}].description;
}

bool has_edge_coordinate(Position const & p)
{
	foreach (pl : playerNums())
		foreach (jt : joints)
		{
			V3 const v = p[pl][jt];
			for (int const q : {quantize(v.x, 2), quantize(v.y, 0), quantize(v.z, 2)})
				if (q == 0 || q == Q_MAX) return true;
		}
	return false;
}

unsigned endpoint_class(PositionReorientation const & r)
{
	if (r.mirror && r.swap_players) return 1u << C_ENDPOINT_MIRROR_SWAP;
	if (r.mirror) return 1u << C_ENDPOINT_MIRROR;
	if (r.swap_players) return 1u << C_ENDPOINT_SWAP;
	return 0;
}

vector<Block_Info> inventory(Graph const & g, vector<Block> const & blocks)
{
	// duplicate_description: the name the original looks a block up by equals another block's of the same kind:
	// the first description line with a literal \n replaced by a space, compared among transitions
	// (step_by_desc, src/metadata.cpp:66-69) or among named positions (node_by_desc, src/metadata.cpp:81-89).
	auto const lookup_name = [&](Block const & blk) {
		return std::make_pair(blk.is_node, replace_all(description(g, blk).front(), "\\n", " "));
	};
	std::map<pair<bool, string>, size_t> names;
	foreach (blk : blocks)
		if (!description(g, blk).empty()) ++names[lookup_name(blk)];

	vector<Block_Info> v;
	foreach (blk : blocks)
	{
		auto const & desc = description(g, blk);
		auto const props = properties_in_desc(desc);
		set<string> tags = tags_in_desc(desc);
		unsigned c = 0;
		Block_Info info{1, nullptr, 0};

		if (blk.is_node)
		{
			c |= 1u << C_NAMED;
			if (has_edge_coordinate(g[NodeNum{uint16_t(blk.index)}].position)) c |= 1u << C_EDGE_COORDINATE;
		}
		else
		{
			auto const & e = g[SeqNum{blk.index}];
			info.length = e.positions.size();
			foreach (t : tags_in_desc(g[*e.from].description))
				if (tags_in_desc(g[*e.to].description).count(t)) tags.insert(t);
			if (props.count("bidirectional")) c |= 1u << C_BIDIRECTIONAL;
			if (props.count("detailed")) c |= 1u << C_DETAILED;
			if (info.length >= LONG_LENGTH) c |= 1u << C_LONG;
			c |= endpoint_class(e.from.reorientation) | endpoint_class(e.to.reorientation);
			foreach (p : e.positions)
				if (has_edge_coordinate(p)) { c |= 1u << C_EDGE_COORDINATE; break; }
			// An endpoint that matches no named position becomes an anonymous node (src/graph.cpp:235-240).
			if (!g[*e.from].line_nr || !g[*e.to].line_nr) c |= 1u << C_ERROR_OR_UNMATCHED;
		}
		if (!desc.empty() && names.at(lookup_name(blk)) > 1) c |= 1u << C_DUPLICATE_DESCRIPTION;
		foreach (line : desc)
		{
			if (line.find("\\n") != string::npos) c |= 1u << C_DESCRIPTION_NEWLINE;
			if (line.find('"') != string::npos) c |= 1u << C_DESCRIPTION_QUOTE;
			foreach (ch : line)
				if (static_cast<unsigned char>(ch) >= 0x80) c |= 1u << C_DESCRIPTION_UTF8;
		}
		if (!lines_with_prefix(desc, {"ref:"}).empty()) c |= 1u << C_HAS_REF;
		if (!lines_with_prefix(desc, {"note:", "todo:"}).empty()) c |= 1u << C_HAS_NOTE;
		if (!blk.is_node && (c & STRUCTURAL) == 0) c |= 1u << C_NORMAL;

		info.family = family_of(tags);
		info.classes = c;
		v.push_back(info);
	}
	return v;
}

void dump_inventory(std::ostream & out, vector<Block> const & blocks, vector<Block_Info> const & inv, Sample const * smp)
{
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (!keep(smp, b)) continue;
		j.begin_object();
		j.key("block").integer(long(b));
		j.key("kind").str(blocks[b].is_node ? "position" : "transition");
		j.key("length").integer(long(inv[b].length));
		j.key("family").str(inv[b].family);
		j.key("length_bucket");
		if (blocks[b].is_node) j.null(); else j.str(length_bucket(inv[b].length));
		j.key("classes").begin_array();
		for (size_t k = 0; k != NUM_CLASSES; ++k)
			if (inv[b].classes & (1u << k)) j.str(CLASSES[k]);
		j.end_array();
		j.end_object();
		out << j.take();
	}
}

vector<string> split_tabs(string const & line)
{
	vector<string> v(1);
	foreach (ch : line)
		if (ch == '\t') v.emplace_back(); else v.back() += ch;
	return v;
}

// sample.tsv: a header "index<TAB>class<TAB>reason", then one row per (block, class), `reason` non-empty. The
// dumper fails if a row names a block outside the class it is listed under, or if a class of CLASSES has no row.
// A class with no block in the whole DB is listed with index "-": the dumper checks it really is empty.
Sample read_sample(string const & path, vector<Block> const & blocks, vector<Block_Info> const & inv)
{
	auto const lines = split_lines(read_file(path));
	if (lines.empty() || lines[0] != "index\tclass\treason") throw std::runtime_error("sample.tsv: bad header");
	Sample s;
	s.in.assign(blocks.size(), false);
	vector<size_t> rows(NUM_CLASSES, 0);
	vector<char> named_row(blocks.size(), false);
	std::set<pair<string, string>> seen;
	for (size_t i = 1; i != lines.size(); ++i)
	{
		string const where = "sample.tsv:" + std::to_string(i + 1) + ": ";
		auto const f = split_tabs(lines[i]);
		if (f.size() != 3 || f[0].empty() || f[2].empty()) throw std::runtime_error(where + "expected index, class, reason");
		size_t k = 0;
		while (k != NUM_CLASSES && f[1] != CLASSES[k]) ++k;
		if (k == NUM_CLASSES) throw std::runtime_error(where + "unknown class " + f[1]);
		if (!seen.insert({f[0], f[1]}).second) throw std::runtime_error(where + "duplicate row");
		++rows[k];
		if (f[0] == "-")
		{
			foreach (info : inv)
				if (info.classes & (1u << k)) throw std::runtime_error(where + "class " + f[1] + " is not empty");
			continue;
		}
		if (f[0].find_first_not_of("0123456789") != string::npos || f[0].size() > 9 || (f[0].size() > 1 && f[0][0] == '0'))
			throw std::runtime_error(where + "bad index " + f[0]);
		size_t const b = std::stoul(f[0]);
		if (b >= blocks.size()) throw std::runtime_error(where + "no block " + f[0]);
		if (!(inv[b].classes & (1u << k))) throw std::runtime_error(where + "block " + f[0] + " is not in class " + f[1]);
		s.in[b] = true;
		if (k == C_NAMED) named_row[b] = true;
	}
	string missing;
	for (size_t k = 0; k != NUM_CLASSES; ++k)
		if (rows[k] == 0) missing += string(missing.empty() ? "" : " ") + CLASSES[k];
	if (!missing.empty()) throw std::runtime_error("sample.tsv: no row for class(es): " + missing);

	// Subsets of the listed blocks, in block order (ties of length broken by block order too).
	s.all_s = s.playback = s.spring = vector<char>(blocks.size(), false);
	size_t n_all_s = 0, n_spring = 0;
	vector<size_t> plain, bidi;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
		if (!s.in[b]) continue;
		if (blocks[b].is_node) continue;
		if (n_all_s != BETWEEN_ALL_S) { s.all_s[b] = true; ++n_all_s; }
		(inv[b].classes & (1u << C_BIDIRECTIONAL) ? bidi : plain).push_back(b);
	}
	auto const shorter = [&](size_t x, size_t y) { return inv[x].length < inv[y].length; };
	std::stable_sort(plain.begin(), plain.end(), shorter);
	std::stable_sort(bidi.begin(), bidi.end(), shorter);
	for (size_t i = 0; i != plain.size() && i != PLAYBACK_SHORT; ++i) s.playback[plain[i]] = true;
	if (!bidi.empty()) s.playback[bidi[0]] = true;
	for (bool const named_first : {true, false})
		for (size_t b = 0; b != blocks.size() && n_spring != SPRING_POSITIONS; ++b)
			if (s.in[b] && blocks[b].is_node && bool(named_row[b]) == named_first) { s.spring[b] = true; ++n_spring; }
	return s;
}

void joint_name(Json & j, Joint const jt) { j.str(to_string(jt)); }

string dump_body()
{
	Json j;
	j.begin_object();

	// src/players.hpp:8-23 (enum order), src/positions.cpp:7-31 (jointDefs), src/players.hpp:73-102 (mirror).
	j.key("joints").begin_array();
	foreach (jt : joints)
	{
		JointDef const & d = jointDefs[jt];
		j.begin_object();
		j.key("index").integer(jt);
		j.key("name"); joint_name(j, jt);
		j.key("radius").num(d.radius);
		j.key("draggable").boolean(d.draggable);
		j.key("mirror").integer(mirror(jt));
		j.end_object();
	}
	j.end_array();

	// src/players.hpp:126-162 (limbs), in array order.
	j.key("segments").begin_array();
	foreach (l : limbs())
	{
		j.begin_object();
		j.key("ends").begin_array().integer(l.ends[0]).integer(l.ends[1]).end_array();
		j.key("length").num(l.length);
		j.key("mid_radius");
		if (l.midpointRadius) j.num(*l.midpointRadius); else j.null();
		j.key("visible").boolean(l.visible);
		j.end_object();
	}
	j.end_array();

	// src/positions.cpp:140, src/math.hpp:62 (red).
	j.key("players").begin_array();
	foreach (p : playerNums())
	{
		j.begin_object();
		j.key("code").str(string(1, playerCode(p)));
		j.key("color"); v3(j, playerDefs[p].color);
		j.end_object();
	}
	j.end_array();

	// Constants of src/playerdrawer.{hpp,cpp} that shape the body. They are private or literal in the
	// original, so they are copied here with their source line.
	j.key("draw").begin_object();
	j.key("pi").num(pi()); // src/math.hpp:12
	j.key("pillar_faces").integer(10); // src/playerdrawer.hpp:32
	j.key("pillar_side_reference").begin_array().num(1).num(1).num(1).end_array(); // src/playerdrawer.cpp:197,225
	j.key("limb_midpoint").str("(a + b) / 2"); // src/playerdrawer.cpp:322,351
	j.key("sphere_subdivisions_fine").integer(2); // src/playerdrawer.cpp:145
	j.key("sphere_subdivisions_coarse").integer(1); // src/playerdrawer.cpp:146
	j.key("fine_sphere_joints").begin_array(); // src/playerdrawer.cpp:270-272,299-301
	for (Joint jt : {Head, Core, RightHip, LeftHip, RightShoulder, LeftShoulder}) j.integer(jt);
	j.end_array();
	j.key("highlight_extra_radius").num(0.005); // src/playerdrawer.cpp:264,294
	j.key("fat_triangles").begin_array(); // src/playerdrawer.cpp:385-389
	for (auto const & t : {array<Joint, 3>{{LeftHip, Core, RightHip}}, array<Joint, 3>{{LeftShoulder, Neck, RightShoulder}},
	                       array<Joint, 3>{{LeftShoulder, Core, RightShoulder}}, array<Joint, 3>{{LeftAnkle, LeftHeel, LeftToe}},
	                       array<Joint, 3>{{RightAnkle, RightHeel, RightToe}}})
		j.begin_array().integer(t[0]).integer(t[1]).integer(t[2]).end_array();
	j.end_array();
	j.end_object();

	j.end_object();
	return j.take();
}

struct Counts
{
	size_t blocks = 0, positions = 0, named_positions = 0, transitions = 0, nodes = 0, anonymous_nodes = 0;
};

// saved: the bytes of the original's save(g, ostream) (src/persistence.cpp:241-252), or nullptr if no graph was dumped.
string dump_meta(Args const & a, optional<vector<string>> const & versions, string const & db_md5,
                 Index const * ix, bool index_consistent, string const * saved, string const & db, Counts const * c,
                 vector<string> const & errors)
{
	Json j;
	j.begin_object();
	j.key("dumper_version").str(DUMPER_VERSION);
	j.key("submodule_commit");
	if (a.commit.empty()) j.null(); else j.str(a.commit);
	j.key("db_md5").str(db_md5);
	j.key("index_md5");
	if (ix) j.str(ix->md5); else j.null();
	j.key("index_matches_db").boolean(ix && ix->md5 == db_md5);
	j.key("index_consistent").boolean(index_consistent);
	j.key("save_md5");
	if (saved) j.str(MD5(*saved).hexdigest()); else j.null();
	j.key("save_equals_db").boolean(saved && *saved == db);
	j.key("versions");
	if (versions) j.strings(*versions); else j.null();
	j.key("counts");
	if (!c) j.null();
	else
	{
		j.begin_object();
		j.key("blocks").integer(long(c->blocks));
		j.key("positions").integer(long(c->positions));
		j.key("named_positions").integer(long(c->named_positions));
		j.key("transitions").integer(long(c->transitions));
		j.key("nodes").integer(long(c->nodes));
		j.key("anonymous_nodes").integer(long(c->anonymous_nodes));
		j.end_object();
	}
	j.key("errors").strings(errors);
	j.end_object();
	return j.take();
}

int run(Args const & a)
{
	string const db = read_file(a.db);
	string const db_md5 = MD5(db).hexdigest();
	optional<vector<string>> versions;
	if (!a.versions.empty()) versions = split_lines(read_file(a.versions));

	// On any error only meta.json is written, with the message in `errors`, and the exit status is 1.
	// Errors of the original loader are recorded verbatim; the dumper's own ones start with "dumper: ".
	auto fail = [&](string const & error)
		{
			write_file(a.out + "/meta.json", dump_meta(a, versions, db_md5, nullptr, false, nullptr, db, nullptr, {error}));
			std::cerr << "grapplemap-dump: " << error << '\n';
			return 1;
		};

	Graph g{vector<NamedPosition>{}, vector<Sequence>{}};
	try
	{
		std::istringstream in(db);
		g = loadGraph(in); // always the istream path: no .index (src/persistence.cpp:171-176)
	}
	catch (std::exception const & e) { return fail(e.what()); }

	try
	{
		Index const ix = read_index(a.index);

		bool consistent = ix.pairs.size() == g.num_sequences();
		foreach (s : seqnums(g))
			consistent = consistent
				&& ix.pairs[s.index] == std::make_pair(unsigned(g[s].from->index), unsigned(g[s].to->index));

		auto const blocks = blocks_in_file_order(g);
		auto const inv = inventory(g, blocks);
		optional<Sample> sample;
		if (!a.sample.empty()) sample = read_sample(a.sample, blocks, inv);
		Sample const * const smp = sample ? &*sample : nullptr;
		Counts c;
		c.blocks = blocks.size();
		c.transitions = g.num_sequences();
		c.nodes = g.num_nodes();
		foreach (n : nodenums(g))
			if (g[n].line_nr) ++c.named_positions; else ++c.anonymous_nodes;
		c.positions = c.named_positions;
		foreach (s : seqnums(g)) c.positions += g[s].positions.size();

		vector<string> errors;
		if (!consistent) errors.push_back("dumper: .index disagrees with loadGraph(istream)");
		if (ix.md5 != db_md5) errors.push_back("dumper: .index md5 differs from the DB md5");

		std::ostringstream save_out;
		save(g, save_out);
		string const saved = save_out.str();

		Staged_Files out(a.out);
		out.write("sequences.ndjson", [&](std::ostream & o) { dump_sequences(o, g, blocks, smp); });
		out.write("graph.ndjson", [&](std::ostream & o) { dump_graph(o, g, blocks, ix, smp); });
		out.write("ops.ndjson", [&](std::ostream & o) { dump_ops(o, g, blocks, smp); });
		out.write("between.ndjson", [&](std::ostream & o) { dump_between(o, g, blocks, smp); });
		out.write("compose.ndjson", [&](std::ostream & o) { dump_compose(o, g, blocks, smp); });
		out.write("playback.ndjson", [&](std::ostream & o) { dump_playback(o, g, blocks, smp); });
		out.write("body.json", [&](std::ostream & o) { o << dump_body(); });
		out.write("spring.ndjson", [&](std::ostream & o) { dump_spring(o, g, blocks, smp); });
		out.write("inventory.ndjson", [&](std::ostream & o) { dump_inventory(o, blocks, inv, smp); });
		if (!smp) out.write("save.txt", [&](std::ostream & o) { o << saved; }); // ~2.7 MB: not in the sample
		out.write("meta.json", [&](std::ostream & o) { o << dump_meta(a, versions, db_md5, &ix, consistent, &saved, db, &c, errors); });
		out.commit();

		foreach (e : errors) std::cerr << "grapplemap-dump: " << e << '\n';
		return errors.empty() ? 0 : 1;
	}
	catch (std::exception const & e) { return fail(string("dumper: ") + e.what()); }
}

} // namespace

int main(int argc, char const * const * argv)
{
	try
	{
		return run(parse_args(argc, argv));
	}
	catch (std::exception const & e)
	{
		std::cerr << "grapplemap-dump: " << e.what() << '\n';
		return 1;
	}
}
