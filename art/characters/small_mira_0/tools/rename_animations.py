# python rename_animations.py <in.glb> <out.glb> : strip Blender ".NNN" suffixes from glTF animation names (JSON chunk only, binary untouched)
import json, re, struct, sys
src, dst = sys.argv[1], sys.argv[2]
b = open(src, "rb").read()
magic, ver, _ = struct.unpack("<4sII", b[:12]); assert magic == b"glTF" and ver == 2
jlen, jtype = struct.unpack("<II", b[12:20]); assert jtype == 0x4E4F534A
j = json.loads(b[20:20 + jlen]); rest = b[20 + jlen:]
names = []
for a in j.get("animations", []):
    new = re.sub(r"\.\d{3}$", "", a["name"]); names.append((a["name"], new)); a["name"] = new
assert len({n for _, n in names}) == len(names), "rename would collide"
js = json.dumps(j, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + len(rest)) + struct.pack("<II", len(js), 0x4E4F534A) + js + rest
open(dst, "wb").write(out)
for o, n in names: print(o, "->", n)
