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

No collision meshes, tactical cover definitions, grid footprints, entrances, traversal links, elevation metadata, spawn suitability, or objective suitability have been generated. Those belong to later Battlefield Generation 2.0 authoring and validation tasks.

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

Runtime wrapper scenes and shared materials should be created only when Battlefield Generation 2.0 establishes their actual contracts. Do not edit the vendor GLBs in place; place FuseFire-authored metadata and wrappers under a future `art/environments/runtime/` structure.
