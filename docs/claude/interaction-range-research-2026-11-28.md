# Milestone 06.08: environmental interaction research and the Interaction Range (2026-11-28)

Branch `review/claude-interaction-range`, from the integrated main `315c76c` (PR #107 merged). **Research and an experimental map only.** Nothing here makes a door open or close in a battle; the two door states are two compiled maps. No production dynamic-door mechanic, no general environmental framework, no animation work, no Milestone 06.09 implementation, nothing merged.

Status words used throughout: **implemented** (code or content that exists and runs), **tested** (an automated check passes), **rendered** (frames I looked at), **proposed** (a design, not built), **unresolved**, **owner-approved** (nothing is).

## 1. What already exists (source-grounded audit)

There is **no door, window or opening entity** in gameplay. A search of `systems/`, `ui/`, `levels/`, `units/`, `presentation/` finds no door state, no opening metadata and no interaction. What exists is static geometry that happens to contain openings, plus most of the machinery a door state would have to go through.

| Area | What is there (file) | Relevance |
|---|---|---|
| Opening in static geometry | `art/environments/authored/components/combat_examples.tscn` "Doorway": two wall boxes and a lintel, each a node with `metadata/solid_size` and `precise_shot_bounds` (1 cell thick). `docs/combat-controlled-examples.md` case 07 proves legal movement and shots through it and a blocked wall beside it. `docs/combat-2-rules.md`: "A painted door texture alone creates no opening." | The precedent for how an opening is authored: separate explicit parts, one cell thick. |
| Geometry compilation | `AuthoredSceneMapCompiler` stamps every node with `solid_size` into cell flags, `movement_parts` (AABBs for sweeps) and a shot index (`authored_shot_parts`, `shot_obstacles`). It never infers solids from render meshes. | A door state is a set of parts; the compiler is the only place that turns parts into cells. |
| Standing points / movement | `SurfaceNavigation.resolve_map`: one supported standing point per cell (body radius 0.28 m, height 1.8 m, clearance 0.04), `edge_clear` sweeps between points, vault over low cover (below 1.2 m). `Pathfinder` (AStar3D) built by `MapGraphBuilder` from the resolved cells; `graph_revision()`, `configure_cell`, `disable_cell` already exist and bump a revision. `SurfaceNavigation.signature` hashes parts and cell flags. | Opening and closing a door is a local change to one cell and some edges; the revision and signature hooks exist. |
| LOS, cover, firing | `CombatRules` reads `grid.map_data` live (LOS index, cell flags, parts). Five body-sample rays, exposure table (0 to 50 points), directional cover (`_protecting_cover`), contextual side step. `MapData.los_revision` increments on any index change. | One shared query for UI, AI, execution and replay: change the map data and bump `los_revision` and every consumer sees it. |
| Destructible objects | **None in gameplay.** `docs/combat-destructible-cover.md` (Milestone 04 step 10) deferred it and lists the prerequisites for any dynamic geometry: stable object identity (compiled parts lose owner identity), one validated action, replace movement, LOS, cover and navigation together, preserve occupied standing points, advance the revision once, invalidate caches, record state in replay and fingerprint, bump the simulation version. `tests/destructible_cover_investigation_test.gd` proves the recompile effects offline. | The most relevant prior research. A door has the same prerequisites. |
| Tactical actions and authority | `TacticalActionService`: query / validate / commit / present for attack, move, reload, aim, shield, overwatch, wait, and the mission actions rescue, extract, `interact_terminal`. `state_revision` advances once per commit; a rejection (`ActionValidationResult.reject`) changes nothing and costs nothing. `interact_terminal` is the closest precedent: an id-addressed interactable, a free action, range "adjacent" via `CombatRules.can_reach_adjacent`, state in `ObjectiveManager`, a result with a schema version, a replay record and a line in the state fingerprint. | An explicit door action fits this pattern with no new framework. |
| AI planning and caches | `AIPlanningSnapshot` is stale when `state_revision` or occupancy changes. `BattleController` preview cache signature includes `los_revision`, `graph_revision`, `state_revision`, `occupancy_revision`; `AIController` cache signature includes `graph_revision` and `los_revision`. | A door commit that bumps those revisions already invalidates the previews and the AI caches. |
| Guard and reactions | `query_guard_reaction` reads the shot rules at a checkpoint cell. Guard fires at movement checkpoints (`_resolve_overwatch_reactions`) and as retaliation after being attacked. **No other state change triggers it.** | Gap: a door opening that exposes a still actor has no trigger today. |
| Replay | `BattleReplayRecording` (schema 3, `SIMULATION_VERSION` string), `BattleReplayPlayer._execute` matches record kinds, `BattleStateFingerprint.capture` includes the geometry signature (`standing_map=`) and terminal states. An unsupported action kind is rejected by the validator. | A new record kind and a fingerprint term plus a version bump; maps without doors must keep their fingerprint. |
| Persistence | There is **no saved-game system.** `user://` holds settings, parcel drafts and seed-failure reports. The only persisted battle form is the replay recording. | "Future saved games" means: door states as a dictionary in the same form as the replay fingerprint. |
| Authoring | Generation 2: a plot scene plus slots, each filled by a reviewed parcel scene (`AuthoredParcelCatalog`) whose nodes carry metadata. Parcel sizes are limited to 16x16, 16x32, 32x32 (`AuthoredParcelDefinition.validate`). The Parcel Editor (`tools/parcel_editor`) edits **visual transforms only** and "never modifies tactical metadata"; `mesh_tactical_bounds.gd` bakes one box per mesh for a newly placed object. | Door metadata must be authored in the scene file; the editor has nothing to extend for it yet. |

## 2. The Kenney Factory Kit assets (measured, not read off a preview)

CC0 (`art/environments/kenney/factory_kit/LICENSE.txt`). Measured with `docs/quality/evidence/interaction-range/asset_inspect*.gd` (node trees, mesh bounds, ray scans through the mesh). The project calibrates the whole kit at **scale 1.5** (`tools/asset_lab/asset_calibrations.json`); sizes below are native, then at 1.5.

| Model | Native size (x, y, z) | At 1.5 | What it is |
|---|---|---|---|
| `structure-wall` | 1.0 x 3.0 x 2.0 (AABB) | 1.5 x 4.5 x 3.0 | The mesh is a **0.2 m thick plane** (vertices at z 0.5 to 0.7) plus two stray vertices at z = -0.5 and 1.5 that stretch its bounding box to 2.0 m. The wall plane is 0.6 off the origin, not centred. |
| `structure-doorway` | 1.0 x 3.0 x 2.0 | 1.5 x 4.5 x 3.0 | Real opening by ray scan: **0.8 wide, 1.6 high native = 1.2 m x 2.4 m** at 1.5. A frame with a lintel. |
| `structure-doorway-wide` | 2.0 x 3.0 x 2.0 | 3.0 x 4.5 x 3.0 | Opening 1.8 x 1.6 native = 2.7 x 2.4 m. |
| `structure-window`, `structure-window-wide` | as the wall | as the wall | **No through-opening at all.** The ray scan finds something in every column at every height: the windows are glazed (frame, bars and pane in one mesh, one material, no transparency). As shipped they are a solid wall for any tactical purpose. |
| `door` | 0.8 x 1.6 x 0.3, centred | 1.2 x 2.4 x 0.45 | A hinged leaf that **fits `structure-doorway`** (0.8 x 1.6). **Ships its own AnimationPlayer** with `open`, `close` and `open-and-close` (1.0 s, one rotation track on the leaf, hinge at its local +x edge, about 100 degrees). Rest pose is closed. |
| `door-wide-closed` / `-half` / `-open` | 1.8 x 1.6 | 2.7 x 2.4 | A roll-up shutter in three static meshes. **`-open` still hangs from y 0.82 to 1.6 native (1.23 to 2.4 m)**: it leaves only 1.23 m of clearance below, less than a 1.8 m body. It is a half-open shutter, not a passable open state. |

None of them carries a collision shape. The kit has no open window frame.

**The mesh-bake trap** (tested, `interaction_range_experiments_test`): the Parcel Editor's `mesh_tactical_bounds` turns each model into one box from `mesh.get_aabb()`. For every one of the wall, doorway and window pieces that box is **3.0 m deep at the project's scale, ten times the real wall**, and one box has no hole: the baked `structure-doorway` compiles to a solid, **the doorway opening is not preserved**. (The compiler is right to say "an opening enclosed by one box is still blocked".) A building from these pieces needs explicit parts, as `combat_examples` did.

## 3. The Interaction Range (implemented, tested, rendered)

A new selectable map, built through the **existing** authoring pipeline: two parcel scenes (`art/environments/authored/parcels/interaction_range_closed.tscn` and `_open.tscn`), one plot (`interaction_range_site.tscn`, `Generation2.InteractionPlot`), catalog entries (`BattlefieldCatalog.INTERACTION_RANGE`, `AuthoredParcelCatalog`), Match Setup ("Interaction Range - Research map (16 x 32)"). The seed's parity picks the door state (even closed, odd open), recorded in the replay manifest like any other parcel choice. Scenes are generated by `docs/quality/evidence/interaction-range/build_range_scenes.py` and are ordinary scenes afterwards.

Layout (16 x 32 cells; the parcel contract allows only 16x16, 16x32, 32x32): a 9 x 18 m building, two 8 x 8 cell rooms (A north, B south), a partition with an **ordinary door** (Kenney `structure-doorway` frame, `door.glb` leaf, 1.2 x 2.4 m), a **separate window opening** (sill 1.25 m, head 2.3 m, drawn with plain boxes because the kit's windows are glazed), **two exterior doorways** (no leaf) so there is a way round, six low crates (Kenney `box-large`) including beside the door jambs, five deployment cells per side (room A against room B), ally cells and all five mission zones outside the rooms. Rendered: `docs/claude/images/interaction-range/door_closed_vs_open.png`.

Things the pipeline made me learn while building it (all fixed or documented):

* **A thin wall on a cell line does not block the cell.** A 0.3 m wall part centred on a cell leaves the cell standable at its edge: the first compile showed every wall cell standable with its standing point displaced 0.395 to 0.47 m (and the closed door cell too). Movement across is still blocked by the edge sweeps, but a unit can stand "in" the wall cell hugging the wall. The existing authored maps never meet this because their obstacles are thick. I made the tactical parts **one cell thick** (1.0 m) and kept the visual at the kit's 0.3 m, as the `combat_examples` doorway does.
* A map must be registered in **six places** (catalog definitions, `SELECTABLE`, `uses_population`, `generate`, two presentation source lists, generator plots, parcel catalog, Match Setup's population toggle); a missing presentation list made the battle fail with "could not reconstruct its imported presentation".
* Mission zones on a cover cell fail validation (`ZONE_CELL_INVALID`).

## 4. Experiments (static door states, through real battles)

`tests/interaction_range_experiments_test.gd`, 40 checks, 0 failures. It builds a real battle on each state and measures with the real movement graph and shot rules; each measurement has a control. The `EXPERIMENT` lines are copied from its output. **These are static experiments: nothing opens or closes in a battle.**

| Question | Closed | Open | Control / note |
|---|---|---|---|
| Door cell | not walkable, not standable | walkable, standable, standing point at its centre | exterior doorway (no leaf) is standable in both: an opening survives compilation |
| Route (7,11) to (7,13), the cells either side of the door | **25.3 m**, round through the exterior doorways | **2.0 m**, through the door | window never a route: 22.8 m round (closed), 9.4 m (open) |
| Diagonal step into the doorway past the jamb | refused by `can_reach_adjacent` | refused; the straight step is allowed | corner blocking holds |
| Shot through the door column | **blocked** (blocker "Closed door") | **legal, 100%**, no blocker | a shot through the solid partition: blocked in both |
| Shot through the **window** | **legal, 50%** | legal, 50% | a window is a partial opening: only the highest body sample clears the 1.25 m sill at the units' 1.0 m standing height; bare rays: clear between 1.3 and 2.2 m, blocked below the sill and above the head |
| Target beside the jamb, same shooter | blocked | **legal, 50%, full cover** (the jamb); in the door column 100% | the jamb behaves as cover |
| Oblique line through the open doorway | blocked | **blocked by the open leaf** ("Open door leaf") | the swung-back leaf is a physical part and has to be modelled |
| Guard from (7,9) at a hostile in the door column / beyond | cannot fire (blocked) | **can fire** at the door cell, the column beyond and (7,15); not at the jamb-shadowed (6,13) | Guard follows the shot rules; no new rule needed for a static state |
| A unit standing in the open doorway | | route (7,11) to (7,13) goes round (25.3 m) | occupancy already blocks a door cell like any occupied cell |
| Geometry signature | `e8c95d00...` | `9f441ba1...` (differs); deterministic per seed | the replay fingerprint includes it, so the state is already distinguishable |
| Whole AI-versus-AI match (2 v 2, one seed per state) | status completed, **victory in 10 rounds**, 48 actions | completed, **defeat in 5 rounds**, 42 actions | the AI plans and commits on the new map without a validation error either way; one seed each is an observation, not a balance claim. I did not isolate how the AI used the door. |
| Match Setup | | | the map is listed, builds a 16 x 32 configuration, population off |

Rendered: the open state shows a unit visible through the door, the closed state a leaf (`door_closed_vs_open.png`). I did not play a battle on it with a person.

## 5. Defects, gaps and reusable components

**Reusable (do not rebuild):** the compiler's explicit-part path; `AuthoredSceneMapCompiler` and the standing-point resolver; `Pathfinder.configure_cell`, `graph_revision`; `MapData.los_revision` and `rebuild_los_index`; the `TacticalActionService` query/validate/commit/present pattern and the `interact_terminal` precedent; `CombatRules.can_reach_adjacent`; the AI and preview cache signatures (they already include `graph_revision` and `los_revision`); the geometry signature in the replay fingerprint; `door.glb`'s own animation; `structure-doorway`.

**Gaps (confirmed by measurement unless stated):**

1. **No owner identity on compiled parts.** `movement_parts` are deduplicated AABBs and cells combine contributions (from the destructible-cover investigation; the compiler code confirms it). A runtime swap needs door-owned parts the compiler does not merge.
2. **The mesh bake cannot make a building.** Walls, doorways and windows come out 3.0 m deep and solid.
3. **Kit windows have no opening** and the kit has no passable "open" wide door (`door-wide-open` leaves 1.23 m of clearance).
4. **Thin walls leave their cell standable at the edge** (see section 3). Not a defect of this map; it is a rule future authored buildings need.
5. **Guard has no trigger for a non-movement state change.**
6. **The open leaf is an obstacle** (oblique shots blocked by it); a toggle must remove or add its footprint.
7. **The Parcel Editor cannot author tactical metadata**, so door metadata is scene-file authoring.
8. **Adding a map touches six places** (not a defect of the feature, a cost to know).
9. Pre-existing failure, not this work: `camera_environment_apertures_test` ("contextual_firing_bay has compatible geometry through the shared environment presenter") fails identically at the exact integrated baseline `315c76c` (reproduced in a clean checkout of that commit), so it is inherited.

## 6. Door and window interaction designs (compared, not selected)

Common to all: the door is one authored object with a stable id; the open and closed parts are two part sets on the door node; a state change replaces the door cell's flags, the leaf's movement and shot parts, the cell's standing point and the cell's graph edges **together**, in one committed step that advances `state_revision` once and bumps `los_revision` and the graph revision; opening is refused (no AP, no change) when the actor is out of range, the door is already in the requested state, the actor is carrying someone (as attack does), a unit stands in the door cell, or (closing/opening) a unit stands under the leaf's swing footprint.

| | A. Explicit action (a button/command "Open door", "Close door") | B. Automatic on movement (moving into a closed door opens it as part of the move) | C. Hybrid (explicit action available; the planner may include "open" as a costed first step of a route) |
|---|---|---|---|
| Fit with the architecture | Matches the query/validate/commit pattern and `interact_terminal`. Smallest change. Every consumer (UI, AI, replay) already speaks "request, query, result". | Touches the move query and the route planner: a closed door becomes a passable edge with a cost; the preview, the AI route and Guard checkpoints all change. | Largest: A plus B's planner change. |
| AP cost | A fixed cost (1 AP proposed; 0 is possible) charged once on commit | Folded into the move's cost (e.g. +1 on the door edge); a move through a door is a single AP total | Both |
| Rejection | Clean: nothing changes, nothing is spent | Must reject mid-route if the door becomes blocked after planning (occupancy) | Both |
| Guard | An explicit transition is easy to treat as a Guard checkpoint for the actor's own cell | Guard already runs at move checkpoints: the door cell is a checkpoint | Both |
| AI | The AI does not use doors at first: a closed door is a wall (measured: it routes round, 25 m). A later AI step can add "open door" as an action | The AI inherits it only if the planner is taught | Needs the planner |
| Replay | A new record kind with the door id and the target state | Part of the move record, but the move then changes geometry mid-path | A plus extra |
| Player feel | A deliberate, visible choice; costs a button | Fluid, the way most tactical games play | Best, at the highest cost |
| Risk | Low | Medium to high (a move whose geometry changes under it breaks "the path is a function of the committed state") | High |

**Windows differ from doors** in what the measurements show: a window with a sill at or above 1.2 m blocks movement (full cover) and leaves a **partial aperture** for shots (50% here) at the standing height used; a sill below 1.2 m would make the cell a vault, which is a different design. Nothing in the existing rules lets glass block movement but pass sight. Three options for the owner: static apertures (what is built), glazed windows that are solid (what the kit actually is), or a later "breakable glass" (the destructible-object prerequisites again).

## 7. Recommended minimal slice for Milestone 06.09 (proposed)

One authored door on the Interaction Range, explicit **open** and **close** actions (design A), end to end:

1. **Authoring:** on the door node, `door_id`, its initial state, and two child part sets (`closed` and `open`), each a list of explicit boxes as in the experiment (the closed leaf one cell thick, the open leaf the thin swung part). No Parcel Editor work.
2. **State and geometry:** a small door registry on `MapData` (id, cell, the two part sets). Compile with the door in its initial state; a toggle applies the **difference** between the two states (compile both once at battle start and keep the cell diff), re-resolves the door cell's standing point, and updates the pathfinder cell and its edges with the existing `configure_cell` and diagonal refresh; then `rebuild_los_index` and the revision bumps. Occupied standing points are not touched (the lesson of the destructible-crate investigation: a fresh solve can move a unit that never changed cells).
3. **Action:** `open_door` / `close_door` in `TacticalActionService`, query and submit sharing one validation, AP cost and range policy (adjacent orthogonal, edge clear, not diagonal), rejection without cost.
4. **Guard:** after a committed toggle, give each hostile Guard watcher one checkpoint at the actor's own cell through the existing `query_guard_reaction` (the same pattern as retaliation). Owner decision below.
5. **Replay and fingerprint:** a record kind, the door states in `BattleStateFingerprint` (appended only when a map has doors, so existing fingerprints are unchanged), a simulation version bump, and the unsupported-kind validator updated.
6. **Presentation:** after the commit, the door node plays its own `open` or `close` animation (`door.glb` has them); suppressed in fast replay; the state is committed instantly, so presentation speed never changes the simulation.
7. **Tests:** the experiments in this PR become the regression tests of the toggle (closed and open have to agree with the static maps measured here), plus rejection-without-cost, occupancy, replay round trip and cache invalidation.

Out of scope for the slice: AI use of doors, automatic opening, windows, breakable glass, Parcel Editor authoring, any animation work.

## 8. Decisions the owner needs to make before 06.09

1. **Design:** A (explicit), B (automatic) or C (hybrid)? I recommend A for the first slice.
2. **Cost:** AP to open and to close (1 each, free, or open 1 and close 0)?
3. **Range:** adjacent orthogonal only, or any adjacent cell including diagonal?
4. **Closing onto a unit / a leaf footprint:** refuse (proposed), or push-back, or allow a stuck door?
5. **Guard on a door opening:** does opening a door provoke Guard reactions at the actor's cell (proposed: yes, once per watcher), or only movement does?
6. **Who may open:** every faction, or only some? (The terminal action is faction-pursued.)
7. **Window rules:** static apertures as built, glazed solid windows, or breakable glass later? And the sill height (1.25 m here, which leaves a 50% partial aperture for 1.0 m units).
8. **Door open leaf as a part:** keep the swung leaf as an obstacle (measured: it blocks oblique shots) or model it as flat against the wall?
9. **Wall thickness convention:** accept one-cell-thick tactical walls with thin visuals for buildings (as the Interaction Range does)?
10. **AI scope:** closed doors are walls for the AI in 06.09 (proposed), with door use as its own later step?
11. **Versioning:** a simulation version bump for 06.09, with old recordings still playable (they contain no doors)?

## 9. Verification (final commit)

Counts are from the runs that produced them.

* `tests/interaction_range_experiments_test.gd`: **40 checks, 0 failures** (headless).
* Catalog check: 325 scripts, 325 catalog entries. Import: pass. **Hosted smoke: GREEN, 27 of 27.**
* Related selection: 13 passed, 1 failed (`camera_environment_apertures_test`, inherited: the same assertion fails in a clean checkout of `315c76c`; it is about `contextual_firing_bay`, which this work does not touch). Passed: `current_generation_test` (updated: Match Setup now offers six maps, an intentional contract change), `current_content_pack_test`, `compact_battlefield_test`, the parcel camera, reservation, local battle, paint scope, population parity and gallery picking tests, `mesh_boundary_battle_test`, `combat_geometry_los_test`, `battle_loading_screen_test`.
* The animation, movement and rescue tiers and the full tier were **not** run: this work does not touch animation, rig, movement presentation or the tactical rules; it adds a map and a catalog entry.
* Not verified: any behaviour in a live battle with a person; Guard and AI behaviour beyond the observations above; how the AI actually used the door; the loading and camera behaviour of the map beyond the headless battle and the rendered frames.

## 10. What changed in the repository

New: the two parcel scenes, the plot scene, `interaction_range_experiments_test`, `interaction_range_capture` (explicit), the evidence scripts and generator under `docs/quality/evidence/interaction-range/`, this report and the contact sheet. Changed: `battlefield_catalog.gd`, `generator.gd`, `authored_parcel_catalog.gd`, `match_setup.gd`, `tests/catalog.json`, `current_generation_test.gd`.
