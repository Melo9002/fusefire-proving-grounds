# Maintainability audit — Prototype 1

Scope: static inspection of runtime scripts, scene references, tools, tests and documentation at 5da9a73 plus the existing working-tree changes. Findings below distinguish confirmed coupling from potential failures. No gameplay feature is classified as removable merely because it is called a prototype or demo.

## Prioritized findings

| Priority | Finding and evidence | Consequence | Recommended action and validation |
| --- | --- | --- | --- |
| High | `systems/grid/map_builder.gd:18` and following scans query SceneTree-wide groups for surfaces, paths, spawn zones, features and links. `units/ai_controller.gd:39`, `ui/unit_world_bar.gd:24` and `systems/replay/battle_replay_recorder.gd:17` select the first global objective manager. | Ownership assumes one battle per SceneTree. Overlapping battle/replay instances or editor test fixtures can read another battle's objects. This is a latent risk, not a reproduced current-match failure. | Pass battle-local references and restrict terrain scans to the owning level. Add a two-level isolation test before changing discovery. |
| High | `ui/debug_tools.gd:324` and `:330` climb two parents and require a child named `Visualizers`. `systems/replay/battle_replay_player.gd:89`, `:109`, `:138` require `CameraRig` and `Visualizers/BattleUI`. | The planned presentation-folder/scene reorganization can break F3 overlays and replay even if ordinary matches still load. | Export presentation-root, camera and UI references or expose them through BattleLevel. Validate debug overlays and replay after a scene-node rename. |
| High | `systems/objectives/objective_manager.gd:98`, `:159`, `:239`, `:273`, `:290`, `:374` branch on prototype mission IDs; `systems/ai/ai_target_scorer.gd:53` repeats an evacuation-ID condition. | Mission identity also selects rules. A new resource with equivalent objective definitions may behave differently solely because its ID changed. | Add explicit mission policies while retaining current preset behavior; compare every mission's rescue, extraction, failure and completion cases. |
| High | `art/characters/vroid_proof/runtime/unit_visual_adapter.gd:1` inherits `demo/vroid_weapon_ik_demo.gd`, which preloads the demo vertical-slice controller. Tools also load that controller. | Demo code is part of the runtime and animation-authoring dependency chain. Deleting or excluding demo assets can break units and the workbench. | Extract a shared rig/presentation implementation, then make the demo and runtime adapter clients. Preserve exported property names, saved scenes, fallback clips and animation tests. |
| Medium | `systems/ai/ai_difficulty_policy.gd:83` and `:87` define `score_target` and `score_path_progress`; repository references occur only in `tests/ai_difficulty_policy_smoke.gd`. Actual gameplay uses AIPositionScorer and AITargetScorer. | The helpers are unused by production and give tests misleading coverage of gameplay scoring. Target vulnerability/focus arithmetic is duplicated; the path helper represents an older scoring formula. | Move assertions to the actual scorers, then remove obsolete helpers or deliberately route gameplay through a shared calculation. Do not delete the tests without replacing their behavioral coverage. |
| Medium | `systems/actions/rescue_action.gd` and `extract_action.gd` validate through ObjectiveManager and call its completion methods; ObjectiveManager constructs the actions and records replay events (`:167` onward). BattleController owns the other action gateways. | Mission state, action orchestration and replay bookkeeping form a circular responsibility boundary. Future action additions have two integration patterns. | Document the existing transaction sequence first; extract an action coordinator only with rescue/extraction/replay tests. Avoid moving validation in a way that changes zero-AP eligibility or async timing. |
| Medium | `presentation/overlays/path_visualizer.gd`, terrain presenters and other visualizers separately construct quads/boxes/materials and embed colors and offsets. | Similar presentation features have separate editing workflows and geometry conventions. | Introduce focused geometry helpers and editable theme resources. Preserve each visualizer's semantics and compare geometry/appearance before and after. |
| Medium | `systems/replay/battle_replay_player.gd:204` finds actors by scene name; `systems/replay/battle_state_fingerprint.gd` sorts and records names; default mission identity derives from unit names. | Renaming runtime nodes is more than an editor cosmetic change: names participate in replay and mission identity. | Document names as an existing serialization contract. Introduce stable IDs with an explicit recording-version migration before decoupling names. |
| Low | `docs/architecture.md` describes current Beans, breadth-first movement range, immediate attacks, and a simple lowest-HP/move-once AI, despite newer sections describing richer behavior. | Readers receive contradictory extension guidance. | Update obsolete paragraphs against current owners; avoid treating historical cleanup notes as a specification. |
| Low | Character roadmap 27A means body-family contract, whereas the current project roadmap 27A means repository audit. | Ambiguous task and commit references. | Namespace the character roadmap identifiers when the main roadmap is consolidated. |

## Dead-code and obsolete-piece assessment

Confirmed production-unused candidates: the two AI policy scoring helpers above. They still have test callers, so deleting them alone would break tests while failing to address the coverage problem.

Confirmed live despite misleading names:

- VRoid demo scripts and generated fallback animation builders: runtime and workbench dependencies.
- `ui/aphud_controller.gd`: referenced by the playable scene; overlapping AP displays do not prove it is dead.
- `BattleReplaySession`: used by battle setup, recorder and replay tests; its static recording is deliberate cross-scene state.
- Prototype mission identifiers: actively used to select behavior, so they cannot be renamed as a cosmetic cleanup.

No wholesale asset or script deletion is justified by this pass. Static searches cannot prove the absence of reflection, Inspector wiring or external authoring usage.

## Warnings and validation limits

A headless Godot 4.7.2 editor scan completed with process exit code 0 and registered changed script classes. Its output reported failures creating editor data/config/cache directories, opening logs/user storage, reading the certificate store and saving editor settings. These are environment/access diagnostics; exit code 0 does not make the run clean. No project script parse error appeared in that output, but this was not a comprehensive GDScript warning inventory or full regression run.

The preceding implementation pass passed the path-cache, battlefield stress, diagonal movement, 80-map quality and 80-map mission-placement tests. Those results do not validate the architectural changes proposed here, which remain recommendations.

## Suggested implementation order

1. Replace obsolete policy-helper tests with actual scorer assertions, then remove the unused helpers.
2. Correct contradictory documentation and document replay/name contracts.
3. Make scene references explicit before moving presentation nodes.
4. Isolate dependencies per battle, with a simultaneous-level test.
5. Extract shared character presentation from the demo, preserving the animation handoff.
6. Replace mission-ID rules and clarify action ownership one behavior at a time.

Each step should be independently reviewable and retain current functionality. Broad file moves should follow dependency cleanup rather than serve as a substitute for it.
