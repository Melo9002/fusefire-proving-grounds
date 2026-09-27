import bpy
import bmesh
import json
from pathlib import Path

PROJECT = Path(r"C:\Users\Blue\Documents\Codex\git\fusefire-proving-grounds")
SOURCE = PROJECT / "art/characters/android_test_dummy/models/android_test_dummy_50k.glb"
MODEL_OUT = PROJECT / "art/characters/android_test_dummy/models/android_test_dummy_rigprep.glb"
BLEND_OUT = PROJECT / "art/characters/android_test_dummy/source/android_test_dummy_rigprep.blend"
REPORT_OUT = PROJECT / "art/characters/android_test_dummy/source/RIGPREP_REPORT.json"
WELD_DISTANCE = 1e-6


def component_sizes(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    remaining = set(bm.verts)
    sizes = []
    while remaining:
        seed = remaining.pop()
        stack = [seed]
        count = 0
        while stack:
            vertex = stack.pop()
            count += 1
            for edge in vertex.link_edges:
                neighbor = edge.other_vert(vertex)
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
        sizes.append(count)
    boundary_edges = sum(1 for edge in bm.edges if not edge.is_manifold)
    bm.free()
    sizes.sort(reverse=True)
    return sizes, boundary_edges


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
body = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
body.name = "AndroidTestDummy_RigMesh"
body.data.name = "AndroidTestDummy_RigMesh"

before_components, before_boundary = component_sizes(body.data)
before = {
    "vertices": len(body.data.vertices),
    "faces": len(body.data.polygons),
    "components": len(before_components),
    "components_under_10_vertices": sum(1 for size in before_components if size < 10),
    "non_manifold_edges": before_boundary,
}

bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=WELD_DISTANCE)
bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-9)
bm.normal_update()
bm.to_mesh(body.data)
bm.free()
body.data.validate(clean_customdata=False)
body.data.update()

after_components, after_boundary = component_sizes(body.data)
after = {
    "vertices": len(body.data.vertices),
    "faces": len(body.data.polygons),
    "components": len(after_components),
    "components_under_10_vertices": sum(1 for size in after_components if size < 10),
    "non_manifold_edges": after_boundary,
}

body["fusefire_asset_role"] = "humanoid_rig_preparation"
body["fusefire_height_m"] = 1.6
body["fusefire_weld_distance_m"] = WELD_DISTANCE
body["fusefire_topology_note"] = "Generated shell topology; preserve rigid armor islands and use controlled anatomical weights."

bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
bpy.ops.export_scene.gltf(
    filepath=str(MODEL_OUT),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)

report = {
    "source": str(SOURCE.relative_to(PROJECT)),
    "output_model": str(MODEL_OUT.relative_to(PROJECT)),
    "output_blend": str(BLEND_OUT.relative_to(PROJECT)),
    "weld_distance_m": WELD_DISTANCE,
    "before": before,
    "after": after,
    "vertices_welded": before["vertices"] - after["vertices"],
    "faces_removed": before["faces"] - after["faces"],
    "strategy": "Preserve generated armor/surface shells. Do not force a watertight remesh; use controlled anatomical weights during rigging.",
}
REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("DUMMY_RIGPREP=" + json.dumps(report))
