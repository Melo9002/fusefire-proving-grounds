"""Build the original FuseFire block mannequin and rifle research proxies.

Run from the repository root:
  blender --background --factory-startup --python art/research/proxies/source/build_proxy_kit.py

The generated assets contain no textures or third-party geometry.
"""

from pathlib import Path
import json

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[4]
SOURCE_DIR = PROJECT / "art" / "research" / "proxies" / "source"
MODEL_DIR = PROJECT / "art" / "research" / "proxies" / "models"
BLEND_OUT = SOURCE_DIR / "fusefire_proxy_kit.blend"
BODY_OUT = MODEL_DIR / "fusefire_animation_proxy.glb"
RIFLE_OUT = MODEL_DIR / "fusefire_rifle_proxy.glb"
REPORT_OUT = SOURCE_DIR / "PROXY_KIT_REPORT.json"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name: str, color: tuple[float, float, float, float]):
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    result.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = color
    result.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.82
    return result


def cube(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    target_collection,
    surface,
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(surface)
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    target_collection.objects.link(obj)
    return obj


def empty(name: str, location: tuple[float, float, float], parent, display: str = "PLAIN_AXES"):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display
    obj.empty_display_size = 0.055
    obj.location = location
    obj.parent = parent
    parent.users_collection[0].objects.link(obj)
    return obj


def add_bone(edit_bones, name: str, head, tail, parent=None):
    bone = edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    bone.parent = parent
    bone.use_connect = False
    return bone


def create_armature(collection):
    armature_data = bpy.data.armatures.new("FuseFireProxySkeleton")
    armature = bpy.data.objects.new("Armature", armature_data)
    collection.objects.link(armature)
    armature.show_in_front = True
    armature["fusefire_original_proxy"] = True
    armature["height_m"] = 1.60
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = armature_data.edit_bones

    root = add_bone(bones, "mixamorig_Root", (0, 0, 0), (0, 0, 0.10))
    hips = add_bone(bones, "mixamorig_Hips", (0, 0, 0.80), (0, 0, 0.94), root)
    spine = add_bone(bones, "mixamorig_Spine", (0, 0, 0.91), (0, 0, 1.08), hips)
    spine1 = add_bone(bones, "mixamorig_Spine1", (0, 0, 1.08), (0, 0, 1.22), spine)
    spine2 = add_bone(bones, "mixamorig_Spine2", (0, 0, 1.22), (0, 0, 1.34), spine1)
    neck = add_bone(bones, "mixamorig_Neck", (0, 0, 1.34), (0, 0, 1.43), spine2)
    add_bone(bones, "mixamorig_Head", (0, 0, 1.43), (0, 0, 1.59), neck)

    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        shoulder = add_bone(
            bones,
            f"mixamorig_{side}Shoulder",
            (0.06 * sign, 0, 1.32),
            (0.22 * sign, 0, 1.32),
            spine2,
        )
        upper_arm = add_bone(
            bones,
            f"mixamorig_{side}Arm",
            (0.22 * sign, 0, 1.32),
            (0.47 * sign, 0, 1.27),
            shoulder,
        )
        forearm = add_bone(
            bones,
            f"mixamorig_{side}ForeArm",
            (0.47 * sign, 0, 1.27),
            (0.68 * sign, 0, 1.22),
            upper_arm,
        )
        add_bone(
            bones,
            f"mixamorig_{side}Hand",
            (0.68 * sign, 0, 1.22),
            (0.78 * sign, 0, 1.20),
            forearm,
        )
        upper_leg = add_bone(
            bones,
            f"mixamorig_{side}UpLeg",
            (0.11 * sign, 0, 0.84),
            (0.11 * sign, 0, 0.48),
            hips,
        )
        leg = add_bone(
            bones,
            f"mixamorig_{side}Leg",
            (0.11 * sign, 0, 0.48),
            (0.11 * sign, 0, 0.12),
            upper_leg,
        )
        foot = add_bone(
            bones,
            f"mixamorig_{side}Foot",
            (0.11 * sign, 0, 0.12),
            (0.11 * sign, -0.13, 0.06),
            leg,
        )
        add_bone(
            bones,
            f"mixamorig_{side}ToeBase",
            (0.11 * sign, -0.13, 0.06),
            (0.11 * sign, -0.24, 0.04),
            foot,
        )

    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def rigid_skin(obj, armature, bone_name: str) -> None:
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature
    obj.parent = armature


def create_character_proxy(proxy_material):
    collection = bpy.data.collections.new("FuseFireAnimationProxy")
    bpy.context.scene.collection.children.link(collection)
    armature = create_armature(collection)

    pieces = [
        ("PelvisBlock", (0, 0, 0.82), (0.32, 0.20, 0.18), "mixamorig_Hips"),
        ("TorsoBlock", (0, 0, 1.15), (0.40, 0.22, 0.42), "mixamorig_Spine1"),
        ("HeadBlock", (0, 0, 1.49), (0.22, 0.20, 0.24), "mixamorig_Head"),
    ]
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        pieces.extend(
            [
                (f"{side}UpperArmBlock", (0.35 * sign, 0, 1.295), (0.25, 0.13, 0.14), f"mixamorig_{side}Arm"),
                (f"{side}ForeArmBlock", (0.575 * sign, 0, 1.245), (0.21, 0.11, 0.12), f"mixamorig_{side}ForeArm"),
                (f"{side}HandBlock", (0.73 * sign, -0.005, 1.21), (0.11, 0.09, 0.10), f"mixamorig_{side}Hand"),
                (f"{side}ThighBlock", (0.11 * sign, 0, 0.62), (0.17, 0.20, 0.36), f"mixamorig_{side}UpLeg"),
                (f"{side}ShinBlock", (0.11 * sign, 0, 0.30), (0.14, 0.16, 0.34), f"mixamorig_{side}Leg"),
                (f"{side}FootBlock", (0.11 * sign, -0.10, 0.08), (0.16, 0.30, 0.13), f"mixamorig_{side}Foot"),
            ]
        )
    body_objects = []
    for name, location, dimensions, bone in pieces:
        obj = cube(name, location, dimensions, collection, proxy_material)
        rigid_skin(obj, armature, bone)
        body_objects.append(obj)

    label = empty("FUSEFIRE_ORIGINAL_PROXY", (0, 0.12, 1.72), armature, "CUBE")
    label["purpose"] = "Original block mannequin for animation and socket experiments"
    return collection, armature, body_objects


def create_rifle_proxy(proxy_material, marker_material):
    collection = bpy.data.collections.new("FuseFireRifleProxy")
    bpy.context.scene.collection.children.link(collection)
    root = bpy.data.objects.new("WeaponOrigin", None)
    root.empty_display_type = "ARROWS"
    root.empty_display_size = 0.07
    root["fusefire_original_proxy"] = True
    root["forward_axis_blender"] = "-Y"
    collection.objects.link(root)

    parts = [
        ("Receiver", (0, -0.19, 0.00), (0.12, 0.34, 0.15)),
        ("Barrel", (0, -0.48, 0.025), (0.055, 0.30, 0.055)),
        ("Stock", (0, 0.10, 0.015), (0.11, 0.24, 0.13)),
        ("Grip", (0, -0.045, -0.105), (0.075, 0.10, 0.20)),
        ("Sight", (0, -0.20, 0.11), (0.07, 0.13, 0.06)),
    ]
    objects = []
    for name, location, dimensions in parts:
        obj = cube(name, location, dimensions, collection, proxy_material)
        obj.parent = root
        objects.append(obj)

    contacts = {
        "GripReference": (0, 0, 0),
        "SupportHandTarget": (0, -0.30, -0.02),
        "MuzzleSocket": (0, -0.64, 0.025),
        "SightReference": (0, -0.20, 0.14),
        "ButtstockContact": (0, 0.22, 0.015),
    }
    marker_objects = []
    for name, location in contacts.items():
        marker = empty(name, location, root, "SPHERE" if name != "MuzzleSocket" else "ARROWS")
        marker["fusefire_contact"] = True
        marker_objects.append(marker)

    label = empty("FUSEFIRE_ORIGINAL_PROXY", (0, -0.18, 0.25), root, "CUBE")
    label["purpose"] = "Original block rifle for grip, support hand, muzzle, sight, and stock tests"
    marker_objects.append(label)
    return collection, root, objects, marker_objects, contacts


def select_objects(objects) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def export_glb(path: Path, objects) -> None:
    select_objects(objects)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=True,
        export_skins=True,
        export_yup=True,
    )


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    proxy_material = material("ProxyNeutral", (0.25, 0.29, 0.34, 1.0))
    marker_material = material("ProxyMarker", (0.0, 0.85, 1.0, 1.0))
    _, armature, body_objects = create_character_proxy(proxy_material)
    _, rifle_root, rifle_objects, rifle_markers, contacts = create_rifle_proxy(proxy_material, marker_material)

    export_glb(BODY_OUT, [armature, *body_objects])
    export_glb(RIFLE_OUT, [rifle_root, *rifle_objects, *rifle_markers])

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    report = {
        "license": "Original FuseFire proxy generated in-repository; no third-party geometry or textures",
        "character_height_m": 1.60,
        "character_bones": [bone.name for bone in armature.data.bones],
        "weapon_forward_axis_blender": "-Y",
        "weapon_contacts_blender_m": contacts,
        "blend": str(BLEND_OUT.relative_to(PROJECT)),
        "character_glb": str(BODY_OUT.relative_to(PROJECT)),
        "rifle_glb": str(RIFLE_OUT.relative_to(PROJECT)),
    }
    REPORT_OUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
