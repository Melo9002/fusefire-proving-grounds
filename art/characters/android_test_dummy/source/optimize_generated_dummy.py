import bpy
from pathlib import Path
from mathutils import Vector

root = Path(r"C:\Users\Blue\Documents\Codex\asset making\test dummy\generation")
source = root / "base_basic_pbr.glb"
out = root / "review"
out.mkdir(exist_ok=True)
source_height = 1.8987271785736084


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    model = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    model.scale *= 1.6 / source_height
    bpy.context.view_layer.objects.active = model
    model.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.context.view_layer.update()
    bpy.ops.mesh.primitive_plane_add(size=5, location=(0, 0, -0.005))
    floor = bpy.context.object
    floor.name = "Review Floor"
    floor_mat = bpy.data.materials.new("Review Floor")
    floor_mat.diffuse_color = (0.035, 0.045, 0.06, 1)
    floor.data.materials.append(floor_mat)
    for name, location, energy, size in [
        ("Key", (-2.4, -3.2, 3.4), 950, 3.0),
        ("Fill", (2.6, -1.0, 2.3), 550, 2.2),
        ("Rim", (1.8, 2.5, 3.0), 850, 2.5),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        aim(light, (0, 0, 0.9))
    bpy.ops.object.camera_add(location=(2.6, -4, 1.55))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.82
    aim(camera, (0, 0, 0.8))
    scene = bpy.context.scene
    scene.camera = camera
    scene.world = bpy.data.worlds.new("Review World")
    scene.world.color = (0.015, 0.02, 0.03)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1200
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    return model, scene


for label, ratio in [("100k", 0.20), ("50k", 0.10), ("25k", 0.05)]:
    model, scene = setup_scene()
    modifier = model.modifiers.new(name="Prototype triangle reduction", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    modifier.use_symmetry = True
    bpy.context.view_layer.objects.active = model
    model.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    minimum_z = min(vertex.co.z for vertex in model.data.vertices)
    maximum_z = max(vertex.co.z for vertex in model.data.vertices)
    height_scale = 1.6 / (maximum_z - minimum_z)
    for vertex in model.data.vertices:
        vertex.co.z = (vertex.co.z - minimum_z) * height_scale
    model.data.update()
    model.data.calc_loop_triangles()
    triangles = len(model.data.loop_triangles)
    model["optimization_source"] = source.name
    model["optimization_method"] = "Blender collapse decimation; UVs preserved"
    model["triangles"] = triangles
    model["height_m"] = 1.6
    scene.render.filepath = str(out / f"generated_dummy_{label}.png")
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(root / f"generated_dummy_{label}_160cm.blend"))
    # Export only the character, excluding review camera, lights, and floor.
    bpy.ops.object.select_all(action="DESELECT")
    model.select_set(True)
    bpy.context.view_layer.objects.active = model
    bpy.ops.export_scene.gltf(
        filepath=str(root / f"generated_dummy_{label}_160cm.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print(f"OPTIMIZED_{label.upper()}={triangles}")
