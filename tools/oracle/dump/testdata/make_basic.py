#!/usr/bin/env python3
"""Writes basic.txt, the hand-designed test DB of the oracle dumper (deterministic, no dependencies).

Blocks: 0 named position (quotes, ref:), 1 transition starting at block 0 translated by +0.5 in x and ending at
an anonymous node (literal \\n, UTF-8, note:/todo:, tab, a middle frame with q = 0 and q = 3843),
2 bidirectional transition from that anonymous node to the mirror of block 3, 3 named position.
Usage: python3 make_basic.py > basic.txt
"""

import sys

DIGITS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"  # src/persistence.cpp:13
JOINTS = 23
# Joint pairs swapped by mirror (src/positions.cpp:77-89); enum order of src/players.hpp:8-23.
LEFT_RIGHT = [(0, 1), (2, 3), (4, 5), (6, 7), (8, 9), (10, 11), (12, 13), (14, 15), (16, 17), (18, 19)]

state = 12345


def rand(lo, hi):
    global state
    state = (state * 1103515245 + 12345) % 2**31
    return lo + state % (hi - lo + 1)


def random_position():
    """[player][joint] = [qx, qy, qz]; x, z within [1500, 2500] so mirroring (q -> 4000 - q) stays on the grid."""
    return [[[rand(1500, 2500), rand(0, 1800), rand(1500, 2500)] for _ in range(JOINTS)] for _ in range(2)]


def translated_x(p, dq):
    return [[[x + dq, y, z] for x, y, z in player] for player in p]


def mirrored(p):
    out = [[[4000 - x, y, z] for x, y, z in player] for player in p]
    for player in out:
        for a, b in LEFT_RIGHT:
            player[a], player[b] = player[b], player[a]
    return out


def encode(p):
    s = "".join(DIGITS[q // 62] + DIGITS[q % 62] for player in p for joint in player for q in joint)
    n = len(s) // 4
    return "".join("    " + s[i * n:(i + 1) * n] + "\n" for i in range(4))


guard = random_position()
mount = random_position()
anon = random_position()
mid1 = random_position()
mid1[0][0][0] = 0  # x = -2
mid1[1][22][2] = 3843  # z = 1.843
mid2 = random_position()

blocks = [
    (['closed guard "classic"', "tags: guard closed_guard", "ref: book, p. 12"], [guard]),
    (["hip bump\\nsweep — ñ ü 柔術", "properties: top detailed",
      'note: back\\slash and "quotes"', "note:\tafter a tab", "todo: check grips"],
     [translated_x(guard, 500), mid1, anon]),
    (["escape", "properties: bidirectional bottom", "tags: mount"], [anon, mid2, mirrored(mount)]),
    (["mount", "tags: mount top_mounted"], [mount]),
]

out = sys.stdout.buffer
for desc, positions in blocks:
    for line in desc:
        out.write((line + "\n").encode("utf-8"))
    for p in positions:
        out.write(encode(p).encode("ascii"))
