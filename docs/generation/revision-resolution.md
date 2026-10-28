# T04 - Revision enforcement and operation resolution

2026-10-26. Implemented scope; no new human content approvals.

## Authorities and flow

`InitialEnvironmentAssemblyLibrary` remains the small inventory. `initial_environment_assembly_revisions.json` freezes 47 asset, 52 module and 26 assembly revisions from existing compatibility state. `owner_visual_approval` remains false. Nothing in generation, capture, loading, validation or rendering writes this file. It is not evidence of owner visual approval.

`EnvironmentResolutionContext` snapshots calibration, semantics and module definitions per operation. Asset reads, assembly validation, fingerprints and visual choices are cached, including failed resolutions. New operations create new contexts; no permanent cache hides content changes.

Generation uses the context catalog, plans a layout, validates baseline/substantive contracts, and invokes the existing tactical writer. Runtime document capture and compilation reuse that context. `MapData.resolved_environment_modules` carries exact presentation records to the renderer. Standalone compilation creates its own context. Editor save shares a context between compilation and persistence validation. Store decode validates with a context-owned catalog; subsequent editor rebuild is a new operation and revalidates. Historical catalog/contract constructors still perform some internal reads; this is not a claim that every constructor read was eliminated.

## Revision and compatibility contract

- Assets pin geometry SHA-256, effective calibration including native bounds, and effective semantics.
- Modules fingerprint authored fields including effects, elevated surfaces, traversal, occupancy/clearance heights, envelopes, visual transforms, connections and candidate lists.
- Assemblies fingerprint full contract/definition and participating modules. Equipment includes socket definitions and validates actual attachment transforms. Buildings validate against the context module. Mutable validation-error caches are excluded.
- Technical validation runs regardless of certification flags. Passing validation cannot renew revision eligibility or human approval.
- Changed/unknown revisions reject with `STALE_APPROVED_REVISION` / `UNREGISTERED_CONTENT_REVISION`, including freshly generated or captured content. Optional orphan decoration may warn; a referenced asset cannot evade validation by marking itself optional.
- Hashing is conservative: descriptive source-field changes can also invalidate a module. Narrowing this later requires a reviewed field contract.

Outer document schema remains 1; the nested dependency contract explicitly becomes `spatial_layout.resolution_version = 1`. New records pin module revisions and semantic signatures. Unsupported resolution versions reject. Exact asset references must match resolved visual choices. Rendering consumes paths/calibration/transforms, without selecting variants or consulting semantics again.

Version-0 dependency records have a bounded legacy importer: compare old assembly signatures to frozen legacy signatures while requiring current complete content to match the full baseline. Do not silently migrate historical content changes. The tracked `docs/architecture/examples/persisted-edited-industrial-layout.json` predates cargo's `shipping_container_family` binding and now rejects with `ASSEMBLY_REFERENCE_MISMATCH`. The original is preserved. Using it as current content requires explicit reauthoring/revalidation of a copy.

No automatic baseline refresh is provided. The investigative bootstrap now writes only a proposed file under artifacts. Future publication must separately record draft technical validation, owner approval of an exact revision, and registration. Do not overwrite the baseline merely to silence stale-content errors.

## Consolidation and limits

Removed document-side live selection/repeated assembly lookup/flag-only acceptance, renderer-side variant/calibration selection, and live legacy-signature reconstruction. Creation/capture shares the placement-ID allocator. No parallel registry or tactical writer.

Compiled maps require resolved records. Changing placements afterward rejects presentation until a new operation resolves them. Direct legacy fixture maps without a document retain one explicit shared-resolver adapter; retire it when those fixtures/captures use the compiler.

Resolved records are in-memory output, not an embedded asset archive. Saved documents pin choices/dependencies and require compatible installed content. Arbitrary compiler/Godot/importer changes or replacing asset files during active presentation are not covered by a cross-version replay guarantee; the broader replay contract remains T14 work.

## Gate B - fresh source and negative-test review

Performed by the implementing agent; not independent signoff or owner visual approval.

| Boundary | Source and negative evidence | Finding |
| --- | --- | --- |
| Identity | Placement allocator/copy, document edit/removal/duplication/remapping, editor transaction boundary; `placement_identity_test` | Transforms preserve IDs; internal copies remap; required-reference deletion refuses; rejected loads preserve state. Shared allocation avoids a resolver-specific identity policy. |
| Merge | Writer staged surface/effect/link passes; `modular_environment_map_writer_test` | Sparse fields do not erase contributions; ground cannot reopen blockers; conflicts/missing endpoints reject transactionally. Sorting only stabilizes output. |
| Dimensionality | Spatial queries, layout/ledger and writer support/plane checks; `modular_elevation_spatial_test` | Independent supported floors work; overlap/headroom failures reject; whole-column mission protection remains explicit. Flat-base pilot/missing-envelope limits remain. |
| Revisions | Resolver, dependency validation, library and presenter; `environment_resolution_context_test` | Geometry/calibration/transform/clearance/effect/envelope changes reject legacy load and fresh resolution. Misaligned sockets fail substantive checks; changed socket relationships invalidate revisions. Repeated instances reuse resolution; renderer does not reroll. |

Corrections during this review: cached failed visual results now retain diagnostics; revision-source metadata restored; missing-asset diagnostics remain actionable; optional orphan-decoration behavior preserved; ID allocation consolidated. The historical cargo assertion changed intentionally to require rejection, not to weaken current-content integrity.

Gate B's source/negative-test self-review is complete within this pilot. Independent review has not been performed. No later task starts automatically.

## Verification

Passed: `environment_resolution_context_test`, `battlefield_layout_document_test`, `battlefield_layout_lifecycle_test`, `map_editor_layout_store_test`, `placement_identity_test`, `modular_environment_map_writer_test`, `modular_elevation_spatial_test`, `certified_socket_assembly_test`, `coherent_geometry_contract_test`, `generation_2_replay_edited_map_test` (35/35 actions).

Logs: `artifacts/t04-<test>.log`; lifecycle: `artifacts/t04-lifecycle-output.log`. Geometry negatives model hash divergence by altering expected baseline in a private context, without editing downloaded assets. Other negatives change in-memory source data. Socket tests execute the real attachment validator. Renderer assertions inspect instantiated metadata/headless transforms; they do not establish visual quality.

Debug parser checks cover resolver/document/presenter/editor. No full suite, new visual captures or owner playtest. Existing root-certificate-store errors persist. Editor import could not save user-level settings in this restricted environment; project parsing completed. No commits or pushes.
