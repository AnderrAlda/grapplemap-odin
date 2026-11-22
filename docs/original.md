# The original GrappleMap, as read from its code

Purpose: let phase 2 reimplement the original's data handling in Odin with exact fidelity **without reading the C++
again**. Source of truth: the submodule `reference/GrappleMap`, pinned at `032c8f9`.

**Conventions**
- A citation `src/x.cpp:L` or `src/x.cpp:A-B` is relative to `reference/GrappleMap` at the pin. On a pin bump every
  citation must be re-checked (`reference/CLAUDE.md`).
- `GrappleMap.txt` means `reference/GrappleMap/GrappleMap.txt`; its line numbers are cited as `GrappleMap.txt:L`.
- **[unverified]** marks a claim that depends on UB, compiler behaviour or a multi-step chain deduced from the code, whose
  runtime behaviour has not been observed (it needs the oracle/dumper; to be linked to the dumper issue when it exists). Each one says why. Claims without the marker were checked against the cited lines.

## Contents
1. [Data format](#1-data-format)
2. [Graph model and node matching](#2-graph-model-and-node-matching)
3. [Player model](#3-player-model)
4. [Units and axes](#4-units-and-axes)
5. [Transforms](#5-transforms)
6. [Interpolation and playback](#6-interpolation-and-playback)
7. [Rendering and camera](#7-rendering-and-camera)
8. [Web tools](#8-web-tools)
9. [Editor semantics](#9-editor-semantics)
10. [Data inventory](#10-data-inventory)

---

## 1. Data format

### 1.1 File layout

`GrappleMap.txt` is plain UTF-8 text with `\n` line endings, read whole into memory and parsed by `readSeqs`
(`src/persistence.cpp:58-116`) from a `[b, e)` byte range (`loadGraph`, `src/persistence.cpp:154-176` for streams; the file overload reads in binary mode, `src/persistence.cpp:186-213`). The parser works on bytes and does not validate UTF-8.

The parser looks at **one byte per line**: if the first byte is a space (`' '`), what follows is a *position block*;
anything else is a *description line* (`src/persistence.cpp:71`). There is no other classification: a blank line, a line
starting with a tab, `#`, etc. are all description lines.

A logical **block** is: one or more description lines, then one or more position blocks. Consecutive description lines
are gathered in `desc`; the first position block after them closes the description and starts a `Sequence`
(`src/persistence.cpp:73-86`); further position blocks with no description in between are appended to that same
sequence (`last_was_position`, `src/persistence.cpp:75,107`). A block with exactly one position is a *named position*
(graph node), with two or more it is a *transition* (`src/persistence.cpp:160-166`; semantics in section 2).

Consequences visible in the code:
- Description lines that are **not followed by a position block** (end of file) are silently dropped: `desc` is only
  consumed when a position starts (`src/persistence.cpp:75-86`) and is not looked at after the loop.
- Line endings: only `'\n'` ends a description line (`src/persistence.cpp:99`). `'\r'` is not stripped, so it would
  become the last character of the line. The DB has no `'\r'` and no tab (`tr -cd`, §1.8).
- The writer always emits `'\n'` and opens the file in binary mode (`src/persistence.cpp:237`, `118-144`).

### 1.2 Description lines

The first description line is the **name** of the block (`description.front()` is used as the name throughout, e.g.
`src/graph.hpp:16-18`, `src/graph_util.cpp:176`). Remaining lines are free-form, except for the prefixes below. A prefix
only counts at **column 0**, and is matched by a plain, case-sensitive `substr` comparison.

| Line | Who reads it | Details |
|---|---|---|
| `tags: a b c` | `tags_in_desc`, `src/graph_util.cpp:147-164`; wrappers `src/metadata.hpp:19-20` | Prefix `tags:`, then the rest is split on whitespace (`istringstream >>`); every token is a tag; multiple `tags:` lines are unioned into a `set`. |
| `properties: a b c` | `properties_in_desc`, `src/metadata.cpp:37-54` | Same parsing. Only on sequences: `detailed` and `bidirectional` are read while loading (`src/persistence.cpp:78,84-85`) and on `set_description` (`src/graph.cpp:370-371`). Other tokens are not interpreted by the C++ loader and are passed to JS (`src/js_conversions.cpp:114,263`), where e.g. `top`/`bottom` color transitions (`src/search.js:669-670`, `src/explorer.js:83-84`). |
| `ref: …` | nothing | No parser support: no string `"ref:"` in `src/`. Documented as the source-material line (`doc/native-editor.md:67`). The JS composer shows it as ordinary text (`src/composer.js:339-346`). |
| `note: …`, `todo: …` | nothing | Same: no code recognizes them; they are plain description lines (shown as text by `src/composer.js:339-346`). |

Notes:
- `tags:`/`properties:` are checked on **every** description line, including the first. A block *named* `tags: x` would
  have its name also parsed as a tag line (code reading, not present in the DB).
- Values of `properties:` found in the DB: `top` 616, `bottom` 558, `detailed` 159, `bidirectional` 38, `sweep` 2,
  `transitive` 1 (§1.8). Only `detailed`/`bidirectional` have behaviour in the loader.
- `composer.js` hides `tags:` and `properties:` lines from the displayed description (`src/composer.js:341-342`).
- **Literal `\n`**: a backslash followed by `n` (two bytes, not a newline) inside a description line marks a
  *display* line break. The parser leaves it untouched; consumers replace it: by a space for name lookup
  (`src/metadata.cpp:69,89`, `src/paths.cpp:32`), by `<BR/>`/`<br>` for output (`src/persistence.cpp:317`,
  `src/mkpospages.cpp:159,178`). 1282 lines of the DB contain it (§1.8). The `lines()` helper splits on real `'\n'`
  only (`src/graph.cpp:350-354`).

### 1.3 Position encoding

A position is the 3D coordinates of both players' joints, stored as **4 text lines** of 4 spaces + 69 base62 digits.

**Size.** `encoded_pos_size = 2 · joint_count · 3 · 2 + 4 · 5` (`src/persistence.cpp:31`). With `joint_count = 23`
(`src/players.hpp:8-19,29`): `2·23·3·2 = 276` digits `+ 4·5 = 20` bytes of layout (per line: 4 spaces + 1 `'\n'`)
`= 296` bytes. 276 digits / 4 lines = 69 per line.

**Order of values** (`decodePosition`, `src/persistence.cpp:33-56`): for each `PlayerJoint` in `playerJoints`
(`src/positions.cpp:65-73,138`): player 0 first, then player 1; within a player, the 23 joints in enum order
(`src/players.hpp:8-19`): LeftToe, RightToe, LeftHeel, RightHeel, LeftAnkle, RightAnkle, LeftKnee, RightKnee, LeftHip,
RightHip, LeftShoulder, RightShoulder, LeftElbow, RightElbow, LeftWrist, RightWrist, LeftHand, RightHand, LeftFingers,
RightFingers, Core, Neck, Head. For each joint, three coordinates in the order **x, y, z**
(`p[j] = {g() - 2, g(), g() - 2}`, `src/persistence.cpp:53`; braced-init order is left to right).

**Base62.** Alphabet `abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789` (`src/persistence.cpp:13`):
`a-z` = 0-25, `A-Z` = 26-51, `0-9` = 52-61 (`src/persistence.cpp:16-23`). Note the order: lowercase first.

**Quantization.** Each coordinate is two digits `d0 d1`: `value = (62·d0 + d1) / 1000` as a `double` division
(`src/persistence.cpp:45-46`). Then `x` and `z` get an offset of **−2**, `y` none (`src/persistence.cpp:53`).

**Range.** `62·61 + 61 = 3843`, so raw `value ∈ [0, 3.843]` in steps of 0.001, giving
- `x, z ∈ [−2.000, 1.843]` m, `y ∈ [0.000, 3.843]` m.

Units and axis meaning belong to section 4.

**Whitespace inside the block.** `nextdigit` skips *any* `isspace` byte before each digit
(`src/persistence.cpp:37-41`), so the decoder does not care where the line breaks are, nor about the 4-space indent. It
only needs 276 digits. But the *caller* then advances by a fixed `encoded_pos_size` (`src/persistence.cpp:93`), see §1.7.

### 1.4 Named positions vs. sequences; `line_nr`

- 1-position blocks become `NamedPosition{position, description, line_nr}` and are removed from the sequence list;
  the rest are edges (`src/persistence.cpp:158-168` for streams, `217-225` for files). Everything about how they are
  linked is section 2.
- A file load also reads/writes `GrappleMap.txt.index` keyed by the md5 of the DB (`src/persistence.cpp:178-233`).
  Out of scope here; see section 2.
- `line_nr` is meant to be the line where the block starts, counting from the start of the file. The counter is
  `+1` per description line and `+4` per position (`src/persistence.cpp:65,94,102`) and the sequence is created with
  `line_nr - desc.size()` (`src/persistence.cpp:83`). **[unverified]** The expression is evaluated after
  `move(desc)` in the same braced initializer (`src/persistence.cpp:81-83`); if the moved-from vector is empty (usual
  for `std::vector`), the subtraction is `0` and `line_nr` is the 0-based index of the first position line, not of the
  block start. Confirm with the dumper (`line_nr` field in the JS conversions, `src/js_conversions.cpp:87,140`).
  Consumers: `l<N>` lookups (`src/metadata.cpp:114-116`) and `@N` labels (`src/mkpospages.cpp:292,306`).

### 1.5 Writer and round trip

`save` writes, in this order, every node that has a description (`desc` + position), then every sequence
(`src/persistence.cpp:241-251`); nodes with an empty description are skipped (`src/persistence.cpp:244`). A sequence
is its description lines each followed by `'\n'`, then each position (`src/persistence.cpp:146-151`).

A position (`src/persistence.cpp:118-144`): per coordinate `i = int(round(d·1000))` (with the `+2` offset on x/z), two
digits `base62digits[i / 62]`, `base62digits[i % 62]`, all 276 digits concatenated then cut in 4 pieces of
`size/4 = 69`, each written as `"    " + piece + '\n'`.

What is and is not preserved on a load → save round trip:
- Coordinates: preserved to the 0.001 grid (exactly for values read from the file, since `i` is recovered from the
  digits; `round` is half away from zero). Edited values are rounded to 1 mm.
- Block order: **changes**. Named positions are written first, then sequences, each in graph order
  (`src/persistence.cpp:243-250`), so the original interleaving of the file is not kept.
- Dropped: trailing description lines without positions (§1.1), nodes with an empty description (above).
- Everything else in description lines (including `ref:`, `note:`, `todo:`, `\n` markers) is written back verbatim.
- Writer asserts `i >= 0` and `i < 4000` (`src/persistence.cpp:125-126`), but the encodable maximum is **3843**
  (`61·62+61`): values 3844-3999 pass the assert and index past the alphabet (`i/62 = 62` reads the string's NUL
  terminator for 3844-3905; above that the index is out of bounds, UB; a negative `i` is UB too). Both asserts are compiled out in release builds (§1.7), so out-of-range values are not detected.

### 1.6 Grammar

What the **parser** accepts (looser than what the writer produces). Terminals are bytes.

```ebnf
file        = { block_item } ;
block_item  = desc_line | pos_block ;

desc_line   = nonspace , { not_newline } , ( "\n" | EOF )     (* first byte != ' ' *)
            | "\n" ;                                          (* the empty line is a desc_line too *)
pos_block   = " " , 295 * byte ;                              (* exactly 296 bytes consumed, see 1.7 *)
nonspace    = byte - " " - "\n" ;
not_newline = byte - "\n" ;
```

Semantics layered on top (`readSeqs`):

```ebnf
sequence    = desc_line , { desc_line } , pos_block , { pos_block } ;   (* desc_line+ then pos_block+ *)
```
- Within a `pos_block`, `decodePosition` takes the first 276 base62 digits, skipping any `isspace` before each one.
- Block with one `pos_block` → named position; two or more → transition.

What the **writer** emits for well-formed data (and what the DB contains, §1.8; the writer does not enforce it):

```ebnf
file        = { block } ;
block       = desc_line_w , { desc_line_w } , position , { position } ;
desc_line_w = line_without_leading_space , "\n" ;
position    = 4 * ( "    " , 69 * base62 , "\n" ) ;
base62      = "a".."z" | "A".."Z" | "0".."9" ;
```

### 1.7 Errors and edge cases

Build flags matter: both the native and the emscripten builds compile with `-DNDEBUG` (`src/SConstruct:4,16`), so
every `assert` below is **compiled out** in the shipped binaries.

| Input | Original behaviour | Cite |
|---|---|---|
| A byte that is not `[a-zA-Z0-9]` where a digit is expected | `fromBase62` calls `error("not a base 62 digit: " + c)`, which throws `runtime_error` (`src/util.hpp:68`). `readSeqs` catches it and rethrows `"at line N: not a base 62 digit: c"` where `N` is `line_nr` at that moment: the number of lines consumed **before** the failing position block (the block's first line is `N+1`, 1-based). Only the first bad digit is reported. | `src/persistence.cpp:16-23,110-113` |
| Position block shorter than 296 bytes left in the file (truncated, or **file without the final `'\n'`**: the last block is then 295 bytes) | `abort()`: process termination, not an exception, so the `catch` does not see it and no message is printed by the code. | `src/persistence.cpp:89` |
| Position block before any description line (the file starts with `' '`) | `assert(!desc.empty())` fires only in debug builds. With `NDEBUG` the sequence is created with an **empty description** and `line_nr = 0`; later code that calls `description.front()` on it would be UB (e.g. `src/graph_util.cpp:176`). **[unverified]** runtime effect; needs the dumper. | `src/persistence.cpp:77,83`, `src/SConstruct:4` |
| A block where **all four** lines have no leading space | Not a position at all (first-byte rule, checked per line): its 4 lines are description lines, never decoded; they attach to the next block's description or are dropped at EOF. | `src/persistence.cpp:71` |
| Position lines indented differently (a different non-zero indent, lines 2-4 with other indentation, or **only line 1 unindented**), or digits split across lines differently | The *decoder* tolerates it: it takes the first 276 base62 digits from the start of the block, skipping `isspace`, wherever they are (it can read on into the next item). The *caller* always advances exactly 296 bytes. If the block's real byte length is not 296, the next read starts mid-block. There is no specific diagnostic; depending on the input: (a) a position is decoded silently from the wrong bytes, with wrong coordinates and no error (letters and digits of the next item count as digits); (b) leftover text becomes a bogus description line, which ends the merging of consecutive positions and splits a transition into 1-position nodes, which `Graph` can then reject with `multiple positions named` (`src/graph.cpp:284-285`); (c) the decoder hits a non-base62 byte (e.g. punctuation in a description) and throws a misleading `not a base 62 digit`; (d) `abort()` near the end of the file. Case *only line 1 unindented*: line 1 becomes a description line; line 2 is still a position and always opens a new sequence (`last_was_position` is false after line 1) whose description is the pending description lines plus the 69 digits as its last line; if there are no pending lines (the previous item was a position, or start of file) the sequence is named by those 69 digits. Decoding from line 2 reads lines 2-4 plus the next block's line 1, and the shift repeats for the remaining positions. **[unverified]** which outcome happens for a given input; derived from the code. | `src/persistence.cpp:37-41,52-53,71,75-86,93,107` |
| CRLF line endings | Same mechanism: each position line has +1 byte, so a block is 300 bytes; `decodePosition` succeeds but the cursor lands inside the last line of the block, the remainder (last 2 digits + `'\r'`) is parsed as a description line, so every transition is split into 1-position nodes named like `XY\r` and `Graph` likely fails with `multiple positions named` (`src/graph.cpp:284-285`); `'\r'` also stays in all description lines. The file is opened in binary mode, so no CRLF translation happens even on Windows (`src/persistence.cpp:188`). **[unverified]** end-to-end result; derived from the code. | `src/persistence.cpp:39,93,99` |
| Tab or other whitespace inside the digits | Skipped by `isspace` like a space (see above); byte count rules still apply. | `src/persistence.cpp:39` |
| A *description* line that starts with a space | Classified as a position block (first-byte rule) and consumes 296 bytes. The writer does not guard against it (it writes description lines verbatim), so an edited line with a leading space is emitted and then misread. | `src/persistence.cpp:71` |
| Empty file | `b < e` is false, no sequences, empty `vector<Sequence>`. What `Graph` does with no nodes is section 2. | `src/persistence.cpp:69,115` |
| Description lines at the end with no positions after | Dropped silently (§1.1). | `src/persistence.cpp:75-86` |
| Two blocks with no description between them | They merge into one sequence (positions appended). | `src/persistence.cpp:75,91` |
| Blank line between blocks | It is a description line (`""`), so it either becomes part of the next block's description (as the *first* line, hence an empty name) or is dropped at EOF. | `src/persistence.cpp:96-105` |
| Description-only edits (`set_description`) | `lines()` splits on `'\n'`; `detailed`/`bidirectional` recomputed. | `src/graph.cpp:350-354,366-373` |

`readSeqs` performs **no** validation of: name uniqueness, tag/property vocabulary, coordinate sanity, number of
positions per block, or count of lines. Everything not in the table above is accepted by `readSeqs`. The `Graph`
constructor then rejects two named positions with identical full descriptions (`src/graph.cpp:284-285`); that and
the rest of graph building are section 2.

### 1.8 Observed in the DB at the pin

All commands run from `reference/GrappleMap` (read-only, `git status --porcelain` empty before and after):

```sh
grep -c '^ ' GrappleMap.txt                                           # 33292 lines starting with a space
grep -cE '^    [A-Za-z0-9]{69}$' GrappleMap.txt                       # 33292: all of them are 4 spaces + 69 base62
grep '^ ' GrappleMap.txt | grep -vcE '^    [A-Za-z0-9]{69}$'          # 0 position-looking lines that are malformed
grep -c '^$' GrappleMap.txt                                           # 0 empty lines
tr -cd '\t' <GrappleMap.txt | wc -c; tr -cd '\r' <GrappleMap.txt | wc -c   # 0 tabs, 0 CRs
awk '/^ /{r++;next}{if(r){if(r%4)b++;r=0}}END{if(r%4)b++;print b+0}' GrappleMap.txt  # 0 runs not multiple of 4
grep -c '\\n' GrappleMap.txt                                          # 1282 lines with a literal \n
grep -c '^tags:' GrappleMap.txt   # 919 · '^properties:' 1244 · '^ref:' 1208 · '^todo:' 302 · '^note:' 4
tail -c 1 GrappleMap.txt | xxd                                        # 0a: final newline present
wc -l GrappleMap.txt                                                  # 39098 lines
grep '^properties:' GrappleMap.txt | sed 's/^properties://' | tr ' ' '\n' | grep -v '^$' | sort | uniq -c   # §1.2 counts
grep '^ ' GrappleMap.txt | sed 's/^    //' | fold -w1 | sort -u | wc -l      # 62 distinct position characters
```

- Position alphabet in the file: the 62 base62 characters all occur and nothing else, so every coordinate is within
  the range of §1.3 by construction.
- 9 lines contain non-ASCII (UTF-8) bytes (`LC_ALL=C grep -c '[^ -~]'`), all in description lines.
- Counts of blocks, named positions and transitions: §10.1 (2,086 / 601 / 1,485; they need the oracle).

---

## 2. Graph model and node matching

Everything here is `Graph` (`src/graph.hpp`, `src/graph.cpp`) plus the loaders in `src/persistence.cpp`. Names:
*named position* = 1-position block; *transition* = block with ≥ 2 positions (§1.4); *node* = vertex of the graph;
*edge* = transition after its endpoints have been resolved to nodes.

### 2.1 Named positions vs. transitions

`loadGraph` splits the output of `readSeqs`: sequences with exactly one position become `NamedPosition{position,
description, line_nr}` and are removed; the rest stay as transitions, in file order (`src/persistence.cpp:154-169` for
buffers/streams, `217-225` for files). Then `Graph(named, transitions)` is built (`src/graph.cpp:279-302`):

1. **Named nodes first**: every named position becomes a node, in file order, so named node `i` is the `i`-th
   1-position block of the file (`src/graph.cpp:281-288`). The DB has 601 (checked: `awk` over runs of position lines, 601 runs of
   4 lines and 1485 runs of more, matching the spec's "Database facts").
2. **Duplicate-name check**: before pushing each named position, it is compared against every node already pushed; if
   the other node's description is non-empty and the **whole description vector** is equal (all lines, not just the
   name), it raises `multiple positions named "<first line>"` (`src/graph.cpp:283-285`). Two named positions with the same
   name but different extra lines are accepted. O(n²), irrelevant at this size.
3. **Named positions are never merged with each other**: two named blocks that are reorientations of each other
   (§2.3) stay as two distinct nodes; no matching is done between named positions at all (`src/graph.cpp:281-288`
   has no `is_reoriented`). Whether the DB has such pairs needs the dumper: **[unverified]**.
4. **Transitions in file order** (`src/graph.cpp:290-296`): for each one, `from = find_or_add(positions.front())`, then
   `to = find_or_add(positions.back())` (that order matters for numbering, §2.4), and the edge is stored with its
   `ReorientedNode from, to` and all its own positions untouched. Edge `i` is the `i`-th transition of the file; this
   is the `SeqNum`/`t<N>` number (§2.8).
5. **in/out lists** are computed at the end for every node (`src/graph.cpp:298-299`, §2.6).
6. `data.forget_past()` clears the undo history (`src/graph.cpp:301`).

Nothing checks the invariant `!is_reoriented(positions.front(), positions.back())` (`src/positions.hpp:16`) when
loading: only editor mutations reject it (`Graph::set`, `src/graph.cpp:134-138`; `Graph::erase`, `src/graph.cpp:179-186`). A DB transition whose end
positions are reorientations of each other could load with `from == to` (likely, not guaranteed: `back` may first
match a lower-index node). Conversely, `from == to` can also arise when both ends are within the threshold of the same
node without being reorientations of each other (they can be up to ~8 cm apart per joint, §2.3). The `Edge`
invariant `*from != *to` (`src/graph.hpp:60`) is only a comment and is never checked, so the port must accept
self-loops. On the DB: exactly one, transition 1225 (§10.3).

Types: `NodeNum` is `uint16_t`, `SeqNum` `uint_fast32_t` (`src/indexed.hpp:57-59`); `num_nodes()` returns `uint16_t`
(`src/graph.hpp:123`) and `num_sequences()` too (`src/graph.hpp:122`), so more than 65535 nodes or sequences would
wrap silently. Far from the DB size (1485 transitions).

**Node data** (`src/graph.hpp:41-52`): `NamedPosition` (position, description, `line_nr`) + `in`, `out`, `in_out`
(§2.6) + `modified` flag (editor). **Edge data** (`src/graph.hpp:54-66`): the `Sequence` (description, positions,
`line_nr`, `detailed`, `bidirectional`) + `from`, `to` + `modified`.

**Empty DB** (§1.7): 0 nodes and 0 edges, no error (`src/graph.cpp:279-302` has nothing to iterate); the file
overload writes an `.index` with only the hash line (`src/persistence.cpp:178-184,230-232`).

### 2.2 Anonymous nodes

A node created by `find_or_add` has an **empty description** and no `line_nr` (`src/graph.cpp:222-233`): its position is
the position passed in, *as is* (not normalized) and the returned reorientation is the identity
(`PositionReorientation{}` = zero offset, angle 0, no swap, no mirror; `src/positions.hpp:79-80`). It is
appended at the end of `nodes`, so anonymous nodes are numbered after the 601 named ones, in order of first
need (§2.4). They are never saved (`save` skips nodes with empty description, `src/persistence.cpp:243-248`; their
edges are written, `src/persistence.cpp:250`). Since they are never saved, their numbering is re-derived on every load
by the matching of §2.3; the index (§2.5) only caches that result.
The DB has 124 anonymous nodes (§10.3).

### 2.3 Matching an endpoint to a node: `is_reoriented`

Two positions are "the same" if one can be moved to the other by a **reorientation**: a rotation about the vertical
axis plus a translation, optionally with **mirror** (left/right) and optionally with **player swap**
(`PositionReorientation{Reorientation{offset, angle}, swap_players, mirror}`, `src/positions.hpp:73-96`,
`src/math.hpp:235-243`).

**Applying a `PositionReorientation` `u` to a position `p`** (`src/positions.hpp:82-88`), in this order:
1. `apply(reorientation, ·)` to every joint: `v' = yrot(angle) · v + offset` (`src/math.hpp:252-255`). With `yrot`
   stored column-major (`src/math.hpp:73-80`) and the product as defined (`src/math.hpp:197-204`):
   `x' = cos(a)·x + sin(a)·z`, `y' = y`, `z' = −sin(a)·x + cos(a)·z`, then `+ offset`.
2. If `mirror`: `Position mirror(p)`: negate `x` of every joint **and** swap the left/right joints of each player
   (shoulder, hip, hand, wrist, elbow, fingers, ankle, toe, heel, knee; Core/Neck/Head do not move)
   (`src/positions.cpp:77-89,130-136`, via `swapLimbs`; `mirror(Joint)`, `src/players.hpp:73-101`, is the equivalent
   per-joint mapping).
3. If `swap_players`: swap player 0 and player 1 (`src/positions.hpp:68-71`).

**`basicallySame(a, b)`** (`src/positions.hpp:49-54`): for every `PlayerJoint` (player 0's 23 joints, then player 1's,
§1.3 order), squared Euclidean distance (`src/math.hpp:190`) ≤ `0.0016` m² (i.e. ≤ 4 cm); the first joint above it
returns false. The test is a strict `>`, so a distance exactly at the threshold passes. Same threshold for all joints (no per-joint radius). Not an equivalence relation (not transitive), so
**the candidate order below decides the result**.

**Precision:** all of this is `double` (`V3 = BasicV3<double>`, `src/math.hpp:34`; `V4`, `src/math.hpp:59`;
`M = std::array<double, 16>`, `src/math.hpp:71`). To agree with the oracle the port must match in f64, not in
raylib's f32.

**`is_reoriented(a, b)` → optional `PositionReorientation u` with `u(a) ≈ b`** (`src/positions.cpp:233-259`). `a` is the
node's stored position, `b` the endpoint to match:

1. **Pre-filter** (`src/positions.cpp:235-241`): `head2head(p) = distanceSquared(p[player0][Head], p[player1][Head])`
   (a *squared* distance in m²). If `|head2head(a) − head2head(b)| > 0.05` → no match. Valid because rotation,
   translation and mirror do not change it (and swap does not either).
2. Try `is_reoriented_without_swap(a, b)` (below). If it finds `u`, return it (`swap_players = false`).
3. Else: swap the players of the **local copy** of `b` (`std::swap(b[player0], b[player1])`,
   `src/positions.cpp:251`), try `is_reoriented_without_swap(a, b)` again, and if it matches set
   `swap_players = true` on the result (`src/positions.cpp:252-253`). Otherwise → no match.

`is_reoriented_without_swap(a, b)` (`src/positions.cpp:213-230`), in this order:
1. `is_reoriented_without_mirror_and_swap(a, b)` → `{r, swap=false, mirror=false}`.
2. else `is_reoriented_without_mirror_and_swap(a, mirror(b))` → `{r, swap=false, mirror=true}`.
3. else no match.

`is_reoriented_without_mirror_and_swap(a, b)` (`src/positions.cpp:198-211`) builds **one** candidate and tests it
(no search, no optimisation, no least squares):
- `a0h, a1h, b0h, b1h` = Head of player 0/1 in `a`/`b`.
- `angleOff = angle(xz(b1h − b0h)) − angle(xz(a1h − a0h))`, with `xz(v) = (v.x, v.z)` (`src/math.hpp:110`) and
  `angle(V2 v) = atan2(v.x, v.y)` (`src/math.hpp:267`; so for `(x, z)` it is `atan2(x, z)`). The difference is
  **not wrapped** (range (−2π, 2π)). Geometry only uses `sin`/`cos` of it, but the raw value is exported
  (`src/js_conversions.cpp:36,182`), so the port must keep it unwrapped, or the oracle comparison must be modulo 2π.
- `r = Reorientation{ offset = b0h − xyz(yrot(angleOff) · V4(a0h, 1)), angle = angleOff }`. So the rotation aligns
  the head-to-head direction in the xz plane and the translation puts player 0's head exactly on `b`'s (**including
  the y component**: there is no separate rule that the offset's `y` be 0; a vertical shift only survives if every
  other joint also stays within the threshold).
- Accept iff `basicallySame(apply(r, a), b)`, else none. Debug asserts that re-check it are compiled out
  (`src/positions.cpp:218,225,256`; `-DNDEBUG`, §1.7).

Consequences phase 2 must reproduce:
- The mirror case compares against `mirror(b)`, and the reported `u` has `mirror = true`; `u(a)` applies the
  rotation first, then the mirror (§above), which is consistent because `mirror` is an involution.
- With the swap, the matched `b` is the swapped copy, but `u.swap_players = true` records it. `mirror(b)` in step 2 is
  taken of the *already swapped* copy in the second pass.
- Order of the four attempts: (no swap, no mirror), (no swap, mirror), (swap, no mirror), (swap, mirror). The first
  that passes `basicallySame` wins; the rest are never evaluated, and the reorientation is *not* the best-fitting one.
- The reorientation is deterministic, computed from the two heads only. It is not stored in the file or the index; it
  is recomputed on every load (§2.5).

**Finding the node: `find_or_add` / `is_reoriented_node`** (`src/graph.cpp:213-241`):
- `is_reoriented_node(p)` scans nodes in index order, `n = 0 … num_nodes()−1`, calling
  `is_reoriented(nodes[n].position, p)` (argument order: **node first**, endpoint second); the first node that
  matches wins and the result is `n * r` (`Reoriented<NodeNum>`; so the edge's `from`/`to` carries `r`, with
  `r(node.position) ≈ endpoint`). No tie-break by distance: with several candidates within the threshold, the one with the lowest
  index is chosen, named nodes before anonymous ones.
- If none matches, `add_new(p)` (§2.2). There is no limit on how many nodes it adds.
- Each call is O(nodes); `find_or_add` is called twice per transition (`from` then `to`), so numbering of anonymous
  nodes is: iterate transitions in file order, endpoint `front` before `back`, and a node is added the first time a
  position matches no existing node (named or anonymous). This fully determines the node numbering, assuming the
  same floating-point results (the original is compiled with `-O3`, no `-ffast-math`, `src/SConstruct:4`; whether
  a result differs on the threshold boundary between machines/compilers is **[unverified]**).
- The match depends on the **order of nodes already in the graph**: the same endpoint can match a different node
  if file order changes, because of the non-transitivity noted above.

**Invariant kept by the original** (`src/graph.hpp:56-58`): `g[edge.from] ≈ edge.positions.front()`, where
`Graph::operator[](ReorientedNode)` is `reorientation(nodes[index].position)` (`src/graph.hpp:114-117`). The edge's
own positions are never replaced by the node's; the reorientation is what lets playback move between the node's
stored position and the edge's frame.

### 2.4 Worked order of construction

For a file with named positions `P0..P600` and transitions `T0, T1, …`:
```
nodes = [P0 .. P600]                       // 2.1 step 1
for each T in file order:
    from = find_or_add(T.front)            // lowest-index node n with is_reoriented(n.pos, T.front), else append anon
    to   = find_or_add(T.back)             // may match the anon node just added for `from`
    edges.push(Edge{from, to, T})
```
`to` can match the node just created for `from` of the same transition, or any other node that `from` also matched;
the `Sequence` invariant (§2.1) does not prevent `from == to` because `basicallySame` is not transitive. Self-loops are
therefore possible even in a DB that respects it (§2.1).

### 2.5 The `.index` cache

Only the **file** overload `loadGraph(string filename)` uses it (`src/persistence.cpp:186-233`). The buffer and
stream overloads (`src/persistence.cpp:154-176`; used by the web editor, `src/editor_canvas.cpp:718`) always rebuild.

**Purpose.** Skip the O(transitions × nodes) matching of §2.3. Not correctness: the index only records which node
each endpoint resolved to.

**File** `<db filename>.index` (e.g. `GrappleMap.txt.index`; generated, git-ignored, absent from the pin: `.gitignore`
lists `GrappleMap.txt.index`):
```
<md5 hex of the DB bytes>\n
<from0> <to0> <from1> <to1> ...        (decimal NodeNum, one pair per transition, separated by single spaces)
```
`writeIndex` writes the 32-char lowercase hex digest (`MD5(db).hexdigest()`, `src/persistence.cpp:195`, `src/md5.cpp:300-311`), `'\n'`,
then for every sequence number in order `from->index`, space, `to->index`, space, so **a trailing space and no final
newline** (`src/persistence.cpp:178-184`). `from`/`to` are node indices; reorientations are *not* stored. Written
with a default `ofstream` (text mode, no check of errors; a failed write is silent).

**Reading** (`src/persistence.cpp:197-211`): open `<filename>.index`; if it opens, read the first line with
`getline`; if it equals the md5 of the DB bytes just read, read `from to` integer pairs with `>>` until extraction fails.
Any other case (missing file, hash mismatch) leaves `connections` empty.

**Use:**
- `connections` non-empty → `Graph(named, transitions, connections)` (`src/persistence.cpp:227-228`,
  `src/graph.cpp:304-348`): named nodes as in §2.1 (same duplicate check); then for transition `i`, endpoint `n =
  index[i].first/second`:
  - `n == num_nodes()` → append a new anonymous node with the endpoint position, identity reorientation;
  - `n < num_nodes()` → `r = is_reoriented(nodes[n].position, p)`; **`abort()` if there is no match**; result `n * r`;
  - `n > num_nodes()` → `abort()` (`src/graph.cpp:315-332`).
  So it skips the search over nodes but still recomputes `r` for the named node; the result equals the no-index
  path **if the index belongs to this DB**, because the same first-match lowest-index node was recorded.
  `index[i]` is not bounds-checked against the number of transitions: an index with fewer pairs than
  transitions reads out of bounds (UB; **[unverified]** runtime effect). With a matching md5 this should not happen (written by the same code
  from the same DB), but a truncated/hand-edited file with the right hash line is trusted.
- `connections` empty → full build (§2.1), then write the index (`src/persistence.cpp:230-232`). This also
  re-creates the file if a stale one is present. The result is returned either way.

**Invalidation:** by hash only (`indexHash == dbhash`); the hash is of the whole DB bytes, so any edit invalidates it. Neither mtime nor
the node/transition counts are consulted. The editor's saved DB is not re-indexed at save time: `save` writes
the DB only (`src/persistence.cpp:235-251`), the next file load rewrites the index.

**Build step:** `grapplemap-indexer GrappleMap.txt` just calls `loadGraph(file)` and discards it
(`src/indexer.cpp:5-17`); the SConstruct rule generates `../GrappleMap.txt.index` from it (`src/SConstruct:58-59`), and the
emscripten builds preload `GrappleMap.txt` and the `.index` into the virtual filesystem
(`src/SConstruct:24,31`); `web_db_loader.cpp:10` then calls the file overload, so the web build gets the cached path.
The `loadGraph` overloads are used by every tool (`src/glfw_editor.cpp:67`, `src/mkpospages.cpp:778`,
`src/dbtojs.cpp:50`, `src/diff.cpp:452-453`, …).

**For the Odin port:** the index is an optimisation of §2.3; reimplementing it is optional. The matching must produce
the same node numbering with or without it. A cached index from the original, if used, must turn into errors (not
`abort()`): `n > num_nodes()`, `is_reoriented` failing for `n < num_nodes()` (`src/graph.cpp:327-328`), and a number
of pairs different from the number of transitions (out-of-bounds `index[i]`, `src/graph.cpp:339-340`). On the DB the cached and uncached paths agree (§10.1): the dump checks that the `.index` pairs equal what `loadGraph(istream)` computes (`index_consistent`), and the indexed constructor recomputes `r` with the same `is_reoriented` (`src/graph.cpp:304-345`); the indexed constructor itself was not run.

### 2.6 `in`, `out`, `in_out`

Computed by `compute_in_out(n)` (`src/graph.cpp:243-277`), called for every node at the end of construction
(`src/graph.cpp:298-299`). Each is a list of `Reversible<SeqNum>` (`{sequence, reverse}`). For node `n`, iterating
sequences `s` in ascending order, and for each `s` in this order:

| Condition | Pushed |
|---|---|
| `s.to == n` | `in += {s, false}`; `in_out += {s, true}` |
| `s.from == n` | `out += {s, false}`; `in_out += {s, false}` |
| `s.bidirectional` and `s.from == n` | `in += {s, true}` |
| `s.bidirectional` and `s.to == n` | `out += {s, true}` |

(`from`/`to` compared by node index only, ignoring the reorientation; `src/graph.cpp:253-269`.) The `in_out` comment
says that `reverse` means "ends in the node", and a transition only appears there in its primary direction
(`src/graph.hpp:45-47`). So the reversed step of a bidirectional transition is in `in`/`out`, not in `in_out`.
Order within a list is by sequence number, and for the same `s` the order above.

### 2.7 `bidirectional` and `detailed`

Both are booleans of the **sequence**, set from `properties:` lines of its description (§1.2): `desc` is searched
with `properties_in_desc` (`src/metadata.cpp:37-54`) when the block is read (`src/persistence.cpp:78,84-85`) and again by
`set_description` (`src/graph.cpp:366-373`). They are never derived from the data, and not stored anywhere else.
Named positions do not have them (`Node` has no such fields, `src/graph.hpp:41-52`); a `properties:` line on a named
position is ignored by the loader.

- **`bidirectional`**: the edge can be traversed backwards. Effects found in the code: reverse steps in `in`/`out`
  (§2.6, `src/graph.cpp:265-269`); `step_by_desc` accepts `{sn, reverse=true}` when `to == from` argument
  (`src/metadata.cpp:74-75`); the editor's selection extension (`src/editor.cpp:194`); `todot` emits `dir="both"`
  (`src/persistence.cpp:338`). 38 in the DB (§1.2). New transitions created in the editor start with both false
  (`src/editor.cpp:355-386`). Not touched by matching: the edge's `from`/`to` are always the file order's front/back, even
  if it is bidirectional.
- **`detailed`**: only affects timing: frames per position are halved in path following
  (`src/paths.cpp:42`: `frames_per_pos / (detailed ? 2 : 1)`); playback and the editor use 10 vs 5 segments per second
  (`src/playback.cpp:130`, `src/editor.cpp:30`); `mkpospages` uses 3 vs 5 frames per position (`src/mkpospages.cpp:126`). Exact use belongs to section 6.
  159 in the DB.

### 2.8 Lookup by description

All case-sensitive exact string comparisons on the **first description line** (`description.front()`), with every
literal `\n` (backslash + `n`) replaced by a space (`replace_all`, boost, all occurrences; `src/util.hpp:70-74`,
`src/metadata.cpp:69,89`). The comparison is **not** normalized otherwise (no trimming or case folding).

`node_by_desc(g, desc)` (`src/metadata.cpp:81-94`):
1. If `desc.size() >= 2`, `desc[0] == 'p'` and the rest is all digits (`all_digits`, `std::isdigit` per `char`,
   `src/util.hpp:83-86`; with a negative (UTF-8) byte that is UB in theory, same pattern in `line_desc`,
   `src/metadata.cpp:101`) → `NodeNum{uint16_t(stoul(desc.substr(1)))}`, **before and instead of** any name lookup, and
   **not range-checked** (a node index ≥ `num_nodes()` is returned as is; `stoul` throws `out_of_range` for numbers
   that do not fit an `unsigned long`; larger than 65535 wraps by the cast). A named position literally called `p12`
   can only be reached by index.
2. Else the first node in index order whose description is non-empty and whose first line (with the replacement)
   equals `desc`; anonymous nodes (empty description) are skipped. Duplicates of the first line are possible (only
   whole-description duplicates are rejected, §2.1): the lowest index wins.
3. Else none.

`step_by_desc(g, desc, from?)` (`src/metadata.cpp:66-79`): scans sequences in index order; candidate if the first
line (with replacement) equals `desc` **or** `desc == "t" + to_string(seq index)`. Note `g[sn].description.front()` is
unconditional here, so a transition with an empty description would be UB (the parser can produce one, §1.7; **[unverified]** runtime effect). Without `from`
(`from` is an optional `NodeNum`) the first candidate is returned as `{sn, false}`. With `from`: returns `{sn, false}` if `edge.from == from`; else
`{sn, true}` if `bidirectional` and `edge.to == from`; else it **continues** with the next candidate.

`named_entity(g, s)` (`src/metadata.cpp:107-124`), used by the editor (`src/editor.cpp:82`,
`src/editor_canvas.cpp:827`) in this order:
1. `"last-trans"` → last sequence (`num_sequences() − 1`; with no transitions the unsigned subtraction wraps).
2. `l<digits>` (size ≥ 2): the first **node** whose `line_nr == N`, then the first **sequence** whose `line_nr == N`.
   If neither matches, **it falls through** to 3 (no early return). `line_nr` semantic is **[unverified]** (§1.4).
3. `step_by_desc` (transitions take priority over nodes), then 4. `node_by_desc` (including `p<N>`), else none.

`readScene` (`src/persistence.cpp:253-298`) uses one description per line with `node_by_desc` first, then `step_by_desc`
with the previous node as `from`; after a node it searches `prev_node.out` for the transition whose target is
that node, `error("could not find transition")` otherwise. The playback/video tools take `--start`/`--demo` through the same two
functions (`src/playback.cpp:71,78`, `src/makevideo.cpp:87,94`).

### 2.9 Mutations that touch matching (editor; for phase 6)

Recorded here because they use the matching of §2.3; full editor behaviour is section 9.
- `Graph::set` (insert/replace/erase a transition): rejects a sequence whose ends are reorientations of each other;
  `find_or_add` on both ends; recomputes `in/out` for the two nodes (for an erase, for all nodes)
  (`src/graph.cpp:130-167`). On a replace only the new `from`/`to` are recomputed (`src/graph.cpp:146-158`): the old
  endpoints of the replaced edge keep stale `in/out` lists. An anonymous node that loses all its edges **stays** (nodes are never deleted).
- `Graph::replace` with `NodeModifyPolicy` (`src/graph.cpp:18-108`): `propagate` rewrites the node's position (as the inverse
  reorientation of the edit) and every edge end attached to it; `local` re-matches (`is_reoriented` against the old node, else `find_or_add`);
  `unintended` asserts it is still a reorientation. The asserts vanish with `NDEBUG`; for `unintended` an empty `reo`
  is then dereferenced (`src/graph.cpp:70-73`), UB (**[unverified]** runtime effect).
- `Graph::erase` of a frame re-matches the new endpoint with `find_or_add` (`src/graph.cpp:169-211`).
- Description edits of a node: `set_description(NodeNum, …)` (`src/graph.cpp:357-364`).

### 2.10 Open points (need the oracle/dumper)

Answered in §10 (§10.3 unless noted): number of anonymous nodes (124), self-loops (one), equality of indexed and non-indexed loads (agree, §10.1, §2.5). Still open (not verifiable by reading, not in the dump; the `line_nr` offset of §1.4 is confirmed by the dumper, `tools/oracle/README.md`): whether any pair of named positions or transition ends are reorientations
of each other; whether any DB endpoint is within the threshold of two nodes (so that order matters);
floating-point boundary cases of `basicallySame`.

---

## 3. Player model

### 3.1 Joints

`enum Joint: uint32_t` lists 23 joints through the `JOINTS` macro (`src/players.hpp:8-21`); `joints[]` is the same list
(`src/players.hpp:23`) and `joint_count = 23` is its size (`src/players.hpp:29`). Display names are `to_string(Joint)`
(`src/positions.cpp:33-63`). Per-joint data is `JointDef{joint, radius, draggable}` (`src/players.hpp:69`), table
`jointDefs` (`src/positions.cpp:7-31`), stored in enum order (`PerJoint<T> = array<T, joint_count>`, `src/players.hpp:61`).

| # | `Joint` | `to_string` | `radius` (m) | `draggable` | `mirror` |
|---|---|---|---|---|---|
| 0 | LeftToe | left toe | 0.025 | false | RightToe |
| 1 | RightToe | right toe | 0.025 | false | LeftToe |
| 2 | LeftHeel | left heel | 0.03 | false | RightHeel |
| 3 | RightHeel | right heel | 0.03 | false | LeftHeel |
| 4 | LeftAnkle | left ankle | 0.03 | true | RightAnkle |
| 5 | RightAnkle | right ankle | 0.03 | true | LeftAnkle |
| 6 | LeftKnee | left knee | 0.05 | true | RightKnee |
| 7 | RightKnee | right knee | 0.05 | true | LeftKnee |
| 8 | LeftHip | left hip | 0.09 | true | RightHip |
| 9 | RightHip | right hip | 0.09 | true | LeftHip |
| 10 | LeftShoulder | left shoulder | 0.08 | true | RightShoulder |
| 11 | RightShoulder | right shoulder | 0.08 | true | LeftShoulder |
| 12 | LeftElbow | left elbow | 0.045 | true | RightElbow |
| 13 | RightElbow | right elbow | 0.045 | true | LeftElbow |
| 14 | LeftWrist | left wrist | 0.02 | false | RightWrist |
| 15 | RightWrist | right wrist | 0.02 | false | LeftWrist |
| 16 | LeftHand | left hand | 0.02 | true | RightHand |
| 17 | RightHand | right hand | 0.02 | true | LeftHand |
| 18 | LeftFingers | left fingers | 0.02 | false | RightFingers |
| 19 | RightFingers | right fingers | 0.02 | false | LeftFingers |
| 20 | Core | core | 0.1 | true | Core |
| 21 | Neck | neck | 0.05 | false | Neck |
| 22 | Head | head | 0.11 | true | Head |

Notes:
- Left/right alternate, so `mirror(j)` (`src/players.hpp:73-101`) swaps indices `2k ↔ 2k+1` for `k < 10` and fixes
  20-22. `mirror(Position)` uses the explicit `swapLimbs` instead (`src/positions.cpp:77-89,130-136`), same mapping (§2.3).
- `radius` is used for the joint spheres, pillar ends and fat triangles when drawing (`src/playerdrawer.cpp:117-119,137-139,269,298,323-328`), and as
  the minimum `y` of each joint in `apply_limits` and `spring` (`src/positions.cpp:177,318`): joints rest *on* the floor,
  not through it.
- `draggable` is declared but **read nowhere** in the C++ (grep of `src/` finds only `src/players.hpp:69`). Which joints
  the editor lets you drag: any (the grabbed joint is the nearest to the cursor, §9.1-9.2).
- `jointDefs[j].joint` repeats the enum value; it is not used for lookup (the table is indexed by position).

### 3.2 Segments (`limbs()`)

`Limb{ends[2], length, midpointRadius (optional, m), visible}` (`src/players.hpp:118-124`); the table is the static
array in `limbs()` (`src/players.hpp:126-167`), 28 entries in this order (one commented-out shoulder-to-shoulder limb,
`src/players.hpp:155`, is not part of it):

| # | ends | length (m) | mid radius (m) | visible |
|---|---|---|---|---|
| 0 / 12 | L/R Toe – L/R Heel | 0.23 | — | yes |
| 1 / 13 | L/R Toe – L/R Ankle | 0.18 | — | no |
| 2 / 14 | L/R Heel – L/R Ankle | 0.09 | — | no |
| 3 / 15 | L/R Ankle – L/R Knee | 0.43 | 0.055 | yes |
| 4 / 16 | L/R Knee – L/R Hip | 0.43 | 0.085 | yes |
| 5 / 17 | L/R Hip – Core | 0.27 | — | no |
| 6 / 18 | Core – L/R Shoulder | 0.37 | — | no |
| 7 / 19 | L/R Shoulder – L/R Elbow | 0.29 | — | yes |
| 8 / 20 | L/R Elbow – L/R Wrist | **0.26 / 0.27** | 0.03 | yes |
| 9 / 21 | L/R Wrist – L/R Hand | 0.08 | — | yes |
| 10 / 22 | L/R Hand – L/R Fingers | 0.08 | — | yes |
| 11 / 23 | L/R Wrist – L/R Fingers | 0.14 | — | no |
| 24 | LeftHip – RightHip | 0.23 | — | no |
| 25 | LeftShoulder – Neck | 0.175 | — | no |
| 26 | RightShoulder – Neck | 0.175 | — | no |
| 27 | Neck – Head | 0.165 | 0.05 | yes |

Rows `a / b` are the left limb (indices 0-11, `src/players.hpp:129-140`) and the right one (12-23,
`src/players.hpp:142-153`), with identical values except the forearm: **left 0.26, right 0.27**
(`src/players.hpp:137,150`). This asymmetry is in the code; reproduce it.

How the fields are used:
- `apply_limits` (`src/positions.cpp:314-322`) is called by `Graph::replace` on every write (`src/graph.cpp:20`) and by
  `spring(Position&)` (`src/positions.cpp:185`); loading does not clamp.
- `length`: only by `spring` (`src/positions.cpp:142-181`), the editor's relaxation that pulls joints toward the
  nominal lengths. Positions in the DB are **not** constrained to these lengths; playback and drawing never read
  `length`.
- `visible` and `midpointRadius`: only by drawing (`src/playerdrawer.cpp:305-360`). A visible limb is a pillar from
  `radius(a)` to `radius(b)`; with a mid radius it is two pillars `a → mid → b`, `mid` the midpoint of the ends, radii
  `radius(a) → midpointRadius → radius(b)` (`src/playerdrawer.cpp:320-328`). Invisible limbs are skipped. In first
  person, the limb ending at `Head` of that player is skipped (`src/playerdrawer.cpp:318`). The rest of the body
  (triangles between joints, colors, lighting) is section 7.
- The torso is not a limb: Hip–Core, Core–Shoulder and Shoulder–Neck are invisible; what the torso looks like comes from
  the triangles of `playerdrawer.cpp` (section 7).

**JS viewer diverges.** `src/gm.js:59-88` (`segments`) and `src/gm.js:92-116` (`joints`) are a hand-kept copy ("should
be in-sync", `src/gm.js:89,117`) that is **not** in sync: every segment has a mid radius, several invisible C++ limbs
are visible there (toe–ankle, heel–ankle, hip–core, core–shoulder, shoulder–neck), and `Core` is not draggable
(`src/gm.js:113`). The fidelity target of this project is the C++ table above; which renderer the golden images follow
is decided with section 7.

The JS viewers render with Babylon.js and no `useRightHandedSystem` appears in `src/*.js` (grep); Babylon's default is
left-handed, so the JS view may be mirrored relative to the C++ one (**[unverified]**: Babylon's docs not checked;
for section 7 / ADR 0004).

### 3.3 Players

- `PlayerJoint{PlayerNum player; Joint joint}` (`src/players.hpp:40`, `operator==` at `src/players.hpp:42-45`)
  addresses one joint of one player.
- `PlayerNum` is an index of type `uint_fast8_t` (`src/indexed.hpp:61`); `player0 = {0}`, `player1 = {1}`
  (`src/players.hpp:31-32`), `opponent(p) = 1 − p` (`src/players.hpp:38`).
- `playerCode(p) = "tb"[p]`: player 0 is **t** (top), player 1 is **b** (bottom) (`src/players.hpp:36`). The function
  itself is not called in the C++ (grep); the top/bottom meaning lives on in the `top`/`bottom` properties (§1.2).
- Colors: `playerDefs = {red, {0.15, 0.15, 1}}` (`src/positions.cpp:140`), `red = {1, 0, 0}` (`src/math.hpp:62`):
  player 0 red, player 1 blue.
- `Position = PerPlayerJoint<V3>` (`src/positions.hpp:9`) = `PerPlayer<PerJoint<V3>>` (`src/players.hpp:103-110`):
  `values[2][23]` of `V3` (doubles), indexed `p[player][joint]` or `p[PlayerJoint{player, joint}]`. A `Player` is one
  `PerJoint<V3>` (`src/players.hpp:169`).
- `playerJoints` is the 46 `PlayerJoint`s, player 0's 23 joints in enum order then player 1's
  (`src/positions.cpp:65-73,138`); it is the iteration order of the encoder/decoder (§1.3), `basicallySame` (§2.3) and
  drawing of joints (`src/playerdrawer.cpp:254,282`).
- `swap_players(p)` swaps the two `Player`s wholesale (`src/positions.hpp:68-71`); no coordinate changes.

## 4. Units and axes

### 4.1 Units

- **Lengths are meters.** The code says so for `midpointRadius` (`src/players.hpp:122`); limb lengths (0.43 m shin and
  thigh, `src/players.hpp:132-133`) and the encoding range (§1.3) are consistent with it. There is no scale factor
  between file values and world coordinates: the decoder writes the values straight into `V3` (`src/persistence.cpp:53`).
- **Angles are radians**, used through `cos`/`sin`/`atan2` (`src/math.hpp:73-80,267`). Exception: `perspective` takes
  `fovy` in **degrees** (`fovy*pi()/360` is the half angle, `src/math.hpp:116-118`).
- **`pi()` is `3.141593`, not π** (`src/math.hpp:12`). It is used for the camera's pitch clamp
  (`src/camera.hpp:61-62`) and the projection (`src/math.hpp:118`), among others; a port that wants bit-level agreement
  must use the same constant there (other uses: section 7).
- All values are `double` (§2.3, *Precision*).

### 4.2 Axes and handedness

- **`y` is vertical, up.** The floor is the plane `y = 0`: the grid is drawn at `y = 0` with normal `(0, 1, 0)`
  (`src/rendering.cpp:249-262`), `apply_limits` keeps every joint at `y ≥ radius` (`src/positions.cpp:318`), the
  encoding gives `y ∈ [0, 3.843]` with no offset (§1.3), and every reorientation rotates about `y` only (`yrot`,
  `src/math.hpp:73-80`; §2.3).
- **Horizontal plane `xz`**, centered on the origin: encoding gives `x, z ∈ [−2, 1.843]` (§1.3) and `apply_limits`
  clamps `x, z` to `[−2, 2]` (`src/positions.cpp:319-320`). `xz(v) = (v.x, v.z)` (`src/math.hpp:110`) and
  `y0(V2) = (v.x, 0, v.y)` (`src/math.hpp:40`): a `V2` "xz" value keeps `z` in its `.y` field.
- **Mirror is `x ↦ −x`** (`mirror(V3)`, `src/positions.hpp:36`), plus left/right joint swap (§2.3).
- **Right-handed**, derived as follows (no assumption about OpenGL defaults beyond the documented fixed pipeline):
  1. Matrices `M` are column-major: `translate` puts the offset in `m[12..14]` (`src/math.hpp:91-98`) and
     `M * V4` reads `m[0], m[4], m[8], m[12]` for `x` (`src/math.hpp:197-204`); they are loaded unchanged with
     `glLoadMatrixd` (`src/rendering.cpp:341-354`), which expects column-major (OpenGL spec, not code). The shader
     editor passes the same matrices through `to_glm` (`src/editor_canvas.cpp:331-338`, columns in order) and
     `glUniformMatrix4fv(…, GL_FALSE, …)` (`src/editor_canvas.cpp:565`): same layout, no flip in either renderer.
  2. `perspective` is the `gluPerspective` matrix (`m[11] = −1`, so `w = −z_eye`; visible points have `z_eye < 0`)
     (`src/math.hpp:116-125`): OpenGL's right-handed eye space, camera looking down `−z`, `x` right, `y` up.
  3. The model-view is `translate(0, 0, −zoom) · xrot(pitch) · yrot(yaw) · translate(−offset)`
     (`src/camera.hpp:18`): only rotations and translations, no `glScale` or axis flip anywhere in `src/` (grep of
     `glScale`). A product of rotations keeps handedness, so world coordinates are right-handed too.
  4. With `yaw = 0` the camera looks toward world `−z` (tilted down by the pitch), with world `+x` to the right of the
     screen and `+y` up.
- **Rotation sign.** `yrot(a)` gives `x' = cos a·x + sin a·z`, `z' = −sin a·x + cos a·z` (§2.3): the standard
  right-handed rotation by `+a` about `+y` (it takes `+z` toward `+x`). `angle(V2{x, z}) = atan2(x, z)`
  (`src/math.hpp:267`) measures from `+z` toward `+x`, so `angle(xz(yrot(a)·v)) = angle(xz(v)) + a` (mod 2π): `yrot` and
  `angle` share the same sign.
- `xrot(a)` (`src/math.hpp:82-89`) gives `y' = cos a·y + sin a·z`, `z' = −sin a·y + cos a·z`, i.e. the standard
  rotation by **`−a`** about `+x`. With the default `orientation = {0, −0.6, 1.7}` (yaw, pitch, zoom;
  `src/camera.hpp:12-13`) the eye sits at `offset + (0, 1.7·sin 0.6, 1.7·cos 0.6) ≈ offset + (0, 0.96, 1.40)`: above and
  on the `+z` side, looking down at `offset` (algebra on `src/camera.hpp:18`). Confirmed on screen by the oracle images
  (`tools/oracle/README.md` "Reference images", "Camera orientation"): the heading-N views (`yaw = 0`) show world `+x` to
  the right and the eye on the `+z` side. In `p96-480x360.png` player 0's head (world `x = 0.22`, `y = 0.98`) has its top
  pixel at column ≈286, right of the centre (240) and at row 105, while player 1's head (`x = 0.00`, `y = 1.27`) is at
  column ≈239 and row 44; in `p267-480x360.png` player 1, the nearer to `+z` (mean `z = +0.21` against `−0.34`), is in the
  foreground, at the bottom of the image. The rest of the camera (fov, near/far, controls, smoothing) is section 7.

### 4.3 `heading`, `normalRotation`, `center`, `cameraOffsetFor`

All in `src/positions.hpp`; all use the two players' **`Core`**, except the matching of §2.3 and the canonical mirror test below, which use
`Head`.

| Function | Definition | Lines |
|---|---|---|
| `heading(p)` | `xz(p[1][Core] − p[0][Core])`: `V2` from player 0's core to player 1's, in `xz` | `src/positions.hpp:132-135` |
| `normalRotation(p)` | `−angle(heading(p)) = −atan2(h.x, h.z)` | `src/positions.hpp:137-140` |
| `center(p)` | midpoint of the two cores, a `V3` (keeps `y`) | `src/positions.hpp:142-145` |
| `xzCenter(p)` | `xz(center(p))` | `src/positions.hpp:147-150` |
| `normalTranslation(p)` | `y0(−xzCenter(p))`: moves the center to `x = z = 0`, `y` untouched | `src/positions.hpp:169` |
| `cameraOffsetFor(p)` | midpoint of the cores with `y = max(0, y − 0.5)` | `src/positions.hpp:182-187` |

Meaning (from §4.2's sign rule): `yrot(normalRotation(p))` turns `heading` to angle 0, i.e. after it **player 1's core
is on the `+z` side of player 0's**. `normalRotation` is not wrapped: `atan2` gives `(−π, π]`, so the result is in
`[−π, π)`; with both cores at the same `xz`, `atan2(0, 0) = 0` (C library behaviour, **[unverified]** for `−0`
inputs).

Users:
- **Canonical orientation** (`src/positions.cpp:261-291`): angle `normalRotation(p)`, offset
  `normalTranslation(rotate(angle, p))` (center computed *after* rotating). `canonical_reorientation_with_mirror` also
  sets `mirror = (apply(reo, p)[player1][Head].x ≥ 0)` (`src/positions.cpp:267`): the canonical form puts player 1's
  head at `x ≤ 0`: `x > 0` becomes `x < 0`, and `x = 0` is mirrored to `−0.0` (still 0; `−0.0 ≥ 0` is true, so
  canonicalising again mirrors again). Who calls these is section 5.
- **`translateNormal`** (`src/positions.hpp:171-174`): translation only, used for the first/last frames of
  transitions in the position pages (`src/mkpospages.cpp:500,528`).
- **`cameraOffsetFor`**: the camera target in the playback and video tools: `hardSetOffset` on the first frame, then
  `setOffset` every frame (`src/glfw_playback.cpp:47,72`, `src/makevideo.cpp:116,123`), which smooths as
  `offset = 0.97·offset + 0.03·target` (`src/camera.hpp:46-50`). The editor does **not** use it: it targets `center`
  with `y *= 0.7` when no joint is chosen and not playing back (`src/editor_canvas.cpp:539-544`; the GLFW editor
  also requires not being in edit mode, `src/glfw_editor.cpp:526-531`). The position images use neither:
  `ImageMaker::png` with a heading view (`src/images.cpp:340-370` → `302-313`, called by `mkpospages`,
  `src/mkpospages.cpp:584-587`) sets the target outright to `{0, ymax − 0.57, 0}` (`hardSetOffset`) and then
  *adds* to the default orientation `{yaw 0, pitch −0.6, distance 1.7}` (`src/camera.hpp:12,52-70`): distance
  `+= 0.55`, yaw `+= angle(heading) = pi()·0.5·heading` (`src/headings.hpp:65-68`), pitch `+= (ymax − 0.6)/2`
  (clamped to `±pi()/2`); fov 45 (`src/images.cpp:309-315`). Player views are first-person (`src/rendering.cpp:345-352`).
  Frame rate and the rest of the camera: section 7.

### 4.4 Input for ADR 0004 (mapping to raylib)

What the port has to preserve, independent of the target convention:
- Meters, `y` up, floor `y = 0`, right-handed world, mirror = `x ↦ −x`, rotations about `y` with the sign of
  `yrot`/`angle` above; f64 in `core` (§2.3).
- The constants that depend on axes: encoding offsets on `x`/`z` only (§1.3), `apply_limits` box, `cameraOffsetFor`'s
  `−0.5` on `y`, the editor's `0.7` on `y`, `pi() = 3.141593`.

Mapping to raylib: **pending, ADR 0004**. Not checked here (this section reads only the original). The question for
the ADR is whether raylib's world/eye convention matches the one derived in §4.2 (right-handed, `y` up, eye looking
down `−z`); if it does, the original's coordinates can be used as-is with no axis swap or flip, and only `f64 → f32` at
the render boundary remains. That must be verified in raylib's code or docs in the ADR, not assumed.

### 4.5 Open points (need the oracle/dumper)

Not verifiable by reading: `normalRotation` with both cores at the same `xz` and `−0` inputs (§4.3); whether the JS viewer is mirrored (§3.2).
`normalRotation`'s `atan2` bits were measured in #140: the oracle's `atan2` is correctly rounded, Odin's is not; see ADR 0003, "Open points".

## 5. Transforms

Notation used below: `R(a) = yrot(a)` (rotation about `+y`, sign as in §4.2), `F = diag(−1, 1, 1)` (negate `x`),
`L` = the left/right joint permutation of §2.3, `S` = swap the two players. A position is 46 `V3` (§1.3); every
transform here acts joint by joint, so the joint permutations (`L`, `S`) commute with each other and with any per-joint
map (`R`, `F`, translation). All arithmetic is `double` (§2.3, *Precision*).

### 5.1 `mirror`

- `mirror(V3 v) = {−v.x, v.y, v.z}` (`src/positions.hpp:36`): `F`, a reflection in the plane `x = 0` **of the world**,
  not about the position's center.
- `mirror(Position p)` (`src/positions.cpp:130-136`): applies `F` to every joint of both players, then `swapLimbs` on
  player 0 and on player 1 (`src/positions.cpp:77-89`): ten `std::swap`s of the Left/Right pairs (Shoulder, Hip, Hand,
  Wrist, Elbow, Fingers, Ankle, Toe, Heel, Knee); `Core`, `Neck`, `Head` stay. So `mirror = L ∘ F` (`= F ∘ L`).
  Players are **not** swapped.
- `mirror(Joint)` (`src/players.hpp:73-101`) is the same permutation as an index map (`default: return j` for the three
  center joints); it is used to look up a single joint without building the whole position (§5.3).
- Involution: `mirror(mirror(p)) == p` **bit for bit** (negation is exact and the swaps are permutations).
- What it preserves: all pairwise distances (so `head2head`, §2.3, and limb lengths, §3.2); `y` of every joint. What it
  changes: `heading(mirror(p)).x = −heading(p).x`, so `angle` and `normalRotation` change sign (§4.3; exact if `atan2(−y, x) == −atan2(y, x)` in the libm used, §5.7); `center.x`
  changes sign.

### 5.2 `swap_players`

- `swap_players(Position & p)`: `std::swap(p[player0], p[player1])` (`src/positions.hpp:68-71`), in place: `S`. Exact,
  an involution, preserves every coordinate (only the player index changes).
- `heading(S(p)) = −heading(p)`: `normalRotation` changes by ±π (§4.3); `center` is bit-identical
  (`(a + b)/2` vs `(b + a)/2`: IEEE addition is commutative).
- `PlayerJoint`-level version: `opponent(pj.player)` (`src/positions.hpp:111`).

### 5.3 `Reorientation` and `PositionReorientation`

**`Reorientation{offset, angle}`** (`src/math.hpp:235-243`, defaults `{0,0,0}` and `0`): a rotation about the vertical
axis followed by a translation.
- `apply(r, v) = (yrot(r.angle) * v) + r.offset` (`src/math.hpp:252-255`), i.e. `r(v) = R(θ)·v + o`. Rotation
  **first**, then translation. `yrot(a) * v` goes through `M * V4(v, 1)` (`src/math.hpp:206-209,197-204`), so the
  evaluated expression is, for `x`: `((m[0]·x + m[4]·y) + m[8]·z) + m[12]` with `m[0] = cos a`, `m[4] = 0`,
  `m[8] = sin a`, `m[12] = 0` (`src/math.hpp:73-80`), then `+ o.x`. The `0·y` and `+0` terms are kept by the compiler
  (no `-ffast-math`, `src/SConstruct:4`); they only matter for the sign of zero results, but a bit-exact port should
  evaluate the same terms in the same order, **without FMA contraction** (each `*` and `+` rounded separately: the
  original targets generic x86-64, which has no FMA; the oracle enforces it, `tools/oracle/Dockerfile:32-33,50-54`).
- Applied to a position, `apply(r, p)` maps every joint (`src/positions.hpp:62-66`).

**`PositionReorientation{reorientation, swap_players, mirror}`** (`src/positions.hpp:73-96`; the comment at line 77:
mirror is a separate flag because it needs the left/right swap). Write it `u = {r, s, m}`.
- On a position, `u(p)` applies, in this order (`src/positions.hpp:82-88`): `apply(r, ·)`, then `mirror` if `m`, then
  `swap_players` if `s`:

  `u(p) = S^s ∘ (L∘F)^m ∘ r (p)`.

  Mirror is therefore applied **after** the rotation and translation, about the world plane `x = 0`, not about the
  rotated position's center.
- On a single `V3`, `u(v)` = `apply(r, v)` then `F` if `m`; the swap is ignored because it has no meaning for a point
  (`src/positions.hpp:90-95`).
- On a `PlayerJoint` index, `apply(u, pj)` maps `joint ↦ mirror(joint)` if `m` and `player ↦ opponent(player)` if `s`
  (`src/positions.hpp:107-114`). `apply(u, p, j)` returns `u(p)[j]` without building `u(p)`:
  `F^m(apply(r, p[apply(u, j)]))` (`src/positions.hpp:116-125`; the `assert` that compares it with `u(p)[j]` is
  compiled out, §1.7). Note that `apply(u, ·)` on an index is its own inverse (both maps are involutions), which is
  why the same map serves for "where does joint `j` of `u(p)` come from".
- The identity is `{{0,0,0}, 0, false, false}` (the constructor's defaults, `src/positions.hpp:79-80`); `u(p)` with it
  is **not** bit-identical to `p` in general (it computes `cos 0·x + 0·y + sin 0·z + 0 + 0`, which only differs for
  `−0` inputs: `−0 + 0 = +0`).

**Mirror conjugation.** Because `F·R(θ)·F = R(−θ)` (from the matrix of §2.3), for any `r = {o, θ}`:
`F ∘ r = mir(r) ∘ F` with `mir(r) = {(−o.x, o.y, o.z), −θ}`. And `L`, `S` commute with every per-joint map. This is the
only fact needed to derive §5.4; it is exactly the "negate `angle` and `offset.x`" that the code does.

### 5.4 `compose` and `inverse`

**On `Reorientation`** (both marked `// formalized` in the source):
- `inverse(x) = {yrot(−x.angle) * −x.offset, −x.angle}` (`src/math.hpp:257-260`): `r⁻¹ = {R(−θ)·(−o), −θ}`. Check:
  `r⁻¹(r(v)) = R(−θ)(R(θ)v + o) − R(−θ)o = v` (exact in reals; in `double`, `R(−θ)R(θ)` is not the identity bit for
  bit).
- `compose(a, b) = {b.offset + (yrot(b.angle) * a.offset), a.angle + b.angle}` (`src/math.hpp:262-265`). It means
  **"first `a`, then `b`"**: `compose(a, b)(v) = b(a(v))`, since `b(a(v)) = R(θb)(R(θa)v + oa) + ob`. Caveats for bit
  equality: the angle is the plain sum `θa + θb` (**not wrapped**; it can grow past ±2π after many compositions), and
  `R(θa + θb)` is not bit-equal to `R(θb)·R(θa)`, so `compose(a, b)(v)` and `b(a(v))` agree only up to rounding.
  Only the angle sum and the offset formula above are what the port must reproduce exactly.

**On `PositionReorientation`** (`src/positions.cpp:97-128`):
- `inverse(u)` (`src/positions.cpp:97-109`): `{inverse(r), s, m}`, and if `m`, then `angle = −angle` and
  `offset.x = −offset.x`. I.e.

  `inverse({r, s, m}) = {mir^m(r⁻¹), s, m}`.

  Derivation: `u⁻¹ = r⁻¹ ∘ (L∘F)^m ∘ S^s`; moving `r⁻¹` to the right of `F` turns it into `mir(r⁻¹)`; `S` and `L`
  commute. Explicitly, with `m = true`: angle `+θ`, offset `F·R(−θ)·(−o)`. The flags `s` and `m` are kept as they are
  (both are involutions). A debug `assert` checking `r(x(testPos)) ≈ testPos` is commented out
  (`src/positions.cpp:106`), and `testPos` itself is commented out (`src/positions.cpp:91-93`).
- `compose(a, b)` (`src/positions.cpp:111-128`; marked `// todo: formalize`): take `b.r`; if `a.m`, replace it by
  `mir(b.r)`; then

  `compose(a, b) = {compose(a.r, mir^{a.m}(b.r)), a.s ≠ b.s, a.m ≠ b.m}`.

  Same order as on `Reorientation`, **"first `a`, then `b`"**: `compose(a, b)(p) = b(a(p))` (the commented-out
  `assert(basicallySame(b(a(testPos)), r(testPos)))`, `src/positions.cpp:125`, states the intent). Derivation:
  `b ∘ a = S^{bs} M^{bm} b.r ∘ S^{as} M^{am} a.r` with `M = L∘F`; moving `b.r` right past `M^{am}` gives
  `mir^{am}(b.r)`; the flags combine by XOR because `S` and `M` are commuting involutions. Note it is `a.mirror`
  that conjugates `b`'s reorientation, not `b.mirror`.
- Not provided: an identity check, equality, or normalisation of the angle. `inverse(inverse(u))` equals `u` only up to
  rounding in the offset (the angle and flags round-trip exactly, since `−(−θ) = θ`).

**How the graph uses them** (the semantics phase 2 must keep; detail of traversal is section 6):
- A `Reoriented<T>` is a value plus a `PositionReorientation` (`src/reoriented.hpp:9-26`; `x * r` builds one). Reading
  a position through it applies the reorientation: `g[ReorientedNode] = u(node.position)` (`src/graph.hpp:114-117`),
  `at(Reoriented<PositionInSequence>) = u(at(pis))` and per joint `apply(u, p, j)` (`src/graph_util.hpp:265-278`).
- Edge endpoints: `edge.from = n * Ef` with `Ef(nodes[n].position) ≈ positions.front()` (§2.3). Viewing a sequence
  through `u` gives its endpoint nodes with `compose(Ef, u)` (`src/graph_util.hpp:145-155`), i.e. "edge's own
  reorientation first, then the view's", so `compose(Ef, u)(node) ≈ u(front)`.
- Walking from a node `n` (viewed with `N`) into a sequence `s` whose `from` is `n * Ef`:
  `compose(inverse(Ef), N)` maps the sequence's frame to the viewer's (`src/graph_util.cpp:67,132,239`),
  and the node reached at the other end `to = m * Et` is viewed with `compose(Et, compose(inverse(Ef), N))`
  (`src/graph_util.cpp:81,117-119`; symmetric for entering by `to`, `src/graph_util.cpp:85,99,122-124,134,241`).
- Editing through a view writes back with `inverse`: `node.position = inverse(u)(p)` (`src/graph.cpp:44`),
  `graph.replace(…, inverse(location.reorientation)(…))` (`src/editor.cpp:347,400`).
- The editor's **mirror view** (`Editor::mirror`, `src/editor.cpp:212-217`, key `I` in the GLFW editor,
  `src/glfw_editor.cpp:141`) just flips the `mirror` flag of the current location and of the selection; by the order in
  §5.3 that is `M ∘ u` (mirror of what was shown, about `x = 0`), and it does not change any stored position
  (`src/editor.hpp:52`). By contrast `swap_players(Editor&)` and `mirror_position` change the stored keyframe
  (`src/editor.cpp:240-265`; keys `X` / `M`, `src/glfw_editor.cpp:134-135`). Editor detail: section 9.
- Known imprecision in the original: `do_edit` composes a camera-only reorientation and notes it ignores
  `swap_players` (`src/glfw_editor.cpp:380-382`, `// todo: this is wrong`). Not to be "fixed" silently in a port;
  §9.2.

### 5.5 Canonical orientation

`canonical_reorientation_without_mirror(p)` (`src/positions.cpp:272-281`) builds `u = {r, false, false}` with:
1. `r.angle = normalRotation(p) = −atan2(h.x, h.z)`, `h = heading(p)` (§4.3, uses the **cores**).
2. `r.offset = normalTranslation(rotate(r.angle, p)) = y0(−xz(center(R(θ)·p)))` (`src/positions.hpp:159-169`):
   the center of the **already rotated** position, negated, with `y = 0`. `rotate` is `yrot(a) * v` per joint, the
   same arithmetic as `apply` with a zero offset.

`canonical_reorientation_with_mirror(p)` (`src/positions.cpp:261-270`): same `r`, `swap_players = false`, and
`mirror = (apply(r, p)[player1][Head].x ≥ 0)`, evaluated on the rotated-and-translated position **before** mirroring.

`orient_canonically_without_mirror(p)` / `…_with_mirror(p)` = `canonical_reorientation_…(p)(p)`
(`src/positions.cpp:283-291`).

What is fixed in the result (exact in reals; in `double` up to rounding, so "≈ 0" below):
- **Center:** `xz(center) ≈ (0, 0)`; `center.y` unchanged (no vertical translation).
- **Heading:** `heading` points along `+z` (`angle ≈ 0`): player 1's core in front of player 0's on `+z` (§4.3).
- **With mirror:** additionally player 1's **head** has `x ≤ 0` (`x > 0` before the test → mirrored to `< 0`;
  `x == 0`, including `−0.0`, also mirrors, §4.3). Mirroring keeps the center at `x ≈ 0` and the heading on `+z`
  (`F` maps `(0, z)` to `(−0, z)`), so both properties above still hold after the mirror.
- **Never swaps players**: `swap_players = false` in both (`src/positions.cpp:266,277`; the
  `assert(!reo.swap_players)` in `src/mkpospages.cpp:662` is compiled out, §1.7). Which player is 0 is never
  canonicalised: `orient_canonically_without_mirror(S(p)) ≈ S(R(π)·orient_canonically_without_mirror(p))` (rotated by
  π **and** with the player labels swapped). With mirror, the test then reads the *other* player's head
  (`−x` of player 0's head in `p`'s canonical form), a decision independent of `p`'s, so the two `with_mirror` forms
  may additionally differ by a mirror. Callers that want a fixed player order swap first themselves:
  `mkpospages` swaps every frame when the transition's `from.reorientation.swap_players` is set, then canonicalises
  the first frame (`src/mkpospages.cpp:430-435`).

Tie-breaks and degenerate cases:
- The only discrete choice is the mirror test, with `≥ 0` (head exactly on the plane → mirrored). There is no other
  tie-break; the angle comes from a single `atan2`.
- Both cores at the same `xz`: `heading` is a component-wise subtraction (`src/math.hpp:135`). If the cores'
  coordinates are **bit-identical**, `x − x = +0` (IEEE 754 round-to-nearest), so `heading = (+0, +0)`,
  `atan2(+0, +0) = +0` and there is no rotation. This covers every position decoded from the file, which never holds
  `−0` (`g() − 2` with `g() ≥ +0`, `src/persistence.cpp:45-53`). A reoriented input (e.g. the `mkpospages` frames,
  which go through `inverse(…)` and `yrot` first, `src/mkpospages.cpp:433,675,711`) can hold `+0` in one core and
  `−0` in the other: `(−0) − (+0) = −0`, so `heading` can be `(−0, −0)`, `atan2(−0, −0) = −π` and the position is
  rotated by π. **[unverified]** at runtime, as in §4.3/§4.5.
- The heading uses `Core` but the mirror test uses `Head`; a position where player 1's head is near `x = 0` flips
  between mirrored and not under tiny edits.

Users: only the web/position-page tools. `orient_canonically_with_mirror` for the position page heading image
(`src/mkpospages.cpp:578`), `canonical_reorientation_with_mirror` for transition GIFs (`src/mkpospages.cpp:433`) and for
the incoming/outgoing frames of a node page (`src/mkpospages.cpp:661,675,711`, applied after
`inverse(this_side.reorientation)` brings each frame to the node's own frame). Neither the graph loader nor matching
(§2.3) use canonical orientation. `canonical_reorientation_without_mirror` is called only by
`orient_canonically_without_mirror` (`src/positions.cpp:285`), which has no caller in `src/` (grep).

### 5.6 Input for phase 2

Must match the original **bit for bit** (f64, same operation order; checked by the oracle):
- `mirror(Position)`: `F` + the ten left/right swaps, players not swapped (§5.1). Oracle: `ops.ndjson` (`mirror`).
- `swap_players` (§5.2). Oracle: `ops.ndjson` (`swap_players`).
- `apply(Reorientation)`: `R(θ)·v` with the term order of §5.3, then `+ offset`; `PositionReorientation` order
  rotate → translate → mirror → swap (§5.3). Oracle: bit for bit through `ops.ndjson` (`orient_canonically_*`,
  non-trivial angle and offset) and the `playback` frames; `graph.ndjson` exports only the edges' `reorientation_from`/`_to`
  *parameters* (§2.3), and applying them reproduces an endpoint only within `basicallySame`.
- `heading`, `center`, `normalRotation`, `normalTranslation`, and `orient_canonically_with_mirror/without_mirror`
  (§4.3, §5.5). Oracle: `ops.ndjson` (`heading`, `center`, `orient_canonically_*`).
- `compose`/`inverse` with the exact formulas of §5.4, angle sum not wrapped, `a.mirror` conjugating `b`. Oracle:
  only indirectly (playback frames, `playback` in the spec); `ops.ndjson` does not list them.

Must match semantically (the port may choose its own representation as long as these hold):
- `compose(a, b) = b ∘ a`; `inverse(u) ∘ u ≈ id`; `PositionReorientation` acts on joint *indices* as in §5.3.
- Canonical orientation never swaps players.

### 5.7 Open points (need the oracle/dumper)

- Bit equality of `sin`/`cos`/`atan2`: **measured in #140.** Over the whole DB the original's (glibc 2.27) are
  correctly rounded; Odin's `atan2` and a modern libm's `sin`/`cos` are not. Data and the pending decision are in
  ADR 0003, "Open points", and #161.
- ~~`compose`/`inverse` are not dumped directly~~: closed by dumper v4 (#141): `compose.ndjson` has, per transition,
  `inverse` of both endpoint reorientations, `compose(from, to)` and `compose(inverse(from), to)`
  (`tools/oracle/README.md`).

## 6. Interpolation and playback

The original has two independent ways of animating a path: **frame-based** (`frames()` + `smoothen()`: a fixed list of
positions, one per rendered frame; used by `makevideo`, `glfw_playback` and the oracle) and **time-based**
(`Playback`: a cursor advanced by wall-clock seconds plus a per-frame "chaser"; used by the editors). They share only
`between`. A third, time-based animator, the web cursor canvas (`src/cursor_canvas.cpp:39-74`: its own segment queue at a
fixed 5 segments/s, `detailed` ignored, sped up when more than 10 segments are queued, its own 0.2 chaser), belongs to
the web editor: §9. Notation as in §5 (`u(p)` applies a `PositionReorientation`, §5.3).

### 6.1 `between`

`between(a, b, s = 0.5)` (`src/positions.hpp:42-47`): for every one of the 46 `PlayerJoint`s,
`r[j] = a[j] + (b[j] − a[j]) * s`, with the `V3` operators acting per component (`src/math.hpp:135,143,151`). So, per
coordinate, `a + ((b − a) · s)`: one subtraction, one multiplication, one addition, each rounded separately (no FMA,
§5.3). This form, not `a·(1 − s) + b·s`, is what must be reproduced.
- Every joint of both players is interpolated independently and linearly in Cartesian space; there is no rotation
  interpolation, no limb-length preservation and no player-level logic.
- `s` is **not clamped**: the `/* [0,1] */` comment is the only constraint. Outside `[0, 1]` the result is a linear
  extrapolation. The callers in this section keep `s ∈ [0, 1]` (§6.2, §6.4), except `Playback` with negative
  elapsed seconds, which the GLFW clock does not produce. The range of the editor's own `howFar` (`at(location)`,
  `src/editor.hpp:41`) is in `[0,1]` in practice (§9.1).
- End points: `s = 0` gives `a + (b − a)·0`, equal to `a` except that `−0` becomes `+0` unless `b < 0`; `s = 1` gives `a + (b − a)`,
  which is **not** bit-equal to `b` in general (observed in `tools/oracle/dump/testdata/basic/playback.ndjson`: frames
  5 and 6 of block 1, see §6.2).
- Not to be confused with the two-argument `between(V3, V3)` / `between(V2, V2)` midpoints, `(a + b) / 2`
  (`src/math.hpp:193-195`), a different formula.
- Oracle: `between.ndjson` holds `between(a, b, s)` for every consecutive pair of every transition and `s` = 0.25, 0.5,
  0.75; all 12 values of `basic/between.ndjson` re-derived in Python doubles are bit-equal to the formula above, and
  `a·(1 − s) + b·s` does not match.

### 6.2 Frame-based path: `follow` and `frames`

**`follow(g, n, s, fpp)`** (`src/graph_util.cpp:60-110`) walks sequence `s` starting from the reoriented node `n`:
- Direction is chosen by **node equality, not by the step's `reverse` flag**: forwards if `*g[s].from == *n`
  (tested first), else backwards if `*g[s].to == *n`, else it throws (`src/graph_util.cpp:65,83,101-102`). A step whose
  two endpoints are the same node is therefore always walked forwards. One such transition
  exists in the DB (§10.3); it is not `bidirectional`, so no `in`/`out` path (the lists `follow` is fed from) reverses it.
- Frame of reference: `r = compose(inverse(E), N)` with `E` the edge's reorientation at the entry end and `N` the
  view of `n` (§5.4).
- For each segment (consecutive pair `A`, `B` of keyframes, in walking order) it emits `fpp + 1` frames,
  `between(r(A), r(B), k / double(fpp))` for `k = 0 … fpp` (`src/graph_util.cpp:69-78,87-96`). The reorientation is
  applied to the **keyframes first**, then interpolated (contrast §6.4). `k / double(fpp)` is a correctly rounded
  division, exactly `1` at `k = fpp`.
- Segment boundaries are therefore **repeated**: the last frame of a segment, `between(r(A), r(B), 1)`, and the first
  of the next, `between(r(B), r(C), 0)`, are both ≈ `r(B)` but not bit-equal (§6.1).
- It returns the frames and the node reached, viewed with `compose(X, r)`, `X` the reorientation of the exit end (`Et` forwards, `Ef` backwards;
  `src/graph_util.cpp:80-81,98-99`). The
  `basicallySame` asserts at `src/graph_util.cpp:104-105` are compiled out (§1.7).

**`frames(g, path, fpp)`** (`src/paths.cpp:23-52`), with `path` a `deque<Reversible<SeqNum>>` (`src/paths.hpp:8`):
- Start node: `from(path.front(), g)` (`src/paths.cpp:37`), which for a `Reversible` is the edge's own endpoint `to` if
  reversed, else `from`, **with the edge's own reorientation** (`src/locations.hpp:166-172`, `src/graph_util.hpp:135-143`).
  The first step's `r` is thus `compose(inverse(E), E)` ≈ identity: the first transition plays in its stored frame
  (bit-equal to the raw keyframes in the `basic` test DB, not guaranteed in general). Each following step starts from
  the node `follow` returned, so the chain carries the reorientation (§5.4): consecutive transitions connect without
  jumps (up to `basicallySame`, §2.3).
- Per step: `follow(g, n, *step, fpp / (detailed ? 2 : 1))` (`src/paths.cpp:41-42`). **Integer** division: `fpp = 11`
  gives 5 for a `detailed` transition (6 frames per segment, not 5.5); `fpp = 1` gives 0, and then `k / double(0)` is
  `0/0 = NaN`: one NaN frame per segment **[unverified]** (deduced from the code; the default is 11, but `--frames-per-pos` accepts any value, and `fpp = 0` gives NaN for
  every step).
- `pop_back()` drops the **last frame of each step** (`src/paths.cpp:44`), so a step of `n` segments yields
  `n · (fpp′ + 1) − 1` frames, `fpp′` the per-segment value. The dropped frame ≈ the first frame of the next step.
  The last step of the path also loses its final frame: the path never shows its exact end keyframe.
- Caption per step: first description line; if it is exactly `...` and the end node `*g[seq].to` (the stored `to`,
  regardless of direction) has a description, its first line; then literal `\n` → space (`src/paths.cpp:27-34`).
- `frames(g, script, fpp)` (`src/paths.cpp:54-59`) just concatenates the `frames` of each path; each path restarts
  from its own first edge's endpoint (no reorientation carried between paths).
- Checked by the oracle: `playback.ndjson` (`fpp = 11`; in `basic`: 2 + 2 segments → 11 + 23 frames, matching
  `n · (fpp′ + 1) − 1`; both frame lists re-derived here from the keyframes with §6.1's formula, bit-equal).

Default `fpp` is 11 (`src/makevideo.cpp:34`, `src/playback.cpp:25`). The web position pages use a separate path
builder: `frames_for_sequence` (`src/mkpospages.cpp:124-149`), with 5 / 3 (detailed) frames per position, `k` from 0 to
`fpp − 1` (no repeated boundary), 10 copies of the first and last keyframe as padding (so the first keyframe shows 11
  times and the last only through its 10 copies, `src/mkpospages.cpp:130-139`), no reorientation, and a reversed
step played by reversing the frame list. Section 7.

### 6.3 `smoothen`

`smoothen(Frames f)` (`src/paths.cpp:8-21`) is a per-joint exponential filter over **all frames of all steps in one
pass** (`foreach` iterates by reference, `src/util.hpp:66`):

```
last = f[0].second[0]
for every frame p, in order, for every PlayerJoint j:
    lag     = std::min(0.83, 0.6 + p[j].y)       // p[j] is the raw (unsmoothed) value
    p[j]    = last[j] = last[j] * lag + p[j] * (1 − lag)
```

- Per coordinate: `(last · lag) + (raw · (1 − lag))`, with `1 − lag` computed once per joint. `std::min(a, b)` returns
  `b` only if `b < a`, so `lag = 0.83` once `0.6 + y ≥ 0.83` (`y` ≳ 0.23 m) and `0.6 + y` below; joints near the
  floor lag less (`0.6` at `y = 0`). Verified bit for bit against `basic/playback.ndjson` (frame 1 of block 1).
- The state crosses step boundaries: every caller passes a whole script (`src/makevideo.cpp:93,105`,
  `src/playback.cpp:77,89`, `src/paths.cpp:261`); the per-transition `smooth` of the oracle is a dumper choice and differs
  from the chained one (`basic`: the first smoothed frame of `seq 1` is not the same alone and in the `chain` line).
- The first frame becomes `p·lag + p·(1 − lag)`, ≈ `p` but **not** bit-equal (in `basic`, 6 of the 138 coordinates of
  each transition's first frame differ by 1 ulp, e.g. `0.789` → `0.7889999999999999`): the port must compute it, not
  copy `p`.
- It is frame-count based: the time constant is a number of frames, so the visible lag depends on `fpp` and the frame
  rate. An empty `Frames` (or an empty first step) is UB (`f[0].second[0]`); not produced with the default arguments (an empty script or a 1-segment
  step with `fpp′ = 0` would).
- Padding added by the callers before smoothing: random scenes get `fpp · 5` (`glfw_playback`, `src/playback.cpp:86`)
  or `fpp · 15` (`makevideo`, `src/makevideo.cpp:102`) copies of the first frame and `fpp · 15` of the last
  (`src/playback.cpp:87`, `src/makevideo.cpp:103`); `demoFrames` adds 70 copies of the last frame and a 70-frame caption
  `"      "` with the first smoothed frame before each scene (`src/paths.cpp:246-267`). Scripts get no padding.
- `mkpospages` has its own `smoothen` on a flat frame list with `std::min(0.55, 0.3 + y)` (`src/mkpospages.cpp:319-331`).

Consumers play one frame per buffer swap with vsync on (`src/glfw_playback.cpp:66-111,152`), so `glfw_playback` shows
about `fpp′ + 1` frames per segment at the monitor's rate (§6.2): 12 at `fpp = 11`, ≈ 5 segments/s at 60 Hz, and 6
for `detailed`, ≈ 10 segments/s: the same speeds as `Playback` (§6.4) and the comment at `src/playback.cpp:131`. `makevideo` only counts
frames: its PNG writer is commented out (`src/makevideo.cpp:124-139`).

### 6.4 Time-based playback: `Playback`

State (`src/playback.hpp:25-38`): an `OrientedPath` (`deque<Reoriented<Reversible<SeqNum>>>`, `src/paths.hpp:10`), the
iterator `i`, `segment`, `howFar`, `wait`, `atEnd`, `chaser`; `pause_before = pause_after = 0.8` s.

- **Location**: `Location{{**i, segment}, howFar}` viewed with `i->reorientation` (`src/playback.hpp:45-52`).
  `howFar` is always measured from keyframe `segment` towards `segment + 1`, also when playing in reverse. The shown
  target is `at(location) = u(between(A, B, howFar))` (`src/graph_util.hpp:260-268`): interpolate **then** reorient, the
  opposite order of §6.2, so equal only up to rounding.
- **Reorientation is not computed by `Playback`**: each element of the path carries its own, set by the caller. The
  editor plays either the current sequence in the current view (`nonreversed(sequence(location))`) or the selection
  (`src/editor.cpp:411-417`), whose reorientations `reorient_from` keeps consistent through `gp_connect`, which is
  `compose(inverse(E), N)` as in §6.2 (`src/paths.cpp:309-330`, `src/graph_util.cpp:232-245`). Section 8.
- **`reset()`** (`src/playback.cpp:102-112`): `i` = first step; `segment` = 0 forwards, or the last segment
  (`positions.size() − 2`, `src/graph_util.hpp:84-88`) in reverse; `howFar` = 0 forwards, 1 in reverse
  (`from_loc`, `src/reoriented.hpp:56-58,74-75`); `wait = 0`, `atEnd = false`. The constructor calls `reset()` and
  sets `chaser` to the exact start (`src/playback.cpp:95-100`): no pause before the first run.
- **Speed** (`src/playback.cpp:129-131`): `detailed ? 10 : 5` **segments per second**, of the step being played; the
  same values as the editor's `segmentsPerSecond` (`src/editor.cpp:28-31`). A step of `n` segments lasts `n / 5` s
  (`n / 10` if detailed), independent of frame rate.

**`progress(seconds)`** (`src/playback.cpp:114-176`), recursive, consumes `seconds` exactly:
1. Pause: if `wait > seconds`, `wait −= seconds` and return. Otherwise `seconds −= wait`, `wait = 0`.
2. If `atEnd` (set at the end of the previous pass): `reset()`, `wait = pause_before`, return. The **remaining seconds
   are discarded**, and `chaser` is not reset, so the jump back to the start is smoothed by the chaser (§6.5).
3. Forwards: `howFar += seconds · speed`; if `< 1` return. Else the leftover is `seconds = (howFar − 1) / speed`; then
   next segment with `howFar = 0`, or, on the last segment, `howFar = 1` and the step is finished. Reverse:
   `howFar −= seconds · speed`; if `> 0` return; leftover `(−howFar) / speed`; previous segment with `howFar = 1`, or on
   segment 0 `howFar = 0` and finished. Hitting exactly `1` (forwards) or `0` (reverse) counts as crossing.
4. Finished step: if it was the last one, `atEnd = true`, `wait = pause_after`, return (**leftover discarded**; the
   end is held at exactly `howFar` 1 / 0, i.e. the last keyframe through `between(·, ·, 1)` / `(·, ·, 0)`). Otherwise
   `++i` and start the next step at its own first segment (`segment` last / `howFar = 1` if reversed, else 0 / 0),
   `src/playback.cpp:156-173`.
5. `progress(seconds)` again with the leftover, which is then advanced at the **new** segment's speed: a `detailed`
   step followed by a normal one is timed correctly across the boundary.

Consequences: with `seconds ≥ 0`, `howFar ∈ [0, 1]` whenever `progress` returns, so `between` is never extrapolated.
There is no bidirectional "ping-pong": the path plays once in the direction of each step, holds the end for 0.8 s,
jumps to the start (`reset`, `src/playback.cpp:121`), holds the start for 0.8 s and plays again, forever. The boundary between two steps is shown once (no repeated frame,
unlike §6.2), but `Playback` holds no frames: what is seen depends on when frames are sampled.

### 6.5 The chaser

`frame(secondsElapsed)` (`src/playback.cpp:178-184`):

```
chaser = between(chaser, at(location(), graph), 0.2);   // todo: the 0.2 should depend on secondsElapsed
progress(secondsElapsed);
```

- The shown position is `chaser` (`getPosition`, `src/playback.hpp:56`; used by `Editor::current_position`,
  `src/editor.hpp:41`), an exponential follower of the target with factor 0.2 **per frame**: the remaining error is
  multiplied by 0.8 each frame (half-life ≈ 3.1 frames, ≈ 52 ms at 60 Hz). Frame-rate dependent, as the source's own
  `todo` says.
- The target is sampled **before** `progress`, i.e. at the previous frame's time: one frame of extra lag.
- Unlike `smoothen` (§6.3), the factor does not depend on joint height, and the formula is `between`'s
  (`c + (t − c)·0.2`), not `c·lag + t·(1 − lag)`.
- Elapsed time: wall-clock between frames, `glfwGetTime()` after the buffer swap: vsync on in the GLFW editor
  (`src/glfw_editor.cpp:537-538,568,570`); the web editor runs from `emscripten_set_main_loop(do_frame, 0, 0)`, i.e.
  the browser's animation frame (`src/editor_canvas.cpp:584-588,685`). Playback only runs while the editor is in playback
  mode (`src/editor.cpp:419-428`).

### 6.6 Chained transitions

- Frame-based: chaining is done by `frames` itself, carrying the node's reorientation through `follow` (§6.2);
  boundaries: the last frame of each step dropped, `smoothen` state carried across (§6.3).
- Time-based: chaining relies on the reorientations stored in the `OrientedPath` (§6.4); the change of step happens
  inside one `progress` call with the leftover time carried over. Any residual mismatch at the junction
  (`basicallySame`, §2.3) is absorbed by the chaser.
- Editor display helpers `timeInSequence`, `duration` and `timeIn` (`src/editor.cpp:33-62`) compute a time from the
  same speeds; `duration` is `num_segments / segmentsPerSecond` in **integer** arithmetic (`uint_fast8_t` and
  `unsigned`), so it truncates (e.g. 7 segments → 1 s instead of 1.4 s). Section 8.

### 6.7 Input for phases 2/3

Must match the original **bit for bit** (f64, same operation order, no FMA; checked by the oracle):
- `between` as `a + (b − a)·s`, no clamping (§6.1). Oracle: `between.ndjson`.
- `frames`: start node with the edge's own reorientation, direction by node equality, `fpp / 2` by integer division for
  `detailed`, reorient keyframes then interpolate, `fpp + 1` frames per segment with repeated boundaries, last frame of
  each step dropped, reorientation chained with `compose` (§6.2). Oracle: `playback.ndjson` (`raw`, both per
  transition and `chain`).
- `smoothen` with `min(0.83, 0.6 + y)` on the raw `y`, in the term order of §6.3, state carried over the whole script.
  Oracle: `playback.ndjson` (`smooth`; the `chain` line for the carried state).

Must match semantically (no dump; time-based):
- `Playback::progress`: segments per second 5 / 10, leftover seconds carried across segments and steps at the new
  speed, `howFar` measured from the lower keyframe in both directions, interpolate-then-reorient, 0.8 s pauses at the
  end and before restarting, leftover discarded at the end, loop forever (§6.4).
- The chaser at 0.2 per frame, sampled before `progress` (§6.5).

### 6.8 Open points

- The chaser and `smoothen` are frame-rate / frame-count dependent. Whether the port keeps 0.2 per frame (faithful)
  or makes it time-based (`1 − 0.8^(60·dt)` at 60 Hz equivalence, the original's own `todo`) is a decision for phase 3
  (ADR); it changes nothing that the oracle checks.
- Bit equality of `at(Reoriented<Location>)` (§6.4) is not dumped; `playback.ndjson` only covers the §6.2 order.
- Self-loop transitions and the direction rule of `follow` (§6.2): the DB has one, not bidirectional (§10.3). A reversed
  self-loop as the first step would start from the `to` end with `Et` but be walked forwards with
  `compose(inverse(Ef), Et)`, which is not ≈ identity.

## 7. Rendering and camera

The original has **two renderers** over the same geometry (`src/playerdrawer.cpp`, `src/rendering.cpp`):
- **Fixed-function OpenGL 1.x** (`glBegin`/`glEnd`, `GL_LIGHTING`), compiled when `EMSCRIPTEN` is not defined: the GLFW
  playback and editor, the VR tools, and `ImageMaker` (OSMesa), which makes **the PNGs/MP4s of `mkpospages`, i.e. the
  oracle images**. Entry points: `renderBasic`/`renderWindow`/`renderScene` (`src/rendering.cpp:311-364,367-407,460-509`).
- **Shader-based** (vertices into `vector<BasicVertex>`, `src/playerdrawer.hpp:9-13`, drawn with
  `triangle.{vertex,fragment}shader`): only the web editor (`src/editor_canvas.cpp`, built into `libgrapplemap.js`,
  `src/SConstruct:55`).

Unless said otherwise, this section describes the fixed-function path, since it is what the reference images use. The
JS viewers (`graphdisplay.js`, Babylon.js, `src/graphdisplay.js:357-383`) are a third, independent renderer with their
own tables (§3.2) and are not covered. VR-only: `vr_playback.cpp`, `vr_editor.cpp` call `setupLights`, `grid` and
`drawPlayers`/`renderScene` (`src/vr_playback.cpp:64-71`, `src/vr_editor.cpp:252-265`) inside Vrui, with Vrui's own
camera; nothing of their view setup applies to phase 3.

### 7.1 Body geometry

`drawPlayers` draws, in this order (`src/playerdrawer.cpp:363-375`): all visible limbs as **pillars**, all 46 joints as
**spheres**, then five **fat triangles** per player. The shader version is the same sequence
(`src/playerdrawer.cpp:378-390`). There is no other geometry for the body (no torso mesh, no caps on pillars: the
spheres at the ends close them, since a pillar end has the joint's own radius).

**Spheres** (`drawJoints`, `src/playerdrawer.cpp:250-274`):
- Center `pos[pj]`, radius `jointDefs[j].radius` (§3.1 table), **+ 0.005** when the joint has an override color
  (`src/playerdrawer.cpp:260-266`, 269).
- Mesh: an icosphere from the 12-vertex icosahedron (`X = .525731112119133606f`, `Z = .850650808352039932f`, **`float`**
  constants widened to `double`; `src/icosphere.cpp:16-29`), each subdivision splits every triangle in 4 with new
  vertices `normalize(e0 + e1)` shared per edge (`src/icosphere.cpp:34-73`). `fine` = 2 subdivisions (162 vertices,
  320 triangles), `course` [sic] = 1 (42 / 80) (`src/playerdrawer.cpp:144-147`).
- **Fine** for `Head`, `Core`, both hips and both shoulders; **coarse** for the other 17 joints (`Neck` included)
  (`src/playerdrawer.cpp:269-272`).
- Vertex `center + v·radius`, normal `v` (≈ unit: the base vertices are `float` constants), triangles emitted with reversed index order `2, 1, 0`
  (`src/playerdrawer.cpp:149-166`). With no face culling anywhere (below) the winding does not change the image.
- In a first-person view, that player's `Head` sphere is skipped (`src/playerdrawer.cpp:256`).

**Pillars** (`drawLimbs` + `drawPillar`, `src/playerdrawer.cpp:306-331,195-219`): which limbs, the split at the
midpoint with `midpointRadius` and the first-person skip are §3.2. Each pillar is a truncated cone:
- `faces = 10` (`src/playerdrawer.hpp:32`); `angles[i] = (sin(i·s), cos(i·s))`, `s = 2·pi()/10`, `i = 0..10`
  (`src/playerdrawer.cpp:178-184`). With `pi() = 3.141593` (§4.1) `angles[10]` is not exactly `angles[0]`
  (`sin(10·s) ≈ 7e-7`): the seam is open by under a micrometre.
- Basis: `a = normalize(cross(to − from, (1,1,1) − from))`, `b = normalize(cross(to − from, a))`
  (`src/playerdrawer.cpp:197-198`). `(1,1,1)` is a fixed world point, not a direction, so the basis (hence where the 10
  edges fall around the axis) depends on where the limb is. Degenerate (NaN) if `(1,1,1)` lies on the limb's line or the two joints coincide
  (never in the DB's stored, canonical or playback positions, §10.3).
- Face `i`: quad between `from + r_f·(a·sinᵢ + b·cosᵢ)` and `to + r_t·(…)` at angles `i`, `i+1`. Normals are
  `a·sin + b·cos`, **perpendicular to the axis even when `r_f ≠ r_t`** (not the true cone normal), smooth per vertex.
- Fixed-function: one `GL_TRIANGLE_STRIP` per pillar with 6 vertices per face in the order
  `fᵢ, tᵢ, fᵢ₊₁, fᵢ₊₁, tᵢ₊₁, tᵢ` (`src/playerdrawer.cpp:200-218`): the strip produces degenerate and duplicate
  triangles but covers exactly the same surface as the shader version's two triangles per face
  `(fᵢ, tᵢ, fᵢ₊₁), (fᵢ₊₁, tᵢ, tᵢ₊₁)` (`src/playerdrawer.cpp:222-241`).

**Fat triangles** (`fatTriangle`, `src/playerdrawer.cpp:15-100`), one per player for each of
`(LeftHip, Core, RightHip)`, `(LeftShoulder, Neck, RightShoulder)`, `(LeftShoulder, Core, RightShoulder)`,
`(LeftAnkle, LeftHeel, LeftToe)`, `(RightAnkle, RightHeel, RightToe)` (`src/playerdrawer.cpp:370-374`), with each
corner's joint radius (`src/playerdrawer.cpp:111-121`). This is the torso, pelvis and feet. For corners `a, b, c` with
radii `ra, rb, rc` (`src/playerdrawer.cpp:17-35`):
- `ab = n(b − a)`, `bc = n(c − b)`, `ca = n(a − c)`, `fwd = n(cross(b − a, c − a))`, `n` = `normalize`.
- Front/back: `a ± fwd·ra`, `b ± fwd·rb`, `c ± fwd·rc`. Side points (on the extension of the other edge through
  each corner): `aleft = a + ca·ra`, `adown = a − ab·ra`, `bleft = b − bc·rb`, `bright = b + ab·rb`,
  `cright = c − ca·rc`, `cdown = c + bc·rc`.
- 14 triangles, in code order (`src/playerdrawer.cpp:37-99`): front `(afwd, bfwd, cfwd)`; two each for front-left
  (`afwd, aleft, bleft, bfwd`), front-right (`bfwd, bright, cright, cfwd`), front-bottom (`cfwd, cdown, adown, afwd`);
  back `(cback, bback, aback)`; two each for back-left, back-right, back-bottom with the same side points. Normals are
  per vertex: `±fwd` on front/back points, and on side points `ca` (aleft), `−bc` (bleft), `ab` (bright), `−ca`
  (cright), `bc` (cdown), `−ab` (adown), i.e. the direction along which the point was pushed.
- The result is a slab of thickness `2·r` at each corner, bevelled out to the corner radii along the edges' directions.

**Normals** are never recomputed: they are the unit vectors above, passed with `glNormal3d` (`src/playerdrawer.cpp:9`).
No `GL_NORMALIZE`, no `glShadeModel` (grep of `src/`), so smooth (Gouraud) shading (OpenGL spec default, not code;
**[unverified]** on OSMesa 20.0.8, see §7.3).

Vertices go to GL as `double` (`glVertex3d`, `src/playerdrawer.cpp:10`); the shader path converts them to `float`
(`V3f`, `src/playerdrawer.hpp:11`).

### 7.2 Colors

| What | Value | Where |
|---|---|---|
| Player 0 / player 1 (limbs, triangles, joints without override) | `(1, 0, 0)` / `(0.15, 0.15, 1)` | `src/positions.cpp:140` (§3.3) |
| Override colors only affect joint spheres | `colors[pj]` | `src/playerdrawer.cpp:258-267` |
| Editor (not playing back), edit mode: every joint | white `(1, 1, 1)` | `src/glfw_editor.cpp:437`, `src/editor_canvas.cpp:456` |
| Editor, explore mode: joints with a candidate path | `0.4·white + 0.6·player color` | `src/glfw_editor.cpp:438-440` |
| Editor: highlighted (closest or chosen) joint | yellow `(1, 1, 0)` | `src/glfw_editor.cpp:442`, `src/math.hpp:63` |
| VR `renderScene`: browse joint / edit joints | yellow / green `(0, 1, 0)` | `src/rendering.cpp:481,485` |
| Background (`Style` default; `glfw_editor` and VR) | black `(0, 0, 0)` | `src/rendering.hpp:29`, `src/glfw_editor.cpp:83` |
| Grid (`Style` default) | `(0.5, 0.5, 0.5)`, size 2, line width 2 | `src/rendering.hpp:28-31` |
| GLFW playback | background white, grid `(0.7, 0.7, 0.7)`, size 20 | `src/glfw_playback.cpp:43-45` |
| Web editor | clear color black, grid `(0.25, 0.25, 0.25)`, size 4 | `src/editor_canvas.cpp:611-612,626` |
| Images: background | `WhiteBg (1,1,1)`, `RedBg (1, .878, .878)`, `BlueBg (.878, .878, 1)` | `src/images.hpp:174-185` |
| Images: grid | `0.8 · background` | `src/images.cpp:71,154,252` |

Image backgrounds: position pages use `WhiteBg` (`src/mkpospages.cpp:584-588`); transition clips use red if the
transition is marked `top`, else blue if `bottom`, else white (`src/mkpospages.cpp:312-317`; tags in §1.2).
Editor overlays (selection paths white 0.6 alpha, viables yellow with alpha `max(0, 0.3 − 0.05·depth)`, highlighted
joint as a 20-px white point without depth test; `src/rendering.cpp:61-101,141-190,396-405`) are display only; what they select is §9.7.

### 7.3 Lights and shading

**Fixed-function** (`setupLights`, `src/rendering.cpp:229-247`), called after the model-view is loaded
(`src/rendering.cpp:341-356`); since `GL_POSITION` is transformed by the current model-view (OpenGL spec, not code),
the light directions are in **world** space:
- `GL_LIGHT0` and `GL_LIGHT1`, both **directional** (`w = 0`), at infinity in the direction of `(2, 2, 2)` and `(−2, 2, −2)`
  (vector toward the light), i.e. unit directions `(1, 1, 1)/√3` and `(−1, 1, −1)/√3`.
- Each: diffuse `0.65` (RGB), ambient `0.03`. Specular not set.
- `GL_COLOR_MATERIAL` is enabled (`src/rendering.cpp:339`) with no `glColorMaterial` call (grep), so with the default
  mode `GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE` (spec default) `glColor` sets the material's ambient and diffuse. No `glMaterial`, `glLightModel`, fog, culling or multisampling anywhere in `src/`
  (grep of `glMaterial|glLightModel|GL_FOG|GL_CULL_FACE|GL_MULTISAMPLE`; the only culling line is commented out,
  `src/editor_canvas.cpp:631`).
- The rest are OpenGL 1.x defaults (spec, not code; **[unverified]** against OSMesa 20.0.8 until the oracle images
  exist): global ambient `0.2`, material specular 0 (so no highlight even though `LIGHT0`'s default specular is 1),
  one-sided lighting, no attenuation, per-vertex evaluation; depth test `GL_LESS` (no `glDepthFunc` in the fixed path;
  only `src/editor_canvas.cpp:629` sets it, to the same value). That gives, per vertex and channel,
  `color · (0.2 + 0.06 + 0.65·(max(0, n·l₀) + max(0, n·l₁)))`, clamped to `[0, 1]`.
- The **grid is lit too** (normal `(0, 1, 0)`, `src/rendering.cpp:251`): factor `0.26 + 0.65·2/√3 ≈ 1.01`, so it shows
  at about its nominal color (clamped).

**Shader** (web editor only; `src/triangle.vertexshader:22-49`, `src/triangle.fragmentshader:18-54`), `mediump`:
- Uniforms `MVP`, `V`, `M` (`M` is identity, `src/editor_canvas.cpp:562`), `LightEnabled`; per-vertex inputs position,
  normal, RGBA color (`src/editor_canvas.cpp:662-681`).
- Two **point** lights at world `(4, 4, 4)` and `(−4, 4, −4)` (`src/triangle.vertexshader:37-38`), white, power 34,
  inverse-square in world distance; ambient `0.3 · color`; diffuse `color · 34 · max(0, n·l) / d²` per light; no
  specular; per fragment (`src/triangle.fragmentshader:22-51`).
- `LightEnabled = 0` outputs the vertex color unlit; used for the overlays, drawn after the body without depth test
  (`src/editor_canvas.cpp:569-580`).
- So the two renderers do **not** look the same: different light type, position, strength and ambient.

Neither renderer enables anti-aliasing beyond `GL_POINT_SMOOTH` (fixed path, `src/rendering.cpp:322`); the images
get theirs from supersampling (§7.6).

### 7.4 Floor

Only a grid of lines on `y = 0` (no plane, no texture): `grid(color, size, line_width)` draws, for
`i = −2·size … 2·size`, the lines `x = i/2` and `z = i/2` from `−size` to `+size` (`src/rendering.cpp:249-264`), i.e. a
square of half-side `size` metres with **0.5 m spacing**: `4·size + 1` lines per direction, drawn as `GL_LINES` of
`line_width` pixels, with depth test, before the players (`src/rendering.cpp:358-363`). The shader path draws each
line as a 0.02 m wide quad in `y = 0` instead (`src/rendering.cpp:267-289`).

### 7.5 Camera

State (`src/camera.hpp:8-75`): `offset` (target, default origin), `orientation = {yaw 0, pitch −0.6, distance 1.7}`,
viewport size and fov. Model-view and its handedness are §4.2. Projection:
`perspective(fov, w/h, 0.01, 15)` (`src/camera.hpp:34`), the `gluPerspective` matrix with `pi()`
(`src/math.hpp:116-125`); **near 0.01 m, far 15 m**, `fov` vertical in degrees. Default viewport 640×480, fov 90
(`src/camera.hpp:24`), but every renderer overrides it per `View` (`src/rendering.cpp:333`).

- `rotateHorizontal(r)`: `yaw += r`, unbounded. `rotateVertical(r)`: `pitch += r` clamped to `[−pi()/2, pi()/2]`.
  `zoom(z)`: `distance += z`, **unclamped** (can go to 0 or negative). (`src/camera.hpp:52-70`.)
- `hardSetOffset(o)` sets the target; `setOffset(o)` moves it 3 % of the way per call (`src/camera.hpp:38-50`; every caller passes a `V3`; the
  `V2` overload, which keeps `offset.y`, is never called;
  per frame, so frame-rate dependent, like the chaser in §6.5).
- First-person views ignore the camera's model-view: `gluLookAt(eye = Head, center = (LeftHand + RightHand)/2,
  up = Head − Neck)` of that player (`src/rendering.cpp:346-352`; shader path `src/editor_canvas.cpp:548-555`).
- `world2xy`/`world2screen` project world points to NDC/pixels for picking (`src/camera.hpp:77-88`; §9.2).

`View{x, y, w, h, first_person, fov}` (`src/rendering.hpp:19-24`) places a sub-viewport (fractions of the window) with
its own fov; each view is scissored and cleared (`src/rendering.cpp:321-337`).

| Program | Views (fov) | Camera setup and per-frame motion | Keys / mouse |
|---|---|---|---|
| `glfw_playback` (640×480, vsync) | one, third person, 50 | `zoom(1.2)` → distance 2.9; `hardSetOffset(cameraOffsetFor(first frame))`; every frame `rotateHorizontal(−0.013)` (auto-orbit) and `setOffset(cameraOffsetFor(pos))` (`src/glfw_playback.cpp:41-47,71-72,94,148-152`) | ↑/↓ pitch ∓0.05, ←/→ yaw ∓0.03, Home/End distance ∓0.05, per frame while held (`src/glfw_playback.cpp:74-79`) |
| `glfw_editor` (640×480, vsync) | single: third person 60; split (toggle): third person 90 on the left half, players 0/1 first person 75 on the right quarters (`src/glfw_editor.cpp:262-268`) | `setOffset(center` with `y·0.7)` when not in edit mode, no joint chosen and not playing back (`src/glfw_editor.cpp:526-531`, §4.3); "jiggle" `rotateHorizontal(sin(jiggle)·0.0005)`, `jiggle += 0.01` per frame when not editing and no joint chosen (`src/glfw_editor.cpp:417-421`) | ↑/↓ pitch ∓0.05, **← yaw +0.03, → yaw −0.03** (opposite of playback; ←/→ also reset the jiggle phase to `pi()`/0), Home/End ∓0.05 (`src/glfw_editor.cpp:410-415`); middle-drag: yaw `+0.002·dx`, pitch `−0.002·dy` per pixel (`src/glfw_editor.cpp:276-291`) |
| web editor (1024×768) | external third person 60, or one player first person 120 (`src/editor_canvas.cpp:48-54`) | as `glfw_editor`, target also while editing (`src/editor_canvas.cpp:539-544`) | keys as `glfw_editor` (`src/editor_canvas.cpp:189-206`); middle-drag `1·Δ` in NDC units (`src/editor_canvas.cpp:389-395`) |
| images (`mkpospages`) | heading views: third person 45; player views: first person 80 | below (§7.6) | none |

The remaining editor bindings (scroll, right/left drag, all letter keys) are §9.2-§9.6. `makevideo`'s rendering call
is commented out at the pin (`src/makevideo.cpp:124-139`).

### 7.6 Reference images (`ImageMaker`)

What the oracle's `--images` (`tools/oracle/README.md`, #35) runs:
- Context: OSMesa, `OSMESA_RGB`, 16-bit depth, no stencil, 16-bit accumulation (`src/images.cpp:525`). The accumulation
  buffer is only used by the `png(pos_beg, pos_end, …)` overload that averages frames (`src/images.cpp:236-300`),
  which nothing calls at the pin (grep of `png(`): no motion blur in the images.
- **2× supersampling**: renders at `2w × 2h`, then each output pixel is the integer (truncating) mean of a 2×2 block
  (`src/images.cpp:63-106`). The image is flipped vertically before writing (`src/images.cpp:111-112`).
- Channels 0 and 2 of every pixel are swapped before writing (`src/images.cpp:89,176,278`). OSMesa's `OSMESA_RGB`
  buffer is R, G, B in memory (probe: `glClearColor(1, 0, 0)` reads back `ff 00 00`), so the swap writes **BGR**: red and
  blue are swapped in the PNGs. Player 0 `(1, 0, 0)` shows **blue** (pixels with R = G = 0 in `p96-480x360.png`, e.g.
  `0000aa`) and player 1 `(0.15, 0.15, 1)` shows **red** (`de2121`, G/R = B/R = 0.149). Evidence:
  `tools/oracle/README.md` "Reference images", "Channel order", and `tests/fixtures/oracle/images/`.
- Driver: with Mesa 20.0.8 the default llvmpipe driver corrupts `OSMESA_RGB` renders (rasterized primitives write 4-byte
  pixels into the 3-byte buffer) and is not deterministic, so the oracle renders with softpipe (`GALLIUM_DRIVER`,
  recorded in `images/meta.json`).
- Style: grid size 2 (±2 m), line width 2 px at the 2× size (`src/images.hpp:149,156`), colors from §7.2.
- **Heading view** (position pages, `src/images.cpp:302-316`, called with `ymax = max(0.8, both heads' y)` of the
  canonically oriented position, `src/mkpospages.cpp:578-588`): offset `(0, ymax − 0.57, 0)`, distance `1.7 + 0.55`,
  yaw `pi()/2 · heading` (N, E, S, W = 0..3), pitch `−0.6 + (ymax − 0.6)/2` (clamped), fov 45; sizes 480×360 and
  320×240. `mirror` views mirror the position first (`src/images.cpp:354`). (Summarised in §4.3.)
- **Player view**: a default `Camera` with a first-person view, fov 80 (`src/images.cpp:362-368`); `views()` does not
  generate them at the pin (commented out, `src/headings.hpp:41-45`).
- Clips (MP4 via ffmpeg, 200×150): per-frame heading camera with `ymax` smoothed 10 times over the frames by a
  3-tap mean (`src/images.cpp:36-53,431-463`); position rotation clips orbit yaw `0..355°` in 5° steps
  (`src/images.cpp:388-409`). Frames: `frames_for_sequence` (§6.2), then mkpospages' **own** `smoothen` with
  `min(0.55, 0.3 + y)` (§6.3, `src/mkpospages.cpp:319-331`), not the one of `paths.cpp`; called at
  `src/mkpospages.cpp:340,349`.

### 7.7 Input for ADR 0006 and phase 3 (no decision here)

Visible in the oracle PNGs, so a pixel comparison depends on it:
- Geometry: icosphere level per joint (2 / 1), radii, 10-face pillars with the `(1,1,1)`
  basis and axis-perpendicular normals, midpoint split, the five fat triangles with their exact vertices and normals.
- Colors: players, `Style` grid/background, image backgrounds and `0.8·bg` grid.
- Fixed-function lighting: two directional lights, 0.65 diffuse, 0.03 + 0.2 ambient, no specular, per-vertex Gouraud.
- Camera math: `pi()`, `gluPerspective` with near 0.01 / far 15, the heading-view formula, fov 45, image sizes,
  2× supersampling with truncating box filter, vertical flip, the channel swap (the PNGs are BGR: a pixel comparison must
  swap red and blue back, §7.6).
- Grid: 0.5 m lines over ±2 m, 2 px at 2× (≈ 1 px), aliased (no `GL_LINE_SMOOTH`, grep) before the box filter.
- The 16-bit depth buffer with near 0.01 / far 15: joints rest at `y = radius` just above the grid plane, so depth
  resolution there can change pixels.
- Only the PNGs compare pixel by pixel: the clips are lossy H.264 `yuv420p` (`src/images.cpp:226-228`).

Not visible in the oracle images (free, or to be chosen for UX):
- Which API/technique draws it (fixed-function vs shaders, per-vertex vs per-pixel lighting) as long as the images
  match within the tolerance ADR 0006 sets; the shader renderer's look (§7.3) is not a reference.
- Interactive camera: auto-orbit speed, jiggle, `setOffset` smoothing per frame vs per second, key/mouse bindings and
  their signs, window size, unclamped zoom, view layouts, overlay styling.
- The +0.005 radius on override-colored joints: `ImageMaker` always passes `{}` as colors and no highlight
  (`src/images.cpp:80-81,167-168,266-267`), so it never shows in the images (editor only; still part of fidelity).
- Mesh layout details with no visual effect (winding, the pillar strip's degenerate triangles, the open seam).

Open points: the lighting defaults above (oracle images, #35); the JS viewers' handedness (§3.2), not covered here (ADR 0004 / section 8). Closed in §10.3: a
pillar basis never degenerates on the DB's stored, canonical or playback positions.

---

## 8. Web tools

The original ships six browser tools next to the native programs: **search** (`src/search.{html,js}`, the site's
`index.html`), the **per-position pages** (generated by `mkpospages`), the **explorer**, the **composer**, the **web
editor** and a static list of example drills. This section describes what each one does and how it is used, as input
for phase 5 (UI). Editing semantics (spring, confinement, persistence rules) are §9; rendering of the C++ side is §7.
Nothing here is a pixel reference: the JS viewers are a third renderer (§7) and the oracle images come from `mkpospages`.

Layout of the deployed site (`scripts/install-pages.sh:11-45`): `index.html` (search), `composer/`, `explorer/`,
`editor/`, `example-drills.html`, `res/` (images, videos, generated pages), each of the first four with its own copy of
`libgrapplemap.{js,data,js.mem}` ("copying this thrice is stupid", `scripts/install-pages.sh:45`). `babylon.js` is
**downloaded from Babylon's "preview release" on `master`** (`scripts/install-pages.sh:26`), so the Babylon version of the
original is not pinned by the repo.

### 8.1 Data pipeline: what the tools load

| Tool | Gets its data from | Format |
|---|---|---|
| composer, explorer | `Module.loadDB()` → `to_elaborate_jsval(loadGraph("GrappleMap.txt"), false)` (`src/web_db_loader.cpp:6-12`) | full: nodes with `position`, transitions with `frames` |
| search | `Module.cursor_canvas_main()` → `to_elaborate_jsval(graph, true)` (`src/cursor_canvas.cpp:82-87`) | **light**: no `frames`, no node `position`, `from`/`to` are bare node indices (`src/js_conversions.cpp:96-111,135`) |
| web editor | the C++ `Editor` itself, built on `loadGraph("GrappleMap.txt")` (`src/editor_canvas.hpp:56`); JS only gets small lists (`get_selection`, `get_dirty`, …) | no DB object in JS |
| position pages | `mkpospages` reads `GrappleMap.txt` and writes static HTML + PNG + MP4 + SVG (§8.3) | files |

`GrappleMap.txt` (and its `.index`) is **preloaded into the emscripten virtual file system** at link time
(`src/SConstruct:24,31`); `libgrapplemap.js` is the C++ `core` compiled with emscripten (`src/SConstruct:55`: graph,
persistence, paths, playback, editor, renderer). So parsing, node matching, reorientations and `tags`/`properties` are
**computed by the original C++ code**, not reimplemented in JS; the JS tools receive them precomputed.

Shape of the object (`src/js_conversions.cpp:14-168`):
- `db = {nodes, transitions, tags}`; `tags` is the union of all node and transition tags (`src/metadata.cpp:56-64`).
- node: `{id, incoming, outgoing, position, description, tags, line_nr}`; `incoming`/`outgoing` are lists of `Step`
  `{transition, reverse}` (`src/js_conversions.cpp:14-20,126-128`; which steps they contain is §2.6). `description` is the
  array of description lines (§1.2), not one string.
- transition: `{id, from, to, frames, description, tags, properties, line_nr}`. In the full form `from`/`to` are
  `{node, reo: {mirror, swap_players, angle, offset: {x,y,z}}}` (`src/js_conversions.cpp:31-47,106-109`), i.e. the
  `ReorientedNode` of §2.3; `frames` is `[frame][player][joint] → {x,y,z}` in joint order (§3.1)
  (`src/js_conversions.cpp:49-64`). `properties` comes from the `properties:` lines (`src/metadata.cpp:37-54`).
- `gm.js` then post-processes (`src/gm.js:570-594`): vectors become Babylon `Vector3`; `desc_lines` is
  `description[0].split('\\n')` (splitting on a literal backslash + `n`, the file's line-break escape); a node without
  description gets `desc_lines = "?"` (a string: `[0]` is `"?"`, `.length` is 1); each node gets random `x, y ∈ [0,1000)`
  as the seed of the force layout.

`grapplemap-dbtojs` (`src/dbtojs.cpp:46-50`) can still write a standalone `transitions.js` with the same data via
`tojs` (`src/js_conversions.cpp:275-312`, which also writes `discriminators` from `query_for`), but **no HTML at the pin
loads it** and the call is commented out in the install script (`scripts/install-pages.sh:47-48`). `doc/windows-package-readme.txt:5`
still says the composer and explorer use it: stale.

### 8.2 Search (`index.html`)

**Purpose.** Filter positions and transitions by tags and text, see them as thumbnails, preview the neighbourhood.

**Inputs.** URL query `?tag1,-tag2,…`: a tag without prefix must be present, `-tag` must be absent
(`src/search.js:793-805`, written back with `history.replaceState`, `src/search.js:478-493,392`). The substring box is
**not** in the URL (`todo` at `src/search.js:304`). Image base URL from `config.js` (`image_url`, `src/mkpospages.cpp:787-792`).

**Matching** (`src/search.js:273-328`):
- Position: every selected tag present/absent as requested **and** every substring (box split on spaces, lower-cased) found
  in some description line or in some tag (`src/search.js:290-302,306-312,757-765`). The substring test is
  case-insensitive on the data and always uses `indexOf`, so a trailing space gives an empty substring that matches
  everything.
- Transition: like a position, except a tag counts if the transition has it **or both its end positions have it**
  (`trans_kinda_has_tag`, `src/search.js:283-288`). Tags implied otherwise are a `todo` (`src/search.js:325`).
- Recomputed by polling a dirty flag every 100 ms (`src/search.js:352-397`).

**Layout** (`src/search.html:19-80`):
1. Tag filter: two lists (include / exclude) with a `×` per tag, plus a dropdown of **refinements**: only tags that split the
   current result (some selected items have it, some do not), each shown with the counts of positions and transitions it
   would keep (include) or drop (exclude) (`src/search.js:495-520`).
2. View controls `↻ ↺ ⇄ ⇅` (rotate the heading, mirror in x / in z) choose among the 8 pre-rendered views (§8.3)
   (`src/search.js:399-428`). Default view `[1,false]` = heading E (`src/search.js:264,530-533`).
3. Two paged lists (9 positions / 12 transitions per page, `src/search.js:807-808`): positions are 320×240 PNGs linking
   to the position page `res/p{n}{view}.html`; transitions are looping 200×150 MP4s linking to the composer with that single
   transition (`composer/index.html?{id}`) (`src/search.js:598-645`). Transition tooltips show the description and `(t{id} @ line {n})`; position tooltips only the description (`src/search.js:587-596`).
4. **Neighbourhood**, only if the graph built below has ≤ 30 nodes (it includes non-selected neighbours): a d3 force graph (§8.5) on the right and, on the left, a WebGL canvas
   running the C++ `cursor_canvas` (`src/search.html:45-80`). Hovering a graph node calls `cursor_canvas_goto(id)`
   (`src/search.js:747-755`): the 3D figure **walks** there along the transition (segments pushed on a queue, 5 segments/s,
   elapsed time multiplied by `(n−10)/2` when more than 10 are queued, chaser `between(…, 0.2)`, `src/cursor_canvas.cpp:39-74,89-100`) instead of
   jumping (it resets instead if the node is not adjacent, `src/cursor_canvas.cpp:95-99`; `recompute_results` also calls
   `cursor_canvas_goto(selected_nodes[0])`, `src/search.js:379-380`). The graph shown has three passes, each used only if the
   previous one gives > 30 nodes: transitions that match the filter **or** have an end selected; then matching **or** both ends
   selected; then both ends selected only (`src/search.js:648-728`); still > 30 → "Too many positions to display".
5. View select external/red/blue and a mirror button for the canvas (`src/search.html:53-59`).

A link to the explorer (`goto_explorer`, `src/search.js:736-745`) exists but its HTML link is commented out
(`src/search.html:60-61`): unreachable.

### 8.3 Per-position pages (`mkpospages`)

Static, generated offline ("the first run will take many hours", `src/mkpospages.cpp:109-112`; `no_anim`
option, `src/mkpospages.cpp:97-98`). Output also includes `lists.html` (sortable tables of all tags, positions and
transitions with counts, `src/mkpospages.cpp:205-282`), `todo.html` (dead ends, dead starts, untagged positions,
`src/mkpospages.cpp:180-203`) and `config.js`. `lists.html` references a `random.mp4` that `mkpospages` does not make
(`src/mkpospages.cpp:213`; `scripts/movie.sh:6` does, from external frames).

**Views.** 4 headings (N, E, S, W) × mirror = 8 (`src/headings.hpp:34-47`), coded as one letter, upper case when mirrored
(`src/headings.hpp:23-32`); the per-player first-person views are commented out. One page per position **per view**:
`p{n}{code}.html`, plus per-transition videos `t{id}…{code}.mp4`. Files are content-addressed in `res/store/` with
the readable names as links (`src/mkpospages.cpp:643-653`).

**One page** (`src/mkpospages.cpp:600-653`), three columns:
- *Incoming transitions* (left): for each, the **other** position as a rotating clip (`rotation_gif`) linking to its page,
  then `via` the transition clip linking to `composer/index.html?{id}`; background tinted by `top` (`#ffe0e0`) /
  `bottom` (`#e0e0ff`), swapped for sweeps (`is_sweep`: `swap_players` differs between the ends,
  `src/graph_util.hpp:347-350`); lists ordered top, neutral, bottom (`src/mkpospages.cpp:471-536,664-748`; tints
  `src/images.hpp:187-196`). Clips of one side are padded so they have equal length (`src/mkpospages.cpp:695-702,720-727`).
- *Centre*: description as `<h1>`, the 480×360 PNG in canonical orientation with mirror (`ymax = max(0.8, head heights)`),
  view controls `↻ ↺ ⇄ ⇅`, **tag list** (each tag links to `../index.html?{tag}`), and `Go to:` composer (`?p{n}`),
  explorer (`?{n}`) and search (`?` + `query_for`: the node's own tags, then negated tags added greedily (the one most frequent
  among the other positions still matching) until the query has 10 entries in total, own tags included,
  `src/metadata.cpp:5-35`, `src/mkpospages.cpp:560-574`).
- *Outgoing transitions* (right): like incoming, but the tint is **not** swapped for sweeps (`src/mkpospages.cpp:716`); the
  linked view is mirrored for sweeps in both lists (`src/mkpospages.cpp:490,518`).
- Below: **Neighbourhood**, an SVG made with Graphviz (`todot`, `gvc`/`cgraph` in `src/SConstruct:48-50`) of the positions up
  to 2 transitions away, ignoring taps (transitions whose first description line is `tap`, `src/graph_util.cpp:174-177`; `nodes_around(…, 2, true)`, `src/mkpospages.cpp:602-618`).

How the clips are timed (padding of 10 frames each end, 5 or 3 interpolated frames per keyframe pair, `smoothen`) is §6.3 /
`src/mkpospages.cpp:124-142,319-331`; rendering is §7.6.

### 8.4 Composer (`composer/index.html`)

**Purpose.** Chain transitions into a drill, play it in 3D, extend it at either end.

**State and URL.** The whole state is a list of steps `[{transition, reverse}]` and a start node
(`src/composer.js:3-4`). It is mirrored into the URL on every change: `?26,276,-5,…` (`-` = reversed step) or `?p{n}`
for a bare position (`src/composer.js:234-244,352-359,566-576,617-646`). With no query it starts from `random_drill()`:
a random walk over `outgoing` of at least 64 frames, never repeating the same transition twice in a row, restarting
from a random node at a dead end (`src/gm.js:433-476`, `src/composer.js:578-594`). This URL is the **only** persistence
and sharing mechanism; `example-drills.html` is a list of such links, two of them (F1, F4) to the bare tool
(`src/example-drills.html:14-20`). Ids are indices into the loaded DB (§2), so a link is only valid for that DB version.

**Panel** (`src/composer.html:27-72`, `src/composer.js:140-362`): view select (external / red / blue first person) and
**mirror**, **pause/play**, **random drill**, link to the explorer for the nodes of the drill, **info** checkbox (widens the
panel to 50 % and adds properties, `t{id}@{line}`, tag links `../?{tag}` and the remaining description lines);
a frame **slider**; the drill as a list (`Start:` node link, then `n. {transition}` with `↳ {end position}`; a bullet
marks the one playing); an `x` on the first step (if ≥ 2) and on the last step; and two columns of buttons,
**Prepend transition** (all `incoming` of the start node) and **Append transition** (all `outgoing` of the end node),
each button showing the transition name and the other position. Position links go to `res/p{n}e.html`
("todo: preserve mirroring", `src/composer.js:201-208`).

**Computation.** `follow(steps, mirror)` (`src/composer.js:471-525`) is a JS re-implementation of §6.2: for each step,
the reorientation is composed from the previous step's end (`compose_reo(compose_reo(inverse(from.reo), prev.to.reo), reo)`),
the first one starts from `from.reo` (toggled if mirrored), reversed steps iterate frames backwards, the duplicated joint
frame between steps is popped, and finally every frame is translated so that the mean `Core` position (xz) of the whole
drill is the origin. `compose_reo`, `inverse_reo`, `apply_reo` and `mirror` are JS copies (`src/gm.js:304-412`); `yrot`
has the same formula as the C++ one (`src/gm.js:351-358` vs `src/math.hpp:73-80`, §4.2); the rest was not compared
**[unverified]** (the oracle can). Non-`detailed` transitions get their frames doubled by midpoint interpolation on load
(`src/composer.js:596-615`).

**Playback** (`src/composer.js:433-469`): per rendered frame `k += min(deltaTime_ms / 100, 2)`, so one keyframe step
every 0.1 s; with the doubling, a non-detailed transition runs at 5 segments/s and a `detailed` one at 10, the
same speeds as §6.4. The last transition holds 6 more steps and the loop restarts at frame −5 (clamped keyframe index), i.e.
pauses of about 0.5-0.7 s (**[unverified]**: derived from the counters, not observed), versus the 0.8 s of C++ (§6.4). The drawn pose
chases the ideal pose, `thepos = lerp(thepos, ideal, 0.20)` per **rendered frame** (0.12 while the pointer is over the slider, which also pauses playback, `src/composer.html:53`, `src/composer.js:435`)
(`src/composer.js:426-431`), so smoothing is frame-rate dependent, like the C++ chaser (§6.5).

### 8.5 Explorer (`explorer/index.html`)

**Purpose.** Walk the graph by pointing at it: hover a neighbouring position and the figure performs the transition.

**Inputs.** `?id,id,…` = the selected positions (the first is the current one); none → one random position
(`src/explorer.js:185-202`). Its URL is rewritten on each selection change (`src/explorer.js:43-50`). Links in: from search
via position pages, from the composer with the drill's nodes.

**Graph** (code in `src/graphdisplay.js`; `search.js` carries its own copy of the same functions, `src/search.js:4-260`; d3 v3
force layout: charge −1000 selected / −300 others, gravity 0.01, link distance 200, `src/graphdisplay.js:332-352`, 30
pre-ticks `src/explorer.js:109-111`): nodes are circles
(radius 7, or 50 if selected; current one light green) labelled with up to 3 description lines; links are lines
coloured **red** if the transition has property `top`, **blue** if `bottom`, else black (`src/explorer.js:78-98`), with a
big arrowhead if the target is selected (`src/graphdisplay.js:168-171`). Hover shows an info box: position = description,
tags, `(p{id})`; transition = description, `(t{id} @ line {n})` (`src/graphdisplay.js:173-192`). Dragging moves nodes.
**Edit node selection** (auto-on when ≤ 5 selected): click a node to add or remove it from the selection (never below 1);
with it on, all neighbours of the selected nodes are shown too (`src/explorer.js:56-76,121-137`).

**Navigation.** `mouse_over_position` → `mouse_over_node` → `try_move(candidate)` (`src/graphdisplay.js:115-123,241-295`,
`src/explorer.js:155-162`): if the hovered node is
reachable by **one stored transition** (forward from the current node, or backward along an incoming one), that
transition's frames are queued with the reorientation composed so the figure continues from where it is (the first frame
of the transition is skipped; the reversed case queues frames backwards); queued frame ids
`transition·100 + i` let a back-and-forth cancel itself (`queue_frame`, `src/graphdisplay.js:247-256`). Only steps with
`reverse == false` are scanned (`src/graphdisplay.js:261,279`): forward along `outgoing`, backward along `incoming`; the reversed
entries of §2.6 are redundant, so nothing is lost. Note it therefore also walks **non-bidirectional** transitions backwards. Playback speed grows
with the queue length: `kf += max(0.1, queue^1.5/500)` per rendered frame (`src/graphdisplay.js:299-312`); drawn pose
smoothing 0.20 (`src/graphdisplay.js:314-315`, `src/explorer.js:1`). The camera target follows the pair's mean `Core`: xz at 0.5 % per frame, y at
5 % (rising) or 0.5 % (falling), height `max(0, y − 0.5)` (`src/graphdisplay.js:317-327`). All of this is per rendered frame.

**Controls** (`src/explorer.html:48-69`): view select (external, red, blue), **mirror** (flips the current pose and the
accumulated reorientation, `src/explorer.js:22-26`), a 0-40 slider that sets the camera's yaw (`alpha = 0.16·v`,
`src/explorer.js:28-32`), and links to search (`?` + the current node's tags) and to the composer (`?p{id}`)
(`src/explorer.js:139-153`).

### 8.6 Web editor (`editor/index.html`): UX only

A WebGL canvas running the C++ `EditorCanvas` (shader renderer, §7) next to a sidebar written in HTML
(`src/editor.html:26-193`). Semantics of every operation are §9; this is what the user sees and does.

**Three modes**, colour-coded tabs (`src/editor.html:45-166`, `src/editor.js:121-134`):
- **Browse** (blue): *Go to* (a `prompt()` accepting `p34`, a position name, `t1383`, a transition name, `l31432` for a
  line number, or `last-trans`, `src/editor.js:157-166`, `src/metadata.cpp:107-119`), *Confine to path* checkbox,
  *Mirror view*, *Load database* (file input).
- **Playback** (green): the path plays; no other controls.
- **Edit** (red): *Transition*: Split, Prepend New, Append New (the last two ask for a position number with `prompt()`, `src/editor.js:527-537`);
  *Frame*: Insert, Delete, Swap players, Mirror; *Transform*: translate / rotate; *Manipulate*: single joint / whole
  player / both players; *Confine to*: horizontal edits, linear interpolations, local edits; *Database*: Save, Undo last change.
  Selecting *rotate* unchecks "linear interpolations" and replaces "single joint" by "both players"; picking *single joint*
  switches back to translate, because rotating one joint makes no sense (`src/editor.js:547-566`).

**Path display** (`src/editor.js:392-525`, CSS `pathTable`): the current *path* (a chain of transitions) drawn in
monospace: `█` for the end positions of each transition, `o` for intermediate keyframes, `┏━┓`/`┃` box-drawing for the
segments between keyframes, each transition numbered with its name; hovering a keyframe or segment moves the 3D
figure there and highlights it lime (`src/editor.js:229-294,301-360`). Above and below the path, buttons list the
transitions that can be **prepended / appended** (tooltip shows the other position); `x` on the first and last
transition removes it from the path (`src/editor.js:380-387,405-418,511-524`). A metadata box shows the description of
the position or transition under the cursor (read-only outside Edit; there it has a Save button,
`src/editor.js:539-545`). Changes are listed as *Added: p…, t…* (green) and *Changed: …* (red) with links that jump to each
(`src/editor.js:176-227`, `src/editor_canvas.cpp:99-130`).

**Canvas input** (`src/editor_canvas.cpp`): mouse **wheel** moves along the path (`:342-351`); **right button drag on a joint**
scrubs the path by choosing the location whose projected joint position best follows the cursor (`:515-532`, scoring in
`whereBetween`/`determineNextPos`, `:9-46`); **left button drag on a joint** edits it in Edit mode (left press pushes an undo step and
fixes the joint nearest to the cursor, `:79-97,534-537`); **middle button drag** orbits the camera (`:389-395`); arrow keys and
Home/End move the camera (`:189-206`, keys ignored while the metadata box has focus, `src/editor.html:184-185`,
`:880-883`). Camera values are §7.5. `set_view` (`:959-966`) is bound but the editor page has no control for it; only the search page's canvas selects first-person views (`src/search.html:54`).

**Persistence.** There is no server: the original DB is the preloaded file; *Load database* reads a local file
(`FileReader`, `Module.editor_loadDB`, `src/editor.js:109-119`, `src/editor_canvas.cpp:712-727`); *Save* serialises with the
C++ writer (§1.5) into a Blob and triggers a download named `GrappleMap.txt`, or `<loaded name>.new`
(`src/editor.js:148-155`, `src/editor_canvas.cpp:729-738`). Leaving the page with unsaved changes triggers the browser's
confirmation (`src/editor.js:570-580`). Undo is in-memory, pushed before each edit operation (§9).

### 8.7 Differences from the C++ viewer

| Aspect | C++ (§7) | JS tools (`gm.js`) |
|---|---|---|
| Body | per-limb table, icosphere joints, fat triangles | own `segments`/`joints` copies (§3.2): two half-pillars of 16 faces per visible segment, 8-face spheres on all 23 joints (`src/gm.js:59-88,186-253`); no torso triangles |
| Skin colours / lights | §7.2-7.3 | red and blue diffuse (0.1,0,0)/(0,0,0.1) with specular, power 0 (`src/gm.js:259-270`); hemispheric + 2 point lights (`src/graphdisplay.js:377-384`) |
| Floor | ±2 m grid | ±3 m grid, 0.5 m step, `grey` lines (`src/gm.js:280-295`); white background |
| Camera | §7.5 | Babylon `ArcRotateCamera` (alpha 0, beta π/4, radius 2.5, radius limits 1-4, `lowerBetaLimit 0`), wheel precision 30; first person `FreeCamera`, fov 1.6 rad, minZ 0.05, looking at the mean of the two **fingers** (C++: the hands) (`src/graphdisplay.js:359-375`, `src/explorer.js:164-179`) |
| Speeds | segments/s of §6.4 | same numbers, but per-frame constants (drag 0.20, camera lerp) and the composer's pauses differ (§8.4) |
| Handedness | right-handed (§4.2) | Babylon scenes are **[unverified]** left-handed by default (unless `useRightHandedSystem` is set), and no `src/*.js` sets it (grep); the typedoc confirms the property exists (`https://doc.babylonjs.com/typedoc/classes/BABYLON.Scene`) but does not state its default, and the library version is unpinned, so whether the JS view is mirrored remains **[unverified]** |
| Frame logic | `follow`/`Playback` | JS re-implementation (`follow`, `compose_reo`, `try_move`), not shared with C++ |

### 8.8 Input for phase 5

Worth keeping (they define the original's UX):
- **State in the URL** for search (tags) and composer (step list); every view is linkable.
- Tag search with include/exclude, refinement dropdown with counts, substring search; thumbnails + looping clips as results.
- **Hover-to-walk** in the graph (explorer, search preview): the figure performs the transition instead of teleporting.
- Composer: pre/post choice lists from `incoming`/`outgoing`, view select (external, red, blue) + mirror, pause, slider,
  random drill, info mode.
- Editor: path display with keyframe/segment hover, wheel and right-drag scrubbing, the three modes, the dirty list,
  undo, metadata editing, load/save of the DB file by download.
- Position page content: in/out transitions grouped by `top`/`bottom` tint, tag links, neighbourhood graph two steps out,
  dead-ends/untagged lists (`todo.html`).

Free to redesign: the technology (Babylon, d3, emscripten, Graphviz SVG), the pre-rendered 8-view PNG/MP4 store and its
naming, polling timers, `prompt()` dialogs, the d3 layout constants, panel layout and widths, per-frame smoothing
constants (use time-based), the unpinned Babylon dependency.

Open points: handedness of the JS view (§8.7); whether the JS `follow`/`compose_reo`/`mirror` match the C++ ones beyond
`yrot` (oracle); exact timing of the composer's loop pauses; the editor's canvas gestures in detail (`determineNextPos`, `closeCandidates`) are §9.

---

## 9. Editor semantics

What the editors *do to the data*; the UX of the web editor is §8.6, rendering of the overlays §7, the pure functions
(`mirror`, `swap_players`, `between`, reorientations) §5-§6, matching §2.3. Input for phase 6 (own editor), so the
emphasis is on numerics and graph effects. Everything below was read in code; runtime effects deduced but not
observed are marked **[unverified]**. All binaries are built with `-DNDEBUG` (`src/SConstruct:4,16`): **every
`assert` in this section is absent from the real programs**.

Which editor is real. The shared model is `class Editor` (`src/editor.hpp:11-65`), used by three front ends:
the **web editor** (`src/editor_canvas.cpp`, `src/editor.js`: the one that works end to end), the **GLFW editor**
(`src/glfw_editor.cpp`) and a VR editor (`src/vr_*.cpp`, only noted where it differs). The GLFW editor never builds a
selection (it never calls `set_selected`; `go_to(NodeNum)` even clears it, `src/editor.cpp:505-515`), and
`Editor::replace` ignores an edit whose sequence is not in the selection (`src/editor.cpp:393-402`), so by this
reading **GLFW drag/paste/translate/rotate/swap/mirror edits are silently dropped at the pin** (all but paste still push an undo step) (**[unverified]**: chain deduced, not run).
Its code is still cited where it is the only place a thing exists.

### 9.1 Editor state

`Editor` (`src/editor.hpp:13-18`):

| Field | Meaning |
|---|---|
| `graph` | the whole `Graph` (§2), with its own undo journal (below) |
| `selection` | `OrientedPath` (deque of reoriented, possibly reversed sequences) = the *path* shown and edited; empty at start |
| `selectionLock` | "Confine to path" (web default on after load, `src/editor_canvas.cpp:712-727`) |
| `location` | `Reoriented<Location>`: sequence, segment, `howFar ∈ [0,1]`, plus the reorientation under which it is displayed (§5.3); default segment 0 of sequence 0 |
| `playback` | optional `Playback` (§6.4); while it exists `setLocation` is ignored (`src/editor.cpp:446-453`) |
| `undoStack` | `std::stack` of `(location, selection)`; unbounded |

The UI state that is *not* in `Editor` (`EditorCanvas`, `src/editor_canvas.hpp:51-71`): `edit_mode` (false), `chosen_joint`
(the joint grabbed on mouse press), `closest_joint` (nearest to the cursor by squared NDC distance of the
projected joints, `src/editor_canvas.cpp:427-432`), `joints_to_edit` (`"single_joint"`), `confine_horizontal` (false),
`confine_interpolation` (false), `confine_local_edits` (**true**), `transform_rotate` (false). The page's checkboxes are
initialised to the same values (`src/editor.html:61,129-151`).

**The current frame is a location, and edits happen only at keyframes.** `position(Location)` is defined only for
`howFar == 0` or `== 1` by **exact** double comparison (`src/locations.hpp:133-138`). Browsing with the right
mouse button sets `howFar` to the clamped projection `whereBetween` (`src/editor_canvas.cpp:9-16`) and on release
`snapToPos` rounds it to 0/1 if `|howFar − round| < 0.2` (`src/editor.cpp:542-560`), so a keyframe can be edited
only after being snapped or reached with the wheel (which steps whole positions, `retreat/advance`, `src/editor.cpp:109-119`).

**Selection.** `set_selected(seq, true)`: if the selection is empty and `seq` is the location's sequence, the
selection becomes `{seq}` forward; otherwise `seq` must start at the end node of the last element or end at the start
node of the first one (`in_sequences`/`out_sequences`, so a bidirectional one may be added reversed), else it is a
no-op. `set_selected(seq, false)` removes only the first or last element (`src/editor.cpp:121-161`). `go_to(SeqNum)` /
`go_to(NodeNum)` extend or reuse the selection when the target is adjacent, else **clear it and unlock**
(`src/editor.cpp:455-516`); with the lock on, `setLocation` refuses a location whose sequence is not selected
(`src/editor.cpp:450`) and `closeCandidates` only offers selected segments (`src/viables.cpp:113-117`).

**After `Editor::replace`, `replace_sequence` and `branch`** (not after insert/delete keyframe, new transitions or undo) the rest of the selection is re-glued with `reorient_from(selection, i, graph)`
(`src/paths.cpp:309-330`), which recomputes the reorientation of each other element outward from the edited one so
consecutive transitions still meet at their shared node (`gp_connect`; **[unverified]**: its internals are not
read here). Without it a node edit would leave the following transitions displayed in the old frame.

**Undo.** `push_undo` pushes `(location, selection)` and opens a new group in the graph's `Rewindable` journal
(`src/editor.cpp:278-282`, `src/rewindable.hpp:151`); each later mutation of `graph` appends its inverse closure to
the **last open group** (`src/rewindable.hpp:54-58`); `undo` restores location and selection, runs the group's
closures in reverse and drops it (`src/editor.cpp:317-324`, `src/rewindable.hpp:153-160`). Consequences:
- The web/GLFW code calls `push_undo` on every **left** mouse press, edit or not (`src/editor_canvas.cpp:79-97`,
  `src/glfw_editor.cpp:233-249`): one drag = one step, a plain click = one empty step. `swap_players`,
  `mirror_position`, `insert/delete_keyframe`, `branch` and GLFW translate/rotate push one step each, *before* knowing
  if the operation will do anything (a refused one leaves an empty step).
- `append_new`, `prepend_new`, `set_description` and GLFW paste do **not** push: their graph change joins the previous
  group and is undone together with that step (or never, with an empty stack) (`src/editor.cpp:355-387,430-438`,
  `src/glfw_editor.cpp:125-127`).
- `delete_keyframe` pops `undoStack` when the erase is refused but leaves the journal group open
  (`src/editor.cpp:231-235`): from then on stack and journal are off by one, so a later undo restores the older entry's
  location/selection but rewinds an *empty* group, and the older graph change stays (**[unverified]** at runtime).
- Redo does not exist. Undo does not restore playback, lock or `edit_mode`.

### 9.2 Dragging a joint: `spring` and limits

**One drag tick** (web, per rendered frame while the left button is down in edit mode, `chosen_joint` set, not playing
back, `transform` = translate: `src/editor_canvas.cpp:533-537`; rotate has its own path, §9.3): `pos = current_position()`
(the *displayed* position: stored one under `location.reorientation`, §5.3) → move the grabbed joint(s) →
`spring` → `Editor::replace(pos, policy)`. The cursor is absolute, so the joint is moved by the remaining gap
between its projection and the cursor every frame (it converges over frames, it does not integrate a mouse delta):

- `hdragger = R_y(−camera.yaw)(1,0,0)` and `vdragger = R_y(−camera.yaw)(0,0,1)` (the camera-only
  `PositionReorientation`; `src/editor_canvas.cpp:255-264`). With `v` the joint and `xy(·)` = `world2xy` (§7.5):
  `offh = (cursor.x − xy(v).x) / (xy(v + hdragger).x − xy(v).x)`, `offv` the same with `y` and `vdragger`,
  `offy = (cursor.y − xy(v).y)·0.01 / (xy(v + (0,0.01,0)).y − xy(v).y)` (`src/editor_canvas.cpp:270-277`).
- Default: `x += hdragger.x·offh`, `z += hdragger.z·offh`, `y += offy` (screen-x moves along the camera's right
  axis, screen-y moves the joint up/down). With `confine_horizontal`: `x,z += hdragger·offh + vdragger·offv`, `y` unchanged
  (`src/editor_canvas.cpp:282-292`).
- `joints_to_edit`: `single_joint` moves only the grabbed joint and calls `spring(pos, grabbed)`; `whole_player` /
  `both_players` add the **same displacement** to every joint of the grabbed player / of both (`:295-311`), then
  `spring(pos)` with **no** fixed joint. `confine_interpolation` replaces the displacement by
  `pos[j] = prev[j] + (next[j] − prev[j])·t` for the same joint set, with `t = whereBetween(xy(prev[g]), xy(next[g]), cursor)`
  (g = grabbed), where prev/next are the neighbouring keyframes **in the same sequence**; with no neighbour (first/last
  frame) the position is not changed (`:212-252`).

**`spring(Position&, optional<PlayerJoint> fixed)`** (`src/positions.cpp:183-194`): `apply_limits(pos)`, then for
each player `pos[player] = spring(pos[player], fixed joint of that player or none)`. It is **one pass**, not an
iteration to convergence; callers repeat it (once per frame in the drag; the VR "interpolate" button and VR drag start call it 30 times, `src/vr_editor.cpp:104`, `src/vr_joint_editor.cpp:64`, as does
commented-out GLFW code, `src/glfw_editor.cpp:153,183`).

`spring(Player, fixed)` (`src/positions.cpp:142-181`), exact:
1. `r = p` (copy). **Every read uses `p`, every write goes to `r`** (Jacobi style: the update order of joints does not
   matter, only the float summation order below).
2. For each joint `j` in enum order (§3.1) except the fixed one (`continue`: the fixed joint is not touched at all,
   not even by step 4): for each limb `s` of `limbs()` **in table order** (§3.2, 28 entries, all used, visible or not
   `src/players.hpp:126-162`) that has `j` as an end:
   `d = s.length − distance(p[end0], p[end1])`; `force = f(d)` with
   `f(d) = max(−0.3, min(0.3, d/3 + d·d·d))` (literal expression `distance / 3 + distance * distance * distance`, `src/positions.cpp:152`; keep the evaluation order for bit-exactness, ADR 0003); `if |force| > 0.001: r[j] -= normalize(p[other] − p[j]) · force`.
   So a stretched limb (`d < 0`) pulls `j` towards the other end, a compressed one pushes it away; both ends move
   (each by `f(d)`), the fixed joint absorbs the rest of the error.
3. (inside the same loop) nothing else: no angle limits, no symmetry, no momentum, no rigid-body logic.
4. `r[j].y = max(jointDefs[j].radius, r[j].y)` for every non-fixed joint (radii: §3.1).
`normalize` of a zero vector (two coincident joints with `|f| > 0.001`) is a division by zero (**[unverified]**: NaN
propagation not run; `normalize` is not read here).

`apply_limits(Position&)` (`src/positions.cpp:314-322`), every joint of both players, **including the grabbed one**:
`y = max(radius, y)`, `x = clamp(x, −2, 2)`, `z = clamp(z, −2, 2)`. It is also applied inside `Graph::replace` to the
position being written (`src/graph.cpp:20`). There is **no upper bound on `y`**. The encodable range is smaller than the
limits (§1.5: indices ≤ 3843, i.e. `x,z ≤ 1.843`, `y ≤ 3.843`): values between are accepted by the editor and
cannot be written back correctly by `save` (**[unverified]** runtime effect: out-of-alphabet index, §1.5).

`spring` in the oracle: `spring.ndjson` is `spring(p)` **without fixed joint** on every named position
(`tools/oracle/dump/dump.cpp:437-447`, `tools/oracle/README.md:56`): it pins the numerics of steps 1-4 for the "no fixed
joint" case only; the fixed-joint variant is not dumped (§9.9).

### 9.3 How an edit reaches the graph: `Editor::replace` and `Graph::replace`

`Editor::replace(p, policy)` (`src/editor.cpp:389-404`): acts only if the location is a keyframe **and** its sequence is
in the selection (else silently nothing); it writes `inverse(location.reorientation)(p)` (back to the stored frame) with
`Graph::replace(pis, …, policy)` and then `reorient_from` (§9.1).

`Graph::replace(pis, p, policy)` (`src/graph.cpp:18-108`; summary in §2.9): `apply_limits(p)`; **return if the stored
position already equals `p`** (`:22`, no dirty flag). If `pis` is **not** an end of its sequence (`node(pis)` empty,
`:7-13`) the position is just written and the sequence marked modified, whatever the policy. If it is an end:

| Policy | Effect on the end |
|---|---|
| `propagate` | node position := `inverse(rn.reorientation)(p)`; **every** sequence starting/ending at that node gets its first/last stored position recomputed from the node (`graph[we.from]`), all marked modified (`:37-66`). All transitions of the node change together. |
| `unintended` | `p` must be a reorientation (rotation about y, translation, mirror, swap, §5.3) of the node's position: write `p` into the sequence's stored position (`apply()`, marks it modified), then `rn.reorientation := is_reoriented(node.position, p)`; the node position and the other edges are untouched (`:68-76`). If it is not, release builds dereference an empty optional (UB, **[unverified]**). |
| `local` | write `p`; if it is a reorientation of the old node only the reorientation changes, else `find_or_add(p)` (§2.3) and the end is re-attached to another (possibly new anonymous) node, recomputing `in/out` of both (`:77-104`). The old node is never deleted. |

Which policy each entry point uses (web unless noted):

| Edit | Not an end | End (node) |
|---|---|---|
| Drag a joint | `unintended` (= plain write) | `confine_local_edits` off → `propagate`; on → `unintended` only if `both_players && confine_horizontal`, else **ignored with a console message** (`src/editor_canvas.cpp:314-326`) |
| Rotate drag (`yrot(Δcursor.x)` about the world origin of all joints of the chosen set, `src/editor_canvas.cpp:397-420`) | plain write | lock off → `propagate`; on → `unintended` if `both_players`, else silently ignored |
| Swap players / mirror frame (`X`, `M`) | `unintended` | `unintended`: the node is kept and only `rn.reorientation` gets `swap_players`/`mirror` set (`is_reoriented` tries the swapped and mirrored forms, `src/positions.cpp:233-259`), i.e. a node-end swap **does not alter any stored node data** and the stored end position is the swapped one (`src/editor.cpp:240-265`) |
| GLFW translate (`numpad 4/6/8/2`, ±0.02 or ±0.2 with shift in x / z) and rotate (`numpad 7/9`, `yrot(±0.05)`) | `unintended` | `unintended` (`src/glfw_editor.cpp:102-106,188-210`) |
| GLFW drag | | `propagate` (`src/glfw_editor.cpp:405`); GLFW paste: `local` |

So with the defaults (lock on) a node keyframe can only be rotated/translated/mirrored/swapped as a whole, or edited
if the user explicitly switches "local edits" off; a free edit at a node then changes **all** transitions that meet there.

### 9.4 Operations

All act on the location (`*location`), most need a keyframe. "Ignored" = a message on `stderr`, nothing changes.

| Operation (web fn / GLFW key) | Preconditions | Effect on the graph | Invariants |
|---|---|---|---|
| **Insert keyframe** (`insert_keyframe` / `Ins`) `src/editor.cpp:267-276`, `src/graph.cpp:122-128` | none (works mid-segment; at a keyframe, `howFar` 0 or 1, it **duplicates** the frame, the GLFW help calls it "duplicate current frame") | inserts `at(location)` (the interpolation `between` of the two keyframes at `howFar`, §6.1; **no `spring`**) after segment `i`: `positions.insert(i+1, …)`; location → segment `i+1`, `howFar 0`; sequence marked modified | ends unchanged, nodes untouched. Position index is a `uint_fast8_t` (`src/indexed.hpp:60`): more than 255 positions is **[unverified]** |
| **Delete keyframe** (`delete_keyframe` / `Del`) `src/editor.cpp:219-238`, `src/graph.cpp:169-211` | keyframe; ignored if the selection is non-empty, the position is a node end and it is not the first position of the selection's first sequence nor the last of its last one (interior joints of the path are protected); ignored (graph level) if the sequence has 2 positions, or deleting the first (last) would make `positions[1]`≈`back` (`front`≈`prev(back)`) a self-transition (`is_reoriented`) | removes the frame; if the new first/last frame is now the end, it is re-matched with `find_or_add` (§2.3): the sequence may attach to another or **new anonymous node**, `in/out` recomputed for old and new (`:193-208`); the old node stays. Location moves to the surviving frame (`go_to(PositionInSequence)`, only effective if the sequence is in the selection, else the location may dangle, **[unverified]**) | no self-transition; ≥ 2 positions |
| **Swap players / mirror frame** (`swap_players`, `mirror_frame` / `X`, `M`) `src/editor.cpp:240-265` | keyframe | §9.3 (`unintended`), applies `swap_players`/`mirror` (§5.1-5.2) to the **displayed** frame only; neighbours are not touched, so interpolation jumps | |
| **Split / branch** (`split_seq` / `B`) `src/editor.cpp:284-315`, `src/graph_util.cpp:32-58` | keyframe, **not an end**; not if either half would be a self-transition | `a = positions[0..i]` replaces the sequence in place (same `SeqNum`), `b = positions[i..]` is **appended** as a new sequence with `" (cont'd)"` appended to its first description line (`detailed`/`bidirectional` copied); both ends found with `find_or_add` (the split frame becomes a node, matched to an existing one if it is a reorientation of it), `in/out` of the affected nodes recomputed; flagged modified/added. The selection gets the new sequence inserted after the current one and is re-glued; location steps back to `howFar = 1` of the previous segment if it was at `0` | |
| **Prepend/append new** (`prepend_new(n)`, `append_new(n)`; no key) `src/editor.cpp:355-387` | selection non-empty (else nothing) | new sequence `"new"`, positions `{last position of the selection's last sequence, node n's position}` (append) or `{node n's position, first position of the selection's first}` (prepend), `detailed`/`bidirectional` false, **appended** to the sequence list (`insert`, `src/graph_util.cpp:5-10`); then selected. Uses the stored frames of the sequence, ignoring the selection's reorientation and reversal (`// todo: not for reverse steps`). `Graph::set` refuses it (`"Transition must not end where it starts"`) when both ends are reorientations of each other, but `insert` still returns the would-be `SeqNum` and the selection step then does nothing. `n` is not range-checked (`NodeNum{n}` from a `prompt()` number, `src/editor_canvas.cpp:811-816`; out of range is UB **[unverified]**). No `push_undo`. | |
| **Set description** (`set_node_desc`, `set_seq_desc`) `src/editor.cpp:430-438`, `src/graph.cpp:357-373`, `src/editor_canvas.cpp:851-867` | node: location at a node end; sequence: any | text split on `'\n'` into lines. Node: marks `added` if it had none (**it becomes a named, saved position**), else `modified`. Sequence: `detailed`/`bidirectional` are **re-derived from the new lines** (`properties_in_desc`, §1.2); `compute_in_out` is **not** rerun, so the node `in/out` lists keep the old `bidirectional` until some other operation recomputes them (**[unverified]**: deduced from `:243-277` vs `:366-373`). `lines("")` gives one empty line, so clearing a name does not make the node anonymous again: it saves as a named position with a blank first line, and two such nodes would fail the duplicate-name check at the next load (`:279-285`; boost `split` of `""` yielding one token is **[unverified]**) | |
| **Select / unselect, lock, mirror view, playback, go to** | | no graph change (§9.1). *Mirror view* (`I` / "Mirror view") only flips the mirror flag of location and selection (§5.4) | |
| **Undo** (`Ctrl+Z` / button) | non-empty stack | §9.1 | |
| GLFW only: **copy / paste** (`Ctrl+C/V`) | | clipboard = `current_position()` (displayed); paste = `replace(clip, local)`: a free write that may re-attach a node end to another node (§9.3) | |
| VR only: `replace_sequence` (the only caller), "interpolate" (`between` of prev/next + 30×`spring` + `propagate`, `src/vr_editor.cpp:92-107`) | | not covered | |

**Not in the original** (no code path in any front end): delete a sequence (`erase_sequence`, `src/graph_util.cpp:12-30`, has
no caller; it refuses the last sequence and returns `max(sn−1, 0)`), delete or rename a *position* other than by
`set_description`, merge sequences, reverse a sequence, create a position from scratch (a "new" transition copies
existing positions), reorder sequences, move a sequence between selections. Nodes are never removed from `graph`
(`Graph::erase`/`set` leave orphans), which is harmless for saving (§9.5).

`Graph::set(num, seq)` (`src/graph.cpp:130-167`; §2.9) is the primitive behind branch/new: reject a self-transition,
`find_or_add` both ends, replace in place (`modified`) or push (`added`), recompute `in/out` of the new ends only.

### 9.5 Persistence on save

- **GLFW/VR**: key `S` / VR button call `save(graph, dbFile)` (`src/glfw_editor.cpp:224-226`, `src/vr_editor.cpp:83`),
  which opens the target with `std::ofstream(filename, binary)` — **truncating, in place**, no temp file, no backup,
  no error check on open or write (`src/persistence.cpp:235-239`; the failure paths are **[unverified]**).
- **Web**: `getDB` runs the same `save` on an `ostringstream`, converts UTF-8 to a `wstring` for the JS bridge
  (`src/editor_canvas.cpp:729-739`), and the page offers it as a download named `GrappleMap.txt` / `<loaded>.new`
  (`src/editor.js:148-155`). The page never writes the repository file.
- **Content and order**: §1.5. In editor terms: all named nodes in node-index order (nodes keep their index; a node that
  gains a name through `set_description` is written at its existing index), then **all**
  sequences in sequence-index order (new ones last). `save` ignores the `modified` flags: they only feed the web
  "Added/Changed" list (`src/editor_canvas.cpp:99-130`). So a saved file is a normalised rewrite, not a patch:
  block order changes (nodes first), unused anonymous nodes vanish, descriptions are written verbatim, positions are
  rounded to 1 mm (§1.5), and `line_nr` is not stored.
- **`.index`**: `save` does not touch it. `loadGraph(filename)` compares the md5 of the file with the stored hash and,
  on mismatch, rebuilds the graph and rewrites `.index` (`src/persistence.cpp:186-233`; §2.5). The web editor loads from a stream and
  uses an index only for its initial `loadGraph("GrappleMap.txt")` (`src/editor_canvas.hpp:56`); *Load database* (`editor_loadDB`) reads a stream without one.
- **Lost or changed on a round trip through the editor**: everything listed in §1.5, plus node `in/out` staleness
  (not persisted), node merges (§2.3 may attach an edited end to another node; the file then stores the position
  inside each transition, so the node identity is recomputed at the next load, **not** preserved), and the exact
  float values of *propagated* ends (recomputed through the node and its reorientation, `src/graph.cpp:44-62`,
  then rounded on write).

### 9.6 C++ editors vs the web editor

| Capability | Web | GLFW | Notes |
|---|---|---|---|
| Browse path / scrub with right-drag, wheel | yes | yes (opposite wheel sign: web `yoffset > 0` = back, GLFW `yoffset == 1` = forward, `src/editor_canvas.cpp:342-351`, `src/glfw_editor.cpp:251-260`) | candidates from `closeCandidates` (`src/viables.cpp:83-120`), best by `determineNextPos` (`src/editor_canvas.cpp:18-46`) |
| Build selection / lock | yes (list buttons, "Confine to path") | **no** (only `L`) | the root of §9's remark on GLFW edits |
| Drag modes (single/whole/both, horizontal, interpolated, local edits), rotate | yes | single joint only, camera-composed dragger (`// todo: this is wrong`, `src/glfw_editor.cpp:379-406`); ends in `Editor::replace`, so dropped without a selection (**[unverified]**) | |
| Keyframe insert/delete, branch, undo | yes | yes (these act on the graph directly) | |
| Swap players, mirror frame | yes | bound (`X`, `M`) but go through `Editor::replace`, so dropped without a selection (**[unverified]**) | |
| Prepend/append new transition, set descriptions | yes | no | |
| Numpad translate/rotate, copy/paste, `H/J/K/U/N` helpers | no | numpad translate/rotate and paste bound but go through `Editor::replace`, so dropped without a selection (**[unverified]**; copy works); `H/J/K/U/N` are commented out (`src/glfw_editor.cpp:143-222`) | |
| Save | download | in-place file | §9.5 |

### 9.7 Viables and candidates (editor-only helper data)

`determineViables` (`src/viables.cpp:8-104`) is **display only** (the yellow trails of §7): from the current
position it walks outwards along the sequence (and through nodes into adjacent sequences) for the chosen joint,
keeping a frame only if the joint moved ≥ √0.003 m in space and ≥ 0.01 in NDC (`distanceSquared > 0.003` /
`> 0.0001`), stopping at depth 7. `viable`/`closeCandidates` (`:83-120`) decide which segments can be scrubbed for a
joint: the joint must move `distanceSquared > 0.001` (and `> 0.0001` in NDC) between the segment's keyframes; candidates
are the current segment plus its `neighbours`. They only filter which segment the right-drag may jump to.

### 9.8 Input for phase 6

**Reproduce exactly** (data results depend on it):
- `spring` numerics of §9.2 (constants `/3`, `0.3`, `0.001`, limb table order, one pass, Jacobi reads, `y` floor,
  fixed joint untouched) and `apply_limits` (`±2`, `y ≥ radius`, no upper `y`).
  `spring.ndjson` covers no-fixed-joint; ask for a fixed-joint dump before relying on it (open point below).
- `Graph::replace` policies, `find_or_add`/`is_reoriented` re-matching, the refusal rules of delete/split/`set`
  (all use the §2.3 tolerances), the `(cont'd)` suffix, append position of new sequences, `modified/added` as UI state only.
- Save format and order (§1.5, §9.5), including that `save` is a full normalised rewrite.

**Free UX** (not data): gestures and key bindings, panels, `prompt()` dialogs, the path widget, per-frame drag
smoothing, camera behaviour while editing, confirmation on leaving, the number of `spring` passes per second (the original
runs one per rendered frame, so the drag feel is **frame-rate dependent**; choose a fixed tick or iterate to a tolerance and say so in the ADR).

**Original quirks to decide on knowingly in phase 6** (do not copy or fix silently): GLFW edits impossible without a
selection; the undo imbalance after a refused delete and the "joins the previous step" operations; `lines("")`; the
unencodable range between 1.843 and 2 m (and no `y` cap); `unintended` on a non-reorientation (UB); unchecked node index in
`prepend/append_new`; a failed `set` still returning a `SeqNum`; in/out lists not refreshed after toggling `bidirectional`;
`replace` with `local`/`propagate` never rejecting a self-transition (`from == to` after `find_or_add` or a node moved onto another, unlike delete/split/`set`; the next load merges them, **[unverified]**); `propagate` not re-applying `apply_limits` to the other transitions' ends; no delete/merge/reverse operations;
in-place save without backup.

### 9.9 Open points (need the oracle/dumper)

`spring(p, fixed)` (a dump with a fixed joint, since only the no-fixed variant is in `spring.ndjson`); behaviour of
`normalize` on coincident joints; the undo imbalance and the `lines("")` effect (needs a scripted editor session, which
the dumper does not have); `reorient_from`/`gp_connect` semantics after an edit; 255-position overflow; the
runtime result of `unintended` with a non-reorientation under `NDEBUG`; whether the GLFW editor can edit at all.

---

## 10. Data inventory

What the DB contains at the pin, measured on the full dump of the oracle (`./build.sh oracle --full`, dumper version 3,
`build/oracle/full/`, `.index` consistent). Nothing here is fixed or normalized: anomalies are documented, not corrected.
Commands run from `build/oracle/full/` with `jq` (`inventory.ndjson` has one line per block with its `classes`;
`sequences.ndjson`, `graph.ndjson`: `tools/oracle/README.md`). Class rules: `tools/oracle/README.md` "Inventory and
sample" (not repeated here).

### 10.1 Counts

| What | Count | Command |
|---|---|---|
| Blocks | 2,086 | `jq -s length sequences.ndjson` |
| Named positions (1-position blocks) | 601 (blocks 0-600) | `jq -s '[.[]\|select(.kind=="position")]\|length' inventory.ndjson` |
| Transitions | 1,485 (blocks 601-2085) | idem, `"transition"` |
| Positions in total | 8,323 (601 + 7,722 in transitions) | `meta.json` `counts.positions` |
| Nodes | 725 = 601 named + 124 anonymous | `meta.json` `counts` |
| Edges | 1,485 (one per transition) | `jq -s '[.[]\|select(.type=="transition")]\|length' graph.ndjson` |

Order in the file: all named positions first (blocks 0-600), then all transitions. Nodes follow the same order (the
601 named, then the anonymous ones, §2.2). The `.index` cache equals what `loadGraph(istream)` computes
(`meta.json` `index_matches_db`, `index_consistent`: both `true`; this closes the "indexed and non-indexed loads"
point of §2.10). Coordinates `q` span 20…3791 of the 0…3843 grid (§1.3).

**Transition length** (positions per transition, `jq -s '[.[]|select(.kind=="transition")]|group_by(.length)|map("\(.[0].length):\(length)")' inventory.ndjson`):

| Positions | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 20 | 21 | 22 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Transitions | 89 | 339 | 349 | 210 | 147 | 116 | 73 | 48 | 44 | 23 | 10 | 14 | 7 | 6 | 1 | 1 | 4 | 2 | 1 | 1 |

Buckets of `inventory.ndjson`: `2` 89, `3-5` 898, `6-10` 428, `>10` 70. No transition has 19 positions, and none has
1 (a 1-position block is a named position, §1.4). `properties:` (§1.2): `top` 616, `bottom` 558 (a transition has
at most one of them; 311 have neither), `detailed` 159, `bidirectional` 38 (6 are both), `sweep` 2, `transitive` 1;
the named positions have no property. Block descriptions have 1-8 lines (first line included): 1 line 63 blocks, 2
885, 3 686, 4 362, 5 75, 6 14, 8 1.

**Tags** (`tags:` lines, §1.2): 161 distinct tags. Most used: `bottom_supine` 246, `top_kneeling` 203, `standing` 125,
`bottom_turned_in` 68, `half_guard` 55, `full_guard` 51; 27 tags occur once. These are a block's own tags: of the
1,485 transitions, 1,159 have none. The `family` below uses `is_tagged` instead (own tags plus those both endpoints have, `src/metadata.hpp:32-37`), which is why only 850 transitions are `other`.

**Family** (the dumper's fixed tag table, first match, `family` of `inventory.ndjson`; it is an inventory aid, not a
concept of the original):

| Family | `other` | `standing` | `guard` | `side_control` | `back` | `mount` | `turtle` | `leg_locks` |
|---|---|---|---|---|---|---|---|---|
| Named positions (601) | 134 | 111 | 196 | 67 | 35 | 24 | 20 | 14 |
| Transitions (1,485) | 850 | 235 | 231 | 66 | 34 | 23 | 29 | 17 |

### 10.2 Anomaly classes

One row per class of the closed list; counts are blocks (a block can be in several classes). `jq -r 'select(.classes|index("<class>"))|.block' inventory.ndjson`
lists the blocks of any class. First description lines have the literal `\n` shown as in the file.

| Class | Blocks | Observation |
|---|---|---|
| `normal` | 635 | Of 1,485 transitions. Only **9** are in no other class: 605, 612, 799, 800, 1091, 1437, 1710, 1713, 1739 (`normal` ignores the text classes, so most "normal" transitions still have a `\n`, a quote, a `ref:`, …). |
| `named` | 601 | See "named positions" below. |
| `edge_coordinate` | **0** | No coordinate is 0 or 3843 (q spans 20…3791). The class exists for the dumper's test DB and for the port to handle (§1.3); the real DB never exercises it. |
| `long` | 16 | **All cases** (block: positions, first line): 657: 22 `100%`; 769: 16 `escape`; 913: 17 `bottom\nstands up`; 1095: 15 `top steps to\nother side`; 1140: 20 `drop\nseoi-nage`; 1470: 15 and 1471: 20 `leg weave\ntakedown`; 1503: 21 `posture\nand wedge`; 1637: 18 `sweep`; 1664: 15 `whizzer\nsweep`; 1763: 18 `hip pop\nlift`; 1917, 1925, 1934: 15 `tap`; 2075: 18 `backdoor`; 2081: 18 `attack\nleg`. The longest has 22 positions. |
| `bidirectional` | 38 | **All cases**: 621, 653, 817, 838, 1001, 1158, 1275, 1295, 1483, 1627, 1881, 1951, 1964, 2059 (all `...`; 14); 639, 842 `switch\nbase`; 662 `get to\nelbow`; 670, 671 `turn`; 685 `move head\nto other side`; 783 `drop\nknee`; 815 `(un)pin\nknee`; 834 `switch\ngrips`; 836 `(un)mount`; 845 `bottom trades\nneck frame\nfor overhook`; 857 `switch near\nleg control`; 1021, 1086 `reverse`; 1048 `switch\nstance`; 1058 `flatten`; 1161 `(un)kneel`; 1236 `to 50/50`; 1312 `step in/out`; 1347 `switch\nhead side`; 1414 `to/from\nkimura`; 1421 `top bends`; 1825 `control hip\nand shoulder`; 1894 `switch\nframe`. Lengths 2-7. |
| `detailed` | 159 | Count and the command only (6 are also `bidirectional`: `jq -c 'select(.classes|index("detailed") and index("bidirectional"))|.block' inventory.ndjson`). |
| `endpoint_mirror` / `endpoint_swap` / `endpoint_mirror_swap` | 217 / 332 / 75 | Transitions whose `reorientation_from` or `_to` has mirror only / swap only / both (§5.4). The classes overlap when the two ends differ (43 transitions are in two): 581 of 1,485 transitions have a mirror or a swap at some end, 904 are pure rotation + translation at both. |
| `duplicate_description` | 894 | 892 transitions and **2** named positions (249 `spiderweb w/o\nleg over head`, 477 `spiderweb\nw/o leg\nover head`: the lookup name replaces `\n` by a space and so differs only in where the line breaks fall, hence the same name; `node_by_desc`, `src/metadata.cpp:81-89`). Of the transitions, **136 are named `...`** (the continuation marker, which `step_by_desc` cannot tell apart, `src/metadata.cpp:66-69`) and 756 others share a name with another transition (`escape` 23, `tap` 22, `stand up` 18, `sweep` 18, `pass` 14, …). Duplicates among transitions are accepted by the loader (no uniqueness check, §1.7); two named positions with an identical **full** description would be rejected (§2.1), which is not the case here. |
| `description_newline` | 1,281 | 549 of 601 named positions and 732 transitions have a literal `\n` in some line. (§1.8 counts 1,282 *lines*: block 389 has it in two lines, `triangle\nbroken by\nknee in butt` and `freshly broken\nstanding\ntriangle`.) The 52 named positions without one have single-line names (74 `toe hold`, 84 `gator roll`, 105 `chill dog`, 109 `swim move`, 112 `new jersey`, …). |
| `description_utf8` | 9 | **All cases**, the 9 lines of §1.8: `¼` in 20 `smashed ¼\nvs whizzer`, 38 `¼ clinch w/\nknee on ground`, 56 `flat ¼ w/\nhead+arm`, 178 `¼ clinch\nknee battle`, 191 `¼ clinch\nw/ underhook`, 200 `¼ clinch`; `¾` in 201 `¾ mount`, 414 `¾ mount\nw/ head&arm`; and 1568 (a 12-position transition) `escape\nto honey`. In 1568 the non-ASCII is in the `ref:` line (curly quotes `‘ ’`), not in the first line; the other 8 are `¼`/`¾` in the name. |
| `description_quote` | 997 | A `"` in a line: 1,136 of the 1,142 such lines are `ref:` lines (book/DVD titles), 5 other description lines, 1 `note:`. Named positions: only 3 (164 `coming up\non distant\nsingle`, 203 `mount w/\ndouble unders`, 273 `power\ndogfight`), each in its `ref:` line. |
| `has_ref` | 1,058 | 1,208 `ref:` lines (§1.8). |
| `has_note` | 304 | 302 `todo:` and 4 `note:` lines. |
| `error_or_unmatched` | 239 | 239 transitions with an endpoint on an anonymous node (§10.3). A DB with a load error does not produce a dump, so there is no error case. |

**Named positions that no transition touches** (5; not in `error_or_unmatched`, §2.2): block = node = 111
`kung fu move\nw/ leg trapped`, 250 `standing\nvs darce`, 292 `completed\no-soto-gari`, 306 `butterflies engaged w/\nover/under body lock`,
546 `full domination\ntop lock half`. The inventory leaves them as nodes with no in or out edge.

**Named positions** have a first line that is the position's name; no named position has a `properties:` line, and
the 601 are distinct as a full description (the graph constructor accepts the DB).

### 10.3 Open points deferred to this section

- **Anonymous nodes: 124** (nodes 601-724; `meta.json` `counts.anonymous_nodes`; `jq -s '[.[]|select(.type=="node" and .block==null)]|length' graph.ndjson`).
  An anonymous node is a transition end that matched no named position and no earlier anonymous node. Degree
  (transitions per anonymous node, either end): 1: 45, 2: 29, 3: 39, 4: 8, 5: 3. 239 transitions touch an anonymous
  node, 28 of them at both ends. Nothing is repaired: they are loaded as the original does (§2.2).
- **Self-loops: exactly one.** Transition index 1225 (block 1826, `switch\nside`, 9 positions, `properties: top`, not
  `bidirectional`, a `ref:` line; `line_nr` 32712) has `from = to = node 506` (`parallel turtle\nw/ hip and\nshoulder control`).
  `jq -c 'select(.type=="transition" and .from==.to)|[.index,.block,.from]' graph.ndjson` → `[1225,1826,506]`. Its two
  ends match node 506 through different reorientations: `from` with `swap` and a translation of (0.4, 0, ~0),
  `to` with `swap` and `mirror` (translation (0.298, 0, 0.014), angle −0.048), i.e. the end is the mirrored start: it is
  a genuine "switch side", not a degenerate edge. Node 506 also has 5 other transitions (blocks 1825, 1831, 1929, 1974,
  1992). It is the §2.4 mechanism (the same node found for both ends).
  - **Consequence for §6.2 / §6.8.** The direction rule of `follow` (forwards if `from == n`, tested first) walks it
    forwards. In `in`/`out`, the lists that `in_paths`/`out_paths` (`src/paths.cpp:262-300`) and `step_by_desc` use, a
    *reversed* step only exists for `bidirectional` edges (`src/graph.cpp:265-268`), and this one is not
    bidirectional, so no such path starts with it reversed. Reversed entries do exist elsewhere: `in_out` gets
    `{s, true}` for every edge ending at the node (`src/graph.cpp:256`, §2.6; node 506 has `{1225, true}`), used by the
    editor's `gp_connect`/viables (`src/viables.cpp:69-72`), and the composer parses `-N` as `reverse` for any transition
    (`src/composer.js:568-574`); those are phase-6 concerns, not the `follow` case. The dump plays
    it forwards like any other transition (`playback.ndjson` line for block 1826: 95 frames, caption `switch side`).
    A port must still accept it (§2.1), and a *new* bidirectional self-loop made in the editor would hit the `follow` case.
- **Pillar basis degeneracy (§7.1): none.** `a = normalize(cross(to − from, (1,1,1) − from))` is zero only if the
  limb's pillar line passes through `(1,1,1)` or `from == to`. Computed with the §7.1 rule over **every pillar** (the 15
  visible limbs of `body.json`; the 7 with a `mid_radius` split in two, so 22 per player) of: the stored positions of
  all 8,323 positions (366,212 pillars), their two canonical orientations (`orient_canonically_with_mirror` and
  `_without_mirror` of `ops.ndjson`, the same count each), and all `raw` and `smooth` frames of the 1,485 transition lines (135,594 frames; the `chain` line's 140 give the same result) in
  `playback.ndjson` (5,966,136 pillars). Result: 0 pillars with a zero `cross` (so no NaN). Tightest margin, as
  `|cross| / (|to − from|·|(1,1,1) − from|)` (the sine of the angle between the limb and the direction to `(1,1,1)`): 0.0042
  stored (block 1669, position 1, limb 4-6), 0.0057 / 0.0047 canonical, 0.00047 over the playback frames (block 1032,
  smoothed frame 42, limb 4-6): about 0.03°-0.33° (limb 4-6 in the stored and playback cases, player 0 and player 1 respectively), small but not zero. **Scope:** this covers the orientations the dump
  has, not the world positions of an interactive session (`Playback` chaser positions, editor drags), where
  `(1,1,1)` is the same fixed point but the figure is placed freely (§7.1, `[unverified]` there remains for those). The
  second basis vector is `cross(to − from, a)`, which cannot vanish if `a` exists.
- **Not answered by this dump** (left open): whether a transition end is within the `basicallySame` threshold of two
  nodes (so that node order decides, §2.3); whether two named positions are reorientations of each other (the dump
  records the node each end matched, not the alternatives); the `basicallySame` boundary cases. They need an
  additional dumper pass over the pairs, not a different reading of this one; follow-up if phase 2 needs them.

### 10.4 How the sample was chosen

The committed fixture (`tests/fixtures/oracle/`) is a stratified selection of the blocks above: `tools/oracle/sample.tsv`
(`index`, `class`, `reason` per row: the `reason` records the selection) and "Inventory and sample" of
`tools/oracle/README.md` (class rules, per-file sampling, sizes). Every class of §10.2 has at least one row; the empty
`edge_coordinate` is the one allowed-empty class (`-`).
