"""Generates the Interaction Range parcel scenes (art/environments/authored/parcels/interaction_range_*.tscn).

The scenes are ordinary Godot scenes and are the source of truth once written; this script exists so the layout is reproducible and reviewable. Run from the project root:
    python docs/quality/evidence/interaction-range/build_range_scenes.py

The parcel contract allows only 16x16, 16x32 and 32x32 parcels (AuthoredParcelDefinition.validate), so the map is a 16 (x) by 32 (z) parcel; a cell's centre is its integer index, as in the other authored parcels.
The layout is DRAWN with x along the building (18 m) and z across it (9 m) and every position is swapped on the way out (P and S below): the world's x is the drawing's z.
Layout (cells; walls on cell lines so that each wall is one cell thick tactically and 0.3 m visually):
  * a 9 x 18 m building: walls on world x = 3 (west), x = 12 (east), z = 3 (north), z = 21 (south); the partition is the line z = 12;
  * two 8 x 8 cell rooms: A (north, rows 4..11) and B (south, rows 13..20), columns 4..11;
  * the partition has an ordinary door at column 7 (frame: Kenney structure-doorway, leaf: Kenney door.glb) and a separate window opening at column 10;
  * each room has an exterior doorway (no leaf) in its east wall: A at row 7, B at row 17, so there is a way round outside;
  * low crates (Kenney box-large) beside the door jambs and in the rooms.
Two scenes: the door leaf closed (a solid part in the opening) or open (swung 90 degrees into room B; the leaf is a thin solid part along its new position).
The tactical parts are explicit boxes, never inferred from the meshes (the kit's wall models report a 2 m deep box for a 0.2 m thick wall; see the report).
"""
import math, os

SCALE = 1.5               # the project's calibration of the Factory Kit (asset_calibrations.json)
WALL_H = 4.5              # 3.0 x 1.5
THICK = 1.0               # tactical wall thickness: one whole cell. A 0.3 m wall on a cell line leaves the cell standable at its edge (see the report), so the tactical part is a cell thick and only the visual is thin
VISUAL_THICK = 0.3        # the kit wall's real thickness (0.2 x 1.5)
OPEN_W = 1.2              # doorway opening width (0.8 x 1.5)
OPEN_H = 2.4              # doorway opening height (1.6 x 1.5)
WALL_PLANE = 0.9          # distance of the kit wall plane from the model's origin along its local +Z (0.6 x 1.5)
SILL_H = 1.25             # window sill: at least the 1.2 m full-cover threshold, so the sill blocks movement and the opening above it does not block a shot
WIN_TOP = 2.3

KIT = "res://art/environments/kenney/factory_kit/models/"
NL = "\n"


def v(x, y, z):
    return "Vector3(%g, %g, %g)" % (round(x, 4), round(y, 4), round(z, 4))


def P(x, z):
    return z, x


def S(sx, sz):
    return sz, sx


class Scene:
    def __init__(self):
        self.ext = {}
        self.body = []

    def res(self, name, path):
        self.ext[name] = path
        return name

    def add(self, *lines):
        self.body.append(NL.join(lines) + NL)

    def render(self):
        out = ["[gd_scene format=3]", ""]
        for name, path in self.ext.items():
            out.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (path, name))
        out.append("")
        out.append(NL.join(['[sub_resource type="StandardMaterial3D" id="yard_mat"]', "albedo_color = Color(0.26, 0.31, 0.32, 1)", "roughness = 0.92", ""]))
        out.append(NL.join(['[sub_resource type="PlaneMesh" id="yard_mesh"]', 'material = SubResource("yard_mat")', "size = Vector2(16, 32)", ""]))
        out.append(NL.join(['[sub_resource type="StandardMaterial3D" id="wall_mat"]', "albedo_color = Color(0.62, 0.6, 0.55, 1)", "roughness = 0.88", ""]))
        out.append(NL.join(['[sub_resource type="StandardMaterial3D" id="frame_mat"]', "albedo_color = Color(0.45, 0.47, 0.5, 1)", "roughness = 0.8", ""]))
        out.extend(self.body)
        return NL.join(out) + NL


def box_part(scene, parent, name, cx, cy, cz, sx, sy, sz, label, look=None):
    """A tactical box (a node with solid_size, read by the compiler) and, where no Kenney mesh stands for it, a plain visual of the same size. Drawing-frame arguments."""
    cx, cz = P(cx, cz)
    sx, sz = S(sx, sz)
    scene.add('[node name="%s" type="Node3D" parent="%s"]' % (name, parent), "position = %s" % v(cx, cy, cz), "metadata/solid_size = %s" % v(sx, sy, sz), "metadata/precise_shot_bounds = true", 'metadata/shot_label = "%s"' % label)
    if look:
        lx, lz = (min(sx, VISUAL_THICK), sz) if sx == THICK else (sx, min(sz, VISUAL_THICK)) if sz == THICK else (sx, sz)
        scene.add('[node name="Look" type="CSGBox3D" parent="%s/%s"]' % (parent, name), "size = %s" % v(lx, sy, lz), 'material = SubResource("%s")' % look)


def kit_piece(scene, parent, name, model, x, z, along_x):
    """A Kenney piece, scaled by the project calibration, whose wall plane lies on the line through (x, z); `along_x` is in the drawing's frame (before the swap)."""
    rid = scene.res(model, KIT + model + ".glb")
    x, z = P(x, z)
    along_x = not along_x   # the swap turns a wall along x into a wall along z
    if along_x:
        px, pz, yaw = x, z - WALL_PLANE, 0.0
    else:
        px, pz, yaw = x - WALL_PLANE, z, 90.0
    scene.add('[node name="%s" parent="%s" instance=ExtResource("%s")]' % (name, parent, rid), "position = %s" % v(px, 0, pz), "rotation = %s" % v(0, math.radians(yaw), 0), "scale = %s" % v(SCALE, SCALE, SCALE))


def wall_run(scene, parent, tag, fixed, start, end, along_x, openings, label, vstart=None, vend=None):
    """A wall on the line `fixed` from `start` to `end` with openings [(a, b, kind)] (kind: door, doorway, window): solid parts between the openings, a lintel over a door or doorway, a sill and a head at a
    window. Kenney pieces every 1.5 m (a doorway piece at each door or doorway, a plain wall piece elsewhere). A window is drawn with boxes: the kit's windows are glazed (no through-opening)."""
    cuts = sorted(openings, key=lambda o: o[0])
    cursor = start
    index = 0
    for a, b, kind in cuts + [(end, end, None)]:
        if a > cursor + 0.001:
            length = a - cursor
            mid = (cursor + a) / 2.0
            cx, cz = (mid, fixed) if along_x else (fixed, mid)
            sx, sz = (length, THICK) if along_x else (THICK, length)
            box_part(scene, parent, "%s_Solid%d" % (tag, index), cx, WALL_H / 2.0, cz, sx, WALL_H, sz, label)
            index += 1
        if kind is None:
            break
        mid = (a + b) / 2.0
        cx, cz = (mid, fixed) if along_x else (fixed, mid)
        width = b - a
        sx, sz = (width, THICK) if along_x else (THICK, width)
        if kind in ("door", "doorway"):
            box_part(scene, parent, "%s_Lintel%d" % (tag, index), cx, OPEN_H + (WALL_H - OPEN_H) / 2.0, cz, sx, WALL_H - OPEN_H, sz, label + " lintel")
        elif kind == "window":
            box_part(scene, parent, "%s_Sill%d" % (tag, index), cx, SILL_H / 2.0, cz, sx, SILL_H, sz, label + " window sill", look="frame_mat")
            box_part(scene, parent, "%s_WindowHead%d" % (tag, index), cx, WIN_TOP + (WALL_H - WIN_TOP) / 2.0, cz, sx, WALL_H - WIN_TOP, sz, label + " window head", look="frame_mat")
        index += 1
        cursor = b
    centres = []
    vstart = start if vstart is None else vstart
    vend = end if vend is None else vend
    p = vstart + 0.75
    while p < vend - 0.01:
        centres.append(p)
        p += 1.5
    for i, c in enumerate(centres):
        model = "structure-wall"
        for a, b, kind in cuts:
            if abs(c - (a + b) / 2.0) < 0.76:
                if kind in ("door", "doorway"):
                    model = "structure-doorway"
                    c = (a + b) / 2.0
                elif kind == "window":
                    model = None
        if model is None:
            continue
        cx, cz = (c, fixed) if along_x else (fixed, c)
        kit_piece(scene, parent, "%s_Piece%d" % (tag, i), model, cx, cz, along_x)


def cells(cs):
    return "Array[Vector3i]([%s])" % ", ".join("Vector3i(%d, 0, %d)" % P(*c) for c in cs)


def build(closed):
    s = Scene()
    pid = "interaction_range_closed" if closed else "interaction_range_open"
    s.add('[node name="InteractionRange" type="Node3D"]', 'metadata/parcel_id = &"%s"' % pid, 'metadata/parcel_role = &"interaction_range"', "metadata/revision = 1", "metadata/parcel_size = Vector2i(16, 32)", "metadata/allowed_rotations = PackedInt32Array(0)", "metadata/access_cell = Vector3i(8, 0, 31)", "metadata/access_direction = Vector2i(0, 1)", "metadata/access_width = 8", 'metadata/access_kind = &"range_entry"')
    s.add('[node name="Yard" type="MeshInstance3D" parent="."]', "position = Vector3(7.5, 0.004, 15.5)", "cast_shadow = 0", 'mesh = SubResource("yard_mesh")')
    s.add('[node name="Building" type="Node3D" parent="."]')
    # Drawing frame: the long walls run along x (z = 3 and z = 12), the short walls along z (x = 3 and x = 21), the partition is the line x = 12.
    wall_run(s, "Building", "WestWall", 3.0, 2.5, 21.5, True, [], "West wall", 2.85, 21.15)                                                       # world x = 3
    wall_run(s, "Building", "EastWall", 12.0, 2.5, 21.5, True, [(6.4, 7.6, "doorway"), (16.4, 17.6, "doorway")], "East wall", 2.85, 21.15)     # world x = 12
    wall_run(s, "Building", "NorthWall", 3.0, 3.0, 12.0, False, [], "North wall")                                                   # world z = 3
    wall_run(s, "Building", "SouthWall", 21.0, 3.0, 12.0, False, [], "South wall")                                                  # world z = 21
    wall_run(s, "Building", "Partition", 12.0, 3.0, 12.0, False, [(6.4, 7.6, "door"), (9.4, 10.6, "window")], "Partition")        # world z = 12
    # The door leaf (Kenney door.glb; its hinge is its local +x edge). Closed it fills the doorway on the partition line (world z = 12, x = 7); open it is swung 90 degrees about the hinge into room B.
    door = s.res("door", KIT + "door.glb")
    if closed:
        s.add('[node name="DoorLeaf" parent="Building" instance=ExtResource("door")]', "position = %s" % v(7.0, 0, 12.0), "rotation = %s" % v(0, 0, 0), "scale = %s" % v(SCALE, SCALE, SCALE))
        box_part(s, "Building", "DoorLeafSolid", 12.0, OPEN_H / 2.0, 7.0, THICK, OPEN_H, OPEN_W, "Closed door")   # fills the doorway's whole cell (one cell thick like the walls)
    else:
        # The hinge stays at world x = 7.6, z = 12; the leaf points into room B (+Z): yaw +90 degrees; its centre is 0.6 m along +Z from the hinge, so its drawing-frame position is (12.6, 7.6).
        s.add('[node name="DoorLeaf" parent="Building" instance=ExtResource("door")]', "position = %s" % v(7.6, 0, 12.6), "rotation = %s" % v(0, math.radians(90.0), 0), "scale = %s" % v(SCALE, SCALE, SCALE))
        box_part(s, "Building", "DoorLeafOpenSolid", 12.6, OPEN_H / 2.0, 7.6, OPEN_W, OPEN_H, 0.15, "Open door leaf")
    crate = s.res("crate", KIT + "box-large.glb")
    s.add('[node name="Cover" type="Node3D" parent="."]')
    for i, (cx, cz) in enumerate([(11, 5), (13, 9), (7, 9), (17, 6), (5, 11), (19, 11)]):
        wx, wz = P(cx, cz)
        s.add('[node name="Crate%d" type="Node3D" parent="Cover"]' % i, "position = %s" % v(wx, 0, wz), 'metadata/asset_id = "factory_kit/box-large"')
        s.add('[node name="Visual" parent="Cover/Crate%d" instance=ExtResource("crate")]' % i, "scale = Vector3(0.85, 0.85, 0.85)")
        s.add('[node name="TacticalVolume" type="Node3D" parent="Cover/Crate%d"]' % i, "position = Vector3(0, 0.24, 0)", "metadata/solid_size = Vector3(0.95, 0.48, 0.88)", "metadata/movement_cost = 2")
    s.add('[node name="MissionStations" type="Node3D" parent="."]')
    # Room A is the drawing's x 4..11 (world z 4..11, the north room); room B the drawing's x 13..20 (the south room). The drawing's z is the world x.
    s.add('[node name="PlayerDeployment" type="Node" parent="MissionStations"]', "metadata/deployment_faction = 0", "metadata/deployment_local_cells = %s" % cells([(5, 5), (5, 7), (6, 10), (8, 5), (8, 8)]))
    s.add('[node name="EnemyDeployment" type="Node" parent="MissionStations"]', "metadata/deployment_faction = 1", "metadata/deployment_local_cells = %s" % cells([(19, 5), (19, 7), (18, 10), (16, 5), (16, 8)]))
    s.add('[node name="AllyDeployment" type="Node" parent="MissionStations"]', "metadata/deployment_faction = 2", "metadata/deployment_local_cells = %s" % cells([(24, 4), (26, 4), (28, 4), (30, 4)]))
    s.add('[node name="Reach" type="Node" parent="MissionStations"]', 'metadata/objective_zone_id = &"reach"', "metadata/objective_local_cells = %s" % cells([(19, 9), (20, 9), (19, 10), (20, 10)]))
    s.add('[node name="Extract" type="Node" parent="MissionStations"]', 'metadata/objective_zone_id = &"extract"', "metadata/objective_local_cells = %s" % cells([(26, 7), (27, 7), (26, 8), (27, 8)]))
    s.add('[node name="EnemyExtract" type="Node" parent="MissionStations"]', 'metadata/objective_zone_id = &"enemy_extract"', "metadata/objective_local_cells = %s" % cells([(0, 7), (1, 7), (0, 8), (1, 8)]))
    s.add('[node name="RescueSpawn" type="Node" parent="MissionStations"]', 'metadata/objective_zone_id = &"rescue_spawn"', "metadata/objective_local_cells = %s" % cells([(5, 10)]))
    s.add('[node name="Terminal" type="Node" parent="MissionStations"]', 'metadata/objective_zone_id = &"terminal"', "metadata/objective_local_cells = %s" % cells([(20, 8)]))
    s.add('[node name="Signs" type="Node3D" parent="."]')
    for text, x, z in [("ROOM A", 7.5, 9.0), ("ROOM B", 16.5, 9.0), ("DOOR (%s)" % ("CLOSED" if closed else "OPEN"), 12.0, 7.0), ("WINDOW", 12.0, 10.0)]:
        wx, wz = P(x, z)
        s.add('[node name="Sign" type="Label3D" parent="Signs"]', "position = %s" % v(wx, 0.03, wz), "rotation = Vector3(-1.5707963, 0, 0)", "pixel_size = 0.012", "font_size = 32", "outline_size = 4", "modulate = Color(1, 0.88, 0.5, 1)", 'text = "%s"' % text)
    return s.render()


if __name__ == "__main__":
    root = os.getcwd()
    for closed, name in ((True, "interaction_range_closed"), (False, "interaction_range_open")):
        path = os.path.join(root, "art", "environments", "authored", "parcels", name + ".tscn")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(build(closed))
        print("wrote", path)
