# T05 - Local chunk sources and named drafts

2026-10-26. Source/persistence foundation only; editor workflow is T06 and resolution/publication is T07. No human approval or registration granted.

## Source contract

`EnvironmentChunkSource` owns a version-1 `fusefire_chunk_source` JSON object. The local origin is fixed at zero; it has no battlefield origin, environment identity, deployment zones or mission binding.

| Field | Meaning |
| --- | --- |
| `chunk_id`, `name` | Stable source identity and human label; filename is independent. |
| `bounds`, `height`, `rotations` | Positive integer width/depth and vertical allocation; allowed quarter turns. Empty rotation list is an unfinished draft. |
| `instances`, `next_placement_id` | Shared `EnvironmentModulePlacement` records and persistent allocation counter. Module references include existing authored assemblies. |
| `ports` | Local ID, role, compatibility profile, X/Z cells, cardinal outward normal, elevation, minimum width, and required/optional/terminated connection. |
| `clearances` | Local ID, X/Y/Z cells, positive height, explicit floor/whole-column scope. |
| `tactical.components` | Placement IDs explicitly opting into referenced module tactical contributions; no duplicate derived cell arrays. |
| `tactical.surfaces`, `effects`, `links` | Authored local cell declarations, sparse writer-compatible effects/layers and traversal endpoints/kind/directionality. |
| `dependencies` | Existing resolver records/pins. Missing or stale dependencies are editable draft problems. |
| `provenance` | Authoring/import metadata; never publication authority. |

This slice references current components/assemblies. Direct raw-asset authoring and nested chunk flattening are not silently invented here. Local IDs remain scoped to a source copy; two copies own independent nested data. World-instance namespaces belong to resolution in T07.

## Three separate questions

1. **Can this source be safely decoded/saved?** `source_errors` checks required fields, versions, types, finite integral transforms, unique IDs, enum values and record shape. Malformed inputs reject instead of being truncated or normalized. Root mission/publication fields reject.
2. **What is unfinished or incompatible?** `draft_diagnostics` reuses the module layout/spatial queries and document dependency resolver. It reports unknown components, invalid arrangement, vertical bounds, incomplete/bad boundary ports and stale/unpinned dependencies. Diagnostics do not rewrite source pins.
3. **May this be played/published?** Not established by either operation above. Full local tactical composition, clearance/access/port compatibility and publication evidence are later resolution/publication gates. An empty diagnostics array is not a play certificate or owner approval.

Incomplete ports, missing referenced content, overlapping/out-of-bounds placements, empty content, missing links/surfaces and stale pins may all be preserved as structurally valid drafts. Invalid field types, duplicated IDs, unsupported versions and malformed JSON may not.

## Persistence API

`ChunkSourceStore.save_named(source, directory, name)` and `load_named(directory, name)` operate on separate named JSON files. `DEFAULT_DIRECTORY` is `res://tools/map_editor/chunks/drafts`; tests use artifacts only. Names cannot contain path traversal or reserved Windows device names. Loading returns a new source on success and null on failure, never mutating a caller's current draft. `copy()` deep-copies nested source state.

`GenerationJsonStore` is shared by chunk and existing map stores: object parsing, file reads and temporary-file/rename writes. Each store retains its own format and validation policy. Both validate before writing, and write errors are reported. The old map store still requires valid battlefield documents; it has not been silently converted into a draft store.

`EnvironmentModulePlacement.to_record/from_record` are shared with battlefield document capture. Loaders validate first; `from_record` is not a malformed-data repair mechanism. Chunk creation uses the same ID allocator, with a high-water counter.

## Explicit legacy import

`ChunkSourceStore.import_legacy(text, chunk_id, name)` supports old schema-1 placements, schema-1 battlefield documents and their schema-2 map-store envelope. Normal load never calls it. It returns a draft and diagnostics without touching the source file or saving automatically.

Existing IDs are retained; missing legacy placement IDs are assigned deterministically with collision avoidance. Current-document missing IDs fail. Original dependency pins remain unchanged, even if stale. Legacy files without pins stay unpinned. World missions/deployments, parcel ownership and battlefield relationships are not carried into the local source; diagnostics explicitly require port/clearance reauthoring. Map origin is retained as local zero, height is a provisional minimum needing review, and only rotation zero is enabled. Source hash records provenance. No approval/certification/registration is inferred.

## Verification and handoff

`chunk_source_store_test` covers incomplete round trips, explicit tactical/port/clearance preservation, nested-copy independence, identity allocation, malformed shapes and JSON, unsupported versions, fractional transforms, invalid-save file preservation, valid replacement, safe names, stale-pin diagnostics without refresh, deterministic explicit legacy import and unchanged original files. Existing map-store, identity and revision-enforcement regressions pass. Replay also passed with 35/35 actions verified.

Logs: `artifacts/t05-chunk.log`, `artifacts/t05-<test>.log`; parser logs `t05-source-parse.log` and `t05-map-parse.log` are warning-free. The preceding preview negative fixture was corrected to use clear geometry so its protected-space rejection actually tests reservation enforcement; `t05-gate-preview.log` passes.

T06 can now attach these source/store APIs to the existing viewport/session, named draft selection and history. T07 must consume explicit contributions and validate complete local tactical/connection contracts before publication. Do not treat successful draft save as technical certification. No new UI or visual playtest is claimed for T05; no commits/pushes.

T06 adds the existing Map Editor's [chunk authoring workspace](chunk-authoring-editor.md). Direct downloaded visuals use the reserved local identifier `asset:<AssetCatalog ID>` with ordinary stable placement records; these remain unresolved for tactical/publication purposes. Draft gallery insertion makes an independent flattened copy; it does not create a nested published instance or register content.
