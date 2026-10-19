# Semantic Asset Catalog

FuseFire records two independent kinds of asset knowledge:

- `asset_calibrations.json` stores visual measurements and placement calibration: scale, yaw, anchor, offsets and measured bounds.
- `asset_semantics.json` stores human-confirmed meaning: what an asset represents, whether it is complete or fragmentary, where it belongs and whether procedural presentation may select it.

Neither file authors tactical movement, occupancy, cover, collision, line of sight or traversal. Those remain explicit properties of `MapData` and environment module definitions.

## Resolution and trust

`SemanticAssetCatalog` creates a provisional record for every stable `pack/model` ID from pack and filename evidence. Provisional records include an asset kind, structural role, completeness, facing, attachment, contexts and confidence. They remain marked **Needs identification**, even when the filename inference is strong.

Entries in `asset_semantics.json` override those provisional fields. The Asset Lab writes only to the `confirmed` section, so a future measurement or filename scan cannot replace a developer decision. A confirmed record may separately opt into procedural visual selection with `generation_ready`. This approval still does not provide tactical behavior.

The current baseline contains 12 confirmed procedural visuals: five complete City Industrial exterior shells and seven pieces of road furniture already used by reviewed environment modules. The other 303 assets retain provisional interpretations and form the human review queue.

The approved baseline is:

- Complete sealed shells: `building-h`, `building-i`, `building-j`, `building-k`, and `building-o` from City Kit Industrial.
- Road context: `light-curved`, `light-square`, `traffic-light`, `road-sign-stop`, `dumpster`, `electricity-pole-single`, and `construction-fence` from City Kit Roads.

## Asset Lab annotation workflow

Open `res://tools/asset_lab/asset_lab.tscn` and run the current scene with **F6**.

The left browser now shows:

- `✓` for a confirmed semantic record.
- `?` for a provisional interpretation that still needs identification.
- **Interpretation state** and semantic-category filters for review batches.
- **Next asset needing identification** to advance within the active pack, category and text filters.

Select an asset and inspect it from several angles beside the 1.64 m MIRA. The semantic editor records:

- A human-readable identity, category and architectural purpose.
- Object kind and structural role.
- Whether it is complete, fragmentary or intentionally open.
- Its front or working face.
- How it contacts or attaches to its surroundings.
- Comma-separated environment contexts and connection families.
- Notes explaining purpose, accessibility, intended combinations or uncertainty.
- Explicit approval for procedural visual selection.

Choose **Save confirmed meaning** only when the interpretation is supported by visual inspection or known pack conventions. **Use inference** removes the confirmed override and returns the asset to the identification queue. Calibration saving remains separate.

**Copy identification question** copies the stable asset ID, current inference, measured dimensions and a compact set of architectural questions. Paste it into a development conversation when a model needs collaborative interpretation; the resulting decision can then be saved as confirmed metadata.

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

## Current limitations

- Most of the catalog is intentionally provisional. Filename inference is navigation help, not architectural truth.
- Confirmed contexts and connections are descriptive tags. Module sockets and tactical placement rules remain explicit typed definitions.
- Monolithic exterior shells do not become accessible interiors.
- Semantic approval does not automatically add a new asset to a district grammar; a compatible module or parcel composition is still required.
