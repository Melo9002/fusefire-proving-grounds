# blender --background --python render_poses.py -- <in.glb> <out_dir> action:frame[,action:frame...]
import bpy, sys, os, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
src, out, shots = argv[0], os.path.abspath(argv[1]), [s.split(":") for s in argv[2].split(",")]
os.makedirs(out, exist_ok=True)
if src.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
COLOR = os.environ.get("MIRA_COLOR", "SINGLE")
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
for o in list(sc.objects):
    if o.type == "MESH" and not any(m.type == "ARMATURE" for m in o.modifiers): o.hide_render = True
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"; sc.display.shading.show_cavity = True
sc.display.shading.show_shadows = False; sc.display.shading.color_type = COLOR
sc.display.shading.show_object_outline = True
sc.render.resolution_x = 520; sc.render.resolution_y = 640
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.18, 0.18, 0.2)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.35
def look(loc, target):
    cam.location = loc; d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
views = {"front": (0, -3, 0.5), "q34": (2.1, -2.1, 0.9), "side": (3, 0, 0.5), "back": (-1.5, 2.6, 0.7)}
arm.animation_data_create()
for act_name, frame in shots:
    act = bpy.data.actions.get(act_name) or bpy.data.actions.get(act_name + ".001")
    if act_name == "rest":
        arm.animation_data.action = None
        for pb in arm.pose.bones: pb.matrix_basis.identity()
    else:
        arm.animation_data.action = act
        if hasattr(arm.animation_data, "action_slot") and act.slots: arm.animation_data.action_slot = act.slots[0]
    sc.frame_set(int(frame)); bpy.context.view_layer.update()
    # keep root motion in frame: aim at hips
    hips = arm.matrix_world @ arm.pose.bones[0].head
    tgt = (hips.x, hips.y, max(hips.z, 0.45))
    for vn, off in views.items():
        look((tgt[0] + off[0], tgt[1] + off[1], tgt[2] + off[2]), tgt)
        sc.render.filepath = os.path.join(out, f"{act_name}_{frame}_{vn}.png")
        bpy.ops.render.render(write_still=True)
print("DONE")
