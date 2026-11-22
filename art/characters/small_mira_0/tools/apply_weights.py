# blender --background --python apply_weights.py -- <in.glb> <audit.json> <decisions.json> <mode> <out>
#   mode=preview  -> <out> is a .blend-free dry run: writes island colour map PNGs + keeps nothing
#   mode=apply    -> <out> is the fixed .glb
import bpy, bmesh, sys, json, os
from collections import defaultdict
from mathutils import Vector
from mathutils.geometry import intersect_point_line

argv = sys.argv[sys.argv.index("--") + 1:]
src, audit_p, dec_p, mode, out = argv[0], argv[1], argv[2], argv[3], os.path.abspath(argv[4])
P = "mixamorig:"
MIN_W, MAX_INF = 0.02, 4
audit = {r["island"]: r for r in json.load(open(audit_p))["islands"]}
dec = json.load(open(dec_p))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
me = [o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)][0]
strays = [o for o in sc.objects if o.type == "MESH" and o is not me]

bm = bmesh.new(); bm.from_mesh(me.data); bm.verts.ensure_lookup_table()
seen = [False] * len(bm.verts); islands = []
for v in bm.verts:
    if seen[v.index]: continue
    stack = [v]; seen[v.index] = True; comp = []
    while stack:
        a = stack.pop(); comp.append(a.index)
        for e in a.link_edges:
            b = e.other_vert(a)
            if not seen[b.index]: seen[b.index] = True; stack.append(b)
    islands.append(comp)
assert len(islands) == len(audit), "island count changed"
for i, comp in enumerate(islands):
    assert len(comp) == audit[i]["verts"], f"island {i} vert count mismatch"

plan = {}
for bone, ids in dec["rigid"].items():
    for i in ids: assert i not in plan, i; plan[i] = ("rigid", [bone])
for bones, ids in dec["soft"].items():
    for i in ids: assert i not in plan, i; plan[i] = ("soft", bones.split(","))
for i, r in audit.items():  # fingers: rigid to dominant
    if i not in plan:
        dom = r["bones"][0][0]
        assert "Hand" in dom and not dom.endswith("Hand"), f"island {i} ({dom}) has no decision"
        plan[i] = ("rigid", [dom])

def ensure_group(name):
    return me.vertex_groups.get(P + name) or me.vertex_groups.new(name=P + name)

seg = {b.name: (arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones}
def seg_dist(co, bone):
    h, t = seg[P + bone]; p, f = intersect_point_line(co, h, t); f = min(max(f, 0), 1)
    return (co - (h + (t - h) * f)).length

gname = {g.index: g.name for g in me.vertex_groups}
new_w = {}
fallback = 0
for i, comp in enumerate(islands):
    kind, bones = plan[i]
    for vi in comp:
        if kind == "rigid":
            new_w[vi] = {bones[0]: 1.0}; continue
        v = me.data.vertices[vi]
        ws = {gname[g.group][len(P):]: g.weight for g in v.groups}
        kept = {b: ws.get(b, 0.0) for b in bones if ws.get(b, 0.0) > 0}
        if sum(kept.values()) < 1e-4:
            co = me.matrix_world @ v.co
            kept = {min(bones, key=lambda b: seg_dist(co, b)): 1.0}; fallback += 1
        top = sorted(kept.items(), key=lambda kv: -kv[1])[:MAX_INF]
        s = sum(w for _, w in top); top = [(b, w / s) for b, w in top if w / s >= MIN_W]
        s = sum(w for _, w in top)
        new_w[vi] = {b: w / s for b, w in top}

# rewrite all groups
all_idx = list(range(len(me.data.vertices)))
for g in me.vertex_groups: g.remove(all_idx)
for vi, ws in new_w.items():
    for b, w in ws.items(): ensure_group(b).add([vi], w, "REPLACE")

multi = sum(1 for ws in new_w.values() if sum(1 for w in ws.values() if w > 0.15) >= 2)
maxinf = max(len(ws) for ws in new_w.values())
print(f"RESULT verts={len(new_w)} multi>0.15={multi} max_inf={maxinf} fallback={fallback} strays={[o.name for o in strays]}")

if mode == "apply":
    for o in strays: bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
        export_animation_mode="ACTIONS", export_skins=True, export_all_influences=False,
        export_def_bones=False, export_yup=True)
    print("WROTE", out)
else:
    # colour map: rigid = per-bone colour, soft = white
    import colorsys, hashlib
    col = me.data.color_attributes.new("decision", "BYTE_COLOR", "POINT")
    for i, comp in enumerate(islands):
        kind, bones = plan[i]
        if kind == "soft": c = (1, 1, 1, 1)
        else:
            hsh = int(hashlib.md5(bones[0].encode()).hexdigest()[:6], 16)
            r, g, b = colorsys.hsv_to_rgb((hsh % 997) / 997, 0.65, 0.9); c = (r, g, b, 1)
        for vi in comp: col.data[vi].color = c
    me.data.color_attributes.active_color = col
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("WROTE", out)
