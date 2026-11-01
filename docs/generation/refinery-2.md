# Refinery 2.0 — authored first playable

## Open and play

In Match Setup, enable the existing generated-map selector and choose **Authored - Refinery 2.0 (96 x 80)**. This entry loads a fixed authored environment through the ordinary battle scene; it does not invoke the quarantined Generator 2. The original **Special - Refinery** remains available.

The map contains two process halls, a six-tank containment yard, boiler columns, loading/control buildings, equipment and service vehicles. Four connected maintenance galleries provide 288 elevated cells and five ladder accesses. Buildings are exterior obstacles, not enterable interiors.

Open `art/environments/authored/refinery_2.tscn` in Godot to edit the actual scene. Imported models retain the saved calibration scales. Geometry is already resolved in the scene; loading a match does not reread Asset Lab metadata or search assembly recipes.

## Reusable content

New custom components live alongside the existing environment collection in `art/environments/authored/components/`:

- `catwalk_deck_2x2.tscn`: two-metre square deck; origin at the walking surface, slab below it, matching physics collider.
- `maintenance_ladder_4m.tscn`: four-metre ladder, origin at ground, climbing face along Z.
- `catwalk_support_2m.tscn`: paired supports spanning two metres along X; supports a deck whose top is four metres above ground.
- `pipe_rack_support.tscn`: 7.5-metre columns, five-metre column spacing along Z and 5.7-metre crossbeam.

The refinery instances these files. They are not merely spare copies. Kenney source files remain unchanged. Rail runs are authored along exposed gallery boundaries; junctions and ladder openings are left clear.

`tools/environment_authoring/refinery_2_author.py` preserves the offline authoring recipe. Run it explicitly from the repository root with Python. It overwrites this map and these generated components using current saved calibrations: review the diff and capture the result afterward. Direct scene edits must be transferred into the recipe before regenerating, or they will be overwritten. This is a single-map authoring aid, not a runtime generator or the finished agent-authoring pipeline.

## Tactical boundary

`Refinery2Layout` reads explicit scene metadata into existing `MapData`:

- Upright box/cylinder `solid_size` volumes merge conservatively into ground cells. Overlapping contributions retain maximum height. Short cover follows the existing vaultable/non-stoppable rule.
- `deck_rect` and `deck_level` author grid surfaces and thin blocking slabs. These rectangles are map coordinates; changing their associated geometry requires updating the metadata too.
- Ladder endpoints and deployment origins are explicit grid coordinates. The shared validator rejects invalid endpoints and deployments.
- Shared mission placement, simulation, movement, camera occlusion and replay remain authoritative. The new selection is preserved in replay configuration.

Overhead pipe runs and handrails are presentation geometry, not individual ballistic obstacles. Water-tower occupancy is a conservative solid footprint. This first map does not add arbitrary stacking, interior navigation, destruction, geometry-derived protection percentages, contextual random population or persistent location changes.

## Verification — 2026-11-01

- `tests/refinery_2_smoke.gd`: passed. Fixed-layout determinism across seeds, scaled heights, solid footprints, open roads, five connected ladder routes, thin containment cover, deck slab obstruction, measured pipe-joint alignment, mission zones, actual battle initialization and JSON replay round-trip with a real movement action.
- `tests/refinery_2_ai_smoke.gd`: passed. Natural Reach mission completed in five rounds; 75 AI decisions, 91 recorded/replayed actions, exact replay agreement. Simulation reported 21.48 seconds on this machine. No teleports or injected victory.
- Ironclad smoke: 10/10 passed; logs `artifacts/test-results/20261101-134423-smoke/`.
- `tests/generation_retirement_test.gd`: passed; retained original-generation/replay behavior and explicit rejection of retired selections.
- Rendered overview, process, tank-yard and loading views inspected after correcting rotated pipe elbows. Captures: `artifacts/refinery2-captures/`; reproduce with `tests/refinery_2_capture.gd` in a graphical Godot run, passing the output directory after `--`.
- Existing restricted-environment certificate-store warnings remain. No new runtime warning is accepted as map correctness.

Failures found and corrected during development: low-cover cells initially violated the vaulting contract; conservative containment coverage exposed an allied deployment on a lip; a cargo pallet blocked a ladder approach; serialized rotation matrices transposed some pipe connectors. The final checks preserve the relevant assertions.

These checks establish integration, not balanced combat or a completed owner playtest. Full Eliminate/Terminal playthroughs and human pacing review remain outstanding. The layout is deliberately spacious; adjust encounter scale based on play rather than interpreting a valid path as good pacing.

## Owner playtest

1. Confirm the pipe returns meet pumps and the halls/tanks feel like one industrial site.
2. Climb the galleries from different ladders, cross between areas, and descend. Inspect overhead clearance, camera fade and grid selection at level 4.
3. Fight around the tank yard and loading area. Note long empty runs, overly exposed deployment positions or dominant firing positions.
4. Try a normal objective and watch its replay. Report the seed, objective and location if movement or targeting disagrees with the scenery.

## Agreed next task

Make this authoring process repeatable for other agents: a concise asset/reference guide, small reusable components, measured connection examples, explicit tactical metadata, automatic checks and required visual captures. Start from this working map and its limitations. Do not resurrect the quarantined generator, create another application, or infer owner approval from a passing test.
