# Phase 6.1: Opt-In Generation 2.0 Battle Preset

## Outcome

Normal Match Setup can now launch the validated Generation 2.0 industrial pipeline as an explicit opt-in. The legacy generator remains selected by default. Generation 2.0 uses the same coherent assembler, unified layout document, dependency validation, tactical compiler, and modular presentation path as the Map Editor, then continues through the existing battle controller, mission, replay, and turn initialization.

The first runtime preset is intentionally bounded to `industrial_district`, a 60×50 map, and an explicit integer seed. Unsupported dimensions and legacy special-map flags fail before battlefield activation. There is no silent fallback to legacy generation.

## Battle pipeline audit

`BattleLevel._ready()` is the existing normal-battle lifecycle boundary. Before this task, its generated branch called `FlatMapGenerator.generate_with_cover()`, presented the resulting `MapData`, spawned combatants, and passed that data to `BattleController.initialize_battle()`. The battle controller then validated the tactical map, registered occupancy, initialized mission zones and transport requirements, and started the turn. The Map Editor already had the newer coherent assembler → layout document → compiler → shared presenter path, but gameplay could not select it.

The Generation 2.0 preset enters at that existing generated-map boundary:

```text
BattleConfiguration preset + seed
  → FlatMapGenerator base MapData
  → CoherentEnvironmentAssembler
  → BattlefieldLayoutDocument
  → document validation and dependency resolution
  → BattlefieldLayoutDocumentCompiler
  → authoritative MapData
  → GeneratedTerrainPresenter / ModularEnvironmentPresenter
  → existing spawning and BattleController initialization
  → mission objectives, replay recording, player turn
```

`Generation2BattlefieldBuilder` is a narrow adapter for document preparation and compilation. It does not duplicate the assembler, editor compiler, presenter, pathfinding, cover, or LOS rules. It checks the requested faction deployment capacity against the compiled map before the battle scene presents or spawns anything.

## Selection and configuration

In Match Setup:

1. Open **Battlefield**.
2. Keep **Use Generated Map** enabled.
3. Select **Generation 2.0 — Industrial District**.
4. Disable **Automatic New Seed** and enter a seed when reproducibility matters.
5. Start the battle.

The selector defaults to **Legacy generator**. Choosing Generation 2.0 disables the incompatible legacy size selector and labels it **Generation 2.0 fixed — 60 × 50 tiles**. Turning generated maps off restores the legacy selection. The battle briefing shows the Generation 2.0 identity, dimensions, and seed before launch.

`BattleConfiguration` carries the preset through runtime and replay configuration. Historical replay dictionaries without the new field continue to resolve to legacy generation.

## Authority and failure behavior

`MapData` remains authoritative for traversal, occupancy, cover, LOS, elevation, deployment legality, and mission zones. Imported meshes and semantic assets remain presentation inputs. The runtime document preserves environment identity, placements, relationships, dependencies, provenance, and seed; it does not derive gameplay rules from visible geometry.

Generation 2.0 rejects:

- use without generated-map mode;
- any map size outside the current 60×50 contract;
- legacy Refinery or Industrial Warehouse flags;
- coherent-assembly or required-relationship failures;
- missing or stale layout dependencies;
- document compilation failures; and
- insufficient faction deployment cells.

Configuration and document failures occur before terrain, units, or a playable turn are activated. A later tactical initialization failure removes generated terrain and spawned actors, clears occupancy and runtime document state, and reports a structured diagnostic. The preset never changes labels and quietly launches a legacy map.

## Regression evidence

`tests/generation_2_battle_preset_test.gd` exercises the real Match Setup and `prototype_map.tscn` path. With industrial seed 17 and a 2v2 Eliminate mission it verifies:

- explicit opt-in and legacy-by-default behavior;
- the fixed size and seed shown by Match Setup;
- replay configuration round-trip and historical replay compatibility;
- coherent document provenance, industrial identity, placements, and resolved dependencies;
- tactical compilation from that document;
- normal `MapValidator` acceptance;
- correct shared presenter identity;
- player/enemy deployment, objective initialization, replay initialization, and entry into round 1 player control;
- stale imported geometry dependency rejection;
- unsupported configuration rejection with no partial playable state; and
- a real legacy generated battle remaining on `generated_cover` with no Generation 2.0 document.

Focused adjacent suites also cover Match Setup, layout-document construction and lifecycle, legacy flat generation, and replay schema compatibility. The generation subsystem runner discovers the new automated suite; the rendered capture remains explicit-only.

## Rendered inspection

The repeatable capture command is:

```powershell
godot_console --path . --resolution 1600x900 --script res://tests/generation_2_battle_capture.gd -- docs/architecture/reviews/evidence/generation-2-battle-task-6.1
```

- [Match Setup opt-in](evidence/generation-2-battle-task-6.1/generation-2-match-setup.png) shows the selected industrial preset, fixed 60×50 contract, seed 17, and battle briefing.
- [Playable industrial battle](evidence/generation-2-battle-task-6.1/generation-2-industrial-17-playable.png) shows the normal player-turn HUD, objective state, combatants, imported road/sidewalk network, buildings, and street furniture produced by the document-driven presentation path.

These captures establish that the normal UI and battle scene present the requested pipeline. They do not certify every seed, mission, camera angle, or gameplay outcome.

## Verification results

The final automated commands were:

```powershell
godot_console --headless --path . --script res://tests/generation_2_battle_preset_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem generation
.\tools\run_tests.ps1 smoke
```

The focused Generation 2.0 suite completed with 0 failures. The generation subsystem completed with `PASS=32`, `FAIL=0`, `SKIP=14` in 1,047.16 seconds. Its 14 skips are the runner's documented explicit-only capture and extended stress scripts; `generation_2_battle_capture.gd` was run separately with a real GPU and both images were inspected. The smoke tier completed with `PASS=10`, `FAIL=0`, `SKIP=0` in 78.84 seconds. Direct adjacent runs of `match_setup_smoke.gd`, `battlefield_layout_lifecycle_test.gd`, `battlefield_layout_document_test.gd`, `flat_map_generator_smoke.gd`, and `replay_schema_test.gd` also completed with 0 failures.

The negative runtime-selection fixture intentionally emits `GENERATION_2_REQUIRES_GENERATED_MAP`; the assertion verifies this failure and the absence of terrain, combatants, and an active turn. Godot's existing sandbox warnings about `user://logs` and the Windows root certificate store appeared during some direct headless runs but did not fail any test process.

## Known limits and Task 6.2 requirements

- Only the industrial identity and its validated 60×50 contract are exposed in gameplay.
- The integration proves initialization and first playable state; extended tactical play, mission completion, and replay playback on Generation 2.0 maps remain Task 6.2 work.
- The Eliminate configuration is exercised end to end. Other existing mission definitions still use the shared initialization boundary but have not received a Generation 2.0 certification matrix.
- A preserved seed does not by itself guarantee historical reproduction after algorithm or unversioned content changes; document dependencies provide the current stale-content checks.
- The current environment can contain intentional mission-protected open space and bounded-search fallbacks already documented in Phase 5.
- This task does not replace the default generator or activate Generation 2.0 in simulations and other callers that do not explicitly select the preset.
