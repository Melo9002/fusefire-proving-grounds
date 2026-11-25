# Project Ironclad

Project Ironclad is FuseFire's lightweight regression-testing practice. Its purpose is to make the game safer and easier to change while its foundations continue to evolve. It wraps the existing Godot tests; it does not introduce a separate framework.

## Current infrastructure

The repository contains ordinary automated GDScript checks plus explicit-only rendered and extended diagnostics under `tests/`. Most extend `SceneTree`, exercise real project classes or scenes, print a concise result, and terminate with `quit(0)` or `quit(1)`. A nonzero Godot process exit is always a failure. The runner also rejects script/parser errors after a zero exit: Godot can otherwise finish a script despite an unhandled runtime error.

| Area | Existing coverage |
| --- | --- |
| Project/resources | Headless editor scan, battle dependency isolation, scene/resource loading |
| Actions/combat | Authoritative queries and execution, AP/SP, Aim, Shield, Reload, Guard reactions, cover, accuracy, elevation and conditions |
| Movement | Pathfinding, diagonal movement, traversal links, elevation selection, vaulting and locomotion |
| Missions | Objective state, terminals, rescue/extraction, evacuation, survival and placement |
| AI | Difficulty, commanders, position/target scoring, abilities, stalemate recovery and deterministic match simulation |
| Generation | Map data/validation, fixed-seed generation, multi-seed batches, buildings, elevation, traversal, mission placement and quality metrics |
| Replay | Schema compatibility, recording/playback, actor continuity, rescue/departure flows and state determinism |
| Assets/presentation | Imports, calibration precedence/persistence, camera behavior, HUD/overlays and visual adapters |

The project currently targets Godot `4.7.2.stable`. Tests require `godot_console` on `PATH`, or an explicit executable passed to the runner. Debug Draw 3D 1.7.3 is vendored in the repository and its smoke check verifies that the matching native library loads; no separately installed test dependency is required.

Rendered capture scripts require an ordinary graphics run and, where documented, an output path. They are manual visual workflows, not automated visual comparisons. Five long batch/stress scripts are also explicit-only. Existing naming varies between `smoke`, `test`, and `validation`; that inconsistency is harmless and has not been rewritten.

## Unified runner

Run from the repository root in PowerShell. Every test is described in `tests/catalog.json` (subsystems, scope, criticality, FAST/SMOKE membership, explicit-only status); the runner selects from it. Day-to-day guidance: [testing developer guide](../claude/testing-developer-guide-2026-11-20.md).

```powershell
.\tools\run_tests.ps1 fast                                # cheap headless tests (about 100)
.\tools\run_tests.ps1 fast -Subsystem animation           # FAST tests of one subsystem
.\tools\run_tests.ps1 smoke                               # 27 boundary/regression tests (what CI runs)
.\tools\run_tests.ps1 subsystem -Subsystem combat         # every ordinary test of a subsystem
.\tools\run_tests.ps1 subsystem -Contract replay -Critical
.\tools\run_tests.ps1 select -Test traversal_*,path_refiner_test
.\tools\run_tests.ps1 changed -Changed <paths>            # or -Since HEAD; add -Thorough for the long tests
.\tools\run_tests.ps1 full                                # every ordinary test
.\tools\run_tests.ps1 check                               # validate the catalog only
```

Subsystems: `core`, `actions`, `combat`, `equipment`, `movement`, `animation`, `ai`, `missions`, `rescue`, `generation`, `replay`, `persistence`, `ui`, `assets`, `tooling` (the older eight names keep selecting at least what they selected before). `-List` shows what would run without executing, `-Why` adds the reason for each test, `-TimeoutSeconds` (default 900) bounds each test, and `-Godot C:\path\to\godot_console.exe` names the executable when it is not on `PATH`.

FAST, SMOKE and the subsystem selections complement the full tier; they never replace it. Full discovers every top-level `tests/*.gd` except the explicit-only scripts. A script missing from the catalog still runs in the full tier and is reported as UNCLASSIFIED; `check` (also run by CI) fails on an unclassified script, a stale entry, an unknown value, an explicit-only or rendering test marked FAST/SMOKE, an area path that does not exist, and (Task 14) any `.gd` or `.tscn` under the source roots (`systems`, `units`, `presentation`, `research`, `ui`, `levels`, `tools`, `content`, `art`) that no area covers: an unmapped file would make `changed` fall back to the critical tests only and never select the suite that guards it (this happened to `presentation/motion/` and `research/` after Task 13).

### Run results and artifacts

Run artifacts go under `artifacts/test-results/<timestamp>-<run-id>-<tier>/` by default. The unique ID prevents runs started in the same second from sharing log files. Each execution records combined text, raw stdout and stderr, the Godot engine log, an atomic `results.json` checkpoint and a final `summary.txt`. `FUSEFIRE_TEST_OUTPUT_DIR` points to the run's writable `test-output` directory in the child process.

| Field | Counts or meaning |
| --- | --- |
| Discovered / catalogued | Top-level GDScript files found and metadata entries loaded. |
| Ordinary selected / explicit exclusions | Tests selected from the ordinary tier and scripts with explicit-only metadata outside the selection. Exclusions never started. |
| Started / completed | Godot test processes started and tests that exited with a pass or failure. A timeout is a started test with its own outcome. Imports and probes have separate entry kinds. |
| Passed / failed / timed out / not run | Test outcomes. A process start failure can fail a test without a started process. An unsuccessful import marks dependent tests `NOT-RUN`. Rendering requirements can block a selection before execution. |
| Import | A separate Godot editor scan with its own result. A failed import prevents dependent scripts from running and invalidates the previous freshness stamp. |
| Retries / distinct failures | Ironclad runs each selected test once. Use a second named selection and compare the two run files if a failure needs investigation. |

The console and JSON distinguish **GREEN**, **RED**, and **INCOMPLETE**. A failed entry makes the run RED even if other entries pass. Catalog errors, rendering blocks or interrupted execution can leave a run INCOMPLETE. Exit 1 means a failed attempt or timeout. Exit 2 means setup, catalog or selection could not provide complete evidence. A regular test with exit 0 is green only when neither its captured output nor its engine log contains a script, parse or compile error. The combined `passed`, `failed` and `skipped_explicit` JSON fields remain available for older consumers. Use the separate test and import fields for new reporting.

While a run is active, the checkpoint is INCOMPLETE and names the entry in progress. With a cooperative interruption, Ironclad stops the current child and releases the checkout lock. On hard termination, the last complete checkpoint and any written streams remain available. Check for surviving Godot processes after killing the entire runner or OS session. The runner can only enforce child cleanup while its process remains alive.

### Windows test data and checkout ownership

Ironclad directs each Windows child entry's `APPDATA` and `LOCALAPPDATA` to a fresh directory under that run's `user-data/`. Godot and nested ADDA invocations resolve `user://` there. Your shell, editor and normal game settings keep their own profile. A passing entry's profile is removed. Failed, timed-out and interrupted entry data stays with the run artifacts for reproduction. Direct Godot commands retain their native user-data paths, as do runner launches on non-Windows hosts.

One Ironclad runner holds the checkout's `.godot/ironclad-run.lock`. Run separate worktrees for simultaneous campaigns. The lock does not coordinate external editor or direct Godot processes. Tests write fixed paths under `res://.godot/`, so keep those other writers out of the same checkout during a validation run. Distinct worktrees and unique run directories allow independent campaigns, including campaigns targeting the same log parent.

A test may declare `fixed_fps` when measured behavior requires deterministic engine stepping. Ironclad then passes the corresponding Godot `--fixed-fps` option and records it for that entry. `ladder_climb_test` uses 60 fps and retains the same poses, samples and assertions. The landing test retains its live-frame and 30 fps coverage. This setting changes the test launch only.

Direct commands remain supported for a single script:

```powershell
godot_console --headless --path . --script res://tests/tactical_action_service_test.gd
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd -- 5000 250
```

## Changed-file comparison and selection accounting

`changed -Since <ref>` resolves a local commit and compares that commit directly to the working tree. This is a tree comparison, so pass a merge-base commit explicitly if that is the comparison you want. It includes staged and unstaged changes and non-ignored untracked files. A rename contributes both its old and new paths. Additions and deletions contribute the path on their respective side. Explicit `-Changed` paths are combined with these results. Git lookup, diff or untracked-list errors exit 2 before selection. A successful comparison with no matching tests reports zero tests and skips automatic import. Explicit `-Import` or failure probes still run when requested.

`-List` and `-Why` distinguish runnable and blocked selections, explicit-only scripts outside the selection, long end-to-end tests deferred by the fallback rule, and other unselected ordinary tests. The long-test omission list excludes any test selected by an affected subsystem. The existing `SKIP` result total counts explicit-only entries skipped by the tier's enumeration policy. Project import, when needed, is a separate execution entry with its own verdict.

Run the deterministic selector controls with `pwsh -NoProfile -File tools/quality/ironclad_selection_test.ps1`. They use a disposable Git fixture and require no Godot installation. Before the correction, an invalid ref returned 0 after Git printed a fatal error, and an objective change listed the mission/replay matrix as both selected and omitted. The controls cover both defects plus a corrupt index, docs-only changes, rename sides, deleted and added paths, ignored files, and render-blocked selections.


## Stability categories

Categories describe the protected behavior, not separate executables.

- **Invariant:** architectural truths expected to survive design iteration. Examples include rejecting illegal actions, preserving authoritative resource constraints, valid mission connectivity, deterministic results for identical inputs, and replay agreement with simulation.
- **Contract:** current intentional rules that may change through an explicit design decision. Examples include action costs, cover modifiers, mission completion conditions, commander composition, and calibration resolution.
- **Experimental:** provisional behavior whose feature is still being developed, such as warehouse-specific presentation, roof cutaways, asset presets, or generation quality thresholds.

A single script may protect more than one category. State the relevant category in a new regression's comments or accompanying documentation when it is not obvious from the assertion.

## Bug-fix workflow

For a reproducible defect:

1. Capture the smallest reliable reproduction, including its seed/configuration when applicable.
2. Add or extend a focused regression when automation is practical.
3. Confirm the regression fails for the expected reason before the fix when feasible.
4. Fix the underlying implementation rather than weakening the assertion.
5. Run the focused test, its subsystem tier, and broader verification when shared systems changed.
6. Preserve the regression with enough failure context to reproduce it later.

Automated coverage is optional for purely cosmetic work, exploratory prototypes, and cases where a stable test would cost more than it protects. Record the manual validation instead.

## Intentional changes and failure investigation

A failure can be an implementation regression, an intentional contract change, an obsolete experiment, a defective/flaky test, or an environment failure. Establish which case applies before editing assertions.

For intentional changes, update implementation and affected contract tests together, preserve still-valid invariants, and explain the changed expectation. Remove or replace a test only when its protected contract is genuinely obsolete. Never skip, loosen, or rewrite a test solely to produce green output.

When investigating a failure:

1. Read the runner's test log and `.godot.log`.
2. Re-run the individual script directly.
3. Record any printed seed, mission, map size, configuration, final state, and expected/actual values.
4. Use a fixed-seed fixture for a specific regression and a multi-seed batch for broader properties.
5. Assert behavioral properties such as connectivity or reachability instead of an exact generated layout unless the layout itself is the contract.
6. Separate filesystem, executable, import, and graphics failures from gameplay failures.

### Compare the original run and focused attempts

```powershell
.\tools\quality\ironclad_compare_runs.ps1 -Initial <full-results.json> -Rerun <focused-results.json> -Baseline <baseline-results.json>
pwsh -NoProfile -File tools/quality/ironclad_runtime_test.ps1
```

The comparison reads existing JSON and keeps the initial verdict. It records every supplied observation separately, including mixed reruns and baseline failures. A passing rerun needs a cause classification. A passed-on-rerun entry can be a corrected fixture, an isolated environment failure or an intermittent product/test behavior. Keep raw evidence, commit, configuration, and execution mode with that conclusion. The runtime regression runs a real disposable Godot project and includes controlled failures, process exit, timeout, import failure, locking, interruption and user-data writes. `-ProbeFailureHandling` still runs the three engine failure probes in a normal checkout when requested.

[Step 12 failure forensics and QA verification](ironclad-failure-forensics-2026-11-25.md) links the original red run, known ladder behavior and the isolated reruns.

## Explicit-only validation

The catalog's explicit-only entries include long batches, benchmarks and rendered captures. Run a headless batch by exact name, for example `.\tools\run_tests.ps1 select -Test container_maps_smoke`. Run a capture directly with graphics and inspect the resulting frames. `check` reports the current explicit count; `full -Why` lists exclusions.

A wildcard in `-Test` never selects an explicit-only script; an exact name does. Headless import or scene success does not establish visual correctness.

## Current limitations

- CI runs the catalog check and the smoke tier (see GitHub smoke automation below). The full subsystem tiers and the explicit-only batches are not run on GitHub, and artifacts are retained only for failed smoke runs.
- No screenshot comparison, job-wide performance budget, coverage percentage, or automatically inferred failure classification.
- Classification lives in `tests/catalog.json`; scope labels and the path-to-subsystem map used by `changed` are judgements, not a computed dependency graph, and the selections are aids, not proofs.
- Individual GDScript tests report their own internal checks differently, so Ironclad reports honest suite counts rather than inventing assertion totals.
- Per-test timeouts default to 900 seconds. The runner serializes Godot entries in a checkout.

Retired map-specific suites are preserved in the outside-project quarantine recorded in [Generation 2.0](../generation-2.md). Shared parcel/deployment/population checks now use Service Depot, and `current_generation_test.gd` protects the one-map menu and standalone generator boundary. Mechanics fixtures live under `tests/fixtures/`; the runner discovers only top-level suite scripts. No assertion was removed merely to make a failure pass.

## Animation architecture gates (Task 14)

The animation architecture's rules are protected by the existing tiers, not a separate harness. See [the animation guide](../animation.md#test-classification-and-gates) for the Invariant, Contract and Experimental classification. In the smoke tier (headless, a few seconds each, so every push runs them): `animation_module_boundaries_test` (dependency direction, single owners, authority and observation gates, production-versus-research isolation, no private reaches), `motion_contract_test` (a non-humanoid family needs no skeleton), `presentation_frame_driver_test` (one advance per frame), `action_handle_test` and `animation_cleanup_test` (settle once, teardown), `rig_bones_test` (portability and degraded reporting). `presentation_authority_test` (the same scripted moves under different presentation speeds and with diagnostics attached produce identical action records and state fingerprints) is critical but not smoke: it runs a real battle (about 20 s). Changed-file selection maps `presentation/motion/`, `presentation/diagnostics/` and `research/` to the animation subsystem.

Performance is measured, not gated: `tools/quality/animation_perf_baseline.gd`, `diagnostics_overhead_probe.gd` and `motion_contract_overhead_probe.gd` print numbers that depend on the machine and its load; the Task 14 report records them with the observed run-to-run variation. A fixed millisecond budget would fail on a loaded CI runner without meaning a regression.

## GitHub smoke automation

`.github/workflows/ironclad-smoke.yml` runs the existing smoke tier on pushes and pull requests targeting `main`. The Windows job downloads the official Godot 4.7.2 stable archive from `godotengine/godot-builds`, verifies its pinned SHA-256, and passes the extracted executable directly to this runner. It has read-only repository permissions and uploads only `artifacts/test-results/` when the job fails.

The workflow runs on GitHub-hosted runners on each push to `main`; the runs checked on 2026-11-18 all passed. Pull-request runs were not checked. It exercises only the smoke tier, so passing it does not replace the subsystem suites for a shared or risky change.


## Audit follow-up coverage — 2026-11-15

- `parcel_session_file_test.gd`: complete object/field save/open, overwrite, stale payload rejection and failure recovery.
- `parcel_population_runtime_parity_test.gd`: mixed parking/container paint across densities 0/65/100 and seeds 17/18; preview and runtime accepted choices and tactical geometry agree. Protection-only edits can intentionally exclude every position.
- `parcel_test_content_test.gd` and `parcel_editor_handoff_test.gd`: immutable local scene dependencies, explicit unavailable/changed-content rejection, Save/Open → Preview → Test battle → saved replay → return with edits preserved.
- `battle_configuration_test.gd`: canonical named selection, legacy-input decoding, normalization and historical feature flags.
- `current_mission_replay_matrix_test.gd`: 16 validated starts/replays covering eight mission kinds on both Depot plots. This is bounded initialization and real-action reconstruction coverage, not a full AI victory matrix.
- `retired_tactical_metadata_test.gd`: obsolete absolute-coordinate metadata rejects before partial compilation; current relative deck/ladder contracts remain valid.

Historical geometry suites explicitly request their legacy fixture IDs rather than relying on the default battle selection. Generic empty-grid parcel tests use TacticalMapBuilder directly. See [fixture classification](../../tests/fixtures/README.md). No historical assertions were removed to make current-map tests pass.

The rendered editor handoff is available with:

```powershell
godot_console --path . --script res://tests/parcel_editor_handoff_test.gd -- capture artifacts/report-cleanup-handoff
```

Local parcel recordings require their hash-named snapshot cache and unchanged project dependencies. The isolated runner redirects that cache into its per-run output directory; this keeps tests separate from actual editor content.


Final verification: **122 suites passed, 0 failed, 14 explicit-only skipped**, in **631.59 seconds** (`artifacts/test-results/20261115-083347-full/`). The preceding integration run was **115/7/14** (`20261115-082155-full`): its failures exposed old default-map expectations, missing local content in the aperture fixture, a helper placed outside the protected Generation 2 dependency boundary, and the intentional mission-copy ownership change. The historical building script also indexed missing fixture geometry and had to be stopped; it now selects its fixture explicitly and fails clearly if that geometry is unavailable. Assertions were preserved or revised to check the new contract, including complete mission equality rather than shared resource identity. Focused reruns and the subsequent full run passed.

Additional executed checks: the historical container sweep passed **300 seeds across three sizes** (`artifacts/report-container-fixture.txt`); the current Depot AI Eliminate battle completed with **0 issues, six rounds, 53 decisions** (`artifacts/depot-ai-batch.txt`); and the rendered editor/save/preview/local-battle/replay/return check passed with captures inspected in `artifacts/report-cleanup-handoff/`. The building suite's separate 300-seed sweep passed as well. The policy-skipped extended AI matrix, stress tests and other capture workflows were not all run; do not infer their results from these bounded checks.

Final logs contain no script parse/compile/runtime errors or new leak warnings. The pre-existing **four ObjectDB instances** warning in `allied_faction_smoke.gd` remains, along with sandbox certificate-store diagnostics. These are recorded limitations, not silently reclassified passes for new failures. The five pre-existing texture-import edits are outside the cleanup commit.


The subsequent [parcel UX and live-battle follow-up](parcel-playtest-2026-11-15.md) records the narrower UI/focused checks, saved ambulance battle completion, and three added suites. Its results do not replace the dated full-run evidence above.


The [current content release](current-content-release.md) adds new parcel/site and mixed-vehicle regressions and extends the mission/replay matrix to 48 cases. The former one-menu-map assertion is intentionally replaced by three curated site IDs sharing one generator; retired IDs and legacy-isolation assertions remain.

Task 14 correction evidence and lifecycle admission policy: [2026-11-23 follow-up](task14-signoff-corrections-2026-11-23.md). The two new cheap invariant regressions are included in SMOKE; historical timing/runner optimization remains a separate campaign.
