extends SceneTree
## Inspects the Kenney Factory Kit door, doorway and window models: node tree, mesh bounds in the model's own frame, pivots, collision nodes, materials, triangle counts, and whether the doorway's opening is a real hole in the
## mesh (rays through the model) rather than a painted texture. Output is text; nothing is written.
##   godot_console --headless --path . --script res://docs/quality/evidence/interaction-range/asset_inspect.gd
const DIR := "res://art/environments/kenney/factory_kit/models/"
const NAMES := ["structure-wall", "structure-doorway", "structure-doorway-wide", "structure-window", "structure-window-wide", "door", "door-wide-closed", "door-wide-half", "door-wide-open", "machine-window", "machine-window-bar"]


func _initialize() -> void:
	for name in NAMES:
		_inspect(name)
	quit()


func _walk(node: Node, depth: int, meshes: Array, to_root: Transform3D) -> void:
	var local := to_root
	if node is Node3D:
		local = to_root * (node as Node3D).transform
	var line := "%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()]
	if node is Node3D:
		var n3 := node as Node3D
		if not n3.transform.is_equal_approx(Transform3D.IDENTITY):
			line += " pos %s rot %s scale %s" % [n3.position, n3.rotation_degrees, n3.scale]
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var box: AABB = local * mi.mesh.get_aabb()
		var tris := 0
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var idx = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		line += " mesh %d surfaces %d tris, bounds pos %s size %s" % [mi.mesh.get_surface_count(), tris, _r(box.position), _r(box.size)]
		meshes.append({"name": node.name, "box": box, "mesh": mi.mesh, "xf": local})
	if node is CollisionShape3D or node is StaticBody3D or node is Area3D:
		line += "  <-- collision node"
	print(line)
	for child in node.get_children():
		_walk(child, depth + 1, meshes, local)


func _r(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001))


func _inspect(name: String) -> void:
	var scene := load(DIR + name + ".glb") as PackedScene
	if scene == null:
		print("== %s: not loadable" % name)
		return
	var root := scene.instantiate()
	print("== %s ==" % name)
	var meshes: Array = []
	_walk(root, 1, meshes, Transform3D.IDENTITY)
	var total := AABB()
	var first := true
	for entry in meshes:
		total = entry.box if first else total.merge(entry.box)
		first = false
	print("  TOTAL bounds pos %s size %s  (min y %.3f, max y %.3f)" % [_r(total.position), _r(total.size), total.position.y, total.end.y])
	# Is the opening a hole? Shoot rays along Z through the model's x-centre at several heights and count triangle hits.
	var center_x := total.position.x + total.size.x * 0.5
	var report := []
	for h in [0.3, 0.9, 1.5, 2.1, 2.7]:
		if h > total.end.y:
			continue
		var hit := _ray_hits(meshes, Vector3(center_x, h, total.position.z - 1.0), Vector3(0, 0, 1))
		report.append("y=%.1f:%s" % [h, "HIT" if hit else "clear"])
	print("  rays along +Z through the x-centre: " + ", ".join(report))
	var edge_x := total.position.x + total.size.x * 0.12
	var report2 := []
	for h in [0.3, 0.9, 1.5, 2.1]:
		if h > total.end.y:
			continue
		var hit2 := _ray_hits(meshes, Vector3(edge_x, h, total.position.z - 1.0), Vector3(0, 0, 1))
		report2.append("y=%.1f:%s" % [h, "HIT" if hit2 else "clear"])
	print("  rays along +Z near the left edge:    " + ", ".join(report2))
	root.free()


func _ray_hits(meshes: Array, origin: Vector3, direction: Vector3) -> bool:
	for entry in meshes:
		var xf: Transform3D = entry.xf
		var mesh: Mesh = entry.mesh
		var inverse := xf.affine_inverse()
		var o := inverse * origin
		var d := (inverse.basis * direction).normalized()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var count: int = (idx.size() if idx != null else verts.size()) / 3
			for t in count:
				var a: Vector3 = verts[idx[t * 3] if idx != null else t * 3]
				var b: Vector3 = verts[idx[t * 3 + 1] if idx != null else t * 3 + 1]
				var c: Vector3 = verts[idx[t * 3 + 2] if idx != null else t * 3 + 2]
				if Geometry3D.ray_intersects_triangle(o, d, a, b, c) != null:
					return true
	return false
