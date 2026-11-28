extends SceneTree
## Second look at the Factory Kit door, doorway and window models: the clear opening found by ray scan through the mesh (not by eye), each surface's material and bounds (is there glass?), the door's animations and pivot, and how thick the
## wall pieces are (the wall models report a 2 m depth: what is in it).
##   godot_console --headless --path . --script res://docs/quality/evidence/interaction-range/asset_inspect_detail.gd
const DIR := "res://art/environments/kenney/factory_kit/models/"


func _initialize() -> void:
	for name in ["structure-wall", "structure-doorway", "structure-doorway-wide", "structure-window", "structure-window-wide"]:
		_wall(name)
	_door("door")
	for name in ["door-wide-closed", "door-wide-half", "door-wide-open"]:
		_door(name)
	quit()


func _meshes(root: Node) -> Array:
	var list: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n != null:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		list.append({"mi": mi, "xf": xf})
	return list


func _surface_info(entry: Dictionary) -> void:
	var mi: MeshInstance3D = entry.mi
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var box := AABB(entry.xf * verts[0], Vector3.ZERO)
		for v in verts:
			box = box.expand(entry.xf * v)
		var material := mi.mesh.surface_get_material(s)
		var info := "none"
		if material is BaseMaterial3D:
			var m := material as BaseMaterial3D
			info = "%s albedo %s transparency %d" % [m.resource_name, m.albedo_color, m.transparency]
		elif material != null:
			info = material.get_class()
		print("    surface %d: %d verts, bounds %s .. %s, material %s" % [s, verts.size(), _r(box.position), _r(box.end), info])


func _r(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01))


func _hit(entries: Array, origin: Vector3, direction: Vector3) -> bool:
	for entry in entries:
		var mi: MeshInstance3D = entry.mi
		var inverse: Transform3D = (entry.xf as Transform3D).affine_inverse()
		var o := inverse * origin
		var d := (inverse.basis * direction).normalized()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
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


func _wall(name: String) -> void:
	var root := (load(DIR + name + ".glb") as PackedScene).instantiate()
	var entries := _meshes(root)
	print("== %s ==" % name)
	for entry in entries:
		_surface_info(entry)
	# Scan along +Z at the model's x/y grid (5 cm), through the whole depth: where is there nothing at all?
	var clear: Array = []
	var x := -1.0
	while x <= 1.0:
		var y := 0.025
		var column_clear := true
		var low := -1.0
		var high := -1.0
		while y < 3.0:
			var free := not _hit(entries, Vector3(x, y, -2.0), Vector3(0, 0, 1))
			if free and low < 0.0:
				low = y
			if free:
				high = y
			y += 0.05
		clear.append([x, low, high])
		x += 0.1
	var rows := []
	for c in clear:
		if c[1] >= 0.0:
			rows.append("x=%.1f clear y %.2f..%.2f" % [c[0], c[1], c[2]])
	print("  clear opening columns (ray along +Z through the whole piece): ", rows if not rows.is_empty() else "none (no through-opening)")
	# Where in Z is the wall itself? Hit depths of a ray at a solid column.
	var depth_samples := []
	for z in [-0.5, -0.4, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5]:
		depth_samples.append("z=%.2f:%s" % [z, "solid" if _hit_slab(entries, Vector3(-0.45, 1.0, z)) else "-"])
	print("  slab probes at x=-0.45,y=1.0 (a 2 cm cube around the point touches the mesh): ", depth_samples)
	root.free()


func _hit_slab(entries: Array, p: Vector3) -> bool:
	for axis in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)]:
		for sign in [-1.0, 1.0]:
			if _hit(entries, p - axis * sign * 0.01, axis * sign) :
				return true
	return false


func _door(name: String) -> void:
	var root := (load(DIR + name + ".glb") as PackedScene).instantiate()
	var entries := _meshes(root)
	print("== %s ==" % name)
	for entry in entries:
		_surface_info(entry)
	for player in root.find_children("*", "AnimationPlayer", true, false):
		var ap := player as AnimationPlayer
		for animation_name in ap.get_animation_list():
			var animation := ap.get_animation(animation_name)
			print("  animation '%s' length %.2fs loop %d, %d tracks" % [animation_name, animation.length, animation.loop_mode, animation.get_track_count()])
			for t in animation.get_track_count():
				var path := animation.track_get_path(t)
				var keys := []
				for k in animation.track_get_key_count(t):
					keys.append("%.2fs=%s" % [animation.track_get_key_time(t, k), animation.track_get_key_value(t, k)])
				print("    track %s %s: %s" % [path, animation.track_get_type(t), keys])
	root.free()
