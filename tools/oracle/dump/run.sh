#!/bin/sh
# In-container entry point (installed as grapplemap-oracle-dump). Usage: grapplemap-oracle-dump DB OUT [dumper options]
# grapplemap-indexer runs on a copy of DB (it writes DB.index next to its input); the dumper reads that .index
# but loads DB itself with loadGraph(istream).
set -eu
db=$1
out=$2
shift 2
tmp=$(mktemp -d)
trap 'rm -r -f "$tmp"' EXIT
cp "$db" "$tmp/db.txt"
grapplemap-indexer "$tmp/db.txt"
mkdir -p "$out"
grapplemap-dump --db "$db" --index "$tmp/db.txt.index" --out "$out" "$@"
