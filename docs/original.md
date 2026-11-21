# The original GrappleMap, as read from its code

Purpose: let phase 2 reimplement the original's data handling in Odin with exact fidelity **without reading the C++
again**. Source of truth: the submodule `reference/GrappleMap`, pinned at `032c8f9`.

**Conventions**
- A citation `src/x.cpp:L` or `src/x.cpp:A-B` is relative to `reference/GrappleMap` at the pin. On a pin bump every
  citation must be re-checked (`reference/CLAUDE.md`).
- `GrappleMap.txt` means `reference/GrappleMap/GrappleMap.txt`; its line numbers are cited as `GrappleMap.txt:L`.
- **[unverified]** marks a claim derived by reading code whose runtime behaviour has not been observed (it needs the
  oracle/dumper). Each one says why. Claims without the marker were checked against the cited lines.

## Contents
1. [Data format](#1-data-format)
2. Graph model: *pending*
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
(`src/persistence.cpp:58-116`) from a `[b, e)` byte range (`loadGraph`, `src/persistence.cpp:154-176`).

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
  become part of the last character of the line. The DB has no `'\r'` and no tab (`tr -cd`, §1.8).
- The writer always emits `'\n'` and opens the file in binary mode (`src/persistence.cpp:237`, `118-144`).

### 1.2 Description lines

The first description line is the **name** of the block (`description.front()` is used as the name throughout, e.g.
`src/graph.hpp:16-18`, `src/graph_util.cpp:176`). Remaining lines are free-form, except for the prefixes below. A prefix
only counts at **column 0**, and is matched by a plain `substr` comparison.

| Line | Who reads it | Details |
|---|---|---|
| `tags: a b c` | `tags_in_desc`, `src/graph_util.cpp:147-164`; wrappers `src/metadata.hpp:19-20` | Prefix `tags:`, then the rest is split on whitespace (`istringstream >>`); every token is a tag; multiple `tags:` lines are unioned into a `set`. |
| `properties: a b c` | `properties_in_desc`, `src/metadata.cpp:37-54` | Same parsing. Only on sequences: `detailed` and `bidirectional` are read while loading (`src/persistence.cpp:78,84-85`) and on `set_description` (`src/graph.cpp:370-371`). Other tokens are not interpreted by the loader and are passed to JS (`src/js_conversions.cpp:114,263`). |
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
  terminator). Both asserts are compiled out in release builds (§1.7), so out-of-range values are not detected.

### 1.6 Grammar

What the **parser** accepts (looser than what the writer produces). Terminals are bytes.

```ebnf
file        = { block_item } ;
block_item  = desc_line | pos_block ;

desc_line   = nonspace , { not_newline } , ( "\n" | EOF )     (* first byte != ' ' *)
            | "\n" ;                                          (* the empty line is a desc_line too *)
pos_block   = " " , 295 * byte ;                              (* exactly 296 bytes consumed, see 1.7 *)
nonspace    = byte - " " ;
not_newline = byte - "\n" ;
```

Semantics layered on top (`readSeqs`):

```ebnf
sequence    = desc_line , { desc_line } , pos_block , { pos_block } ;   (* desc_line+ then pos_block+ *)
```
- Within a `pos_block`, `decodePosition` takes the first 276 base62 digits, skipping any `isspace` before each one.
- Block with one `pos_block` → named position; two or more → transition.

What the **writer** emits (the canonical form, and what the DB contains, §1.8):

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
| Position lines indented differently (more/less/no spaces), or digits split across lines differently | The *decoder* tolerates it (skips `isspace`), but the *caller* always advances exactly 296 bytes. If the block's real byte length ≠ 296, the next read starts mid-block (a position suffix becomes a "description line", or the next block is entered misaligned). No diagnostic. | `src/persistence.cpp:37-41,93` |
| CRLF line endings | Same mechanism: each position line has +1 byte, so a block is 300 bytes; `decodePosition` succeeds but the cursor lands inside the last line of the block, the remainder is parsed as a description line, and `'\r'` stays in all description lines. **[unverified]** end-to-end result; derived from the code. | `src/persistence.cpp:39,93,99` |
| Tab or other whitespace inside the digits | Skipped by `isspace` like a space (see above); byte count rules still apply. | `src/persistence.cpp:39` |
| A *description* line that starts with a space | Classified as a position block (first-byte rule) and consumes 296 bytes. The writer never emits one for a name, but a hand-edited note with a leading space is a trap. | `src/persistence.cpp:71` |
| Empty file | `b < e` is false, no sequences, empty `vector<Sequence>`. What `Graph` does with no nodes is section 2. | `src/persistence.cpp:69,115` |
| Description lines at the end with no positions after | Dropped silently (§1.1). | `src/persistence.cpp:75-86` |
| Two blocks with no description between them | They merge into one sequence (positions appended). | `src/persistence.cpp:75,91` |
| Blank line between blocks | It is a description line (`""`), so it either becomes part of the next block's description (as the *first* line, hence an empty name) or is dropped at EOF. | `src/persistence.cpp:96-105` |
| Description-only edits (`set_description`) | `lines()` splits on `'\n'`; `detailed`/`bidirectional` recomputed. | `src/graph.cpp:350-354,366-373` |

The parser performs **no** validation of: name uniqueness, tag/property vocabulary, coordinate sanity, number of
positions per block, or count of lines. Everything not in the table above is accepted.

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
grep -c '^tags:' GrappleMap.txt   # 919 · '^properties:' 1244 · '^ref:' 1208 · '^todo:' 303 · '^note:' 4
tail -c 1 GrappleMap.txt | xxd                                        # 0a: final newline present
wc -l GrappleMap.txt                                                  # 39098 lines
```

- Position alphabet in the file: the 62 base62 characters all occur and nothing else, so every coordinate is within
  the range of §1.3 by construction.
- 9 lines contain non-ASCII (UTF-8) bytes (`LC_ALL=C grep -c '[^ -~]'`), all in description lines.
- Counts of blocks, named positions and transitions are deferred to section 10 (they need the oracle).
