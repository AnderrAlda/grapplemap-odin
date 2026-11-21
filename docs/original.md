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
3. Player model: *pending*
4. Units and axes: *pending*
5. Transforms: *pending*
6. Interpolation and playback: *pending*
7. Rendering and camera: *pending*
8. Editor: *pending*
9. Controls and UI: *pending*
10. Observed in the DB and oracle: *pending*

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
- Counts of blocks, named positions and transitions are deferred to section 10 (they need the oracle).

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
   is the `SeqNum`/`t<N>` number (§2.7).
5. **in/out lists** are computed at the end for every node (`src/graph.cpp:298-299`, §2.6).
6. `data.forget_past()` clears the undo history (`src/graph.cpp:301`).

Nothing checks the invariant `!is_reoriented(positions.front(), positions.back())` (`src/positions.hpp:16`) when
loading: only `Graph::set` (editor insertions) rejects it (`src/graph.cpp:134-138`). A DB transition whose end
positions are reorientations of each other would load with `from` and `to` the same node. Not checked on the DB:
**[unverified]** (dumper).

Types: `NodeNum` is `uint16_t`, `SeqNum` `uint_fast32_t` (`src/indexed.hpp:57-59`); `num_nodes()` returns `uint16_t`
(`src/graph.hpp:123`) and `num_sequences()` too (`src/graph.hpp:122`), so more than 65535 nodes or sequences would
wrap silently. Far from the DB size (1485 transitions).

**Node data** (`src/graph.hpp:41-52`): `NamedPosition` (position, description, `line_nr`) + `in`, `out`, `in_out`
(§2.6) + `modified` flag (editor). **Edge data** (`src/graph.hpp:54-66`): the `Sequence` (description, positions,
`line_nr`, `detailed`, `bidirectional`) + `from`, `to` + `modified`.

### 2.2 Anonymous nodes

A node created by `find_or_add` has an **empty description** and no `line_nr` (`src/graph.cpp:222-233`): its position is
the position passed in, *as is* (not normalized) and the returned reorientation is the identity
(`PositionReorientation{}` = zero offset, angle 0, no swap, no mirror; `src/positions.hpp:79-80`). It is
appended at the end of `nodes`, so anonymous nodes are numbered after the 601 named ones, in order of first
need (§2.4). They are never saved (`save` skips nodes with empty description, `src/persistence.cpp:243-248`; their
edges are written, `src/persistence.cpp:250`), which is why the index (§2.5) exists: it makes the numbering reproducible.
The number of anonymous nodes in the DB is runtime data: pending (§10).

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
   (`src/positions.cpp:77-89,130-136`; the joint pairs in `src/players.hpp:73-` `mirror(Joint)`).
3. If `swap_players`: swap player 0 and player 1 (`src/positions.hpp:68-71`).

**`basicallySame(a, b)`** (`src/positions.hpp:49-54`): for every `PlayerJoint` (player 0's 23 joints, then player 1's,
§1.3 order), squared Euclidean distance (`src/math.hpp:190`) ≤ `0.0016` m² (i.e. ≤ 4 cm); the first joint above it
returns false. Strict `>` fails, so a distance of exactly the threshold passes. Same threshold for all joints (no per-joint radius). Not an equivalence relation (not transitive), so
**the candidate order below decides the result**.

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
  `angle(V2 v) = atan2(v.x, v.y)` (`src/math.hpp:267`; so for `(x, z)` it is `atan2(x, z)`). No wrapping of the
  difference into (−π, π]: it is not needed because only `sin`/`cos` of it are used.
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
`to` can match a node created for `from` of the same transition only if they are reorientations of each other, which
the invariant forbids (§2.1), so in a valid DB it does not.

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
  transitions reads out of bounds (UB). With a matching md5 this should not happen (written by the same code
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
the same node numbering with or without it. A cached index from the original, if used, has to be checked for `n >
num_nodes()` instead of aborting. [unverified] on the DB: that the cached and uncached paths give identical graphs
(needs the dumper run with and without the `.index`).

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
1. If `desc.size() >= 2`, `desc[0] == 'p'` and the rest is all digits (`all_digits`, `std::isdigit` per byte,
   `src/util.hpp:83-86`) → `NodeNum{uint16_t(stoul(desc.substr(1)))}`, **before and instead of** any name lookup, and
   **not range-checked** (a node index ≥ `num_nodes()` is returned as is; `stoul` throws `out_of_range` for numbers
   that do not fit an `unsigned long`; larger than 65535 wraps by the cast). A named position literally called `p12`
   can only be reached by index.
2. Else the first node in index order whose description is non-empty and whose first line (with the replacement)
   equals `desc`; anonymous nodes (empty description) are skipped. Duplicates of the first line are possible (only
   whole-description duplicates are rejected, §2.1): the lowest index wins.
3. Else none.

`step_by_desc(g, desc, from?)` (`src/metadata.cpp:66-79`): scans sequences in index order; candidate if the first
line (with replacement) equals `desc` **or** `desc == "t" + to_string(seq index)`. Note `g[sn].description.front()` is
unconditional here, so a transition with an empty description would be UB (the parser can produce one, §1.7). Without `from`
(`from` is an optional `NodeNum`) the first candidate is returned as `{sn, false}`. With `from`: returns `{sn, false}` if `edge.from == from`; else
`{sn, true}` if `bidirectional` and `edge.to == from`; else it **continues** with the next candidate.

`named_entity(g, s)` (`src/metadata.cpp:107-124`), used by the editor (`src/editor.cpp:82`,
`src/editor_canvas.cpp:827`) in this order:
1. `"last-trans"` → last sequence (`num_sequences() − 1`; with no transitions the unsigned subtraction wraps).
2. `l<digits>` (size ≥ 2): the first **node** whose `line_nr == N`, then the first **sequence** whose `line_nr == N`.
   If neither matches, **it falls through** to 3 (no early return). `line_nr` semantic is **[unverified]** (§1.4).
3. `step_by_desc` (transitions take priority over nodes), then 4. `node_by_desc` (including `p<N>`), else none.

`readScene` (`src/persistence.cpp:253-300`) uses one description per line with `node_by_desc` first, then `step_by_desc`
with the previous node as `from`; after a node it searches `prev_node.out` for the transition whose target is
that node, `error("could not find transition")` otherwise. The playback/video tools take `--start`/`--demo` through the same two
functions (`src/playback.cpp:71,78`, `src/makevideo.cpp:87,94`).

### 2.9 Mutations that touch matching (editor; for phase 8)

Recorded here because they use the matching of §2.3; full editor behaviour is section 8.
- `Graph::set` (insert/replace/erase a transition): rejects a sequence whose ends are reorientations of each other;
  `find_or_add` on both ends; recomputes `in/out` for the two nodes (for an erase, for all nodes)
  (`src/graph.cpp:130-167`). An anonymous node that loses all its edges **stays** (nodes are never deleted).
- `Graph::replace` with `NodeModifyPolicy` (`src/graph.cpp:18-108`): `propagate` rewrites the node's position (as the inverse
  reorientation of the edit) and every edge end attached to it; `local` re-matches (`is_reoriented` against the old node, else `find_or_add`);
  `unintended` asserts it is still a reorientation. The asserts vanish with `NDEBUG`.
- `Graph::erase` of a frame re-matches the new endpoint with `find_or_add` (`src/graph.cpp:169-211`).
- Description edits of a node: `set_description(NodeNum, …)` (`src/graph.cpp:357-364`).

### 2.10 Open points (need the oracle/dumper)

Not verifiable by reading: number of anonymous nodes; whether any pair of named positions or transition ends are reorientations
of each other; whether any DB endpoint is within the threshold of two nodes (so that order matters); the `line_nr`
offset (§1.4); equality of indexed and non-indexed loads; floating-point boundary cases of `basicallySame`.
