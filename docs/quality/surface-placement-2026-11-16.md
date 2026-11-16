# Surface placement integration — 2026-11-16

## Scope and contract

An opt-in ordinary parcel can expose one supported, quantized standing point per logical cell. The current pipeline resolves existing asset boxes automatically. Standing cylinders must fit, and graph edges must clear a conservative swept enclosing box with floor support. Neighboring-cell bodies cannot overlap or be crossed by a route. Source/target shot geometry remains independently indexed. Physical cover contacts replace the four-neighbor shortcut in this mode, including cover overlays and pose context.

The enabled content is **Surface Fit Range — container, truck, building edges**. Other maps keep their existing traversal. The pilot covers flat supported floors; unsupported rises and unvalidated vertical links reject. No universal stair/ladder/curved-surface claim is made. The body proxy does not guarantee every weapon or animation extremity clears geometry. Per-mesh boxes still conservatively fill concavities and curved footprints.

Compiler revision **5** retains historical compilers 1–4. Replay simulation **prototype-1.5-surface-placement-6** deliberately rejects previous simulation recordings. Move payload **10** records canonical XYZ per checkpoint, rounded to 1/10000 tile. Reconstruction signatures include supported points, availability, obstacle parts and the body profile. State fingerprints include within-cell point evidence; the presentation transform is not the tactical authority.

## Focused executed checks

| Check | Result |
| --- | --- |
| `surface_placement_test.gd` | 64 checks, zero failures. Existing geometric/contact contracts retained. |
| `surface_navigation_test.gd` | 52 checks, zero failures. Fits, support, conservative sweeps, body separation and safe detours, mission registration, actual cover markers, own-cell LOS, thin tile-edge wall, low beam, entrance width, unsupported rises, preview/live/Guard agreement, deterministic signatures and three scales × four rotations. |
| `surface_battle_replay_test.gd` | 43 checks, zero failures headless; editor-preview parity, three real Move actions beside a container/truck/building, archive/save/reopen/replay, quantized checkpoints, changed-map-evidence rejection and missing-checkpoint rejection. |
| Rendered battle/replay | 46 checks, zero failures with three close review captures. Images inspected in `artifacts/surface-battle-review/`. This checks final placeholder poses and a three-Move replay, not every animation frame or a completed combat match. |
| Tactical pose and directional cover regressions | Passed; existing directional-cover suite retains all 40 checks. |

Logs: `artifacts/surface-navigation-focused.log`, `artifacts/surface-placement-integration.log`, `artifacts/surface-battle-replay.log`, `artifacts/surface-battle-render.log`, `artifacts/surface-pose.log`, `artifacts/surface-cover.log`. The rendered run printed the known Windows certificate-store diagnostic; its assertions and replay passed.

## Failures investigated during development

- The first example parcel serialized children both as inherited instances and as new children. That retained the container's old coarse reservation and produced detached duplicate visual geometry. Flattening only the small outer assembly while retaining imported visual instances fixed the scene. No existing reusable asset was edited. The earlier leaked render instances and aperture errors from that bad scene are absent from the corrected run.
- The first building example accidentally multiplied an already calibrated scale by three, enclosing the battlefield. Correcting the authored example's object scale fixed this fixture error; no clearance assertion was relaxed.
- Float32 coordinates far from zero could reject an exactly constructed face candidate. A small relative fit tolerance plus a separate quantized-point/body-clearance check handles this. Tiny-body rejection assertions still pass.
- An integration test used a nonexistent service property instead of the actual `submit_move(request, suppress_presentation)` API; corrected the test. Immediate teardown before deferred debug attachments also leaked their nodes; the test now allows the normal initial frame before actions/teardown.
- GDScript required an explicit Dictionary annotation for a value read from replay configuration; corrected before executable testing.
- A detour test initially demanded more than three points, assuming cardinal travel. A legal pair of diagonal segments cleared the neighbor instead. The assertion now requires a real deviation from the blocked straight route and checks clearance on every segment, retaining the actual safety invariant.

## Broad verification

Full Ironclad: **144 suites passed, 0 failed, 14 explicit-only skipped**, **950.70 seconds**. Logs: `artifacts/test-results/surface-placement-integration/20261116-132929-full/`. This includes the new pilot checks, current content/mission/replay matrix, AI, geometry/cover, Guard, editor handoff, camera, loading and existing vertical traversal. Focused final navigation and saved-replay runs also passed after retaining the native path fast path with body-aware fallback.

The 14 policy-skipped stress/capture workflows were not all run. The surface pilot's rendered capture was run separately and inspected. Headless success is not a claim of universal visual correctness, completed combat balance, finished IK or arbitrary vertical traversal. Known certificate-store diagnostics and the pre-existing allied-faction ObjectDB warning remain environment/baseline limitations. No new leak or script runtime error remains in the corrected pilot logs. Six pre-existing texture-import modifications remain outside this change.
