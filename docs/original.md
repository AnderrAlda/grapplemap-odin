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
   is the `SeqNum`/`t<N>` number (§2.8).
5. **in/out lists** are computed at the end for every node (`src/graph.cpp:298-299`, §2.6).
6. `data.forget_past()` clears the undo history (`src/graph.cpp:301`).

Nothing checks the invariant `!is_reoriented(positions.front(), positions.back())` (`src/positions.hpp:16`) when
loading: only editor mutations reject it (`Graph::set`, `src/graph.cpp:134-138`; `Graph::erase`, `src/graph.cpp:179-186`). A DB transition whose end
positions are reorientations of each other could load with `from == to` (likely, not guaranteed: `back` may first
match a lower-index node). Conversely, `from == to` can also arise when both ends are within the threshold of the same
node without being reorientations of each other (they can be up to ~8 cm apart per joint, §2.3). The `Edge`
invariant `*from != *to` (`src/graph.hpp:60`) is only a comment and is never checked, so the port must accept
self-loops. On the DB: **[unverified]** (dumper).

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
of pairs different from the number of transitions (out-of-bounds `index[i]`, `src/graph.cpp:339-340`). [unverified] on the DB: that the cached and uncached paths give identical graphs
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

### 2.9 Mutations that touch matching (editor; for phase 8)

Recorded here because they use the matching of §2.3; full editor behaviour is section 8.
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

Not verifiable by reading: number of anonymous nodes; self-loops (`from == to`, §2.1); whether any pair of named positions or transition ends are reorientations
of each other; whether any DB endpoint is within the threshold of two nodes (so that order matters); the `line_nr`
offset (§1.4); equality of indexed and non-indexed loads; floating-point boundary cases of `basicallySame`.

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
  the editor lets you drag is section 8.
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
  on the `+z` side, looking down at `offset` (algebra on `src/camera.hpp:18`; **[unverified]** on screen: the on-screen look is to be confirmed with
  the oracle images, section 7). The rest of the camera (fov, near/far, controls, smoothing) is section 7.

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

Not verifiable by reading: the on-screen orientation of the default camera (§4.2, compare with oracle images);
`normalRotation` with both cores at the same `xz` and `−0` inputs (§4.3); whether the JS viewer is mirrored (§3.2).

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
  changes: `heading(mirror(p)).x = −heading(p).x`, so `angle` and `normalRotation` change sign (§4.3); `center.x`
  changes sign.

### 5.2 `swap_players`

- `swap_players(Position & p)`: `std::swap(p[player0], p[player1])` (`src/positions.hpp:68-71`), in place: `S`. Exact,
  an involution, preserves every coordinate (only the player index changes).
- `heading(S(p)) = −heading(p)`: `normalRotation` changes by ±π (§4.3); `center` is unchanged up to rounding
  (`(a + b)/2` vs `(b + a)/2`: IEEE addition is commutative, so it is in fact identical).
- `PlayerJoint`-level version: `opponent(pj.player)` (`src/positions.hpp:111`).

### 5.3 `Reorientation` and `PositionReorientation`

**`Reorientation{offset, angle}`** (`src/math.hpp:235-243`, defaults `{0,0,0}` and `0`): a rotation about the vertical
axis followed by a translation.
- `apply(r, v) = (yrot(r.angle) * v) + r.offset` (`src/math.hpp:252-255`), i.e. `r(v) = R(θ)·v + o`. Rotation
  **first**, then translation. `yrot(a) * v` goes through `M * V4(v, 1)` (`src/math.hpp:206-209,197-204`), so the
  evaluated expression is, for `x`: `((m[0]·x + m[4]·y) + m[8]·z) + m[12]` with `m[0] = cos a`, `m[4] = 0`,
  `m[8] = sin a`, `m[12] = 0` (`src/math.hpp:73-80`), then `+ o.x`. The `0·y` and `+0` terms are kept by the compiler
  (no `-ffast-math`, `src/SConstruct:4`); they only matter for the sign of zero results, but a bit-exact port should
  evaluate the same terms in the same order.
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
  (`src/editor.cpp:240-265`; key `X`, `src/glfw_editor.cpp:134`). Editor detail: section 8.
- Known imprecision in the original: `do_edit` composes a camera-only reorientation and notes it ignores
  `swap_players` (`src/glfw_editor.cpp:380-382`, `// todo: this is wrong`). Not to be "fixed" silently in a port;
  section 8.

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
- **Never swaps players** (`swap_players = false` in both; `assert(!reo.swap_players)` in `mkpospages`,
  `src/mkpospages.cpp:662`). Which player is 0 is never canonicalised: a position and its `swap_players` image have
  canonical forms rotated by π from each other. Callers that want a fixed player order swap first themselves:
  `mkpospages` swaps every frame when the transition's `from.reorientation.swap_players` is set, then canonicalises
  the first frame (`src/mkpospages.cpp:430-435`).

Tie-breaks and degenerate cases:
- The only discrete choice is the mirror test, with `≥ 0` (head exactly on the plane → mirrored). There is no other
  tie-break; the angle comes from a single `atan2`.
- Both cores at the same `xz`: `heading = (0, 0)`, `atan2(0, 0) = 0` so no rotation (§4.3). C's `atan2(±0, −0)` is
  `±π`, which would rotate by π, but `heading` is a component-wise subtraction (`src/math.hpp:135`) and `x − x = +0`
  under IEEE 754 round-to-nearest, so only `(+0, +0)` can arise and the angle is `0` (`−0` after `normalRotation`'s
  negation). Derived, not observed: **[unverified]** only in that it assumes the default rounding mode.
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
  rotate → translate → mirror → swap (§5.3). Oracle: indirectly, `graph.ndjson` exports every edge's
  `reorientation_from`/`_to` (§2.3) and `ops.ndjson` the canonical forms.
- `heading`, `center`, `normalRotation`, `normalTranslation`, and `orient_canonically_with_mirror/without_mirror`
  (§4.3, §5.5). Oracle: `ops.ndjson` (`heading`, `center`, `orient_canonically_*`).
- `compose`/`inverse` with the exact formulas of §5.4, angle sum not wrapped, `a.mirror` conjugating `b`. Oracle:
  only indirectly (playback frames, `playback` in the spec); `ops.ndjson` does not list them.

Must match semantically (the port may choose its own representation as long as these hold):
- `compose(a, b) = b ∘ a`; `inverse(u) ∘ u ≈ id`; `PositionReorientation` acts on joint *indices* as in §5.3.
- Canonical orientation never swaps players.

### 5.7 Open points (need the oracle/dumper)

- Bit equality of `sin`/`cos`/`atan2`: the original uses glibc's `libm` (via `<cmath>`); whether the Odin port's
  functions give the same bits for every angle in the DB is **[unverified]**; if not, either call the same libm or
  compare with a tolerance (needs a decision, phase 2).
- `compose`/`inverse` are not dumped directly; adding them to `ops.ndjson` (e.g. `inverse(reorientation_from)` and
  `compose` of the two endpoint reorientations of each edge) would check §5.4 directly. To be proposed on #34.
