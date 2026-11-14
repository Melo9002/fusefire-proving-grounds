# The current code map

Start a normal game in `ui/match_setup.tscn`. There is one normal map: Service Depot.

```text
Match Setup (seed + mission + population on/off)
    -> BattlefieldCatalog (select the implementation)
    -> Generation2 (resolve actual plot, parcels and population)
    -> MapData + content_manifest
    -> imported environment presentation
    -> BattleLevel (validate, deploy, start tactical play)
```

`systems/generation2/generator.gd` is the current generator entry point. Its `generate()` returns MapData with exact accepted choices in `content_manifest` and explicit `generation_errors`. Its `present()` reconstructs those choices. It rejects unsupported sources. Neither function calls an older generator.

Within that folder, `authored_plot_resolver.gd` chooses compatible content, `authored_battlefield_layout.gd` compiles/presents it, and `authored_scene_map_compiler.gd` translates authored tactical metadata. Parcel transforms, interfaces and population belong alongside them. These are parts of one pipeline, not independent generators.

`systems/grid/tactical_map_builder.gd` creates an empty tactical grid and deployment candidates. It is shared game infrastructure, independent of map content or generator version. Deployment repair preserves valid cells and repairs blocked candidates in their original columns; impossible requirements fail.

`systems/generation/battlefield_catalog.gd` is the narrow integration point. A future generator can supply the same MapData/accepted-choices/presentation boundary and be selected here without changing combat. No universal generator framework is required.

`levels/prototype_map/battle_level.gd` owns battle initialization. Asynchronous AI decisions recheck the owning scene after yielding; removed battles cannot continue targeting or advancing turns. `tests/ai_scene_lifetime_test.gd` protects removal during both the initial delay and a suspended decision. `systems/battle_controller.gd` dispatches tactical actions; `systems/turn_manager.gd` manages turns. Movement, LOS, cover and occupancy use MapData through the existing grid/combat systems. Imported mesh collision never silently replaces tactical authority.

Replay uses `systems/replay/` and records accepted content, seed/configuration and action/state evidence. The existing numeric replay preset/envelope is retained; its historical `LEGACY` enum name does not mean Service Depot invokes Generator 1. Old recordings for quarantined maps reject explicitly; do not substitute a different battlefield.

`tools/parcel_editor/` edits and previews parcel scenes/rules. `tools/asset_lab/` browses and calibrates imported assets. Their current limitations are in [Generation 2.0](generation-2.md).

## Compatibility is separate

`tests/fixtures/legacy_generation/` contains old implementations required by existing mechanics regressions. `tests/fixtures/legacy_battlefields.gd` dispatches them only for explicit fixture identities. They are not menu options and Generation2 does not import them. The integration catalog retains a deliberate compatibility branch for those tests/recordings; this is not part of Generation2.

Shared map data types and quality metrics still live in `systems/generation/`; their historical names do not mean they run an old generator. Renaming every type is unnecessary for this cleanup.

`tests/current_generation_test.gd` checks both source dependencies and a real Service Depot initialization: the old generator and procedural renderer must not even be loaded. Tests for retired authored maps were preserved outside the project; core mechanics tests remain active.
