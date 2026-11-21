#!/bin/sh
# In-container entry point (installed as grapplemap-oracle-dump). Usage: grapplemap-oracle-dump DB OUT [dumper options]
# grapplemap-indexer runs on a copy of DB (it writes DB.index next to its input); the dumper reads that .index
# but loads DB itself with loadGraph(istream). Exit status: the dumper's (1 if meta.json has errors).
set -eu
db=$1
out=$2
shift 2
tmp=$(mktemp -d)
trap 'rm -r -f "$tmp"' EXIT
cp "$db" "$tmp/db.txt"
# If the original cannot load DB the indexer fails too; the dumper then records the original's error in meta.json.
grapplemap-indexer "$tmp/db.txt" || echo "grapplemap-oracle-dump: grapplemap-indexer failed; see meta.json" >&2
mkdir -p "$out"
grapplemap-dump --db "$db" --index "$tmp/db.txt.index" --out "$out" "$@"
