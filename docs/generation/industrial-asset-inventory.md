# Industrial environment asset inventory

## Prepared library

FuseFire retains one Godot-friendly GLB representation for each environment model. The original downloads supplied equivalent GLB, FBX, and OBJ versions; the redundant FBX and OBJ/MTL copies, previews, promotional links, overview pages, and unused texture variations are excluded from the project library.

| Pack | Version | Models | Project location | License |
| --- | ---: | ---: | --- | --- |
| Kenney City Kit Industrial | 2.0 | 37 | `art/environments/kenney/city_kit_industrial/models/` | CC0 1.0 |
| Kenney City Kit Roads | 2.2 | 95 | `art/environments/kenney/city_kit_roads/models/` | CC0 1.0 |
| Kenney Factory Kit | 3.0 | 143 | `art/environments/kenney/factory_kit/models/` | CC0 1.0 |
| Kenney Modular Space Kit | 1.0 | 40 | `art/environments/kenney/modular_space_kit/models/` | CC0 1.0 |

Each pack retains its original `LICENSE.txt`. Kenney permits personal, educational, and commercial use without required attribution under the Creative Commons Zero dedication. Crediting Kenney remains appreciated.

No downloaded ZIP, 7z, RAR, tar, or gzip archive was present in `art/environments/` during preparation. If the original archives still exist in download storage, keep them outside the repository as pristine source packages.

## Source-package audit

Before cleanup, the extracted downloads contained 315 unique model names in three parallel representations:

- 315 GLB files;
- 315 FBX files;
- 315 OBJ files plus 315 MTL files;
- 349 PNG files, primarily per-model preview renders and shared OBJ textures;
- four overview pages, twelve promotional URL shortcuts, and four original licenses.

Godot imported the source packages successfully. The final library occupies roughly 15.1 MiB of source GLBs plus four small required colormaps, instead of roughly 49.5 MiB of extracted source-package content. Godot-generated `.import` metadata and `.godot/imported` cache files are local derived data rather than authored assets.

## Godot compatibility

The canonical assets are binary glTF (`.glb`) scenes with embedded mesh data. Each pack's GLBs retain a relative reference to one external `models/Textures/colormap.png`; that required texture is preserved beside the models. Godot 4.7.2 imported the complete set without model, texture, material, script, or scene errors. `tests/environment_asset_import_smoke.gd` loads and instantiates all 315 models to catch missing or invalid imports.

Kenney assets use the conventional Godot-compatible orientation observed on import: Y-up models with their authored forward orientation preserved. Source dimensions are expressed in glTF metres, but individual pieces vary substantially in footprint. Pivots are the pack-authored pivots and have not been normalized. Generation work must measure actual imported bounds rather than infer grid footprint from filenames.

No collision meshes, tactical cover definitions, grid footprints, entrances, traversal links, elevation metadata, spawn suitability, or objective suitability have been generated. Those belong to later future environment generation authoring and validation tasks.

Goal 2.1 adds a separate FuseFire-owned visual calibration catalog for 14 representative assets and a laboratory that can browse the entire library. See [Environment Asset Calibration Laboratory](asset-calibration-laboratory.md). Its measured bounds and scales remain presentation metadata; no imported mesh creates tactical occupancy.

## Organization contract

```text
art/environments/
└── kenney/
    ├── city_kit_industrial/
    │   ├── models/*.glb
    │   ├── models/Textures/colormap.png
    │   └── LICENSE.txt
    ├── city_kit_roads/
    │   ├── models/*.glb
    │   ├── models/Textures/colormap.png
    │   └── LICENSE.txt
    ├── factory_kit/
    │   ├── models/*.glb
    │   ├── models/Textures/colormap.png
    │   └── LICENSE.txt
    └── modular_space_kit/
        ├── models/*.glb
        ├── models/Textures/colormap.png
        └── LICENSE.txt
```

Runtime wrapper scenes and shared materials should be created only when future environment generation establishes their actual contracts. Do not edit the vendor GLBs in place; place FuseFire-authored metadata and wrappers under a future `art/environments/runtime/` structure.

## Additional packs imported 2026-10-31

| Pack | Version | Imported GLB models | Project folder |
| --- | --- | ---: | --- |
| Car Kit | 3.1 | 50 | `art/environments/kenney/car_kit/` |
| City Kit Commercial | 2.1 | 41 | `art/environments/kenney/city_kit_commercial/` |
| City Kit Suburban | 2.0 | 40 | `art/environments/kenney/city_kit_suburban/` |
| Train Kit | 1.1 | 103 | `art/environments/kenney/train_kit/` |

The Asset Lab now lists all eight packs (549 assets), with native bounds and family-scale calibration baselines for the 234 additions. No new calibration approval, tactical behavior or generator eligibility is implied. The original 315 calibration/review records and original bounds are unchanged.

### Calibration baseline � 2026-11-01

Open Asset Lab (F6), select the family filter, and use Unreviewed to inspect the new assets beside MIRA. Save individual scale overrides where needed, then mark reviewed only after inspection. The owner will assign special-item scales.

- Commercial buildings and details, including parasols: 10x, matching established industrial buildings.
- Suburban houses and paths: 10x; fences: established construction-fence category at 5x (standard fence height 1.35 m).
- Cars and parts: provisional shared 1.25x, because native dimensions differ from the City Kits.
- Trains and track: provisional shared 2x. Track uses a common +2 m vertical origin correction to preserve ramp/curve alignment; straight pitch is 8 m. Rail vehicles preserve source pivots; the comparison uses +0.2 m placement for rail contact.

No per-asset overrides were added. Building and fence scales follow the owner-requested existing family values rather than the earlier experimental 7x calibration. Representative rendered inspections were performed; the new catalog is not individually visually certified. Semantic classification remains explicitly pending for all 234 additions.

Focused verification: asset calibration and semantic catalog suites; original calibration and bounds records compared structurally against Git HEAD. Existing sandbox certificate-store warnings do not indicate an asset-load failure.

Each new pack retains its supplied CC0 license and the `models/Textures/colormap.png` referenced by its GLBs. Copied source hashes match. Godot instantiated all 234 scenes with nonempty mesh bounds; no visual/scale certification was performed. The sandbox import reported certificate-store/editor-settings access warnings; the model-load check passed.

The complete original packages (including alternate formats and previews) were moved out of `additional assets` to `C:/Users/Blue/Documents/Codex/asset-sources/fusefire/2026-10-31/`. Every moved source file was hash-verified against that archive's manifest. The incoming folder is empty. This source archive is local and is not pushed to Git.


### Counterpart-scale experiment � 2026-11-01

Owner proposed deriving new-pack scale from equivalent reviewed objects. Tested without modifying saved calibrations or review flags.

- City Roads construction cone: native 0.075 x 0.09375 x 0.075; reviewed 5x gives 0.375 x 0.46875 x 0.375 m.
- Car Kit cone: native approximately 0.476194 x 0.595243 x 0.476194. A uniform 0.7875x matches the reviewed cone on all axes within float tolerance. Mesh geometry is not identical (40 versus 88 unique normalized position samples); matching envelopes alone do not establish identical source models.
- Applying 0.7875x to the Car Kit sedan gives 1.18125 m width, 1.02375 m height and 2.008125 m length. Rendered alongside the 1.60 m MIRA reference, it reads as miniature. Current 1.25x yields 1.875 x 1.625 x 3.1875 m. This supports separate vehicle/standalone-prop calibration, not the cone as a pack-wide ruler.
- Train container cargo mesh is 1 x 0.9 x 2.575 native units. Reviewed Industrial container A is approximately 2.9808 x 2.78464 x 6.5808 m. Matching width, height and length requires respectively 2.9808x, 3.0940x and 2.5557x: no single uniform conversion. The cargo mesh was measured separately from the wagon/wheels.
- An exploratory scan of normalized mesh-position sets found no exact cross-pack counterpart between the four new packs and City Roads, City Industrial or Factory (excluding trivial meshes with 12 or fewer unique positions). This is not proof no shared components exist: rotations, topology differences and combined meshes can prevent a match. Shared building filenames do not denote shared geometry. No defensible new ratio was established for Commercial/Suburban.

Recommendation: use multiple counterpart measurements where available, validate against MIRA and functional connections, and keep mechanically connected families at one scale. A standalone prop can require an exception. Do not resize a whole pack from one coincidentally matching envelope. No new calibration system or production changes are needed. Special-item overrides remain for owner review.

Rendered experiment: `artifacts/additional-calibration/counterpart-scale-comparison.png` (local, ignored). Top row uses 0.7875x; bottom row uses the existing 1.25x. Each row includes the reviewed City Roads cone, Car Kit cone, sedan and MIRA. No gameplay code changed; no test rerun needed for this documentation-only experiment.


### Owner visual approval - 2026-11-01

The owner explicitly reported that everything had been visually inspected and requested marking the catalog reviewed. All 549 assets are now visually reviewed. Existing 33 saved individual records and all category presets were preserved exactly, including the owner's scale adjustments. Remaining inherited calibrations were frozen into per-asset records so later category edits cannot silently change the approved baseline. Individual overrides now take precedence for the entire reviewed catalog.

This records approval of saved on-disk calibration; any unsaved viewport edits are outside that record. Semantic data, generation eligibility and tactical properties were not changed. Earlier pending-visual-review notes describe historical stages, not current visual approval. Semantic interpretation remains pending for the 234 newly imported assets.


### Agent-authored meaning pass - 2026-11-01

At the owner's request, all 234 new assets now have explicit meaning records in the existing semantic catalog. The original 315 records and all visual calibrations remain unchanged. This supersedes the earlier pending-identity status: basic identities/purposes are filled, but uncertain working faces, clearance and assembly relationships retain review flags. The schema calls persisted annotations `confirmed`; for this pass that means an authored record, not owner approval of every directional/assembly detail. Evidence fields describe the naming/bounds/reference basis. No new six-axis geometry certification is claimed.

Commercial/Suburban buildings are exterior shells; low-detail buildings represent full-size background massing. Cars are separated from detached wheels/debris and standalone props. Tracks have a distinct rail_track role; damaged/curved/spline pieces do not acquire invented connection contracts. Train carriages retain cargo-specific descriptions. Contexts and clearance notes describe intended placement without authoring gameplay collision, cover, interiors or walkability.

All new generation_ready flags remain false. Browser `!` markers prioritize outstanding review questions over the saved-meaning checkmark. Use Meaning to refine descriptions; Advanced > Needs semantic review filters the remaining questions. Existing socket data and the original 35 visual-generation approvals were preserved.


### Rendered working-face pass - 2026-11-01

Inspected opposing native-axis views of the 234 additions, with top/front detail views for fences, canopies, a wheel and a detached door. Added directional or explicitly axis-neutral findings to 233 records; preserved the owner's debris-bolt meaning correction and calibration edits. Original 315 semantic records remain unchanged. Per-record evidence identifies a contact-sheet/item index. These are agent visual findings requested by the owner, not a new declaration of owner certification.

Cars point +Z; wheel outer hubs and painted detached-door exteriors face +X. Primary commercial/residential frontages generally face -Z, with explicit corner/dual-frontage exceptions. U fences open toward -Z; low parallel fences and paths admit approach from +/-Z. Powered train noses generally point +Z, intermediate passenger stock uses lateral +/-X presentation, and container cargo doors face +Z. Axis-neutral means no preferred horizontal working facade, not rotational symmetry or arbitrary connection compatibility. Background masses do not acquire invented entrances. Rail connections, clearance, mounting and tactical behavior remain separately unresolved where flagged.

Local evidence: `artifacts/working-face-review/sheet-00.png` through `sheet-19.png`, `detail-00.png`, manifests and capture scripts. Models were shown without saved calibration yaw, so the faces are model-local; the Asset Lab applies saved yaw to the compass. The semantic regression suite checks representative directions, dual faces, explicit neutrality and preservation of unresolved connection gates. Calibration tests check existing yaw/compass behavior. Graphics capture completed despite existing sandbox shader-cache warnings.
