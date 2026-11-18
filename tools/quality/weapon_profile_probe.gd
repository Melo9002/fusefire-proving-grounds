extends SceneTree
## Slices the weapon mesh along the barrel (z) and prints each slice's vertical and sideways extent
## in the weapon's own frame, so grips and handles can be located from the geometry.
##   godot_console --headless --path . --script res://tools/quality/weapon_profile_probe.gd
func _initialize() -> void:
	var weapon := (load("res://art/weapons/aug/models/aug_runtime_socketed.glb") as PackedScene).instantiate() as Node3D
	root.add_child(weapon)
	var mesh_node := weapon.find_child("AUG_Runtime", true, false) as MeshInstance3D
	var to_weapon := weapon.global_transform.affine_inverse() * mesh_node.global_transform
	var slices := {}
	for surface in mesh_node.mesh.get_surface_count():
		var arrays := mesh_node.mesh.surface_get_arrays(surface)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var point := to_weapon * vertex
			var key := int(floor(point.z / 0.02))
			if not slices.has(key):
				slices[key] = {"min_y": INF, "max_y": -INF, "min_x": INF, "max_x": -INF, "count": 0}
			var slice: Dictionary = slices[key]
			slice.min_y = minf(slice.min_y, point.y)
			slice.max_y = maxf(slice.max_y, point.y)
			slice.min_x = minf(slice.min_x, point.x)
			slice.max_x = maxf(slice.max_x, point.x)
			slice.count += 1
	var keys := slices.keys()
	keys.sort()
	for key in keys:
		var s: Dictionary = slices[key]
		print("WPROFILE z %.2f..%.2f  y %.3f..%.3f  x %.3f..%.3f  verts %d" % [key * 0.02, key * 0.02 + 0.02, s.min_y, s.max_y, s.min_x, s.max_x, s.count])
	for marker_name in ["MuzzleSocket", "SupportHandTarget", "WeaponOrigin"]:
		var marker := weapon.find_child(marker_name, true, false) as Node3D
		var local: Vector3 = weapon.global_transform.affine_inverse() * marker.global_position
		print("WMARKER %s (%.4f, %.4f, %.4f)" % [marker_name, local.x, local.y, local.z])
	quit(0)
