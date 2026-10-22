# Versioned battlefield layout persistence

Task 4.3 replaces the Map Editor's placement-only storage boundary with persistence of the unified battlefield layout document. Persistence envelope schema 2 contains one layout document at `layout_document`; the construction document retains its own schema version so storage evolution and construction-contract evolution remain independent.

## Audit and ownership

The former schema 1 stored only `layout_id`, `map_size`, and component placement transforms. It discarded environment identity, generator seed and configuration, stable placement IDs, parcel and assembly relationships, content revisions, and repaired deployment zones. Loading reconstructed a new authored document and assigned `mixed_service`, even when the source had been an industrial generated map.

Schema 2 persists the Task 4.1 document without duplicating compiled tactical cells or generated meshes. `BattlefieldLayoutDocument` owns construction intent and provenance. Assembly, asset, and calibration catalogs remain external dependencies pinned by revision. `BattlefieldLayoutDocumentCompiler` reconstructs authoritative `MapData`; presentation resolves the stored environment identity from that same document.

## Load policy

Load follows one transaction boundary:

1. Parse the envelope and reject malformed or unsupported formats.
2. Reconstruct the document and validate required fields, placement and relationship references, dependency revisions, and mission zones.
3. Reconstruct the module layout through the active catalog.
4. Only then replace the Map Editor's active document, layout, and dimensions.

Required missing assets and stale geometry, calibration, template, or assembly dependencies invalidate the load. The diagnostic identifies the dependency and the placement or relationship that requires it. Optional unreferenced decoration may be unavailable; it produces a warning and does not invalidate required construction. Revision mismatches do not resize tactical footprints or silently accept new geometry. Revalidation must occur through the relevant assembly/calibration authoring workflow before the saved revision is updated.

## Legacy compatibility

Schema-1 files remain readable, but they cannot establish an authentic environment identity from information they never stored. A caller must explicitly select `legacy_compatibility`. The resulting document records `identity_status = explicit_legacy_compatibility`, uses legacy presentation mode, and reports the unrecoverable provenance, dependency, relationship, and mission information. Loading never rewrites the source file. An explicit later Save writes schema 2.

The tracked `starter_layout.json` intentionally remains schema 1 as a permanent migration fixture. New custom saves use schema 2.

## Remaining lifecycle work

Task 4.3 does not migrate the normal battle entry point, introduce named-map libraries, or provide future schema migrations beyond the one real historical format. Gameplay adoption, if approved, remains Task 4.4 work.
