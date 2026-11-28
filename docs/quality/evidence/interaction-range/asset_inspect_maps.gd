extends SceneTree
## Third look: (a) where in Z the wall pieces' vertices lie (how thick is the wall itself: the models report 2 m of depth), (b) an ASCII hit map of rays along +Z through the doorway and window pieces, x across and y up
## (# = something is in the way somewhere along the ray, . = nothing), so the real openings, the glazing and the bars can be read directly.
##   godot_console --headless --path . --script res://docs/quality/evidence/interaction-range/asset_inspect_maps.gd
const DIR := "res://art/environments/kenney/factory_kit/models/"


func _initialize() -> void:
	for name in ["structure-wall", "structure-doorway", "structure-doorway-wide", "structure-window", "structure-window-wide"]:
		var root := (load(DIR + name + ".glb") as PackedScene).instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		print("== %s ==" % name)
		_z_histogram(mi)
		_map(mi, name)
		root.free()
	quit()


func _triangles(mi: MeshInstance3D) -> Array:
	var tris: Array = []
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var count: int = (idx.size() if idx != null else verts.size()) / 3
	for t in count:
		tris.append([verts[idx[t * 3] if idx != null else t * 3], verts[idx[t * 3 + 1] if idx != null else t * 3 + 1], verts[idx[t * 3 + 2] if idx != null else t * 3 + 2]])
	return tris


func _z_histogram(mi: MeshInstance3D) -> void:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bins := {}
	for v in verts:
		var key := snappedf(v.z, 0.05)
		bins[key] = int(bins.get(key, 0)) + 1
	var keys := bins.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%.2f:%d" % [k, bins[k]])
	print("  vertices by z: ", " ".join(parts))


func _map(mi: MeshInstance3D, name: String) -> void:
	var tris := _triangles(mi)
	var lines := []
	var y := 2.95
	while y > 0.0:
		var row := ""
		var x := -0.975 if name.contains("wide") else -0.475
		var limit := 1.0 if name.contains("wide") else 0.5
		while x < limit:
			var hit := false
			for tri in tris:
				if Geometry3D.ray_intersects_triangle(Vector3(x, y, -3.0), Vector3(0, 0, 1), tri[0], tri[1], tri[2]) != null:
					hit = true
					break
			row += "#" if hit else "."
			x += 0.05
		lines.append("  y=%.2f %s" % [y, row])
		y -= 0.15
	print("\n".join(lines))
