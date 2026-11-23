# ADDA, Assignment 1: baseline and architecture

ADDA = **AniLab Diagnostic & Debugging Assistant**, the name of AniLab's existing diagnostic suite (it is not a separate framework). The Animation Workbench is now **ADDA — Workbench**. This report is the baseline the work started from, what the architecture is, and where ADDA's boundary lies.

## 1. Baseline (2026-11-23)

| Item | State |
|---|---|
| Branch | `review/claude-adda`, cut from `review/claude-animation` at `38d3865` (pushed). `main` untouched; nothing merged. |
| Dependency | `review/claude-animation` is **not merged**. It carries `fa7da9a` (ladder clearance investigation) and `38d3865` (mesh-level clearance, SkinnedSurface, ladder fixes). `main` ends at `6323afb`. This branch therefore contains those two commits; merge order is: `review/claude-animation` first, then `review/claude-adda`. |
| Uncommitted at start | none (two stray `*.svg.import` files in `docs/claude/images/`, left alone). |
| Inherited failures | `ladder_climb_test` (2 capsule checks) and `ladder_landing_test` (capsule checks). Deliberate, documented in `docs/claude/ladder-landing-generalization-2026-11-23.md`; thresholds not loosened. **One more inherited failure found while verifying** (reproduced identically on a clean checkout of `38d3865`): `ladder_landing_test` "small armed posts up at 30 fps: each hand holds its grip" fails its sample count (`held > 15`) with 14-15 samples whose worst error is 0.000-0.002 m. It is a count threshold at 30 fps that the rail-grip change sits just under, not a contact error; the earlier report described this test's failures as capsule-only, which was incomplete. Left unchanged. Nothing else failed in the `changed` tier. |
| Known limitations carried | landing transitional overlap (10–23% of landing frames, up to 58 mm deck overlap); MIRA knee spread ~52–60 cm; capsule vs mesh contract disagreement; I could not view video. |

History that matters: the ladder investigation read a skinned mesh outside `skeleton_updated`, got the **base** pose, and reported mesh numbers that were wrong (withdrawn in the ladder report, Addendum 2). That incident is why Assignment 1 is about measurement integrity.

## 2. Architecture as it is

```
host (tactical adapter | exploration host | workbench)
  └─ CharacterPresenter ── intent, holds, attacks, rescue clock (public accessors)
       └─ CharacterRig ── Skeleton3D + modifiers in PoseOwnership.STAGE_ORDER
            ├─ writes pose; pose is FINAL only inside Skeleton3D.skeleton_updated
            └─ presentation/diagnostics/*   read-only, opt-in, created by diagnostic hosts only
tools/animation_workbench/   host + panel (ADDA — Workbench): 4 tabs, scenarios, evidence export
tools/quality/               probes, traces, demos (shared quality infrastructure ADDA consumes)
tests/                       Ironclad tests, catalog.json, explicit-only captures
```

Boundary rules already enforced by tests (`animation_module_boundaries_test`): `presentation/diagnostics` may read a `CharacterRig`; the game never creates a diagnostic; no bone-name strings in generic code (hence the label in `LadderOverlay` prints a bone, not a trimmed name).

## 3. Where ADDA sits

* **Core ADDA** (this report's subject): everything in `presentation/diagnostics/`, `presentation/characters/rig/skinned_surface.gd` (the measurement surface, shared with rig build), `tools/animation_workbench/`, and the measurement contract (`Measurement`, `PoseWitness`).
* **Shared quality infrastructure ADDA consumes** (not ADDA, not renamed): `tools/run_tests.ps1`, `tests/catalog.json`, `tools/quality/pose_trace.gd`, `route_trace.gd`, probes, captures, the replay system (`docs/replay.md`), F3 battle inspection (`docs/debug-inspection.md`: a tactical/AI inspector, a separate suite).
* **FuseFire-specific today:** every diagnostic takes a `CharacterRig`; ladder tools take `LadderGeometry`/`LadderLanding`; the workbench loads FuseFire characters. Generic already: `Measurement`, `PoseWitness` (they know only `Skeleton3D`, plus `CharacterRig` for the identity string), `RigInspection`'s pure functions. No extraction is attempted; the contract classes were written so that a later extraction has a clean seam (see ADR-0001).

## 4. What changed in Assignment 1

1. **Identity:** `WorkbenchSession.PRODUCT = "ADDA — Workbench"`; viewport title, OS window title, README, a folded "ADDA guide" section on the Diagnostics tab mapping questions to tools, section titles carry the measurement kind, and the exported report has an `adda` block. Scene path `res://tools/animation_workbench/pose_workbench.tscn`, CLI arguments, scenarios and test names are unchanged.
2. **Measurement contract:** `Measurement` (envelope: kind, status, pose, space, method, units, limits, identity, frame/update stamp) and `PoseWitness` (one reference-counted listener per skeleton; the only source of `final_pose`). See `03-measurement-contract.md`.
3. **Retrofits:** `LadderClearance` samples itself from the witness and refuses to answer from a stale or base pose (`status()`, `vertex_evidence()`); `ContactErrorDiagnostics` samples from the witness and exports `evidence()`; `SkinnedSurface.has_capture()`.
4. **Negative controls:** `tests/adda_measurement_integrity_test.gd` (21 checks).
5. **Research:** `tools/quality/skeleton_update_timing_probe.gd` verifies the signal timing on the installed Godot (4.7.2).

## 5. Findings of the audit (stale-read risks)

| Where | Risk | Verdict |
|---|---|---|
| `LadderClearance`/`SkinnedSurface` | mesh read outside the signal = base pose | **Fixed** (capture in the witness window; status; control test) |
| `ContactErrorDiagnostics`, `BoneHighlight`, `HandContactDiagnostics`, workbench `_record_stair_ankles` | read inside `skeleton_updated` already | sound; ContactError moved onto the witness |
| `HandContactSampler.sample("manual")` | can be called from anywhere; records `meta.timing` so a reader can tell | documented; not changed (its contract is the label) |
| `tools/quality/pose_trace.gd` | `_snapshot` reads `get_bone_global_pose` | **Sound**: it is called from a `skeleton_updated` callback (checked: `capture` connected at the scenario start, line ~84), so bones are final. (I first suspected a gap here and verified before writing it down.) |
| `tools/quality/ladder_transfer_demo.gd` | reads knee/shoulder bones | **Sound**: `_sample` runs from `ContactErrorDiagnostics.sampled`, emitted inside the final-pose window. |
| `PresentationMonitor` | `presenter.time` clock, public accessors only | sound |
