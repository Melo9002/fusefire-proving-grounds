# Handoff to Assignment 2 (spatial observability, timelines, structured reports, workflows)

> **Status:** Assignment 2 is done on this branch: see [08-assignment-2-report.md](08-assignment-2-report.md) and [07-usage.md](07-usage.md). Gaps 1, 3, 4 (per-finding overlay) and 5 below are filled; 2 (migrating `HandContactDiagnostics`, `BoneHighlight`, `MotionTrail` to envelopes) and 6 (full mesh intersection) are not.

## State

* Branch `review/claude-adda`, based on `review/claude-animation@38d3865` (unmerged; merge that first). `main` untouched.
* Inherited, intentional failures: `ladder_climb_test` and `ladder_landing_test` (capsule checks). Not changed.
* Nothing speculative was added: no recorder, no AI diagnosis, no extraction.

## What you can build on safely

| Foundation | Contract | Where |
|---|---|---|
| `PoseWitness.acquire/release`, `final_pose`, `stamp()`, `judge()` | the only sampling point; update counter, not frame; stamps carry the witness id | `presentation/diagnostics/pose_witness.gd` |
| `Measurement` | kind/status/pose/space/unit/method/limits/identity/stamp; `to_dict()` is stable JSON; `establishes(kind)` | `presentation/diagnostics/measurement.gd` |
| `ContactErrorDiagnostics.evidence()` | per hand: TARGET_ERROR + REACH_FEASIBILITY; per foot: TARGET_ERROR + SUPPORT_CLAIM | contact_error_diagnostics.gd |
| `LadderClearance.vertex_evidence()` / `status()` / `intersection_evidence()` | VERTEX_OVERLAP FRESH only for the current update; MESH_INTERSECTION UNSUPPORTED | ladder_clearance.gd |
| Evidence tab `adda` block (`schema: 1`) | list of `Measurement.to_dict()`; tools that are off appear as UNAVAILABLE | `ui/evidence_tab.gd` |
| Negative-control test | extend it for every new instrument | `tests/adda_measurement_integrity_test.gd` |
| Probes | `ladder_sweep_probe`, `ladder_offender_probe`, `skeleton_update_timing_probe` | `tools/quality/` |

## Rules to keep

1. Sample only in `final_pose`; one witness per skeleton; pair acquire with release.
2. Return `Measurement.missing(...)` (null value) rather than zero when you cannot vouch for the pose.
3. A new instrument ships with a negative control and a normal-case check, in the same test file or its own.
4. Do not call a vertex count an intersection, a claim a support, a capsule a mesh.
5. Keep file paths, scene names and CLI arguments (`pose_workbench.tscn`, `--scenario=`, test names).

## Known gaps and suggestions (not done)

1. **Timeline:** `Measurement.update` and `frame` already allow a per-update log; a bounded ring of Measurements per provider is the natural first step (watch memory: the vertex sampler costs ~3 ms per sample, so record counts, not points).
2. **Migrate** `HandContactDiagnostics`, `BoneHighlight`, `MotionTrail` to emit envelopes (the first two read in the signal today).
3. **Structured session report:** a runner that plays a scenario at fixed fps and emits one JSON of Measurements with the scenario id, character and per-frame stats (the sweep probes are the prototype).
4. **Spatial observability:** generalise `LadderOverlay` (red vertices, knees, pelvis, targets) into a small overlay for any `Measurement` with a world position; add saved camera views (the close-up capture has four).
5. **Test contracts:** tag each ladder test with its measurement kind; keep goal and baseline separate (the mesh test already does).
6. **Full mesh intersection** (MESH_INTERSECTION) needs a triangle-vs-cylinder test or a shape query: a P2 item, and the answer stays UNSUPPORTED until it exists.
7. The mesh test's counts vary slightly run to run (headless deltas); use `--fixed-fps 60` for exact comparisons.

## Verification at handoff

Commands:

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test adda_measurement_integrity_test,ladder_mesh_clearance_test,workbench_*,exploration_actions_test
.\tools\run_tests.ps1 changed -Since review/claude-animation
```
