# Project Ironclad

Project Ironclad is FuseFire's lightweight regression-testing practice. Its purpose is to make the game safer and easier to change while its foundations continue to evolve. It wraps the existing Godot tests; it does not introduce a separate framework.

## Current infrastructure

The repository contains ordinary automated GDScript checks plus explicit-only rendered and extended diagnostics under `tests/`. Most extend `SceneTree`, exercise real project classes or scenes, print a concise result, and terminate with `quit(0)` or `quit(1)`. Godot's process exit code is therefore the authoritative suite result.

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

Run from the repository root in PowerShell:

```powershell
.\tools\run_tests.ps1 smoke
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem replay
.\tools\run_tests.ps1 full
```

Available subsystem names are `combat`, `movement`, `ai`, `replay`, `generation`, `missions`, `assets`, and `ui`. Use `-List` to inspect a tier without executing it. Use `-Godot C:\path\to\godot_console.exe` when the executable is not on `PATH`.

The smoke tier runs the project scan and ten representative critical regressions. Subsystem tiers select existing tests by stable filename conventions. Full discovers every top-level test except the explicit-only visual and extended lists in the runner. This keeps new ordinary tests in broad verification without maintaining a second exhaustive manifest.

Each run prints suite-level pass/fail/skip totals and elapsed time. Detailed stdout, stderr, and Godot engine logs are written under `artifacts/test-results/<timestamp>-<tier>/`; that generated directory is ignored by Git. The runner supplies a writable isolated test-output directory for tests that serialize reports. A missing executable, missing required script, or nonzero Godot result produces a nonzero runner result.

Direct commands remain supported for a single script:

```powershell
godot_console --headless --path . --script res://tests/tactical_action_service_test.gd
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd -- 5000 250
```

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

## Explicit-only validation

The full tier reports these as skipped by policy:

- `ai_match_simulation_smoke.gd`
- `battlefield_stress_smoke.gd`
- `container_maps_smoke.gd`
- `map_quality_metrics_smoke.gd`
- `prototype_1_milestone.gd`
- `asset_lab_capture.gd`
- `parcel_editor_capture.gd`
- `industrial_warehouse_capture.gd`
- `semantic_asset_contact_sheet.gd`
- `semantic_asset_review_capture.gd`
- `semantic_machine_connection_capture.gd`

Run long scripts directly when their subsystem changes. Run capture scripts without `--headless` and inspect their images manually. Headless import or scene success does not establish visual correctness.

## Current limitations

- No CI execution or hosted artifact retention.
- No screenshot comparison, performance budget, coverage percentage, or flaky-test history.
- Suite classification is filename-based and intentionally lightweight.
- Individual GDScript tests report their own internal checks differently, so Ironclad reports honest suite counts rather than inventing assertion totals.
- The runner does not impose per-test timeouts yet; long deterministic scenarios remain visible through per-suite timing.

After the first hosted smoke run, the next useful milestones are optional timeouts for hung processes, machine-readable summary output, and measured promotion or retirement of explicit-only batches.

Retired map-specific suites are preserved in the outside-project quarantine recorded in [Generation 2.0](../generation-2.md). Shared parcel/deployment/population checks now use Service Depot, and `current_generation_test.gd` protects the one-map menu and standalone generator boundary. Mechanics fixtures live under `tests/fixtures/`; the runner discovers only top-level suite scripts. No assertion was removed merely to make a failure pass.

## GitHub smoke automation

`.github/workflows/ironclad-smoke.yml` runs the existing smoke tier on pushes and pull requests targeting `main`. The Windows job downloads the official Godot 4.7.2 stable archive from `godotengine/godot-builds`, verifies its pinned SHA-256, and passes the extracted executable directly to this runner. It has read-only repository permissions and uploads only `artifacts/test-results/` when the job fails.

This workflow has been validated locally for structure, paths, engine version and runner behavior. Its first GitHub-hosted execution still requires a future push or pull request.


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
