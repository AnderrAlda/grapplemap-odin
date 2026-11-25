### Added
- `core.export_json`: writes a graph as the project's own JSON (ADR 0005) with a fixed, hand-written layout and
  RFC 8259 string escaping; `Json_Error` for empty or duplicate descriptions, bad ids, invalid UTF-8 and coordinates
  outside 0…3843, all checked before allocating (#146).
- Stable ids: `Sequence.id` (1-based block number), `Node.id` (`NO_ID` for anonymous nodes) and `Graph.next_id` (#146).
