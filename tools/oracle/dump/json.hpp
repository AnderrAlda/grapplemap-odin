// Minimal JSON writer for the oracle dumper: no whitespace, keys in insertion order, doubles as %.17g.
// Strings are UTF-8; invalid UTF-8 or non-finite doubles throw (the dump must stay valid JSON).
#ifndef GRAPPLEMAP_DUMP_JSON_HPP
#define GRAPPLEMAP_DUMP_JSON_HPP

#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

namespace dump {

class Json
{
	std::string out_;
	std::vector<bool> first_; // per open container: no element written yet
	bool after_key_ = false;

	void sep()
	{
		if (after_key_) { after_key_ = false; return; }
		if (!first_.empty())
		{
			if (!first_.back()) out_ += ',';
			first_.back() = false;
		}
	}

	static size_t utf8_len(std::string const & s, size_t i)
	{
		auto const c = static_cast<unsigned char>(s[i]);
		size_t n;
		unsigned min;
		if (c < 0x80) return 1;
		else if ((c & 0xE0) == 0xC0) { n = 2; min = 0x80; }
		else if ((c & 0xF0) == 0xE0) { n = 3; min = 0x800; }
		else if ((c & 0xF8) == 0xF0) { n = 4; min = 0x10000; }
		else return 0;
		if (i + n > s.size()) return 0;
		unsigned cp = c & (0x7F >> n);
		for (size_t k = 1; k != n; ++k)
		{
			auto const d = static_cast<unsigned char>(s[i + k]);
			if ((d & 0xC0) != 0x80) return 0;
			cp = (cp << 6) | (d & 0x3F);
		}
		if (cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return 0;
		return n;
	}

public:
	Json & begin_object() { sep(); out_ += '{'; first_.push_back(true); return *this; }
	Json & end_object() { out_ += '}'; first_.pop_back(); return *this; }
	Json & begin_array() { sep(); out_ += '['; first_.push_back(true); return *this; }
	Json & end_array() { out_ += ']'; first_.pop_back(); return *this; }

	Json & key(std::string const & k) { str(k); out_ += ':'; after_key_ = true; return *this; }

	Json & str(std::string const & s)
	{
		sep();
		out_ += '"';
		for (size_t i = 0; i < s.size();)
		{
			auto const c = static_cast<unsigned char>(s[i]);
			if (c >= 0x80)
			{
				size_t const n = utf8_len(s, i);
				if (n == 0) throw std::runtime_error("invalid UTF-8 in string: " + s);
				out_.append(s, i, n);
				i += n;
				continue;
			}
			switch (c)
			{
				case '"': out_ += "\\\""; break;
				case '\\': out_ += "\\\\"; break;
				case '\n': out_ += "\\n"; break;
				case '\r': out_ += "\\r"; break;
				case '\t': out_ += "\\t"; break;
				default:
					if (c < 0x20)
					{
						char buf[8];
						std::snprintf(buf, sizeof buf, "\\u%04x", c);
						out_ += buf;
					}
					else out_ += static_cast<char>(c);
			}
			++i;
		}
		out_ += '"';
		return *this;
	}

	Json & num(double d)
	{
		if (!std::isfinite(d)) throw std::runtime_error("non-finite double");
		sep();
		char buf[32];
		std::snprintf(buf, sizeof buf, "%.17g", d);
		out_ += buf;
		return *this;
	}

	Json & integer(long long i) { sep(); out_ += std::to_string(i); return *this; }
	Json & boolean(bool b) { sep(); out_ += b ? "true" : "false"; return *this; }
	Json & null() { sep(); out_ += "null"; return *this; }

	Json & strings(std::vector<std::string> const & v)
	{
		begin_array();
		for (auto const & s : v) str(s);
		return end_array();
	}

	// Takes the finished line (one complete value) and resets the writer.
	std::string take()
	{
		if (!first_.empty()) throw std::logic_error("unclosed JSON container");
		std::string r;
		r.swap(out_);
		r += '\n';
		return r;
	}
};

} // namespace dump

#endif
