import bpy
import math
import json
from mathutils import Vector
from pathlib import Path

PROJECT = Path(r"C:\Users\Blue\Documents\Codex\git\fusefire-proving-grounds")
SOURCE = PROJECT / "art/characters/android_test_dummy/source/android_test_dummy_rigprep.blend"
BLEND_OUT = PROJECT / "art/characters/android_test_dummy/source/android_test_dummy_rigged.blend"
GLB_OUT = PROJECT / "art/characters/android_test_dummy/models/android_test_dummy_rigged.glb"
REPORT_OUT = PROJECT / "art/characters/android_test_dummy/source/RIG_REPORT.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
body = bpy.data.objects.get("AndroidTestDummy_RigMesh")
if body is None:
    body = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")

# Armature coordinates follow the 1.60 m mesh in Blender Z-up space.
bones = {
    "Root": ((0.0, 0.0, 0.02), (0.0, -0.10, 0.02), None, False),
    "Pelvis": ((0.0, 0.0, 0.76), (0.0, 0.0, 0.92), "Root", True),
    "Spine": ((0.0, 0.0, 0.92), (0.0, 0.0, 1.10), "Pelvis", True),
    "Chest": ((0.0, 0.0, 1.10), (0.0, 0.0, 1.30), "Spine", True),
    "Neck": ((0.0, 0.0, 1.30), (0.0, 0.0, 1.39), "Chest", True),
    "Head": ((0.0, 0.0, 1.39), (0.0, 0.0, 1.58), "Neck", True),
    "Clavicle.L": ((0.035, 0.0, 1.27), (0.19, 0.0, 1.27), "Chest", True),
    "UpperArm.L": ((0.19, 0.0, 1.27), (0.275, 0.0, 1.06), "Clavicle.L", True),
    "Forearm.L": ((0.275, 0.0, 1.06), (0.325, 0.0, 0.86), "UpperArm.L", True),
    "Hand.L": ((0.325, 0.0, 0.86), (0.337, -0.005, 0.75), "Forearm.L", True),
    "Clavicle.R": ((-0.035, 0.0, 1.27), (-0.19, 0.0, 1.27), "Chest", True),
    "UpperArm.R": ((-0.19, 0.0, 1.27), (-0.275, 0.0, 1.06), "Clavicle.R", True),
    "Forearm.R": ((-0.275, 0.0, 1.06), (-0.325, 0.0, 0.86), "UpperArm.R", True),
    "Hand.R": ((-0.325, 0.0, 0.86), (-0.337, -0.005, 0.75), "Forearm.R", True),
    "Thigh.L": ((0.115, 0.0, 0.79), (0.12, 0.0, 0.48), "Pelvis", True),
    "Shin.L": ((0.12, 0.0, 0.48), (0.12, 0.0, 0.14), "Thigh.L", True),
    "Foot.L": ((0.12, 0.0, 0.14), (0.12, -0.105, 0.055), "Shin.L", True),
    "Toe.L": ((0.12, -0.105, 0.055), (0.12, -0.205, 0.045), "Foot.L", True),
    "Thigh.R": ((-0.115, 0.0, 0.79), (-0.12, 0.0, 0.48), "Pelvis", True),
    "Shin.R": ((-0.12, 0.0, 0.48), (-0.12, 0.0, 0.14), "Thigh.R", True),
    "Foot.R": ((-0.12, 0.0, 0.14), (-0.12, -0.105, 0.055), "Shin.R", True),
    "Toe.R": ((-0.12, -0.105, 0.055), (-0.12, -0.205, 0.045), "Foot.R", True),
    "hand_ik.L": ((0.325, 0.0, 0.86), (0.325, -0.10, 0.86), "Root", False),
    "hand_ik.R": ((-0.325, 0.0, 0.86), (-0.325, -0.10, 0.86), "Root", False),
    "weapon_socket_r": ((-0.337, -0.005, 0.79), (-0.337, -0.16, 0.79), "Hand.R", False),
    "carry_socket": ((0.0, 0.055, 1.18), (0.0, 0.18, 1.18), "Chest", False),
}

bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
armature = bpy.context.object
armature.name = "AndroidTestDummy_Armature"
armature.data.name = "AndroidTestDummy_Skeleton"
armature.data.display_type = "BBONE"
armature.show_in_front = True
armature.data.edit_bones.remove(armature.data.edit_bones[0])

for name, (head, tail, _parent, deform) in bones.items():
    bone = armature.data.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    bone.use_deform = deform

for name, (_head, _tail, parent_name, _deform) in bones.items():
    if parent_name:
        armature.data.edit_bones[name].parent = armature.data.edit_bones[parent_name]

bpy.ops.object.mode_set(mode="OBJECT")

deform_names = [name for name, (_h, _t, _p, deform) in bones.items() if deform]
segments = {name: (Vector(bones[name][0]), Vector(bones[name][1])) for name in deform_names}


def point_segment_distance(point, start, end):
    direction = end - start
    length_squared = direction.length_squared
    if length_squared == 0.0:
        return (point - start).length
    amount = max(0.0, min(1.0, (point - start).dot(direction) / length_squared))
    return (point - (start + direction * amount)).length


def adjusted_distance(point, bone_name):
    distance = point_segment_distance(point, *segments[bone_name])
    # Prevent weights from crossing the body centre except at the axial skeleton.
    if bone_name.endswith(".L") and point.x < -0.015:
        distance += 0.35
    elif bone_name.endswith(".R") and point.x > 0.015:
        distance += 0.35
    # Keep central torso vertices on the axial chain rather than nearby limbs.
    if abs(point.x) < 0.075 and (bone_name.endswith(".L") or bone_name.endswith(".R")):
        distance += 0.18
    return distance


# Build connected components. Small generated armor pieces receive one rigid weight;
# larger undersuit/body shells receive smooth weights between their nearest bones.
adjacency = [[] for _ in body.data.vertices]
for edge in body.data.edges:
    a, b = edge.vertices
    adjacency[a].append(b)
    adjacency[b].append(a)
remaining = set(range(len(body.data.vertices)))
components = []
while remaining:
    seed = remaining.pop()
    stack = [seed]
    component = [seed]
    while stack:
        current = stack.pop()
        for neighbor in adjacency[current]:
            if neighbor in remaining:
                remaining.remove(neighbor)
                stack.append(neighbor)
                component.append(neighbor)
    components.append(component)

for group in list(body.vertex_groups):
    body.vertex_groups.remove(group)
groups = {name: body.vertex_groups.new(name=name) for name in deform_names}

rigid_components = 0
smooth_components = 0
for component in components:
    if len(component) <= 24:
        centroid = sum((body.data.vertices[index].co for index in component), Vector()) / len(component)
        ranked = sorted((adjusted_distance(centroid, name), name) for name in deform_names)[:3]
        raw = [(math.exp(-distance * 32.0), name) for distance, name in ranked]
        total = sum(weight for weight, _name in raw)
        for weight, name in raw:
            normalized = weight / total if total > 1e-8 else (1.0 if name == ranked[0][1] else 0.0)
            if normalized >= 0.015:
                groups[name].add(component, normalized, "REPLACE")
        rigid_components += 1
        continue
    smooth_components += 1
    for index in component:
        point = body.data.vertices[index].co
        ranked = sorted((adjusted_distance(point, name), name) for name in deform_names)[:3]
        # Strong falloff keeps armor stable while blending naturally at shared joints.
        raw = [(math.exp(-distance * 32.0), name) for distance, name in ranked]
        total = sum(weight for weight, _name in raw)
        if total <= 1e-8:
            groups[ranked[0][1]].add([index], 1.0, "REPLACE")
        else:
            for weight, name in raw:
                normalized = weight / total
                if normalized >= 0.015:
                    groups[name].add([index], normalized, "REPLACE")

modifier = body.modifiers.new(name="AndroidHumanoidSkin", type="ARMATURE")
modifier.object = armature
modifier.use_vertex_groups = True
body.parent = armature
body.matrix_parent_inverse = armature.matrix_world.inverted()

armature["fusefire_rig_version"] = "26C-v1"
armature["fusefire_height_m"] = 1.6
armature["fusefire_forward_axis"] = "-Y"
armature["fusefire_socket_weapon"] = "weapon_socket_r"
armature["fusefire_socket_carry"] = "carry_socket"

bpy.context.view_layer.objects.active = armature
armature.select_set(True)
body.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
bpy.ops.export_scene.gltf(
    filepath=str(GLB_OUT),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_animations=True,
)

report = {
    "bones_total": len(bones),
    "deform_bones": len(deform_names),
    "control_and_socket_bones": len(bones) - len(deform_names),
    "vertices": len(body.data.vertices),
    "weighted_vertices": sum(1 for vertex in body.data.vertices if len(vertex.groups) > 0),
    "connected_components": len(components),
    "rigid_weighted_components": rigid_components,
    "smooth_weighted_components": smooth_components,
    "weapon_socket": "weapon_socket_r",
    "left_hand_ik": "hand_ik.L",
    "right_hand_ik": "hand_ik.R",
    "carry_socket": "carry_socket",
    "output_glb": str(GLB_OUT.relative_to(PROJECT)),
    "output_blend": str(BLEND_OUT.relative_to(PROJECT)),
}
REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("DUMMY_RIG=" + json.dumps(report))
