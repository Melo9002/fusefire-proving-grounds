# Code organization

## Runtime owners

| Location | Responsibility |
| --- | --- |
| `systems/actions/` | Validated action costs and effects: movement, attack, defend, rescue, extraction |
| `systems/grid/` | Authoritative terrain, coordinates, occupancy, graph queries and map validation |
| `systems/generation/` | Seeded terrain data and generation analysis; terrain presenters remain here pending a separate extraction |
| `systems/objectives/` | Mission definitions, objective state, placement and outcome rules |
| `systems/ai/` | Difficulty, position/target scoring and squad coordination |
| `systems/replay/` | Recording, playback and state verification |
| `systems/simulation/` | Automated matches and reproducible failure reports |
| `units/components/` | UnitStats and MissionActor data and signals |
| `units/` | Unit composition, movement/presentation orchestration and AI execution |
| `presentation/overlays/` | Grid, cursor, path, cover, selection, objectives and debugging visualizations; extraction transport is retained here for now |
| `presentation/camera/` | Tactical camera movement and action-camera direction |
| `presentation/actions/` | Result-driven action camera, animation, feedback, and visual cleanup sequencing |
| `presentation/characters/runtime/` | Reusable character rig, animation adapter, traversal poses, IK, and fallback clips |
| `presentation/team_presentation_palette.tres` | Shared faction colors and tactical unit ground-ring appearance |
| `ui/` | Screen controls, HUDs and input forwarding |
| `levels/` | Scene composition and explicit dependency wiring |
| `art/` | Art assets and current character rig implementation/workbench |
| `tools/` | Offline animation authoring utilities |

Presentation consumes game state; moving a presentation script must not alter movement rules, costs, AI scoring or replay identifiers. Unit components announce state changes; they do not discover UI consumers. Scenes wire dependencies through exported properties.

`ShotResultFeedback` listens to BattleController's resolved-attack signal and displays a short target-local HIT or MISS cue. It is presentation-only: the action has already resolved damage, AP, replay data and AI state before the cue is created.

## Explicit debug presentation interface

AIController receives its ObjectiveManager from BattleLevel before entering the tree. BattleReplayRecorder.begin receives the same battle-local manager explicitly; null represents a battle without objectives. Neither consumer searches global groups. The dependency-isolation test creates two generated battles with an unrelated global manager first, and checks both teams and recorders. Other global consumers (world bars and authored terrain discovery) still require migration; this is not yet full multi-battle isolation.

`DebugTools.presentation_root` is an exported Node3D reference supplied by the battle scene. Developer overlays attach to that root instead of climbing parents and requiring a node called Visualizers. Preserve this reference when reorganizing the scene. The root may be renamed or moved without changing DebugTools.

## Migration and preservation

The first architecture pass moves `scripts/actions/` to `systems/actions/`, `scripts/components/` to `units/components/`, `visualizers/` to `presentation/overlays/`, and `systems/camera/` to `presentation/camera/`. Existing script UID files move with their scripts. Source paths in scenes, preloads, tests and documentation are updated together. Scene node names and runtime actor names remain stable because existing consumers and replay recordings depend on them.

Remaining extractions are explicit follow-up work: battle-local service lookup; mission policies out of mission-ID branches; player interaction out of BattleController; generated terrain presentation out of generation. Those changes require dedicated regression coverage and are not implied by these file moves.

## Shared character presentation

`presentation/characters/runtime/character_rig.gd` owns model/weapon construction, contact settings, arm IK, aiming and shot feedback. Both the MIRA workbench and UnitVisualAdapter inherit it. The rig has no demo input or camera controls. `presentation/characters/runtime/character_animation_controller.gd` owns animation state, library loading and fallback clips. Its original script UID is preserved.

`art/characters/mira_0/demo/mira_0_pose_workbench.gd` owns keyboard input, orbit camera, status labels, locomotion previews and the preview rescue passenger. UnitVisualAdapter owns tactical presentation and the gameplay passenger. `TacticalActionPresenter` coordinates action-specific camera and adapter calls after authoritative commit. Exported contact and clip settings remain visible on the MIRA scene.

## Validation of this pass

Debug tools, AI overlay, camera direction, diagonal movement and path-cache tests report zero failures. Battle replay verifies 39/39 recorded actions and the expected DEFEAT outcome. Headless runs report environment errors accessing Godot logs/certificate storage; editor import also cannot write editor settings/cache. This does not replace graphics playtesting or the complete mission matrix.
