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
