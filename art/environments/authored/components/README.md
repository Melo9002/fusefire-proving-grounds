# Custom environment components

These original structural pieces complement the downloaded packs in the adjacent `kenney/` collection. Refinery 2.0 references these scene files directly.

All dimensions are in metres. Keep scene transforms uniform when fitting them to the tactical grid. Visual/collision geometry alone does not declare a walkable tactical surface or a traversal link: the map must author those records explicitly.

| Scene | Origin and orientation | Use |
| --- | --- | --- |
| catwalk_deck_2x2 | Walking surface at Y=0, centred X/Z | Tile a gallery; includes a 0.22m slab and collider |
| maintenance_ladder_4m | Ground at Y=0, width along X | Four-metre access; declare bottom/top grid endpoints |
| catwalk_support_2m | Ground at Y=0, paired posts along X | Two-metre-wide gallery with surface Y=4 |
| pipe_rack_support | Ground at Y=0, column spacing along Z | Support overhead pipes above a service route |

The offline refinery recipe currently emits these files. Avoid regenerating over manual improvements without transferring them to the recipe. Boundary railings remain map-authored to keep junctions and ladder approaches open.
