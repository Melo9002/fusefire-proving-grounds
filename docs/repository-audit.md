# Prototype 1 Repository Audit

This document records the 27A repository-wide audit. Its recommendations preserve the current game rules, diagonal movement, AI behavior, replay determinism, mission outcomes, presentation, and editor workflow. Performance changes should be accepted only when the regression suite remains green and a benchmark demonstrates an improvement.

## Executive assessment

The project has a sound playable foundation and unusually broad smoke-test coverage for a prototype. The main optimization opportunity is avoiding repeated work rather than simplifying game behavior. Input preview currently repeats physics queries and mesh/path construction every frame, AI evaluation repeatedly scans static map geometry, and generated scenery creates many small render objects. The VRoid asset is also expensive enough that draw calls and animation processing should be profiled on the home graphics setup.

The safest sequence is:

1. Reconcile the battlefield stress assertion with verified AI behavior and establish performance baselines.
2. Make hover and preview updates event-driven without changing their outputs.
3. Replace inefficient search queues behind the existing `Pathfinder` interface.
4. Add static geometry indexes and reuse attack evaluations within one AI decision.
5. Consolidate generated scenery meshes and shared materials.
6. Profile the VRoid renderer before changing its fidelity or animation behavior.

## Findings

### P0 — Establish a trustworthy regression contract

At the original audit baseline, `tests/battlefield_stress_smoke.gd` failed five combined AP/Defend assertions. That result alone did not establish which part failed. Follow-up inspection confirmed that `_execute_turn()` explicitly permits `_try_safe_second_advance()` to spend the remaining AP. The updated assertion retains zero remaining AP without requiring Defend; the complete stress test now passes.

Before optimization work:

- Decide whether “all remaining AP must be spent on Defend” is still a game rule.
- If it is a rule, fix the AI and keep the assertion.
- If it is not a rule, assert durable outcomes: the AI turn completes, AP is valid, occupancy remains unique, movement ends, and the next phase begins.
- Add timing probes for hover preview, reachable-cell search, one AI turn, terrain presentation, and representative attack evaluation. Store thresholds generously enough to avoid machine-dependent failures; use trend reports for tighter performance comparisons.

The 100-seed map generation test passes and completed in 6.24 seconds on the work computer. This is a useful baseline, though it measures generation and validation together.

### P1 — Stop recomputing unchanged mouse previews every frame

`BattleController._process()` requests a floor raycast every frame. `MouseRaycaster._process()` independently requests the same result for its floor hint. Attack preview calls `get_unit_under_mouse()`, which requests the floor result again and can perform up to 32 additional physics ray intersections. A floor query can perform up to 64 intersections to discover stacked surfaces.

Movement preview also runs A* and rebuilds the path visualization mesh every frame while the cursor remains over the same cell. Clearing an inactive path repeatedly also assigns an empty mesh every frame.

Preserving behavior:

- Cache the floor candidates and hovered unit by viewport frame, mouse position, camera transform, and selected floor index.
- Emit a hover-changed signal when the resolved cell or unit changes.
- Recalculate a movement path only when the hovered cell, active unit, movement budget, map revision, or mode changes.
- Redraw or clear visualizers only when their content changes.
- Invalidate the cache after camera movement, floor cycling, unit movement, map replacement, and viewport changes.

This should be the first production optimization because it removes work from every interactive frame without altering any rule or visual result.

### P1 — Replace repeated frontier sorting with proper queues

`Pathfinder.get_reachable_cells()` sorts the whole frontier on every Dijkstra iteration and then uses `pop_front()`. `MissionPlacementEvaluator` follows the same pattern. Breadth-first searches in map quality and mission-zone planning also remove the first array element repeatedly.

Preserving behavior:

- Put a small stable min-heap behind `Pathfinder` for weighted searches.
- Use an array plus a head index for unweighted breadth-first searches.
- Preserve neighbor order and verify equal-cost extraction order against the existing implementation. An insertion-sequence tie-breaker is deterministic but does not necessarily reproduce the existing unstable sort order; changing it can alter AI decisions.
- Compare complete reachable sets, path costs, chosen AI destinations, and replay recordings for fixed seeds before merging.

This becomes more valuable as maps and movement budgets grow. It should remain behind existing public interfaces during 27B.

### P1 — Avoid repeated line-of-sight scans during AI decisions

Attack visibility samples five points on a target. Geometry collection for those samples can traverse every map cell and discard cells without cover. Position scoring then performs line-of-sight checks for each reachable candidate against each hostile. Target selection also evaluates the same attacker/target pair more than once in its carrier-threat branch.

Preserving behavior:

- Build immutable indexes for cover geometry and LOS blockers when `MapData` is finalized.
- Restrict candidate blockers to the segment's grid-space bounds before running the existing geometric test.
- Create a per-decision `AIAnalysisContext` that memoizes attack evaluations, LOS results, hostile lists, and common distances. Discard it whenever a unit moves, is defeated, is extracted, or the map changes.
- Keep the current five target samples and obstruction rules until equivalence tests prove a replacement produces the same results.

Do not use a permanent global LOS cache yet; unit height, occupancy, and map mutations make invalidation easy to get wrong.

### P1 — Consolidate generated scenery render objects

`GeneratedTerrainPresenter` creates a separate `MeshInstance3D` and `BoxMesh` for most cover blocks, container ribs, rails, ladder pieces, steps, windows, doors, and building details. It also creates many identical `StandardMaterial3D` resources. This produces numerous nodes, render instances, materials, and draw calls for static scenery.

Preserving behavior:

- Introduce a presentation palette resource containing shared materials and tunable colors.
- Batch static boxes by material and shadow policy into a small number of `ArrayMesh` surfaces or `MultiMeshInstance3D` groups.
- Keep input/roof colliders and metadata in a separate gameplay structure so raycast behavior remains identical.
- Preserve named parent nodes where debug inspection depends on them, but avoid a named child node for every decorative rib.
- Compare generated-map screenshots, floor selection, collision, camera obstruction, and map validation across fixed seeds.

This aligns performance work with 27C: artists gain an inspector-editable palette instead of colors scattered through construction code.

### P2 — Profile and budget the VRoid presentation

The runtime character contains roughly 31,000 vertices, 46,000 triangles, 22 material surfaces, 29 images, and 229 joints. Ten visible units can therefore create roughly 220 character surface submissions before weapon and shadow passes. Textures are resource-shared between instances, so texture duplication is not the primary concern. Material surfaces, skinning, shadows, and per-unit animation/IK are the more likely costs.

The work computer's DirectX 12 freeze makes graphics measurements there unreliable. Profile this item on the home setup in Forward+ and Compatibility using Godot's frame profiler and render diagnostics.

Possible changes after measurement:

- Atlas compatible materials to reduce surfaces while preserving the current appearance.
- Confirm imported mesh LODs and shadow meshes are actually selected at tactical-camera distances.
- Disable or reduce IK updates only for offscreen or sufficiently distant idle units.
- Add an optional presentation quality resource for shadow and animation distance budgets.

These are scalability controls. The default should retain the current semi-realistic presentation.

### P2 — Separate planning, execution, and presentation responsibilities

Several large scripts own multiple kinds of work:

- `BattleController` handles setup, input modes, hover previews, ranges, action execution, replay recording, and battle events.
- `AIController` handles mission intent, candidate generation, scoring orchestration, async execution, reservations, and debug explanations.
- `ObjectiveManager` handles objective state, mission-specific rules, rescue carrying, extraction, and battle-result policy.
- `DebugTools` builds and controls a large runtime interface in one script.

The goal is clearer ownership without a big-bang rewrite:

- Extract a `PlayerInteractionController` for modes, hover state, and previews.
- Extract a pure `AIPlanner` that returns a decision record; keep animation and awaited actions in an `AIExecutor`.
- Move mission-specific victory and extraction policy into data-backed mission rules instead of checking prototype mission IDs throughout `ObjectiveManager`.
- Keep `BattleController` as the coordinator and preserve its existing external calls during migration.

Pure planners and explicit contexts also make benchmarks and deterministic tests much easier.

### P2 — Remove mission-name coupling

`ObjectiveManager` and `AITargetScorer` contain direct checks for IDs such as `prototype_rescue`, `prototype_extract`, `prototype_survive`, and `prototype_enemy_evacuation`. Adding or renaming a mission can silently bypass behavior.

Represent those differences as capabilities or policies on `MissionDefinition`, for example extraction policy, survival completion policy, VIP handling, and target-priority policy. Migrate one rule at a time and retain fixture tests for every current mission.

### P2 — Centralize tactical presentation resources

Cursor, path, range, cover, trajectory, debug, and terrain code independently create meshes and materials. A `TacticalPresentationTheme` resource can expose colors, opacity, vertical offsets, widths, and shared material policies in the Inspector. Small geometry helpers can remove duplicated quad/line construction while keeping each visualizer responsible for its own meaning.

This is a 27C improvement with a modest allocation benefit. Avoid a universal visualizer superclass; shared data and focused helpers are easier to edit and test.

### P3 — Define export and asset boundaries

There is currently no `export_presets.cfg`. The VRoid `source` and `review` directories correctly contain `.gdignore` files, preventing Godot import work, but they remain in Git. Together they account for about 112 MB and the repository pack is about 130 MB. Keeping source and review artifacts in version control may be intentional, but release inputs should be explicit.

Before 27F:

- Add versioned Windows and Linux export presets.
- Verify that only runtime dependencies enter release builds.
- Document whether large source/review artifacts belong in Git, Git LFS, or a separate art archive.
- Add a clean-clone export smoke test.

This primarily affects clone size, import workflow, and release reliability rather than frame rate.

### P3 — Resolve roadmap identifier collision

`docs/character-presentation-roadmap.md` already labels “Body-family contract” as 27A, while the current product roadmap labels 27A as the repository-wide audit. Use namespaced identifiers or rename the character sub-roadmap steps so discussions and commits cannot refer to two different “27A” tasks.

## Proposed 27B boundaries

The following interfaces give cleanup work a stable destination:

| Area | Owns | Does not own |
| --- | --- | --- |
| `BattleController` | Battle coordination and public action gateway | Pointer polling, mesh generation, AI scoring |
| `PlayerInteractionController` | Input modes, hover state, preview invalidation | Rules or action commitment |
| `Pathfinder` | Graph construction, paths, reachable sets and costs | Unit policy or presentation |
| `CombatRules` | Pure attack legality, visibility, cover and hit evaluation | Physics polling or UI text |
| `AIPlanner` | Pure deterministic decision from a snapshot/context | Animation, waits or node lifecycle |
| `AIExecutor` | Applying a chosen decision through battle actions | Candidate scoring |
| `ObjectiveManager` | Objective state transitions | Hard-coded mission-name policy |
| `GeneratedTerrainPresenter` | Static visual and collision presentation from `MapData` | Generation rules or mission placement |
| `TacticalPresentationTheme` | Artist-editable colors, offsets, widths and material settings | Gameplay rules |

## Validation gates

Every optimization should pass the narrowest relevant checks followed by the full Prototype 1 suite:

1. Parser/import check from a clean `.godot` cache.
2. Unit tests for diagonal corner rules, elevation, movement cost, LOS, cover, and objectives.
3. Fixed-seed snapshots for reachable cells, path costs, AI decisions, mission results, and replay records.
4. All authored missions and generated map kinds.
5. 100-seed generation validation and AI simulation batches.
6. Replay round-trip comparisons.
7. Forward+ testing on the home graphics setup and Compatibility testing on both machines.
8. Before/after profiler capture for the subsystem being changed.

An optimization is complete only when behavior remains equivalent, the intended metric improves, and the change makes ownership or editing clearer.

## Current working-tree note

At audit time the repository already contained uncommitted cursor/compositor compatibility changes and three generated UID files. The initial audit added this report. Subsequent implementation is recorded below.

## Implementation pass 1

- PathVisualizer now reuses geometry for identical path vertices, cell size, and padding. Color changes remain immediate, and clearing forces a rebuild on the next draw. This removes repeated SurfaceTool construction; A* and raycast optimization remains pending.
- Map-quality flood fill and mission-zone growth use indexed FIFO reads instead of shifting arrays. Traversal order is unchanged.
- Battlefield stress retains its AP, movement, occupancy, and turn-completion checks while allowing the implemented second-advance policy.
- A focused cache test checks mesh reuse over 100 calls, exact restored vertex equality, tint updates, coordinate/elevation changes, Inspector padding, cell size, and clear/rebuild behavior.

These changes do not establish a measured frame-rate improvement. Graphics profiling, broader architecture changes, weighted-queue equivalence testing, and the full release regression matrix remain outstanding. The original audit's suggested APIs are design proposals, not approved requirements or proven performance improvements.
