# Plan: #151 test: parser allocation-failure regression test (point 2)
Spec: docs/specs/phase-2-core.md (edge cases: no panic, no leak); issue #151 point 2. Point 1 (the
`ODIN_TEST_FAIL_ON_BAD_MEMORY` define in `build.sh`) is done by #138.

## Pasos
1. In `src/core/parse_test.odin`, a test-only `Failing_Allocator` that wraps `context.allocator` (the test's tracking
   allocator) and returns `.Out_Of_Memory` on the N-th allocation (`.Alloc`, `.Alloc_Non_Zeroed`, `.Resize`,
   `.Resize_Non_Zeroed` count; `.Free`/`.Free_All` pass through).
2. Test: for N in `0 ..< K` (K = allocations of a full successful run, measured first by counting, so every allocation
   point is hit; assert K > 0), on (a) a small valid file of 2 blocks with tags and properties and (b) the same file
   ending in a `Bad_Base62_Digit`: `parse_db` with the failing allocator returns `mem.Allocator_Error.Out_Of_Memory`
   (or, for (b) past the failing point, the parse error), never panics, and after it the tracking allocator has no
   live allocation and no bad free. On success (N ≥ K) the result is freed with `sequences_destroy`.
3. `changelog.d/151-parse-alloc-failure.md` (`### Added`, tests). Close #151 in the PR (`Closes #151`, once #138 has
   done point 1; otherwise `Refs #151`).
4. `./build.sh ci`.

## Ficheros a tocar
`src/core/parse_test.odin`, `changelog.d/151-parse-alloc-failure.md`. No change to `parse.odin` unless the test finds
a leak or bad free: then the fix goes in this PR and the reviewer checks it.

## Tests a escribir primero
This PR is the test. Check it can fail: temporarily break the error path locally (e.g. skip one free) and see the test
go red; do not commit that.

## Riesgos
- Without `ODIN_TEST_FAIL_ON_BAD_MEMORY` (until #138 merges) a leak would only be logged: the test checks the tracking
  allocator itself (`len(track.allocation_map) == 0`, `len(track.bad_free_array) == 0`) instead of relying on the flag.
- `Allocator_Error.None` assigned to `Error` is non-nil (`errors.odin`): compare against the expected kind explicitly.

## Criterio de hecho
Test green, fails when the error path is broken; `./build.sh ci` green; `code-reviewer` (opus, `src/core`) without
blockers; labels `type:test`, `area:core`, `phase-2`, milestone «Fase 2: Núcleo de datos» (#151 moved to that
milestone with `priority:high` if Ander agrees).
