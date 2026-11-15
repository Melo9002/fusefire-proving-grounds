# Retained test fixtures

These scenes and generators support mechanics or historical compatibility assertions. They are not normal map choices. Service Depot, Freight Yard, Fleet Station and local parcel tests run through Generation 2 without importing the legacy generators.

- `legacy_generation/` and `legacy_battlefields.gd`: explicit old battlefield identities, deterministic legacy layout/geometry checks, and historical replay or known-seed AI regressions. Keep the assertions until an equivalent fixture preserves their behavior; do not remove them merely to reduce file count.
- Generator-independent empty-grid checks use `systems/grid/tactical_map_builder.gd` directly. Seven parcel/geometry/population suites were migrated off the legacy wrapper without dropping their assertions.
- Current coverage: `current_generation_test.gd` protects dependency isolation and the normal menu; `current_mission_replay_matrix_test.gd` checks both layouts of all three current sites against eight mission kinds and action replay. The explicit `ai_match_simulation_smoke.gd` batch defaults to Service Depot. Initialization/action replay is not evidence of full AI mission success.

Compatibility decoding and historical compiler/rule revisions are intentional retained behavior. None requires restoring old maps to the menu or connecting Generation 2 to an old generator.
