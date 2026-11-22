# Plan: #147 ci: fidelity workflow over the full oracle dump
Spec: docs/specs/phase-2-core.md (deliverable 11; "Decisions and trade-offs", *Fidelity in CI: a separate workflow*) ·
ADR 0002 · ADR 0003 ("Open points": the libm of each platform over the whole DB)

## Pasos
1. **`.github/workflows/fidelity.yml`** (new). This is a CI workflow edit: **approved by Ander with this plan**.
   `Edit(./.github/workflows/**)` is `ask`, so the worker will get the permission prompt: it stops there, and MAIN asks
   Ander to answer it in the worker's space.
   - `name: fidelity`. Triggers:
     - `pull_request` with `paths: [src/core/**, tests/fidelity/**, tests/fixtures/oracle/**, build.sh,
       .github/workflows/fidelity.yml]`;
     - `workflow_dispatch`;
     - `schedule: cron "17 5 * * *"`, two hours after the nightly `oracle` (03:17), so it uses that night's artifact.
   - `permissions: {contents: read, actions: read}`.
   - `concurrency: fidelity-${{ github.ref }}`, with `cancel-in-progress` only on `pull_request`, as in `oracle.yml`.
   - Job `fidelity`:
     - matrix `os: [ubuntu-latest, macos-latest]` with `fail-fast: false`, and `timeout-minutes: 60`;
     - `actions/checkout@v7.0.1` with `submodules: true`, then `./.github/actions/setup` (same versions as `ci.yml`);
     - **Download step** (`env: GH_TOKEN: ${{ github.token }}`): `gh` comes preinstalled on both runners, so there is
       no new action and no new dependency. It runs
       `run=$(gh run list --workflow oracle.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId // empty')`.
       If that is empty, it prints `::error::` "no successful oracle run on main with an oracle-full-dump artifact
       (7-day retention): run the oracle workflow (workflow_dispatch)" and fails. Then
       `gh run download "$run" -n oracle-full-dump -D "$RUNNER_TEMP/oracle-full"`, which fails with the same message if
       the artifact has expired.
     - **Check step**: `(cd "$RUNNER_TEMP/oracle-full" && shasum -a 256 -- *) | diff tests/fixtures/oracle/FULL.sha256 -`.
       `shasum` exists on both runners, unlike `sha256sum` on macOS, and its format (`<hash>  <file>`) is the same as
       `FULL.sha256`. On a mismatch it prints `::error::` "the oracle-full-dump of run N does not match this commit's
       FULL.sha256 (another dumper version?)" and fails.
     - **Test step**: `GM_ORACLE_DIR="$RUNNER_TEMP/oracle-full" ./build.sh test`, with the same flags and collection as
       locally. Nothing in `build.sh` changes.
   - Header comment as in `oracle.yml`: what it does, that it is not a required check, and that `ci.yml` doesn't
     change.
2. **Docs**:
   - `docs/architecture.md`, row "Fidelity (full DB)": "by hand today; a CI job later" becomes "`fidelity` workflow
     (`.github/workflows/fidelity.yml`, linux + macOS, PRs touching core/fidelity/fixtures/build.sh, nightly, manual);
     or by hand". This settles item 4 of #157, with a comment there.
   - `tools/oracle/README.md`, section "CI (#36)": one line saying the artifact is consumed by `fidelity.yml`.
   - `changelog.d/147-fidelity-workflow.md`.
3. **Check before ready**:
   - Run the workflow on the PR itself: the PR touches `.github/workflows/fidelity.yml`, so `pull_request` triggers it.
     Both jobs must be green, with their duration in the PR.
   - Show that the failure is real: the PR lists the verifiable negative cases, such as the empty `run` message.
     Corrupting `FULL.sha256` is **not** committed and not pushed. Running the check step's hash command by hand on a
     downloaded dump with a modified line, and seeing `diff` fail, is enough; paste its output in the PR.
   - `./build.sh ci` locally (it doesn't change, but the checklist requires it).

## Ficheros a tocar
`.github/workflows/fidelity.yml`, `docs/architecture.md` (one row), `tools/oracle/README.md` (one line),
`changelog.d/147-fidelity-workflow.md` (+ the plan, `docs/plans/147-fidelity-workflow.md`). Not touched: `ci.yml`,
`oracle.yml`, `build.sh`, `src/`, `tests/` (those belong to #139).

## Tests a escribir primero
There is no Odin code. The "test" is the workflow itself on the PR: green on both platforms over the full dump. It must
also show it isn't vacuous: the job log shows the fidelity tests ran with `GM_ORACLE_DIR`. For example,
`sequences_test` requires a record for every block when it isn't on the sample: if the dump were missing a block, it
would fail.

## Riesgos
- **Expired artifact (7 days):** the job fails with a clear message, never a silent pass. The nightly `oracle` run
  keeps one fresh. Recovery is to run `oracle` by `workflow_dispatch`.
- **`gh run list --branch main`** might pick a run whose dump comes from an older dumper. The `FULL.sha256` check
  catches that, by design (spec).
- **PR from a fork:** with no token to read the artifacts, it would fail. The repo is private and has no forks today;
  the plan notes it and does nothing more.
- **Cost:** about 550 MB of download per platform, plus the tests with ASan over `sequences` (and from #139 on, `ops`
  and `between`). With `timeout-minutes: 60` it won't hang. If a job takes more than 30 min, the PR says so and a
  `tech-debt` issue is opened. Nothing is cut without Ander's OK.
- **Interaction with #139:** if #139 merges first, this workflow runs its fidelity tests too. If this merges first,
  #139 triggers it (it touches `src/core/**`). The two PRs touch different files.

## Criterio de hecho
- The `fidelity` workflow is green on both platforms in the PR, with the duration and the oracle run used.
- `./build.sh ci` green locally, and CI green.
- The negative checks are documented in the PR.
- `code-reviewer` without blockers (sonnet; opus if it touches anything beyond the workflow and docs).
- Labels `type:ci`, `area:infra`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #147`.
- Worker model: sonnet.
