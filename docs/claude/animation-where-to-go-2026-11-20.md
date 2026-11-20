# Animation: where do I go to change X?

A short navigation guide for character animation. It has two kinds of paths and they must not be confused: **Today** paths exist in the repository right now (each was checked); **After Task 07** paths are the *proposed* homes from [the module organisation design](animation-module-organization-2026-11-20.md) and do **not** exist yet. Until the migration, use the "Today" column. Deeper reading: [ownership and contracts](animation-ownership-contracts-2026-11-20.md), [rig profiles](animation-rig-profiles-2026-11-20.md), [testing guide](testing-developer-guide-2026-11-20.md).

Maintained animation documentation will live under `docs/` (owner decision, 2026-11-20); this dated guide is the starting point for it and the research reports stay in `docs/claude/`.

Run tests from the repository root: `.\tools\run_tests.ps1 fast -Subsystem animation` (about 15 s), `.\tools\run_tests.ps1 changed -Changed <path> -List` to see what a change selects, `.\tools\run_tests.ps1 check` to validate the test catalog.

## The picture in one paragraph

Gameplay (tactical today; exploration and base later) decides what happens and owns authority. A thin **context adapter** turns that into presentation requests. One shared **presenter** (planned) owns state, facing, transitions and timing. The **rig** applies poses through an ordered stack of skeleton modifiers. **Pure solvers** plan contacts. **Profiles** describe the body (anatomy), the gait (style) and what it carries (equipment). Today the presenter does not exist: `UnitVisualAdapter` and `CharacterRig` do its work.

## Change X: go here

| I want to change... | Today | After Task 07 (proposed) | Check with |
| --- | --- | --- | --- |
| Walking, jogging, running thresholds and filters | `presentation/characters/runtime/locomotion_profile.gd` | `presentation/characters/motion/locomotion_profile.gd` | `locomotion_foundation_test`, `locomotion_speed_test` |
| Gait style (stride, cadence, joint tables) | `presentation/characters/runtime/locomotion_gait.gd`, clips in `presentation/characters/runtime/character_fallback_animation_builder.gd` | `motion/locomotion_gait.gd`, `rig/character_fallback_animation_builder.gd` | `locomotion_gait_test` |
| Turning (twist, bank, lean) | `presentation/characters/runtime/locomotion_profile.gd` and `locomotion_pose_modifier.gd`; the turn is started by `UnitVisualAdapter.face_world_position` | presenter facing stage, `motion/locomotion_profile.gd`, `rig/modifiers/locomotion_pose_modifier.gd` | `locomotion_cover_composition_test` |
| A posture (crouch, kneel, a new one) | `presentation/characters/runtime/cover_crouch_modifier.gd`, `cover_posture_profile.gd`; `UnitVisualAdapter._sync_cover_crouch` | `presenter/posture_arbiter.gd` (requests), `motion/posture_profile.gd`, `rig/modifiers/` | `cover_crouch_test`, `locomotion_cover_composition_test` |
| Which cover edge is chosen, firing from cover (tactical policy) | `presentation/characters/runtime/cover_edge_selector.gd` | `presentation/tactical/cover_edge_selector.gd` | `cover_edge_selection_test`, `cover_target_aware_test` |
| Aim, attack timing, weapon readiness | `presentation/characters/runtime/unit_visual_adapter.gd` (`present_attack`), `weapon_readiness.gd`, `weapon_handling_profile.gd` | presenter attack lane; `presenter/weapon_readiness.gd`; `equipment/weapon_handling_profile.gd` | `aim_hold_presentation_test`, `unit_visual_weapon_readiness_test` |
| Weapon grips, stock, sight, stow | `presentation/characters/runtime/weapon_handling_profile.gd` | `equipment/weapon_handling_profile.gd` and an equipment presentation resource | `weapon_pose_modifier_test`, `unit_visual_torso_weapon_frame_test` |
| Hand contacts and fingers | `presentation/characters/runtime/hand_grip_modifier.gd`; diagnostics in `presentation/diagnostics/hand_contact_diagnostics.gd` | `rig/modifiers/hand_grip_modifier.gd`; diagnostics unchanged | `unit_visual_hand_contact_diagnostics_test` |
| Elbows and the weapon pose | `presentation/characters/runtime/weapon_pose_modifier.gd`, `character_rig.gd` | `rig/modifiers/weapon_pose_modifier.gd` | `unit_visual_elbow_guidance_test`, `weapon_pose_modifier_test` |
| Stair foot placement | `presentation/characters/runtime/stair_foot_planner.gd`, `stair_model.gd`, `stair_profile.gd` | `motion/` (same names) | `traversal_stair_feet_test`, `traversal_stair_gait_test`, `traversal_stair_gameplay_test` |
| Ladders and vaulting | `presentation/characters/runtime/traversal_solver.gd`, `traversal_profile.gd`, `traversal_pose_modifier.gd` | `motion/traversal_*`, `rig/modifiers/traversal_pose_modifier.gd` | `traversal_solver_test`, `traversal_rig_test`, `traversal_ladder_gameplay_test` |
| Path smoothing and how a route is turned into stairs, ramps and ladders | `presentation/characters/runtime/path_refiner.gd`; route expansion inside `units/tactical_unit.gd` | `motion/path_refiner.gd`; `presentation/tactical/tactical_route_builder.gd` (new) | `path_refiner_test`, `traversal_path_gameplay_test`, `traversal_timing_contract_test` |
| Rescue pickup, carry, release | `presentation/characters/runtime/rescue_interaction.gd`, `rescue_passenger.gd`, `passive_passenger_pose.gd` | `presenter/rescue_interaction.gd`, `rig/` passenger files | `rescue_interaction_test`, `rescue_lifecycle_test`, `rescue_passenger_visual_test` |
| What a tactical action looks like and when it counts as finished | `presentation/actions/tactical_action_presenter.gd` | `presentation/tactical/tactical_action_presenter.gd` | `tactical_action_presenter_test`, `traversal_timing_contract_test` |
| The per-frame update order | `presentation/characters/runtime/unit_visual_adapter.gd` (`_process`) and the workbench's own `_process` (two drivers today) | one driver in `presenter/character_presenter.gd` | `locomotion_cover_composition_test`; the update-order probe `research/animation_update_order_probe/update_order_probe.gd` |
| Modifier order or a pose conflict | `presentation/characters/runtime/character_rig.gd` (the build order); the five modifier files | `rig/modifiers/pose_ownership.gd` (declared writes) and the ownership report | `locomotion_cover_composition_test` and the planned ownership test |
| Add another humanoid or change a body | no single place: bone names and proportions are spread across the builder, rig, controller and locomotion modifier. The validated design is the prototype in `research/rig_profile_prototype/` | a rig profile `.tres` next to the model, `art/characters/<name>/` | `tests/rig_profile_prototype_test.gd` (`rig_profile_test` after promotion) |
| Add a weapon or go unarmed | `presentation/characters/runtime/character_rig.gd` (`weapon_scene`; a rifle is always built) | an equipment presentation resource beside the weapon | none yet (a new unarmed test is planned) |
| Exploration movement | experimental only: `research/exploration_playground/exploration_playground.gd` (Match Setup, Exploration) | an exploration adapter in `presentation/exploration/` (future) | `tests/exploration_playground_test.gd` |
| The animation workbench | `art/characters/mira_0/demo/mira_0_pose_workbench.tscn` and `.gd` | `tools/animation_workbench/` | capture scripts are explicit-only (`*_capture.gd`) |
| MIRA's scene or model | `art/characters/mira_0/runtime/mira_0_unit_visual.tscn`, `art/characters/mira_0/models/mira_0_prototype.glb` | same paths (they are referenced widely and do not move) | any test that instantiates the visual |
| Add a test | `tests/` (flat) and register it in `tests/catalog.json` | same | `.\tools\run_tests.ps1 check`, then `select -Test <name>` |

## Rules a contributor should know

1. **Shared character presentation never imports gameplay.** No `TacticalUnit`, grid, action service or archetype in `presentation/characters/` (after Task 07; today three files break this and are moving to `presentation/tactical/`).
2. **Pure solvers stay pure:** `RefCounted` or `Resource`, no nodes, numbers in and plain data out.
3. **A body is data.** Bone names, proportions and sockets belong in a rig profile, not in GDScript.
4. **Presentation never changes gameplay results.** The replay-determinism test guards it.
5. **A migration step moves files or changes behaviour, never both.**
