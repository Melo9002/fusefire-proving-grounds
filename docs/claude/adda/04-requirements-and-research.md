# ADDA requirements matrix and research findings

## 1. Research, verified on the installed engine (Godot 4.7.2.stable, `skeleton_update_timing_probe.gd`)

| Question | Finding | Consequence |
|---|---|---|
| Is a bone read outside `skeleton_updated` the pose that is drawn? | **No.** Outside the signal `get_bone_global_pose` returns the animation pose without the modifiers. In the probe the wrist read inside the signal stayed at y = 1.1600 (modifier-driven) while the read outside followed the base pose (1.2141 down to 0.8160). On a ladder climb the wrist read outside differed from the final one by up to **0.47 m** (`adda_measurement_integrity_test`). | Only a listener inside the signal may read poses. |
| Can a tool tell, from outside, that it is inside the signal? | **No.** A flag set in the handler and cleared with `call_deferred` is still set when the next `_process` runs (the handler ran first in that frame). | The contract has to be structural: one witness emits `final_pose`; samples carry a stamp; staleness is judged by comparing stamps. Rejected: a global "inside" flag (ADR-0001). |
| How often does `skeleton_updated` fire? | **More than once per rendered frame** (twice per frame in the probe: one before the node `_process`, one after). | Stamps use an **update counter**, not the frame number. |
| Do reads inside the signal include every modifier? | Yes: the signal is emitted after all `SkeletonModifier3D` processing (class reference; consistent with the probe and with the existing 0.0000 m agreement of `SkinnedSurface.rest_error` and the final-pose tests). | `skeleton_updated` is the sampling point; this was already the project's rule for hand and contact tools. |
| CPU-side skinning | `SkinnedSurface` reproduces the engine's linear blend skinning from the mesh arrays and cached bone poses; at rest it matches the mesh's own vertex positions to 0.0000 m; about 3 ms per sample for the leg set. | Fine for a diagnostic that is off by default; not for every frame of gameplay. |
| Cost of the existing instruments (headless, `diagnostics_overhead_probe.gd`) | monitor refresh 14 us, contact measure 15 us (+37 us draw), stage report 90 us, rig report 59 us; a frame with the monitor and contact overlay on cost 6.86 ms against 6.90 ms off (noise). | Optional instrumentation is cheap enough to leave opt-in; the mesh sampler is the one heavy tool. |
| Determinism | The mesh test's counts vary slightly between runs (for example 0.05 to 0.08 mean vertices per frame) because headless frame deltas differ; the capsule/pose traces use `--fixed-fps 60` and are exact. | Baselines in tests carry margin; exact comparison belongs to fixed-fps traces. |

**Other tools studied** (general knowledge, not re-fetched for this assignment): engine animation debuggers share three habits: draw what the solver was *asked* next to what the pose *is*, record a timeline that can be scrubbed, and tag every datum with the frame it came from (Unreal's Rewind Debugger and Animation Insights, Unity's Animation Rigging gizmos and Profiler, Chaos Visual Debugger). ADDA already does the first (target vs wrist); the stamp added here is the third; the timeline is Assignment 2. A full recorder or physics visual debugger was not adopted: too much machinery for a read-only suite.

## 2. Requirements matrix

Users: **A** animator/designer, **D** gameplay developer, **R** reviewer, **C** coding agent (Codex, Claude, Pixie), **Q** quality owner (Ironclad).
Cost: S (hours), M (a day), L (several days). Priority: P0 now, P1 Assignment 2, P2 later.

| # | User | Question | Evidence available now | Missing capability | Cost | Pri |
|---|---|---|---|---|---|---|
| 1 | C, R | Is this number from the pose that is drawn? | none (the ladder incident) | stamp + status on every reading | M | **P0 done** |
| 2 | C, Q | Does the instrument detect the fault it claims to? | scattered controls | negative controls per instrument | M | **P0 done** (ladder bar, stale, outside signal, foot, hand) |
| 3 | A, D | Which tool answers my question? | README prose | in-app index by question + kind tags | S | **P0 done** |
| 4 | R | Is this capsule, vertex or mesh evidence? | comments in tests | kind in the data and in every export | S | **P0 done** (`Measurement.Kind`) |
| 5 | C | Machine-readable evidence | Evidence JSON (rig, stages, contacts scalars) | envelope with kind/status/pose/space/limits | S | **P0 done** (`adda` block); more tools to emit it: P1 |
| 6 | A | Where, in space, is the problem? | ladder overlay, contact overlay | annotated views, knee/feet/hips for any scenario, saved views | M | P1 |
| 7 | A, R | When did it happen, what led to it? | `ContactErrorDiagnostics.history`, trail | frame timeline of Measurements with scrub and markers | L | P1 |
| 8 | C, Q | One report per scenario run | sweep probes, tests' printed lines | a structured session report (scenario id, character, per-frame stats, controls) | M | P1 |
| 9 | Q | Are baselines honest about what they measure? | ladder tests (capsule vs mesh) | contract per test: measurement kind + goal vs baseline | M | P1 |
| 10 | R | Does the mesh really intersect? | sampled vertices only | triangle-vs-bar test (or a physics-shape query) | L | P2 |
| 11 | D | Is it reachable / supported physically? | reach convention, support claims | physical support probe (ray/shape against the environment) | L | P2 |
| 12 | A | New humanoid: does it fit? | RigInspection, compatibility check | surfaced in a checklist with measurements | S | P1 |
| 13 | C, Q | Do we notice a regression in what ADDA sees? | pose and route traces | trace of Measurements for key scenarios under fixed fps | M | P1 |
| 14 | D | Reuse outside FuseFire | none | seam between generic contract and FuseFire adapters | L | P2 (no extraction) |
| 15 | A | Cost when I leave it on | overhead probe | per-tool budget shown in the panel | S | P2 |

## 3. Architecture options and decision summary

Detail and the decision are in `05-adr-0001-measurement-architecture.md`. In short: a small shared **measurement contract** (envelope + witness), diagnostics as **optional providers** that emit it, overlays as pure consumers of a provider's sample, and the workbench evidence export as the first **evidence interface**. Alternatives rejected: a global singleton "ADDA server", a rewrite of every diagnostic around one base class, wrapping `get_bone_global_pose`, and a per-frame recorder now.
