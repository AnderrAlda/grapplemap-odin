// Oracle dumper (#34): loads GrappleMap.txt with the original loader and writes the files of
// docs/specs/phase-1-original-research.md ("Dump format") to --out. Linked against the original's
// `common` objects (reference/GrappleMap/src/SConstruct:33); nothing of the original is modified.
//
// Usage: grapplemap-dump --db FILE --index FILE --out DIR [--versions FILE] [--commit SHA]
//   --index: the .index written by grapplemap-indexer on a copy of the DB (only read, never used to load).
//
// Files (fixed order, no timestamps): meta.json, sequences.ndjson, graph.ndjson, body.json.
// PR 2 of #34 adds ops, between, playback and spring.
#include "json.hpp"

#include "graph_util.hpp"
#include "md5.hpp"
#include "metadata.hpp"
#include "persistence.hpp"

#include <fstream>
#include <iostream>
#include <iterator>
#include <sstream>

namespace {

using namespace GrappleMap;
using dump::Json;

char const DUMPER_VERSION[] = "1";

struct Args
{
	string db, index, out, versions, commit;
};

[[noreturn]] void usage()
{
	std::cerr << "usage: grapplemap-dump --db FILE --index FILE --out DIR [--versions FILE] [--commit SHA]\n";
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

// Inverse of decodePosition (src/persistence.cpp:33-61): x = q/1000 - off. Exact or it throws.
int quantize(double const x, double const off)
{
	long const q = std::lround((x + off) * 1000);
	if (q < 0 || q > 61 * 62 + 61 || double(q) / 1000 - off != x)
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

string dump_sequences(Graph const & g, vector<Block> const & blocks)
{
	string out;
	Json j;
	for (size_t b = 0; b != blocks.size(); ++b)
	{
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
		out += j.take();
	}
	return out;
}

string dump_graph(Graph const & g, vector<Block> const & blocks, Index const & ix)
{
	vector<long> node_block(g.num_nodes(), -1), seq_block(g.num_sequences(), -1);
	for (size_t b = 0; b != blocks.size(); ++b)
		(blocks[b].is_node ? node_block : seq_block)[blocks[b].index] = long(b);

	string out;
	Json j;
	foreach (n : nodenums(g))
	{
		j.begin_object();
		j.key("type").str("node");
		j.key("index").integer(n.index);
		j.key("block");
		if (node_block[n.index] < 0) j.null(); else j.integer(node_block[n.index]);
		j.key("description").strings(g[n].description);
		j.key("tags").strings(set_to_vector(tags_in_desc(g[n].description)));
		j.key("position_q"); position_q(j, g[n].position);
		j.end_object();
		out += j.take();
	}
	foreach (s : seqnums(g))
	{
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
		out += j.take();
	}
	j.begin_object();
	j.key("type").str("index");
	j.key("md5").str(ix.md5);
	j.key("pairs").begin_array();
	foreach (p : ix.pairs) j.begin_array().integer(p.first).integer(p.second).end_array();
	j.end_array();
	j.end_object();
	out += j.take();
	return out;
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

string dump_meta(Args const & a, optional<vector<string>> const & versions, string const & db_md5,
                 Index const * ix, bool index_consistent, Counts const * c, vector<string> const & errors)
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
			write_file(a.out + "/meta.json", dump_meta(a, versions, db_md5, nullptr, false, nullptr, {error}));
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

		// Everything is built before anything is written, so a failure never leaves a partial dump.
		string const sequences = dump_sequences(g, blocks), graph = dump_graph(g, blocks, ix), body = dump_body(),
		             meta = dump_meta(a, versions, db_md5, &ix, consistent, &c, errors);
		write_file(a.out + "/sequences.ndjson", sequences);
		write_file(a.out + "/graph.ndjson", graph);
		write_file(a.out + "/body.json", body);
		write_file(a.out + "/meta.json", meta);

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
