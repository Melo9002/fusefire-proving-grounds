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

Current parcel clearance uses the compiler's existing active-shape predicate. Historical revision shapes remain available for exact tactical reconstruction; authoring clearance uses current shapes.

`systems/grid/tactical_map_builder.gd` creates an empty tactical grid and deployment candidates. It is shared game infrastructure, independent of map content or generator version. Deployment repair preserves valid cells and repairs blocked candidates in their original columns; impossible requirements fail.

`systems/generation/battlefield_catalog.gd` is the narrow integration point. A future generator can supply the same MapData/accepted-choices/presentation boundary and be selected here without changing combat. No universal generator framework is required.

`levels/prototype_map/battle_level.gd` owns battle initialization. It supplies its own `WorldEnvironment` to presentation and limits fixture-geometry toggles to its authored environment subtree. The controller receives an explicit battle root for hazard discovery; other battles and unrelated group members cannot supply hazards to this map. Standalone geometry inspections may omit the environment reference; atmosphere is then left unchanged. Asynchronous AI decisions recheck the owning scene after yielding; removed battles cannot continue targeting or advancing turns. `tests/ai_scene_lifetime_test.gd` protects removal during both the initial delay and a suspended decision. `systems/battle_controller.gd` dispatches tactical actions; `systems/turn_manager.gd` manages turns. Movement, LOS, cover and occupancy use MapData through the existing grid/combat systems. Imported mesh collision never silently replaces tactical authority.

Replay uses `systems/replay/` and records accepted content, seed/configuration and action/state evidence. The existing numeric replay preset/envelope is retained; its historical `LEGACY` enum name does not mean Service Depot invokes Generator 1. Old recordings for quarantined maps reject explicitly; do not substitute a different battlefield.

`tools/parcel_editor/` edits one complete parcel session. `parcel_session_file.gd` wraps the existing object/field payloads in one validated Save/Open operation. Preview builds the current scene/rules through `population_scene_export.gd`, then uses the runtime plot resolver. Test battle archives that built scene and exercises it directly through Generation 2; optional review export is no longer a prerequisite for local play.

`systems/generation2/parcel_test_layout.gd` supplies a single-parcel plot and parcel lookup to the existing resolver/compiler. It is not a second generator. `systems/generation2/local_parcel_content.gd` preserves local snapshots by hash and validates dependency hashes for replay. Battles never import editor implementation code. The editor retains its session, detaches its displayed parcel during the battle, and restores it through BattleLevel's return callback, which also survives rewatch. The battle scene explicitly activates its own Camera3D on entry, including rewatch, so the retained editor camera cannot keep rendering a frozen view. Returning selects the editor camera again without changing its retained view.

`BattleConfiguration.normalized()` is the single configuration normalization step; its existing codec also supplies replay inputs. Internally there is one named battlefield ID. Old map booleans are interpreted only at compatibility inputs, and explicit named IDs take priority.

`tools/asset_lab/` browses and calibrates imported assets. Workflow and limitations are in [Generation 2.0](generation-2.md).

`art/environments/authored/objects/` contains the reusable crate, three containers, delivery truck and three parking cars. Loading-yard and office parcels instance these scenes, keeping positions and population membership on the parcel instances. The editor placement library and parking vehicle templates instantiate the object scenes directly; they no longer load an example parcel or look up an object by its node name. The object scene owns its visual and tactical children, including historical/current truck shapes. Export preserves that ownership instead of packing the same children twice.

For newly placed ordinary objects, `tools/parcel_editor/mesh_tactical_bounds.gd` derives one starting box per visible mesh part and saves it as ordinary tactical metadata. Existing explicit solids take precedence. The compiler consumes those saved parts; Generation 2 and replay do not import editor code or infer live geometry. Only the new parts request standing clearance below their visible bottom; precise shot bounds stay at the visible height. The default clearance is zero for existing authored/historical solids, preserving their results. Export identity includes derived shape transforms and metadata. This is a bounded ordinary-prop fallback, not exact polygon collision, automatic floors or a structural-assembly solver.

## Compatibility is separate

`tests/fixtures/legacy_generation/` contains old implementations required by existing mechanics regressions. `tests/fixtures/legacy_battlefields.gd` dispatches them only for explicit fixture identities. They are not menu options and Generation2 does not import them. The integration catalog retains a deliberate compatibility branch for those tests/recordings; this is not part of Generation2.

Shared map data types and quality metrics still live in `systems/generation/`; their historical names do not mean they run an old generator. Renaming every type is unnecessary for this cleanup.

`tests/current_generation_test.gd` checks both source dependencies and a real Service Depot initialization: the old generator and procedural renderer must not even be loaded. Tests for retired authored maps were preserved outside the project; core mechanics tests remain active.

Generator-independent empty-map tests now call TacticalMapBuilder directly. Retained generator-specific fixtures are classified in [the fixture guide](../tests/fixtures/README.md). The current mission/replay matrix covers all eight mission kinds on both Depot plots without relying on those generators. Obsolete absolute-coordinate scene metadata is rejected explicitly; current relative geometry contracts and historical solid revisions remain intact.
