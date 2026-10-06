# 🌐 External resource ledger

This ledger tracks assets, plugins, and references considered during FuseFire
pre-production. An entry is evidence of evaluation, not permission to add a
dependency.

| ID | Candidate | Version / compatibility | License | Labor saved | Coupling and risk | Removal path | Decision |
|---|---|---|---|---|---|---|---|
| EXT-01 | [Prototype Texture](https://godotengine.org/asset-library/asset/5503) · [source](https://github.com/xAnTuA/Prototype-Texture) | 1.0.0 · Godot 4.7 | MIT | Fast, scale-independent graybox materials for the modular-kit proof | New and lightly proven; its visual pattern must not become authoritative distance measurement | Keep it inside the graybox experiment and replace materials without changing map data | **Experiment** |
| EXT-02 | Godot editor gizmos and Inspector helpers | Candidate not selected | TBD | Could make map/module metadata visible and editable | Editor APIs and maintenance burden are unknown | Prefer native Inspector data; isolate any plugin | **Research when MAP-03 begins** |
| EXT-03 | Blender rigging/retargeting helpers | Candidate not selected | TBD | Could reduce repetitive MIRA rig and clip preparation | May impose naming, skeleton, or export conventions | Preserve canonical source and document a manual path | **Research during W1** |
| EXT-04 | Camera obstruction/cutaway references | Reference survey, not necessarily a dependency | Varies | Avoids rediscovering common visibility techniques | A generic camera package may conflict with FuseFire's working ownership and replay rules | Study techniques first; implement only the needed behavior locally | **Research after a representative dense map exists** |
| EXT-05 | UI themes and audio/VFX utilities | Candidate not selected | TBD | Could accelerate generic polish | Visual identity, attribution, and runtime dependencies can spread widely | Require replaceable assets and centralized configuration | **Park until the playable slice names a need** |
| EXT-06 | [Adobe Mixamo](https://www.mixamo.com/) · [official FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Current web service; bipedal humanoids | Adobe royalty-free use terms described in its FAQ | Large library of prototype humanoid motion and optional auto-rigging | Requires Adobe ID; generic motion needs cleanup; only the last used character is retained online | Archive original downloads, settings, and provenance locally; final clips remain replaceable | **Use for EXP-001's first source-motion proof** |
| EXT-07 | [Godot 4.7 humanoid retargeting](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/retargeting_3d_skeletons.html) | Built into Godot 4.7 | Engine feature | Bone mapping, rest correction, position normalization, and shared animation libraries | Incorrect rest-axis correction can distort a rig; model proportions still need visual correction | Import settings remain per asset and can be reverted; source assets stay untouched | **Adopt as the manual baseline** |
| EXT-08 | [Mixamo Animation Batcher](https://github.com/KarnesTH/mixamo-animation-batcher) | 1.0.0; tested on Godot 4.6.2 | MIT | Batch conversion of Mixamo FBX animations to retargeted Godot `.res` files | Very young project with two commits; 4.7 compatibility and generated output need inspection | Test in a disposable project/folder; retain documented manual import path | **Experiment only after one manual import** |
| EXT-09 | [Animation Node Redirector](https://godotengine.org/asset-library/asset/3627) | 1.0.0; Godot 4.3 | MIT | Repairs broken AnimationPlayer NodePaths after scene rearrangement | Treating repair as normal workflow could conceal unstable scene paths | Use only on a copy and review every changed track | **Reserve tool** |
| EXT-10 | [Edit Resources as Table 2](https://godotengine.org/asset-library/asset/1479) | 2.17.4; Godot 4.x | MIT | Human-friendly bulk editing for future weapon, character, and terrain resources | Adds an editor workflow dependency; value exists only after resource schemas stabilize | Resources remain ordinary Godot files editable without the plugin | **Promising; test when two real data sets exist** |
| EXT-11 | [Godot Inverse Kinematics 3D Demo](https://store.godotengine.org/asset/godot-foundation/inverse-kinematics-3d-demo/) | Godot 4.7; marked unstable | MIT | Reference for built-in IK and FABRIK approaches | Current store feedback reports broken bone positioning | Study code/concepts only; do not depend on the project | **Study only** |

## Entry checklist

- [ ] Exact name, source, author, version, and license are recorded.
- [ ] Current Godot/Blender compatibility and maintenance activity are checked.
- [ ] The specific repeated labor it removes is demonstrated.
- [ ] Editor/runtime/export coupling is understood.
- [ ] Attribution and local modifications have a home.
- [ ] A removal or replacement path exists.
- [ ] The decision is **adopt**, **adapt**, **study only**, **experiment**, or **reject**.

