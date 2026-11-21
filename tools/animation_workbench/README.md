# Animation workbench

`pose_workbench.tscn` is a context host (a `Node3D` with a `CharacterRig` child) for inspecting the production character without the game: poses, locomotion, cover, ladder, stair and path benches, rescue carry, and hand-contact diagnostics. Open it in Godot and press F6. `locomotion_test_panel.gd` is the on-screen control panel.

Keys: `H` hand diagnostics, `J` labels, `G` mark contact, `Z` crouch/kneel preset, `X` diagnostic view, `T` turning preview, `[` `]` preview speed. It drives the rig exactly as the tactical adapter does (presenter tick, action stage, weapon pose). See [`docs/animation.md`](../../docs/animation.md).
