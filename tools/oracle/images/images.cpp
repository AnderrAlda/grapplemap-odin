// Oracle reference images (#35): renders the named positions of images.tsv with the original's ImageMaker::png,
// exactly as mkpospages' position pages do (src/mkpospages.cpp:578-588), and copies each stored PNG to OUT.
// Usage: grapplemap-images --db DB --list TSV --out OUT [--versions FILE] [--commit SHA]
// Writes OUT/p<node>-480x360.png per row and OUT/meta.json. Exit status 1 on any error.
#include "images.hpp"
#include "persistence.hpp"
#include "graph_util.hpp"
#include "../dump/json.hpp"
#include <boost/program_options.hpp>
#include <cstdlib>
#include <fstream>
#include <iostream>

using namespace GrappleMap;
namespace po = boost::program_options;

namespace {

unsigned const WIDTH = 480, HEIGHT = 360; // the larger of mkpospages' two position-page sizes
ImageView const VIEW{false, Heading::N, {}}; // view code 'n': the one every index/list page links to

struct Row { size_t block; string reason; };

vector<string> read_lines(string const & path)
{
	std::ifstream in(path);
	if (!in) throw std::runtime_error("cannot read " + path);
	vector<string> v;
	for (string line; std::getline(in, line);) v.push_back(line);
	return v;
}

// images.tsv: header "index<TAB>reason", then one row per image; index = block index of sequences.ndjson.
vector<Row> read_list(string const & path)
{
	auto const lines = read_lines(path);
	if (lines.empty() || lines[0] != "index\treason") throw std::runtime_error(path + ": bad header");
	vector<Row> rows;
	for (size_t i = 1; i != lines.size(); ++i)
	{
		auto const tab = lines[i].find('\t');
		string const idx = lines[i].substr(0, tab);
		if (tab == string::npos || idx.empty() || idx.size() > 9 || (idx.size() > 1 && idx[0] == '0')
			|| idx.find_first_not_of("0123456789") != string::npos || tab + 1 == lines[i].size())
			throw std::runtime_error(path + ":" + to_string(i + 1) + ": bad row");
		rows.push_back({std::stoul(idx), lines[i].substr(tab + 1)});
	}
	return rows;
}

// Block index -> node, with the dumper's block order (nodes and edges merged by line number, dump.cpp).
optional<NodeNum> node_of_block(Graph const & g, size_t const block)
{
	vector<std::pair<unsigned, optional<NodeNum>>> v;
	foreach (n : nodenums(g)) if (g[n].line_nr) v.emplace_back(*g[n].line_nr, n);
	foreach (s : seqnums(g)) v.emplace_back(*g[s].line_nr, none);
	std::stable_sort(v.begin(), v.end(), [](auto const & a, auto const & b) { return a.first < b.first; });
	if (block >= v.size()) return none;
	return v[block].second;
}

string gl_string(GLenum const e)
{
	auto const s = glGetString(e);
	return s ? reinterpret_cast<char const *>(s) : "";
}

// GL strings of a context like ImageMaker's (src/images.cpp:525); a separate one, since ImageMaker's is private.
vector<string> gl_strings()
{
	OSMesaContextPtr ctx(OSMesaCreateContextExt(OSMESA_RGB, 16, 0, 16, nullptr));
	vector<unsigned char> buf(3);
	if (!ctx.context || !OSMesaMakeCurrent(ctx.context, buf.data(), GL_UNSIGNED_BYTE, 1, 1))
		throw std::runtime_error("OSMesa context for GL strings");
	return {gl_string(GL_VENDOR), gl_string(GL_RENDERER), gl_string(GL_VERSION)};
}

void copy_file(string const & from, string const & to)
{
	std::ifstream in(from, std::ios::binary);
	std::ofstream out(to, std::ios::binary);
	if (!in || !(out << in.rdbuf()) || !out.flush()) throw std::runtime_error("cannot copy " + from + " to " + to);
}

int run(int argc, char const * const * argv)
{
	string db, list, out, versions, commit;
	po::options_description desc("options");
	desc.add_options()
		("db", po::value(&db)->required())
		("list", po::value(&list)->required())
		("out", po::value(&out)->required())
		("versions", po::value(&versions))
		("commit", po::value(&commit));
	po::variables_map vm;
	po::store(po::parse_command_line(argc, argv, desc), vm);
	po::notify(vm);

	auto const rows = read_list(list);
	std::ifstream dbin(db);
	if (!dbin) throw std::runtime_error("cannot read " + db);
	// The istream path, like the dumper; mkpospages uses loadGraph(filename) (the .index path), equivalent here since
	// the dumper checks that both agree (meta.json index_consistent).
	Graph const g = loadGraph(dbin);

	// ImageMaker writes into res/store/ and symlinks res/<linkname> to it (src/images.cpp:318-338).
	char tmpl[] = "/tmp/grapplemap-images.XXXXXX";
	if (!mkdtemp(tmpl)) throw std::runtime_error("mkdtemp");
	string const res = string(tmpl) + "/res";
	fs::create_directories(res + "/store");

	auto const gl = gl_strings();

	dump::Json j;
	j.begin_object();
	j.key("submodule_commit");
	if (commit.empty()) j.null(); else j.str(commit);
	j.key("versions");
	if (versions.empty()) j.null(); else j.strings(read_lines(versions));
	j.key("gl").begin_object().key("vendor").str(gl[0]).key("renderer").str(gl[1]).key("version").str(gl[2]).end_object();
	// The Mesa driver the bytes depend on (build.sh sets softpipe; README, "Reference images").
	char const * const driver = std::getenv("GALLIUM_DRIVER");
	j.key("env").begin_object().key("GALLIUM_DRIVER");
	if (driver) j.str(driver); else j.null();
	j.end_object();
	j.key("images").begin_array();
	{
		ImageMaker mkimg(g, res + "/");
		foreach (row : rows)
		{
			auto const n = node_of_block(g, row.block);
			if (!n) throw std::runtime_error("block " + to_string(row.block) + " is not a named position");

			// src/mkpospages.cpp:578-588, verbatim.
			auto const pos_to_show = orient_canonically_with_mirror(g[*n].position);
			double const ymax = std::max(.8, std::max(pos_to_show[player0][Head].y, pos_to_show[player1][Head].y));
			string const base = 'p' + to_string(n->index);
			mkimg.png(pos_to_show, ymax, VIEW, WIDTH, HEIGHT, mkimg.WhiteBg, base);

			// Copy the file the symlink points to: store names depend on boost::hash_value.
			string const link = res + "/" + base + code(VIEW) + to_string(WIDTH) + 'x' + to_string(HEIGHT) + ".png";
			string const file = base + '-' + to_string(WIDTH) + 'x' + to_string(HEIGHT) + ".png";
			copy_file(res + "/" + fs::read_symlink(link).native(), out + "/" + file);

			j.begin_object()
				.key("file").str(file).key("block").integer(long(row.block)).key("node").integer(n->index)
				.key("view").str(string(1, code(VIEW))).key("width").integer(WIDTH).key("height").integer(HEIGHT)
				.key("background").str("white").key("reason").str(row.reason)
				.end_object();
		}
	}
	j.end_array().end_object();

	std::ofstream meta(out + "/meta.json", std::ios::binary);
	if (!(meta << j.take()) || !meta.flush()) throw std::runtime_error("cannot write meta.json");
	fs::remove_all(tmpl);
	return 0;
}

} // namespace

int main(int argc, char ** argv)
{
	try { return run(argc, argv); }
	catch (std::exception const & e)
	{
		std::cerr << "grapplemap-images: " << e.what() << '\n';
		return 1;
	}
}
