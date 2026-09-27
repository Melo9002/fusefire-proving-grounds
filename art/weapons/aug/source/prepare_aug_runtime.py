import bpy
import json
from mathutils import Vector
from pathlib import Path

ROOT = Path(r"C:\Users\Blue\Documents\Codex\asset making\aug by castelobravo")
SOURCE = ROOT / "aug-assault_rifle.glb"
OUTPUT_BLEND = ROOT / "aug_runtime.blend"
OUTPUT_GLB = ROOT / "aug_runtime.glb"
REPORT = ROOT / "AUG_OPTIMIZATION_REPORT.json"
TARGET_LENGTH = 0.79


def mesh_stats(objects):
    return {
        "objects": len(objects),
        "vertices": sum(len(obj.data.vertices) for obj in objects),
        "triangles": sum(sum(len(poly.vertices) - 2 for poly in obj.data.polygons) for obj in objects),
    }


def world_bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
source_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
source_stats = mesh_stats(source_meshes)
source_min, source_max = world_bounds(source_meshes)
source_dimensions = source_max - source_min

# Loose cartridges live inside the opaque magazine and are never visible during play.
removed = []
for obj in list(source_meshes):
    if "Ammo" in obj.name:
        removed.append(obj.name)
        bpy.data.objects.remove(obj, do_unlink=True)

runtime_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
# Bake imported hierarchy transforms before combining visible parts.
bpy.ops.object.select_all(action="DESELECT")
for obj in runtime_meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = runtime_meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.context.view_layer.objects.active = runtime_meshes[0]

# Join to one draw-ready static mesh while retaining material slots and UVs.
bpy.ops.object.join()
rifle = bpy.context.active_object
rifle.name = "AUG_Runtime"
rifle.data.name = "AUG_Runtime_Mesh"

# Normalize to a real AUG length after joining, center it, and bake predictable transforms.
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
runtime_min, runtime_max = world_bounds([rifle])
runtime_dimensions = runtime_max - runtime_min
longest_axis = max(range(3), key=lambda index: runtime_dimensions[index])
rifle.scale = (TARGET_LENGTH / runtime_dimensions[longest_axis],) * 3
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
runtime_min, runtime_max = world_bounds([rifle])
rifle.location -= (runtime_min + runtime_max) * 0.5
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
runtime_min, runtime_max = world_bounds([rifle])
runtime_dimensions = runtime_max - runtime_min

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT_GLB),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)

result = {
    "source": source_stats,
    "source_dimensions_m": list(source_dimensions),
    "removed_hidden_objects": removed,
    "runtime": mesh_stats([rifle]),
    "runtime_dimensions_m": list(runtime_dimensions),
    "target_length_m": TARGET_LENGTH,
    "materials": [slot.material.name if slot.material else "" for slot in rifle.material_slots],
    "uv_layers": len(rifle.data.uv_layers),
}
REPORT.write_text(json.dumps(result, indent=2), encoding="utf-8")
print("AUG_RUNTIME=" + json.dumps(result))
