import bpy
import hashlib
import json
from pathlib import Path


PROJECT = Path(r"C:\Users\Blue\Documents\Codex\git\fusefire-proving-grounds")
SOURCE = PROJECT / "art/characters/vroid_proof/source/vroidTest.vrm"
BLEND_OUT = PROJECT / "art/characters/vroid_proof/source/vroidTest_intake.blend"
REPORT_OUT = PROJECT / "art/characters/vroid_proof/docs/VRM_INTAKE_REPORT.json"


def world_bounds(objects):
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    if not points:
        return None
    minimum = [min(point[index] for point in points) for index in range(3)]
    maximum = [max(point[index] for point in points) for index in range(3)]
    return {
        "minimum": [round(value, 6) for value in minimum],
        "maximum": [round(value, 6) for value in maximum],
        "dimensions": [round(maximum[index] - minimum[index], 6) for index in range(3)],
    }


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
result = bpy.ops.import_scene.vrm(filepath=str(SOURCE))
if "FINISHED" not in result:
    raise RuntimeError(f"VRM import failed: {result}")

objects = list(bpy.context.scene.objects)
armatures = [obj for obj in objects if obj.type == "ARMATURE"]
meshes = [obj for obj in objects if obj.type == "MESH"]
if len(armatures) != 1:
    raise RuntimeError(f"Expected one armature, found {len(armatures)}")

armature = armatures[0]
mesh_reports = []
for obj in meshes:
    obj.data.calc_loop_triangles()
    shape_keys = []
    if obj.data.shape_keys:
        shape_keys = [key.name for key in obj.data.shape_keys.key_blocks]
    mesh_reports.append({
        "object": obj.name,
        "vertices": len(obj.data.vertices),
        "triangles": len(obj.data.loop_triangles),
        "materials": [slot.material.name if slot.material else None for slot in obj.material_slots],
        "shape_key_count": len(shape_keys),
        "shape_keys": shape_keys,
        "armature_modifiers": [modifier.object.name for modifier in obj.modifiers if modifier.type == "ARMATURE" and modifier.object],
    })

extension = getattr(armature.data, "vrm_addon_extension", None)
spec_version = getattr(extension, "spec_version", "unknown") if extension else "unknown"

humanoid_assignments = {}
if extension:
    if spec_version == "1.0":
        human_bones = extension.vrm1.humanoid.human_bones
        for name in dir(human_bones):
            if name.startswith("_"):
                continue
            assignment = getattr(human_bones, name, None)
            node = getattr(assignment, "node", None)
            bone_name = getattr(node, "bone_name", "") if node else ""
            if bone_name:
                humanoid_assignments[name] = bone_name
    else:
        for human_bone in extension.vrm0.humanoid.human_bones:
            if human_bone.bone and human_bone.node.bone_name:
                humanoid_assignments[str(human_bone.bone)] = human_bone.node.bone_name

report = {
    "source": str(SOURCE.relative_to(PROJECT)),
    "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest().upper(),
    "vrm_spec_version": spec_version,
    "object_count": len(objects),
    "armature": armature.name,
    "bone_count": len(armature.data.bones),
    "bones": [bone.name for bone in armature.data.bones],
    "humanoid_assignments": humanoid_assignments,
    "mesh_count": len(meshes),
    "total_vertices": sum(item["vertices"] for item in mesh_reports),
    "total_triangles": sum(item["triangles"] for item in mesh_reports),
    "material_count": len(bpy.data.materials),
    "materials": [material.name for material in bpy.data.materials],
    "image_count": len(bpy.data.images),
    "images": [image.name for image in bpy.data.images],
    "bounds_metres": world_bounds(meshes),
    "meshes": mesh_reports,
    "blend_output": str(BLEND_OUT.relative_to(PROJECT)),
}

armature["fusefire_asset_role"] = "vroid_proof_source"
armature["fusefire_source_sha256"] = report["sha256"]
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
REPORT_OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
print("VRM_INTAKE=" + json.dumps({
    "version": spec_version,
    "bones": report["bone_count"],
    "meshes": report["mesh_count"],
    "triangles": report["total_triangles"],
    "dimensions": report["bounds_metres"]["dimensions"] if report["bounds_metres"] else None,
    "shape_keys": sum(item["shape_key_count"] for item in mesh_reports),
}))
