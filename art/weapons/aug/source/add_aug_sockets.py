import bpy
import json
from mathutils import Vector
from pathlib import Path

PROJECT = Path(r"C:\Users\Blue\Documents\Codex\git\fusefire-proving-grounds")
SOURCE = PROJECT / "art/weapons/aug/source/aug_runtime.blend"
BLEND_OUT = PROJECT / "art/weapons/aug/source/aug_runtime_socketed.blend"
GLB_OUT = PROJECT / "art/weapons/aug/models/aug_runtime_socketed.glb"
REPORT_OUT = PROJECT / "art/weapons/aug/source/AUG_SOCKET_REPORT.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rifle = bpy.data.objects.get("AUG_Runtime")
if rifle is None:
    rifle = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")

world_vertices = [rifle.matrix_world @ vertex.co for vertex in rifle.data.vertices]
minimum_y = min(vertex.y for vertex in world_vertices)
tip_vertices = [vertex for vertex in world_vertices if vertex.y <= minimum_y + 0.025]
tip_center = sum(tip_vertices, Vector()) / len(tip_vertices)
muzzle_location = Vector((tip_center.x, minimum_y - 0.012, tip_center.z))

for existing in [obj for obj in bpy.data.objects if obj.name in {"MuzzleSocket", "WeaponOrigin"}]:
    bpy.data.objects.remove(existing, do_unlink=True)

muzzle = bpy.data.objects.new("MuzzleSocket", None)
muzzle.empty_display_type = "ARROWS"
muzzle.empty_display_size = 0.045
muzzle.location = muzzle_location
bpy.context.scene.collection.objects.link(muzzle)
muzzle.parent = rifle
muzzle.matrix_parent_inverse = rifle.matrix_world.inverted()

origin = bpy.data.objects.new("WeaponOrigin", None)
origin.empty_display_type = "PLAIN_AXES"
origin.empty_display_size = 0.08
origin.location = Vector((0.0, 0.0, 0.0))
bpy.context.scene.collection.objects.link(origin)
origin.parent = rifle
origin.matrix_parent_inverse = rifle.matrix_world.inverted()

rifle["fusefire_length_m"] = 0.79
rifle["fusefire_muzzle_marker"] = "MuzzleSocket"

bpy.ops.object.select_all(action="DESELECT")
for obj in (rifle, muzzle, origin):
    obj.select_set(True)
bpy.context.view_layer.objects.active = rifle
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
bpy.ops.export_scene.gltf(
    filepath=str(GLB_OUT),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)

report = {
    "muzzle_location_blender_m": list(muzzle_location),
    "tip_sample_vertices": len(tip_vertices),
    "markers": ["WeaponOrigin", "MuzzleSocket"],
    "output_glb": str(GLB_OUT.relative_to(PROJECT)),
    "output_blend": str(BLEND_OUT.relative_to(PROJECT)),
}
REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("AUG_SOCKETS=" + json.dumps(report))
