# Prototype Texture

Third-party prototype material pack by AnTuA, version 1.0.0.

- Source: <https://github.com/xAnTuA/Prototype-Texture>
- Godot Asset Library: <https://godotengine.org/asset-library/asset/5503>
- License: MIT; see [LICENSE](LICENSE).

This is a material pack, not an EditorPlugin. It does not need a `plugin.cfg`
entry or activation in Project Settings. Apply one of the five `.tres`
materials to prototype geometry. `texture_size_m` controls the object-space
triplanar repeat size; it defaults to one meter.

The projection keeps a consistent texel scale across differently scaled
meshes, but the triplanar blend means the printed grid is a spatial guide, not
an exact distance-measurement tool.
