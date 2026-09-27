import bpy
import math
from mathutils import Vector
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[4]
SOURCE = PROJECT / "art/characters/android_test_dummy/source/android_test_dummy_rigged.blend"
OUTPUT = PROJECT / "art/characters/android_test_dummy/review"
OUTPUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
armature = bpy.data.objects["AndroidTestDummy_Armature"]

bpy.ops.object.select_all(action="DESELECT")
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode="POSE")
for pose_bone in armature.pose.bones:
    pose_bone.rotation_mode = "XYZ"
    pose_bone.rotation_euler = (0.0, 0.0, 0.0)

# Asymmetric joint stress pose: forward arm flex, torso twist, and left-leg crouch.
armature.pose.bones["UpperArm.L"].rotation_euler.x = math.radians(-48)
armature.pose.bones["Forearm.L"].rotation_euler.x = math.radians(-82)
armature.pose.bones["UpperArm.R"].rotation_euler.x = math.radians(-28)
armature.pose.bones["Forearm.R"].rotation_euler.x = math.radians(-58)
armature.pose.bones["Chest"].rotation_euler.z = math.radians(12)
armature.pose.bones["Neck"].rotation_euler.z = math.radians(-7)
armature.pose.bones["Thigh.L"].rotation_euler.x = math.radians(-28)
armature.pose.bones["Shin.L"].rotation_euler.x = math.radians(58)
armature.pose.bones["Foot.L"].rotation_euler.x = math.radians(-22)
armature.pose.bones["Thigh.R"].rotation_euler.x = math.radians(10)
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.mesh.primitive_plane_add(size=5, location=(0, 0, -0.005))
floor = bpy.context.object
floor_material = bpy.data.materials.new("ValidationFloor")
floor_material.diffuse_color = (0.025, 0.035, 0.05, 1)
floor.data.materials.append(floor_material)

def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

for name, location, energy, size, color in [
    ("Key", (-2.4, -3.2, 3.4), 1100, 3.0, (0.78, 0.9, 1.0)),
    ("Fill", (2.6, -1.0, 2.3), 650, 2.2, (1.0, 0.72, 0.55)),
    ("Rim", (1.8, 2.5, 3.0), 900, 2.5, (0.28, 0.78, 1.0)),
]:
    data = bpy.data.lights.new(name, "AREA")
    light = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(light)
    light.location = location
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    aim(light, (0, 0, 0.9))

camera_data = bpy.data.cameras.new("ValidationCamera")
camera = bpy.data.objects.new("ValidationCamera", camera_data)
bpy.context.scene.collection.objects.link(camera)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 1.9

scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.new("ValidationWorld")
scene.world.color = (0.012, 0.016, 0.024)

views = {
    "front": (0, -4, 0.86),
    "three_quarter": (2.7, -4, 1.55),
    "side": (4, 0, 0.86),
    "back": (0, 4, 0.86),
}
for name, position in views.items():
    camera.location = position
    aim(camera, (0, 0, 0.82))
    scene.render.filepath = str(OUTPUT / f"rig_validation_{name}.png")
    bpy.ops.render.render(write_still=True)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "android_test_dummy_rig_validation.blend"))
print("RIG_VALIDATION=" + str(OUTPUT))
