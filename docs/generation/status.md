# Generation status

Generator 1 remains active: seeded cover maps, the original Refinery, Industrial Warehouse, gameplay, missions and replay. Refinery 2 is the supported fixed authored environment; Loading Yard is a bounded authored-parcel proof. All downloaded assets, licenses, calibration and the Asset Lab remain available.

Map selection now uses one stable `battlefield_id` resolved by `BattlefieldCatalog`. Authored tactical metadata compiles through one `AuthoredSceneMapCompiler`. Historical per-map booleans remain only to interpret existing replay data. See [Current map architecture](current-map-architecture.md).

Generator 2 code, plots, chunks, Map Editor tools, dedicated tests, certificates and roadmaps were moved to a local archive on 2026-10-31 at the owner's request. They are not active fallbacks. Its old recordings are rejected explicitly rather than regenerated as a different battlefield.

Local archive: `C:/Users/Blue/Documents/Codex/quarantine/fusefire-before-simplification-2026-10-31/`.

- `project/`: complete pre-cleanup project snapshot, including uncommitted and ignored drafts; excludes `.git` and generated `.godot` caches. Open its `project.godot` with Godot 4.7.2 to consult the old tools (first import rebuilds caches).
- `retired-code/`, `retired-content/`, `retired-docs-and-data/`, `retired-history/`: moved originals.
- Inventory JSON files and `base-commit.txt` document provenance. This archive stays local and is not included in Git pushes.

The retired chunk creator is a useful reference, especially placement, duplication, history and draft persistence. Its supported successor is named **Parcel Editor** and targets only the standard 16×16, 16×32 and 32×32 parcel footprints. Recover specific capabilities into a small isolated authoring tool; do not restore the retired runtime generator, publication/certification stack or dependency chain. Preserve user drafts in the archive unchanged.

The superseded `map-plan-1-5-to-2-0.md` draft was moved into `retired-docs-and-data/post-quarantine-2026-11-02/`. Its active test command and architecture claims have been removed from current documentation.

Next design discussion: one authored environment, contextual tactical population, and existing authoritative gameplay data. First prove a believable, playable Refinery. Do not resume the archived task pack automatically.

Battle startup now has an opaque loading transition driven by real initialization stages. It preserves Match Setup until the selected battlefield has compiled and passed tactical validation, and exposes initialization failures instead of activating a partial battle.

## Verification

- Smoke: 10/10 suites passed (`artifacts/test-results/20261031-204616-smoke`).
- Generation: 13 suites initially passed; warehouse replay exposed a leftover `preparation_context` reference. Fixed that integration regression; the failing warehouse check then passed with 30/30 replay actions. Four explicit-only stress/capture suites were not run (`20261031-204812-subsystem-generation`). Passing generation suites were not repeated.
- Replay after the fix: 9/9 passed (`20261031-205147-subsystem-replay`), including 41/41 normal battle actions and 286/286 Refinery rescue actions. The earlier failed replay run is retained as diagnostic evidence; its stale headless rescue process was stopped before rerunning.
- Focused retirement test passed: retired/unknown configurations and document-bearing replay reject explicitly, no partial map/team activation, match setup preserves Refinery selection/seed, and repeated Generator 1/Refinery inputs reproduce cell, spawn and traversal signatures.
- Refinery elevation-selection/camera test passed. All 642 environment asset files matched the backup. Retained Generator 1 source matched the backup except removal of unused Generator 2 entry points in the flat generator and presenter.
- Mixed calibration/debug-addon suites retain their current checks; only retired Map Editor assertions were removed from active tests. The original tests remain in quarantine. Dedicated retired-feature tests were quarantined, not weakened to claim they pass.
- Initial restricted import failed to load a native extension; import with normal filesystem access passed. A rendered capture attempt triggered the existing renderer-preference restart and produced no reviewable screenshots. No new visual certification is claimed; the owner began a manual match. Restart an already-open game to load the replay fix.

Scope: approximately 18,500 fewer GDScript lines (including retired tests) and 5,900 fewer documentation lines. Obsolete certificates, fixtures and investigation captures also moved out. Combat, assets, animation, Generator 1 and the original Refinery remain. Archived content is recoverable locally, not shipped or pushed with this cleanup.

Historical Prototype 1.5 audits, the superseded action migration plan, the 27A recovery audit and retired VRoid roadmap were also quarantined. Current gameplay, asset, animation and research references remain indexed.

## Authored replacement pilot — 2026-11-01

Refinery 2.0 is now a fixed 96 x 80 environment using the reviewed downloaded assets and reusable custom catwalk components. Original Generator 1 and Refinery remain unchanged. See [the map handoff](refinery-2.md) for opening instructions, boundaries, verification and the next agent-authoring task.
