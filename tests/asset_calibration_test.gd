extends SceneTree
const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
func run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/asset_lab/native_bounds.json"))
	check(Catalog.all_ids().size() == 315, "All four packs must be browsable")
	check(records.size() == Catalog.PROFILES.size(), "Every curated asset has measured bounds")
	for id in Catalog.PROFILES:
		check(not str(Catalog.PROFILES[id].orientation).is_empty(), id + " orientation is documented")
		var instance = load(Catalog.path_for(id)).instantiate()
		var native := Placement.mesh_bounds(instance)
		check(native.position.distance_to(vector(records[id].position)) < 0.0001, id + " source pivot changed")
		check(native.size.distance_to(vector(records[id].size)) < 0.0001, id + " source dimensions changed")
		instance.free()
		for quarter in 4:
			for anchor in 3:
				var at := Vector3(3, 2, -1)
				var piece := Placement.instantiate_calibrated(parent, Catalog.path_for(id), at, 1.5, quarter * PI / 2, anchor)
				var box: AABB = piece.transform * piece.occlusion_bounds
				check(piece.scale.distance_to(Vector3.ONE * 1.5) < 0.0001, "Uniform scale")
				if anchor == Placement.Anchor.SOURCE_ORIGIN:
					check(piece.position.distance_to(at) < 0.0001, "Authored pivot retained")
				else:
					check(absf(box.get_center().x - at.x) < 0.0001 and absf(box.get_center().z - at.z) < 0.0001, "Horizontal anchor")
					check(absf((box.position.y if anchor == 0 else box.end.y) - at.y) < 0.0001, "Vertical anchor")
				piece.free()
	var lab = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	check(lab.asset_list.item_count == 315, "Empty search shows every asset")
	lab._filter("structure-doorway-wide")
	check(lab.asset_list.item_count == 1, "Browser filter")
	lab.select_asset("factory_kit/machine")
	lab.angle.value = 90
	check(absf(lab.current_bounds.size.x - 1.5) < 0.001, "UI rotation updates dimensions")
	lab.x_offset.value = 2.5
	check(absf(lab.current_bounds.get_center().x - 2.5) < 0.001, "UI anchor snap")
	lab.duplicate_piece.button_pressed = true
	check(lab.content.get_child_count() == 3, "Neighbor plus MIRA")
	lab.duplicate_piece.button_pressed = false
	for index in range(1, 5):
		lab.mode.select(index)
		lab.rebuild(true)
		var pieces: Array = lab.content.get_children()
		check(pieces.size() > 2, "Assembly is populated")
		if index == 1:
			var a: AABB = pieces[0].transform * pieces[0].occlusion_bounds
			var b: AABB = pieces[2].transform * pieces[2].occlusion_bounds
			var paving: AABB = pieces[1].transform * pieces[1].occlusion_bounds
			check(absf(a.end.x - b.position.x) < 0.001, "Road seam X")
			check(absf(paving.end.z - a.position.z) < 0.001, "Sidewalk/paving seam Z")
		if index == 2:
			var door: AABB = pieces[0].transform * pieces[0].occlusion_bounds
			var wall: AABB = pieces[3].transform * pieces[3].occlusion_bounds
			check(absf(door.end.x - wall.position.x) < 0.001, "Door-wall seam")
			check(absf(door.end.y - wall.end.y) < 0.001, "Shared structure height")
		if index == 4:
			var a: AABB = pieces[1].transform * pieces[1].occlusion_bounds
			var b: AABB = pieces[3].transform * pieces[3].occlusion_bounds
			check(absf(a.end.x - b.position.x) < 0.001, "Space wall seam")
	# Bounds inspection must include transformed imported ancestors.
	var hierarchy := Node3D.new()
	hierarchy.position = Vector3(2, 0, 0)
	var child := Node3D.new()
	child.scale = Vector3.ONE * 2
	hierarchy.add_child(child)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	child.add_child(mesh)
	check(Placement.mesh_bounds(hierarchy).size.is_equal_approx(Vector3.ONE * 2), "Nested transforms measured")
	hierarchy.free()
	lab.free()
	parent.free()
	print("Asset calibration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
