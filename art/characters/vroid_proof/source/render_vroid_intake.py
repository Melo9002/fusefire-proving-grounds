import bpy
from mathutils import Vector
from pathlib import Path


PROJECT = Path(r"C:\Users\Blue\Documents\Codex\git\fusefire-proving-grounds")
SOURCE = PROJECT / "art/characters/vroid_proof/source/vroidTest_intake.blend"
OUTPUT = PROJECT / "art/characters/vroid_proof/review"
OUTPUT.mkdir(parents=True, exist_ok=True)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

bpy.ops.mesh.primitive_plane_add(size=5.0, location=(0.0, 0.0, -0.004))
floor = bpy.context.object
floor.name = "IntakeReviewFloor"
floor_material = bpy.data.materials.new("IntakeReviewFloor")
floor_material.diffuse_color = (0.045, 0.055, 0.075, 1.0)
floor.data.materials.append(floor_material)

for name, location, energy, size, color in [
    ("Key", (-2.2, -3.2, 3.2), 950.0, 2.8, (0.85, 0.92, 1.0)),
    ("Fill", (2.4, -1.0, 2.1), 500.0, 2.0, (1.0, 0.78, 0.62)),
    ("Rim", (1.4, 2.8, 2.8), 800.0, 2.4, (0.42, 0.72, 1.0)),
]:
    data = bpy.data.lights.new(name, "AREA")
    light = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(light)
    light.location = location
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    aim(light, (0.0, 0.0, 0.9))

camera_data = bpy.data.cameras.new("IntakeReviewCamera")
camera = bpy.data.objects.new("IntakeReviewCamera", camera_data)
bpy.context.scene.collection.objects.link(camera)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 1.82

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.new("IntakeReviewWorld")
scene.world.color = (0.018, 0.022, 0.032)
scene.view_settings.look = "Medium High Contrast"

views = {
    "front_a": (0.0, -4.0, 0.9),
    "front_b": (0.0, 4.0, 0.9),
    "side": (4.0, 0.0, 0.9),
    "three_quarter": (2.8, -4.0, 1.45),
}
for name, location in views.items():
    camera.location = location
    aim(camera, (0.0, 0.0, 0.82))
    scene.render.filepath = str(OUTPUT / f"vroid_intake_{name}.png")
    bpy.ops.render.render(write_still=True)

print("VRM_REVIEW=" + str(OUTPUT))
