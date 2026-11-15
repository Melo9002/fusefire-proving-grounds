extends SceneTree
## Distant content stays static, subdued, bounded and distributed around the site.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var backdrop := load("res://art/environments/authored/plots/depot_distant_blocks.tscn").instantiate() as Node3D
	root.add_child(backdrop)
	var headings: Array[float] = []
	for district: Node3D in backdrop.get_children():
		headings.append(fposmod(atan2(district.position.x, district.position.z), TAU))
		check(district.position.length() > 70, "Distant districts stay clear of tactical and peripheral scenery")
	headings.sort()
	for index in headings.size():
		var next := headings[(index + 1) % headings.size()] + (TAU if index == headings.size() - 1 else 0.0)
		check(rad_to_deg(next - headings[index]) <= 65, "No horizon sector is left without a neighboring district")
	var triangles := 0
	var meshes := backdrop.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Distant detail casts no extra shadows")
		var material := mesh.material_override as StandardMaterial3D
		check(material != null and maxf(material.albedo_color.r, maxf(material.albedo_color.g, material.albedo_color.b)) <= 0.55 and material.albedo_color.s < 0.2, "Backdrop uses its own quiet, desaturated material")
		var bounds := mesh.global_transform * mesh.get_aabb()
		# Rotated district pads have conservative world AABBs. Measure the
		# actual oriented rectangle instead of treating that empty AABB space as geometry.
		var local_origin := mesh.to_local(Vector3.ZERO)
		var box := mesh.get_aabb()
		var point := mesh.to_global(Vector3(clampf(local_origin.x, box.position.x, box.end.x), 0, clampf(local_origin.z, box.position.z, box.end.z)))
		var closest := Vector2(point.x, point.z)
		check(closest.length() > 70 and bounds.position.y >= -0.05, "Backdrop geometry remains distant and grounded")
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
			triangles += int((indices if indices > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3.0)
	check(meshes.size() <= 60 and triangles <= 6500, "The modest backdrop stays within its explicit geometry cap")
	check(backdrop.find_children("*", "PhysicsBody3D", true, false).is_empty() and backdrop.find_children("*", "NavigationRegion3D", true, false).is_empty(), "Distant content adds no gameplay collision or navigation")
	check(backdrop.find_children("*", "Light3D", true, false).is_empty(), "The backdrop needs no extra lights")
	print("[DistantGeometry] %d meshes, %d triangles" % [meshes.size(), triangles])
	backdrop.free()
	print("Depot distant view: %d failure(s)" % failures)
	quit(1 if failures else 0)
