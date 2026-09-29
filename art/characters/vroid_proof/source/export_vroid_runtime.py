import bpy
import json
from pathlib import Path


PROJECT = Path(r"C:\Users\Blue\Documents\Codex\git\fusefire-proving-grounds")
SOURCE = PROJECT / "art/characters/vroid_proof/source/vroidTest_intake.blend"
BLEND_OUT = PROJECT / "art/characters/vroid_proof/source/vroidTest_runtime.blend"
GLB_OUT = PROJECT / "art/characters/vroid_proof/models/vroid_test_runtime.glb"
REPORT_OUT = PROJECT / "art/characters/vroid_proof/docs/VRM_RUNTIME_REPORT.json"
TARGET_HEIGHT = 1.60


def mesh_bounds(meshes):
    points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    minimum = [min(point[index] for point in points) for index in range(3)]
    maximum = [max(point[index] for point in points) for index in range(3)]
    return minimum, maximum


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]

minimum, maximum = mesh_bounds(meshes)
source_height = maximum[2] - minimum[2]
scale_factor = TARGET_HEIGHT / source_height

# Scale armature and its children as one hierarchy, then bake matching object
# transforms into the runtime copy. The untouched VRM and intake blend remain
# available if this normalization ever needs to be repeated differently.
armature.scale = tuple(value * scale_factor for value in armature.scale)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
armature.select_set(True)
for mesh in meshes:
    mesh.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bpy.context.view_layer.update()

minimum, maximum = mesh_bounds(meshes)
runtime_height = maximum[2] - minimum[2]

armature.name = "VRoidProof_Armature"
armature.data.name = "VRoidProof_Skeleton"
armature["fusefire_asset_role"] = "vroid_proof_runtime"
armature["fusefire_height_m"] = TARGET_HEIGHT
armature["fusefire_forward_axis"] = "-Y"
armature["fusefire_right_hand_bone"] = "J_Bip_R_Hand"
armature["fusefire_left_hand_bone"] = "J_Bip_L_Hand"
armature["fusefire_head_bone"] = "J_Bip_C_Head"

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

bpy.ops.object.select_all(action="DESELECT")
armature.select_set(True)
for mesh in meshes:
    mesh.select_set(True)
bpy.context.view_layer.objects.active = armature

export_parameters = {
    "filepath": str(GLB_OUT),
    "export_format": "GLB",
    "use_selection": True,
    "export_apply": True,
    "export_skins": True,
    "export_morph": True,
    "export_morph_normal": True,
    "export_animations": True,
    "export_force_sampling": True,
}
available = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
export_parameters = {key: value for key, value in export_parameters.items() if key in available}
bpy.ops.export_scene.gltf(**export_parameters)

for mesh in meshes:
    mesh.data.calc_loop_triangles()

report = {
    "source_blend": str(SOURCE.relative_to(PROJECT)),
    "runtime_blend": str(BLEND_OUT.relative_to(PROJECT)),
    "runtime_glb": str(GLB_OUT.relative_to(PROJECT)),
    "source_height_m": round(source_height, 6),
    "target_height_m": TARGET_HEIGHT,
    "runtime_height_m": round(runtime_height, 6),
    "scale_factor": round(scale_factor, 8),
    "armature": armature.name,
    "bone_count": len(armature.data.bones),
    "mesh_count": len(meshes),
    "triangles": sum(len(mesh.data.loop_triangles) for mesh in meshes),
    "shape_keys": sum(len(mesh.data.shape_keys.key_blocks) if mesh.data.shape_keys else 0 for mesh in meshes),
    "right_hand_bone": "J_Bip_R_Hand",
    "left_hand_bone": "J_Bip_L_Hand",
    "head_bone": "J_Bip_C_Head",
    "secondary_colliders_exported": False,
    "authoritative_root_motion": False,
}
REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("VRM_RUNTIME=" + json.dumps(report))
