# Headless audit: blender --background --python audit_islands.py -- <in.glb> <out.json>
import bpy, bmesh, sys, json
from collections import defaultdict
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
print("MESHES", [(m.name, len(m.data.vertices)) for m in meshes])
print("ACTIONS", [a.name for a in bpy.data.actions])
me = meshes[0]
vg = {g.index: g.name for g in me.vertex_groups}
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
res = []
multi_total = 0
for i, comp in enumerate(islands):
    tot = defaultdict(float); multi = 0; maxinf = 0
    lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
    for vi in comp:
        v = me.data.vertices[vi]
        co = me.matrix_world @ v.co
        lo = Vector(map(min, lo, co)); hi = Vector(map(max, hi, co))
        ws = [(vg[g.group], g.weight) for g in v.groups if g.weight > 0.001]
        maxinf = max(maxinf, len(ws))
        if sum(1 for _, w in ws if w > 0.15) >= 2: multi += 1
        for n, w in ws: tot[n] += w
    s = sum(tot.values()) or 1
    ranked = sorted(tot.items(), key=lambda kv: -kv[1])
    multi_total += multi
    res.append(dict(island=i, verts=len(comp), center=[round(c,3) for c in (lo+hi)/2],
        size=[round(c,3) for c in hi-lo], bones=[(n.replace("mixamorig:",""), round(w/s,3)) for n,w in ranked[:4]],
        dominant_share=round(ranked[0][1]/s,3) if ranked else 0, multi_verts=multi, max_influences=maxinf))
res.sort(key=lambda r: -r["verts"])
json.dump(dict(total_verts=len(me.data.vertices), islands=res, multi_total=multi_total,
    bones=[b.name for b in arm.data.bones], actions=[a.name for a in bpy.data.actions]), open(out,"w"), indent=1)
print("ISLANDS", len(islands), "MULTI", multi_total)
