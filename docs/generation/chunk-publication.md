# T07 — Chunk publication and industrial proof library

2026-10-27. Implementation and agent inspection are not owner approval. **The industrial pilot is unapproved and unregistered. Gate C remains pending the owner's hands-on review.**

## Owner workflow

1. Open `tools/map_editor.tscn`, F6, and choose **Author — Chunk Authoring**.
2. Click **Browse saved chunks** near the top. Choose **Industrial examples** to narrow the list, or search a name such as `loading yard`. Select an entry and press **Open selected draft for editing** (unsaved changes prompt for confirmation). Do not confuse opening a source with placing an independent copy of it.
3. Use **Publish → Validate saved draft**. Existing current captures are reused; otherwise choose **Capture three review views**. The capture operation renders exact resolved choices and temporarily disables editing. It does not approve anything.
4. Choose **Owner review / approve**. Inspect overview, opposite and overhead; **Open full size** opens each original capture. Check orientation, seams, completeness and access in the editor too. Only if satisfied, enter your name, affirm that you personally reviewed this exact revision, and confirm approval.
5. **Register approved revision** is separate. It reruns substantive validation and checks source/dependency/evidence freshness. **Revoke review / unregister** removes eligibility explicitly.
6. Editing/saving an existing registered source makes it a new draft. The older immutable revision remains archived, but the active library entry is ineligible while its bound source differs. A fresh validation or capture never inherits prior owner approval.

For a source made entirely in the editor: author content/ports, use **Add ground across chunk bounds** to declare the base surface, then save and validate. This command is explicit and undoable; it is not automatically inferred from visuals. The proof UI test creates a downloaded cone, declares visual-only behavior, authors a port, saves/reopens, validates and exercises the review/registration dialog in an isolated test library without a new code recipe.

Raw props require **Selected → Declare visual-only decoration**. This means no cover or movement blocking, not "ignore all validation." Support, visual bounds, clearances, dependencies and completeness still apply. Use an existing tactical component for physical obstacles/cover. Raw building fragments cannot be waved through as decoration: complete custom modular-building assembly remains later work. **Use component tactical behavior** restores the component role. Declarations follow stable IDs through duplication, deletion and history.

If pins are stale or their owner lists changed, **Refresh dependency pins** is an explicit undoable source edit, followed by save, validate, capture and review. It grants no human approval and does not override the T04 approved component/assembly baselines. A failed baseline may require separate upstream content review.

## Contracts and authority

- `EnvironmentChunkSource` remains the editable JSON source. Schema 1 accepts an additive optional `tactical.visual_only` ID array; old drafts are not rewritten or auto-declared. Mission bindings and publication state remain outside the source.
- `ChunkPublicationCompiler` validates local structure, measured visual envelopes, explicit roles, spatial overlap/support/headroom, dependency pins, complete structural assemblies, port geometry and reachable access. It produces a local MapData and exact resolved presentation records, not a mission-ready battlefield.
- `EnvironmentModuleMapWriter.apply` now accepts optional explicit local contributions. Module and authored surfaces/effects/links enter the same transaction. Surfaces precede occupants and traversal; omitted effect fields do not erase other claims; conflicts reject. There is no second tactical writer.
- `ModularEnvironmentPresenter.build_chunk_snapshot` consumes the resolved records. It does not select variants again. Neutral base terrain is permitted; no substitute structural boxes/canopies are fabricated for the pilot.
- `ChunkPublicationLibrary` uses one project-local `content/chunks/library/index.json`, immutable revision manifests and content-hashed PNG evidence. Revisions include canonical source, dependencies, compiler/implementation fingerprint and port-profile hash. Index records distinguish validation, evidence, owner review and registration.
- `eligible(context)` is the candidate boundary for later chunk composition. It returns sorted, fresh, registered revisions only. Draft files, stale source bindings, changed asset/calibration/assembly behavior, altered captures and absent owner attestation exclude a candidate. The existing pre-chunk generator is not silently redirected through this library; T09–T11 integrate composition.
- The local human review record is an explicit attestation, not a remote authentication/signature system. Agents must not fill the owner dialog or call owner approval on real content without explicit authorization. Automated affirmative fixtures are confined to unique directories beneath the test-output directory.

## Spatial and street rules

Rectangular dimensions are authored from content, not stretched to a universal parcel grid. Current publication limit: 65,536 cells per floor, height 256; ordinary pilot chunks are much smaller. Whole-column and floor-specific clearances remain distinct. Existing shallow measured assemblies are reused; general chunk nesting is not introduced.

`chunk_port_profiles.json` contains the small data-driven profile vocabulary: pedestrian 1-cell, walkway 2-cell, loading 4-cell and street 10-cell. Port spans must be unique, contiguous, outward-facing and match role/profile/width. Active ports need supported, traversable cells, inward approach and headroom; all accesses must connect. Complete assembly entrance/working-face clearance must be reachable. A loading width is not a vehicle turning-radius guarantee.

Street ports use all ten cells, including two-cell sidewalks and six-cell carriageway. Validation compares the actual chosen street component's cross-section; equal labels alone are insufficient. `ports_match` requires opposite normals, matching elevation/profile and adjacent matching world-cell spans (caller performs world transforms). No new curves or end caps are claimed. Terminated interfaces cannot connect.

## Tactical intent of the proof content

| Source | Bounds | Purpose / choice |
| --- | --- | --- |
| Warehouse frontage | 16×20×10 | Sealed exterior shell and protected apron. Approach is exposed; the shell creates flanking cover. Visible doors do not imply a traversable interior. |
| Loading yard | 20×12×5 | Clear four-cell loading lane, containers on opposite sides and offset smaller cover. Short exposed middle versus movement between side cover; no objects in reserved access. |
| Service yard | 12×10×6 | Measured pipe/receiver assembly, cargo and a third cover position. Working face stays reachable; positions offer different approach angles. |
| Alley/courtyard | 6×14×4 | Narrow through-connection with two exits and side clutter. Intentionally a connector, not a self-contained arena. |
| Straight / T / cross street | 10×10×3 each | Reviewed downloaded street geometry with complete sidewalk interfaces. Open exposure is deliberate; later world population must preserve routes and seams. |

These are small composition/authoring proofs, not finished art dressing or combat-balance certification. Overall sightlines, deployments, cross-chunk flanks, mission fairness and vehicle turning are not established by local validation. Loading/service population regions are not a new feature of T07; fixed access reservations must constrain later population.

## After-assembly utilities and dressing

Owner observation: the downloaded pole/wire spans can form convincing connected runs. Proposed later boundary: plot planning reserves utility corridors; after chunks are assembled, a deterministic world-level population pass resolves compatible endpoints and places a continuous network across chunk boundaries. Endpoints may deliberately share a pole/joint; that must be a measured compatibility rule, not a blanket collision exemption for the whole asset.

Check entrance/access clearance, street/sidewalk ownership, wire headroom, intended support and tactical obstruction. Any movement/cover/LOS contribution returns through the same compiler before the accepted battlefield snapshot. Do not mutate tactical data as a late renderer side effect. Pole/wire topology, endpoint deduplication and draw-a-run tools are recorded future work; T07 does not implement them.

## Enxugar / remaining adapters

The seven proof compositions are editable JSON data, not production code recipes. The temporary investigative builder under `artifacts/` is not read by the game/editor/library; data is authoritative. Editor gallery/open/save and publication consume these sources directly.

Retain current coherent code recipes, the legacy battlefield composer and catalog/module adapters until their runtime consumers migrate to plot/chunk composition with parity evidence (T09–T11/T15). Existing measured asset/component/assembly contracts still provide the leaf semantics. Deleting those now would remove working runtime paths, not eliminate duplication. Source-only optional visual declarations replace the blanket unresolved-raw-asset diagnostic only when explicitly authored. Shared placement allocation, JSON persistence, spatial queries, writer and presenter remain the authorities.

Old immutable revisions/evidence remain available for audit; later retention cleanup must account for supported saves/replays and explicit approval references. No downloaded assets or user drafts were removed.

## Verification and limitations

- `chunk_publication_test.gd`: malformed/mismatched/blocked ports, missing support, incomplete structures, inaccessible assembly clearance, source/evidence/revision freshness, negative registration gates, raw role declarations, deterministic explicit surfaces and seven pilot fixtures.
- `chunk_publication_workflow_test.gd`: actual gallery/command flow creates a raw-asset chunk without a recipe, authors ground/port, saves/reopens, validates, confirms review starts unchecked, fits the review controls on screen, simulates human input only in an isolated fixture library, registers, then edits back to an ineligible draft.
- `chunk_publication_capture.gd`: explicit graphics-only workflow captures three views of each production proof without approval/registration. Registered as explicit-only in the runner.
- Shared regression coverage: writer, elevation spatial contracts, chunk store, session/history, existing authoring workflow; edited-map replay verifies 35/35 actions. Logs are `artifacts/t07-*.log`.
- Initial failures were corrected rather than weakening checks: JSON float lane membership; newly inserted Dictionary keys needing string keys; review dialog sizing; controller/panel reference cycle. A UI test initially attempted rotation after reopening without selecting an instance; it now selects through the real instance list and asserts the rotation occurred before testing invalidation.
- Root-certificate-store and restricted user editor-settings diagnostics persist. Captures are agent visual observations, never aesthetic certification or owner approval. Gate C closes only after the owner finds the workflow usable and explicitly reviews the intended content.
