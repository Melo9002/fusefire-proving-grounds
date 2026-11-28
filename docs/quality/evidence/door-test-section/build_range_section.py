"""Adds (or regenerates) the Environmental Interaction section of the Tactical Test Range parcel (art/environments/authored/parcels/tactical_test_range.tscn).

The parcel scene stays the source of truth; this script only writes the block of nodes under `InteractionSection` (plus the resources it needs) so the layout is reproducible and reviewable. Run from the project root:
    python docs/quality/evidence/door-test-section/build_range_section.py

Layout (cells; world frame, a cell's centre is its integer index; the free block of the range is x 8..14, z 16..23, between the gallery ladders, the reference sedan and the static doorway station):
  * a small building: walls on x = 9 (west) and x = 13 (east), z = 17 (north) and z = 21 (south); interior 3 x 3 (x 10..12, z 18..20);
  * two independent doors with the 06.09 door implementation, the same geometry as the Interaction Range door: `door_north` at (11, 17) (its leaf swings outward, north, into the approach) and `door_south` at (11, 21)
    (its leaf swings inward, north, into the room): different swing sides on purpose, so both leaf-obstruction cases exist;
  * a static window aperture in the east wall at (13, 19): sill 1.25 m, head 2.3 m, never changes;
  * a one-cell ring of open ground around the building (x = 8 and x = 14, z = 16 and z = 22) and open ground beyond, so there are routes around it; a low crate inside at (10, 20).
Tactical parts are explicit boxes (one cell thick, as in the Interaction Range); the Kenney factory-kit wall, doorway and door models are the visuals.
"""
import math, os, re

SCALE = 1.5
WALL_H = 4.5
THICK = 1.0
VISUAL_THICK = 0.3
OPEN_W = 1.2
OPEN_H = 2.4
WALL_PLANE = 0.9
SILL_H = 1.25
WIN_TOP = 2.3
KIT = "res://art/environments/kenney/factory_kit/models/"
NL = "\n"
SECTION = "InteractionSection"

EXT = {
    "structure-wall": KIT + "structure-wall.glb",
    "structure-doorway": KIT + "structure-doorway.glb",
    "door": KIT + "door.glb",
}
SUBS = NL.join([
    '[sub_resource type="StandardMaterial3D" id="isec_frame_mat"]', "albedo_color = Color(0.45, 0.47, 0.5, 1)", "roughness = 0.8", ""])


def v(x, y, z):
    return "Vector3(%g, %g, %g)" % (round(x, 4), round(y, 4), round(z, 4))


class Block:
    def __init__(self):
        self.nodes = []

    def add(self, *lines):
        self.nodes.append(NL.join(lines) + NL)


def box_part(b, parent, name, cx, cy, cz, sx, sy, sz, label, look=None):
    b.add('[node name="%s" type="Node3D" parent="%s"]' % (name, parent), "position = %s" % v(cx, cy, cz), "metadata/solid_size = %s" % v(sx, sy, sz), "metadata/precise_shot_bounds = true", 'metadata/shot_label = "%s"' % label)
    if look:
        lx, lz = (min(sx, VISUAL_THICK), sz) if sx == THICK else (sx, min(sz, VISUAL_THICK)) if sz == THICK else (sx, sz)
        b.add('[node name="Look" type="CSGBox3D" parent="%s/%s"]' % (parent, name), "size = %s" % v(lx, sy, lz), 'material = SubResource("%s")' % look)


def kit_piece(b, parent, name, model, x, z, along_x):
    if along_x:
        px, pz, yaw = x, z - WALL_PLANE, 0.0
    else:
        px, pz, yaw = x - WALL_PLANE, z, 90.0
    b.add('[node name="%s" parent="%s" instance=ExtResource("%s")]' % (name, parent, model), "position = %s" % v(px, 0, pz), "rotation = %s" % v(0, math.radians(yaw), 0), "scale = %s" % v(SCALE, SCALE, SCALE))


def wall_run(b, parent, tag, fixed, start, end, along_x, openings, label, vstart=None, vend=None):
    cuts = sorted(openings, key=lambda o: o[0])
    cursor = start
    index = 0
    for a, c, kind in cuts + [(end, end, None)]:
        if a > cursor + 0.001:
            length = a - cursor
            mid = (cursor + a) / 2.0
            cx, cz = (mid, fixed) if along_x else (fixed, mid)
            sx, sz = (length, THICK) if along_x else (THICK, length)
            box_part(b, parent, "%s_Solid%d" % (tag, index), cx, WALL_H / 2.0, cz, sx, WALL_H, sz, label)
            index += 1
        if kind is None:
            break
        mid = (a + c) / 2.0
        cx, cz = (mid, fixed) if along_x else (fixed, mid)
        width = c - a
        sx, sz = (width, THICK) if along_x else (THICK, width)
        if kind in ("door", "doorway"):
            box_part(b, parent, "%s_Lintel%d" % (tag, index), cx, OPEN_H + (WALL_H - OPEN_H) / 2.0, cz, sx, WALL_H - OPEN_H, sz, label + " lintel")
        elif kind == "window":
            box_part(b, parent, "%s_Sill%d" % (tag, index), cx, SILL_H / 2.0, cz, sx, SILL_H, sz, label + " window sill", look="isec_frame_mat")
            box_part(b, parent, "%s_WindowHead%d" % (tag, index), cx, WIN_TOP + (WALL_H - WIN_TOP) / 2.0, cz, sx, WALL_H - WIN_TOP, sz, label + " window head", look="isec_frame_mat")
        index += 1
        cursor = c
    vstart = start if vstart is None else vstart
    vend = end if vend is None else vend
    p = vstart + 0.75
    centres = []
    while p < vend - 0.01:
        centres.append(p)
        p += 1.5
    for i, c in enumerate(centres):
        model = "structure-wall"
        for a, d, kind in cuts:
            if abs(c - (a + d) / 2.0) < 0.76:
                if kind in ("door", "doorway"):
                    model = "structure-doorway"
                    c = (a + d) / 2.0
                elif kind == "window":
                    model = None
        if model is None:
            continue
        cx, cz = (c, fixed) if along_x else (fixed, c)
        kit_piece(b, parent, "%s_Piece%d" % (tag, i), model, cx, cz, along_x)


def door(b, parent, door_id, dx, dz, label):
    """The same door as the Interaction Range's, translated to the doorway cell (dx, dz): hinge on the leaf's +x edge, swing about 100 degrees toward -z (an open leaf whose bounding box is the open part)."""
    hx, hz = dx + 0.6, float(dz)
    b.add('[node name="Door_%s" type="Node3D" parent="%s"]' % (door_id, parent), 'metadata/door_id = &"%s"' % door_id, "metadata/door_cell_local = Vector3i(%d, 0, %d)" % (dx, dz), 'metadata/door_initial_state = &"closed"',
          "metadata/door_hinge_local = %s" % v(hx, 0, hz), "metadata/door_swing_radius = 1.2", "metadata/door_swing_from_deg = 180.0", "metadata/door_swing_to_deg = 280.0")
    me = "%s/Door_%s" % (parent, door_id)
    b.add('[node name="Leaf" parent="%s" instance=ExtResource("door")]' % me, "position = %s" % v(dx, 0, dz), "rotation = Vector3(0, 0, 0)", "scale = %s" % v(SCALE, SCALE, SCALE), 'metadata/door_visual_id = &"%s"' % door_id)
    b.add('[node name="ClosedLeaf" type="Node3D" parent="%s"]' % me, "position = %s" % v(dx, OPEN_H / 2.0, dz), "metadata/solid_size = %s" % v(OPEN_W, OPEN_H, THICK), "metadata/precise_shot_bounds = true", 'metadata/shot_label = "Closed door"',
          'metadata/door_id = &"%s"' % door_id, 'metadata/door_state = &"closed"')
    direction = (math.cos(math.radians(280.0)), math.sin(math.radians(280.0)))
    ox, oz = hx + 0.6 * direction[0], hz + 0.6 * direction[1]
    sx = OPEN_W * abs(direction[0]) + 0.15 * abs(direction[1])
    sz = OPEN_W * abs(direction[1]) + 0.15 * abs(direction[0])
    b.add('[node name="OpenLeaf" type="Node3D" parent="%s"]' % me, "position = %s" % v(ox, OPEN_H / 2.0, oz), "metadata/solid_size = %s" % v(sx, OPEN_H, sz), "metadata/precise_shot_bounds = true", 'metadata/shot_label = "Open door leaf"',
          'metadata/door_id = &"%s"' % door_id, 'metadata/door_state = &"open"')


def build_block():
    b = Block()
    b.add('[node name="%s" type="Node3D" parent="."]' % SECTION)
    b.add('[node name="Building" type="Node3D" parent="%s"]' % SECTION)
    parent = "%s/Building" % SECTION
    wall_run(b, parent, "WestWall", 9.0, 16.5, 21.5, False, [], "West wall", 16.85, 21.15)
    wall_run(b, parent, "EastWall", 13.0, 16.5, 21.5, False, [(18.4, 19.6, "window")], "East wall", 16.85, 21.15)
    wall_run(b, parent, "NorthWall", 17.0, 9.0, 13.0, True, [(10.4, 11.6, "door")], "North wall")
    wall_run(b, parent, "SouthWall", 21.0, 9.0, 13.0, True, [(10.4, 11.6, "door")], "South wall")
    door(b, parent, "door_north", 11, 17, "North door")
    door(b, parent, "door_south", 11, 21, "South door")
    b.add('[node name="Cover" type="Node3D" parent="%s"]' % SECTION)
    b.add('[node name="Crate10_20" type="Node3D" parent="%s/Cover"]' % SECTION, "position = %s" % v(10, 0, 20), 'metadata/asset_id = "factory_kit/box-large"')
    b.add('[node name="Visual" parent="%s/Cover/Crate10_20" instance=ExtResource("crate")]' % SECTION, "scale = Vector3(0.85, 0.85, 0.85)")
    b.add('[node name="TacticalVolume" type="Node3D" parent="%s/Cover/Crate10_20"]' % SECTION, "position = Vector3(0, 0.24, 0)", "metadata/solid_size = Vector3(0.95, 0.48, 0.88)", "metadata/movement_cost = 2")
    b.add('[node name="Sign" type="Label3D" parent="%s"]' % SECTION, "position = %s" % v(11, 0.019, 23.5), "rotation = Vector3(-1.5707963, 0, 0)", "pixel_size = 0.017", "font_size = 32", "outline_size = 0",
          "modulate = Color(0.91, 0.88, 0.72, 1)", 'text = "11  DOORS  /  WINDOW"')
    return NL.join(b.nodes)


def regenerate(text):
    """Remove any previous generated section, then add the ext/sub resources and the node block."""
    blocks = re.split(r"(?m)^(?=\[)", text)
    kept = []
    for blk in blocks:
        if re.match(r'\[node name="%s" ' % SECTION, blk) or re.match(r'\[node name="[^"]+" (?:type="[^"]+" )?parent="%s[/"]' % SECTION, blk) or re.match(r'\[node name="[^"]+" parent="%s[/"]' % SECTION, blk):
            continue
        if re.match(r'\[sub_resource type="StandardMaterial3D" id="isec_frame_mat"\]', blk):
            continue
        if re.match(r'\[ext_resource [^\]]*id="(structure-wall|structure-doorway|door)"\]', blk):
            continue
        kept.append(blk)
    text = "".join(kept).rstrip("\n") + "\n"
    ext_lines = "".join('[ext_resource type="PackedScene" path="%s" id="%s"]\n' % (path, name) for name, path in EXT.items())
    first_sub = text.index("[sub_resource")
    text = text[:first_sub] + ext_lines + "\n" + text[first_sub:]
    first_node = text.index("[node name=")
    text = text[:first_node] + SUBS + NL + text[first_node:]
    return text.rstrip("\n") + "\n\n" + build_block().rstrip("\n") + "\n"


if __name__ == "__main__":
    path = os.path.join(os.getcwd(), "art", "environments", "authored", "parcels", "tactical_test_range.tscn")
    with open(path, encoding="utf-8", newline="") as f:
        original = f.read()
    crlf = "\r\n" in original
    out = regenerate(original.replace("\r\n", "\n"))
    out = re.sub(r"metadata/revision = \d+", lambda m: "metadata/revision = 4", out, count=1)
    with open(path, "w", encoding="utf-8", newline="\r\n" if crlf else "\n") as f:
        f.write(out)
    print("wrote", path)
