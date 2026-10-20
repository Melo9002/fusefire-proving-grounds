# Semantic Asset Catalog

FuseFire records two independent kinds of asset knowledge:

- `asset_calibrations.json` stores visual measurements and placement calibration: scale, yaw, anchor, offsets and measured bounds.
- `asset_semantics.json` stores human-confirmed meaning: what an asset represents, whether it is complete or fragmentary, where it belongs and whether procedural presentation may select it.

Neither file authors tactical movement, occupancy, cover, collision, line of sight or traversal. Those remain explicit properties of `MapData` and environment module definitions.

## Resolution and trust

`SemanticAssetCatalog` creates a catalog record for every stable `pack/model` ID from pack naming, geometry, rendered family comparison and established module conventions. Records include an asset kind, structural role, completeness, facing, attachment, contexts, connection families, confidence, evidence and placement guidance. Uncertainty is field-specific: an understood machine may still request connector review without returning to an unidentified state.

Entries in `asset_semantics.json` override those provisional fields. The Asset Lab writes only to the `confirmed` section, so a future measurement or filename scan cannot replace a developer decision. A confirmed record may separately opt into procedural visual selection with `generation_ready`. This approval still does not provide tactical behavior.

The completed family-by-family review is now recorded for all 315 stable IDs. The catalog-wide working-face and Factory machine-connection pass resolved every review flag, and the developer confirmed the resulting interpretations after rendered batch inspection. Semantic confirmation remains distinct from procedural selection: 32 assets have explicit visual placement contracts and `generation_ready`; the remaining confirmed assets stay available for authored work without entering procedural candidate pools. `factory_kit/oopi` remains a non-environment Oopi character reference. See `semantic-asset-identification-report.md` for the evidence and decisions.

The approved baseline is:

- Complete sealed shells: `building-a` through `building-t` from City Kit Industrial. Each remains an exterior-only obstacle with a calibrated profile; parcel fit and environment context further restrict actual selection.
- Road context: `light-curved`, `light-square`, `traffic-light`, `road-sign-stop`, `dumpster`, `electricity-pole-single`, and `construction-fence` from City Kit Roads.
- Road surfaces: `road-straight`, `road-crossroad`, `road-intersection`, `road-curve`, and `tile-low`, each backed by an explicit module presentation contract.

## Asset Lab annotation workflow

Open `res://tools/asset_lab/asset_lab.tscn` and run the current scene with **F6**.

The left browser now shows:

- `✓` for a confirmed semantic record.
- `?` for an unknown identity, `!` for an understood asset with scoped review flags, and `·` for a catalog classification with no flagged fields.
- **Interpretation state** and semantic-category filters for catalog-classified, confirmed, unresolved and unidentified batches.
- **Next unresolved semantic asset** to advance within the active pack, category and text filters.

Select an asset and inspect it from several angles beside the 1.60 m MIRA. The semantic editor records:

- A human-readable identity, category and architectural purpose.
- Object kind and structural role.
- Whether it is complete, fragmentary or intentionally open.
- Its one or two equal working faces.
- How it contacts or attaches to its surroundings.
- Comma-separated environment contexts and connection families.
- Notes explaining purpose, accessibility, intended combinations or uncertainty.
- Explicit approval for procedural visual selection.

The information panel also shows descriptive connection families and semantic sockets. Schema version 4 sockets use a stable name, connection type, model-local position, cardinal local normal and role. A reviewed socket may include an example mate with its asset-local endpoint, required rotation and pivot-aware origin offset. These fields document visual assembly evidence; environment modules still author the tactical placement contract.

The optional **Model-local facing compass** appears above the selected asset. Red arrows label local `+X` and `-X`, blue arrows label local `+Z` and `-Z`, and every selected working face is highlighted in gold. The compass includes the asset's current calibration yaw, so change **Working face 1** until the gold arrow points out of the storefront, entrance, sign face, machine work side, or other intended frontage. For an inner or outer corner, choose its second outward normal in **Working face 2 (equal)**; neither direction is treated as subordinate, and both rotate together when the module is placed. Structural connection sockets remain separate module metadata because they describe where adjoining pieces attach rather than which surfaces face outward. Orbit around the model to confirm the result from more than one angle. Use **Axis Neutral** for objects without a meaningful front and **Unknown** when visual inspection is inconclusive.

Choose **Save confirmed meaning** only when the interpretation is supported by visual inspection or known pack conventions. **Use inference** removes the confirmed override and returns the asset to its catalog classification and any remaining review flags. Calibration saving remains separate.

**Copy identification question** copies the stable asset ID, current interpretation, unresolved fields, measured dimensions and a compact review request. Paste it into a development conversation when a model needs collaborative interpretation; the resulting decision can then be saved as confirmed metadata.

Useful review batches use the family, semantic category and search controls together. For example, select Factory Kit plus `Factory Structure Modules` to review walls and corners as one family, or City Kit Industrial plus `Industrial Buildings` to decide which models are complete shells and which side faces a street.

## Generator integration

`SemanticAssetCatalog.generation_candidates()` returns only confirmed assets with explicit procedural approval. It can additionally require an asset kind. The prebuilt industrial shell catalog uses this API and requires `complete_building`; structural fragments therefore cannot be accepted as parcel-sized buildings merely because their dimensions fit.

The modular presenter applies the same approval gate to catalog-driven visual variants. Existing direct asset paths remain authored component decisions and are not reinterpreted automatically. This keeps current assemblies stable while allowing future modules to migrate to semantic selection deliberately.

## Adding assets safely

1. Import the source model without changing its stable `pack/model` ID.
2. Calibrate its scale, yaw and anchor in the Asset Lab.
3. Inspect the model and its likely family connections.
4. Save a confirmed semantic interpretation.
5. Approve procedural selection only if its intended use is clear.
6. Author a module with explicit tactical cells, clearance and sockets before giving it gameplay effects.

An asset may be well understood but remain unapproved for procedural use. Typical reasons include missing clearance, unknown frontage, lack of a complete building contract or absent tactical authoring.

## Replacing the reference art later

The Kenney library is a reference implementation of the catalog contracts, not a permanent dependency of tactical rules. A future FuseFire-owned art kit should receive new stable asset IDs while the original imported library remains available for comparison. Measure and calibrate each new mesh independently, then confirm its working faces, sockets and semantic role from its own geometry. A module may adopt the new visual reference without changing its authored `MapData` footprint when the replacement satisfies the same tactical and placement contract.

Do not copy calibration, pivots or socket transforms merely because a new model replaces the same kind of object. Reuse semantic intent where appropriate, visually revalidate geometry-specific facts, and grant procedural eligibility only after the new asset has been inspected. If the replacement catalog grows large, explicit semantic inheritance or visual-variant aliases are the next useful extension; the current schema does not infer them automatically.

## Current limitations

- All current stable IDs are human-confirmed. Future catalog additions begin as evidence-backed inferences and can reintroduce field-specific review flags where evidence is insufficient.
- Confirmed contexts and connections are descriptive tags. Module sockets and tactical placement rules remain explicit typed definitions.
- Monolithic exterior shells do not become accessible interiors.
- Semantic approval does not automatically add a new asset to a district grammar; a compatible module or parcel composition is still required.
