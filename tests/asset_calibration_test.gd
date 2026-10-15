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
	var catalog_data := Catalog.load_calibrations()
	check(Catalog.all_ids().size() == 315, "All four packs must be browsable")
	var scale_counts := {1.0: 0, 5.0: 0, 9.0: 0}
	for id in Catalog.all_ids():
		var expected := Catalog.scale_for(id, catalog_data)
		check(is_equal_approx(Catalog.profile(id, catalog_data).scale, expected), id + " resolves its calibration")
		check(scale_counts.has(expected), id + " uses a known calibration tier")
		if scale_counts.has(expected):
			scale_counts[expected] += 1
	check(scale_counts[9.0] == 127, "City architecture and infrastructure use scale 9")
	check(scale_counts[5.0] == 5, "Five human-scale street props use scale 5")
	check(scale_counts[1.0] == 183, "Factory and Space assets retain native scale")
	for id in ["city_kit_industrial/chimney-basic", "city_kit_industrial/chimney-large", "city_kit_industrial/chimney-medium", "city_kit_industrial/chimney-small"]:
		check(is_equal_approx(Catalog.profile(id, catalog_data).scale, 9.0), id + " remains industrial scale 9")
	for id in ["city_kit_roads/construction-fence", "city_kit_roads/dumpster"]:
		check(is_equal_approx(Catalog.profile(id, catalog_data).scale, 5.0), id + " uses its observed scale 5 category")
	var priority_data := Catalog.default_data()
	priority_data.fallback.scale = 2.0
	priority_data.category_presets.buildings.scale = 3.0
	priority_data.asset_overrides["city_kit_industrial/building-a"] = {"scale": 4.0}
	check(Catalog.profile("factory_kit/oopi", priority_data).scale == 2.0, "General fallback resolves")
	check(Catalog.profile("city_kit_industrial/building-b", priority_data).scale == 3.0, "Category preset overrides fallback")
	check(Catalog.profile("city_kit_industrial/building-a", priority_data).scale == 4.0, "Asset override wins resolution")
	check(Catalog.profile("city_kit_industrial/building-a", priority_data).calibration_source == "asset override", "Resolution source reported")
	check(records.size() == Catalog.PROFILES.size(), "Every curated asset has measured bounds")
	for id in Catalog.PROFILES:
		check(Catalog.PROFILES[id].has("anchor") and Catalog.PROFILES[id].has("category") and Catalog.PROFILES[id].has("orientation") and Catalog.PROFILES[id].has("note"), id + " metadata preserved")
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
	var persistence_path := "res://tests/_asset_calibration_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(persistence_path))
	check(Catalog.save_calibrations(Catalog.default_data(), persistence_path) == OK, "Calibration fixture saved")
	var lab = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	lab.calibration_path = persistence_path
	root.add_child(lab)
	await process_frame
	check(lab.asset_list.item_count == 315, "Empty search shows every asset")
	lab.family_filter.select(1)
	lab._filter("")
	check(lab.asset_list.item_count == 37, "Industrial family filter")
	lab.family_filter.select(2)
	lab._filter("")
	check(lab.asset_list.item_count == 95, "Road family filter")
	lab.family_filter.select(3)
	lab._filter("")
	check(lab.asset_list.item_count == 143, "Factory family filter")
	lab.family_filter.select(4)
	lab._filter("")
	check(lab.asset_list.item_count == 40, "Space family filter")
	lab.family_filter.select(0)
	lab._filter("")
	lab._filter("structure-doorway-wide")
	check(lab.asset_list.item_count == 1, "Browser filter")
	lab.select_asset("city_kit_industrial/chimney-large")
	check(is_equal_approx(lab.factor.value, 9.0), "Industrial selection initializes at scale 9")
	lab.factor.value = 3.25
	lab.reset_button.pressed.emit()
	check(is_equal_approx(lab.factor.value, 9.0), "Catalog reset restores family scale 9")
	check(is_equal_approx(float(lab.calibration_record().scale), 9.0), "Calibration JSON exports family scale 9")
	lab.select_asset("city_kit_roads/construction-fence")
	check(is_equal_approx(lab.factor.value, 5.0), "Street furniture initializes at scale 5")
	lab.select_asset("factory_kit/oopi")
	check(is_equal_approx(lab.factor.value, 1.0), "Unreviewed Factory selection initializes at native scale")
	lab.fallback_scale.value = 1.25
	lab._save_fallback()
	check(is_equal_approx(lab.factor.value, 1.25), "Edited fallback applies to uncategorized asset")
	lab.select_asset("city_kit_industrial/building-a")
	lab.factor.value = 7.25
	lab.angle.value = 90
	lab.x_offset.value = 0.5
	check("UNSAVED CHANGES" in lab.save_status.text, "Unsaved edits are visible")
	lab._save_override()
	var persisted := Catalog.load_calibrations(persistence_path)
	check(is_equal_approx(float(persisted.asset_overrides["city_kit_industrial/building-a"].scale), 7.25), "Asset override persists")
	check(Catalog.profile("city_kit_industrial/building-a", persisted).yaw_degrees == 90, "Override rotation persists")
	lab.reviewed_toggle.button_pressed = true
	persisted = Catalog.load_calibrations(persistence_path)
	check("city_kit_industrial/building-a" in persisted.reviewed, "Reviewed state persists")
	lab.review_filter.select(2)
	lab._filter("")
	check(lab.asset_list.item_count == 1, "Reviewed-only filter")
	lab.review_filter.select(1)
	lab._filter("")
	check(lab.asset_list.item_count == 314, "Unreviewed-only filter")
	var reviewed_id: String = lab.selected
	lab._next_unreviewed()
	check(lab.selected != reviewed_id and lab.selected not in persisted.reviewed, "Next unreviewed navigation")
	lab.review_filter.select(0)
	lab._filter("")
	lab.select_asset("city_kit_industrial/building-a")
	lab._reload_calibrations()
	check(is_equal_approx(lab.factor.value, 7.25), "Reload restores saved override")
	lab._clear_override()
	check(is_equal_approx(lab.factor.value, 9.0), "Reset removes override and restores category preset")
	lab.select_asset("city_kit_roads/dumpster")
	lab.category_scale.value = 6.0
	lab._save_category_preset()
	check(is_equal_approx(lab.factor.value, 6.0), "Edited category preset applies")
	lab.fallback_scale.value = 1.0
	lab._save_fallback()
	lab.select_asset("factory_kit/machine")
	check(is_equal_approx(lab.factor.value, 1.0), "Curated Factory selection inherits restored fallback")
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
	var lab_reloaded = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	lab_reloaded.calibration_path = persistence_path
	root.add_child(lab_reloaded)
	await process_frame
	lab_reloaded.select_asset("city_kit_roads/dumpster")
	check(is_equal_approx(lab_reloaded.factor.value, 6.0), "Category preset survives laboratory restart")
	check("city_kit_industrial/building-a" in lab_reloaded.calibration_data.reviewed, "Review state survives laboratory restart")
	lab_reloaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(persistence_path))
	parent.free()
	print("Asset calibration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
