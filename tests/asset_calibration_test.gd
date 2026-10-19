extends SceneTree
const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
const OrbitCamera = preload("res://tools/inspection_orbit_camera.gd")
const PlacementConventions = preload("res://tools/asset_lab/asset_placement_conventions.gd")
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
	var camera := Camera3D.new()
	parent.add_child(camera)
	var orbit = OrbitCamera.new(camera)
	orbit.frame(AABB(Vector3.ZERO, Vector3(10, 5, 2)))
	var framed_distance: float = orbit.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	check(orbit.handle_mouse(wheel) and orbit.distance < framed_distance, "Shared inspection camera zooms")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	motion.relative = Vector2(20, -10)
	var old_focus: Vector3 = orbit.focus
	check(orbit.handle_mouse(motion) and not orbit.focus.is_equal_approx(old_focus), "Shared inspection camera pans")
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/asset_lab/native_bounds.json"))
	var catalog_data := Catalog.load_calibrations()
	check(Catalog.all_ids().size() == 315, "All four packs must be browsable")
	var unknown_semantics: Array[String] = []
	for id in Catalog.all_ids():
		check(not Catalog.semantic_category(id).is_empty(), id + " has a semantic category")
		check(Catalog.inferred_classification(id) in ["unclassified", "structural", "ground", "entrance", "tactical_obstacle", "decorative"], id + " has a broad classification")
		if Catalog.semantic_category(id) == "unknown_manual_review":
			unknown_semantics.append(id)
	check(unknown_semantics.is_empty(), "Every catalog asset has a supported semantic category")
	var resolved_sources := {"default": 0, "category": 0, "asset override": 0}
	for id in Catalog.all_ids():
		var expected := Catalog.scale_for(id, catalog_data)
		check(is_equal_approx(Catalog.profile(id, catalog_data).scale, expected), id + " resolves its calibration")
		check(is_finite(expected) and expected > 0.0, id + " resolves a finite positive scale")
		var source: String = Catalog.profile(id, catalog_data).calibration_source
		check(resolved_sources.has(source), id + " reports a recognized calibration source")
		if resolved_sources.has(source):
			resolved_sources[source] += 1
	check(resolved_sources.default == 0, "Every catalog asset is covered by a saved category or asset calibration")
	check(resolved_sources["asset override"] == catalog_data.asset_overrides.size(), "Every saved asset override resolves with highest priority")
	check(resolved_sources.category + resolved_sources["asset override"] == Catalog.all_ids().size(), "Saved calibration coverage includes all catalog assets")
	check(is_equal_approx(Catalog.scale_for("factory_kit/machine", catalog_data), 1.5), "Factory Kit inherits the human-reviewed 1.5 baseline")
	check(is_equal_approx(Catalog.scale_for("modular_space_kit/template-floor", catalog_data), 1.0), "Space Kit inherits the human-reviewed scale-one baseline")
	check(is_equal_approx(Catalog.scale_for("city_kit_roads/road-straight", catalog_data), 5.0), "Road surfaces inherit the reviewed scale-five baseline")
	check(is_equal_approx(Catalog.scale_for("city_kit_roads/light-curved", catalog_data), 5.0), "Road lights inherit the reviewed scale-five baseline")
	check(is_equal_approx(Catalog.scale_for("modular_space_kit/stairs-wide", catalog_data), 0.5), "Double-size Space stairs retain their individual half-scale correction")
	check(catalog_data.asset_overrides.size() == 15 and catalog_data.reviewed.size() == 315, "All reviewed calibration choices and individual exceptions load")
	var priority_data := Catalog.default_data()
	priority_data.fallback.scale = 2.0
	priority_data.category_presets.buildings.scale = 3.0
	priority_data.asset_overrides["city_kit_industrial/building-a"] = {"scale": 4.0}
	check(Catalog.profile("future_pack/uncategorized", priority_data).scale == 2.0, "General fallback resolves for uncategorized assets")
	check(Catalog.profile("factory_kit/oopi", priority_data).scale == 1.5, "Factory category preset overrides the general fallback")
	check(Catalog.profile("city_kit_industrial/building-b", priority_data).scale == 3.0, "Category preset overrides fallback")
	check(Catalog.profile("city_kit_industrial/building-a", priority_data).scale == 4.0, "Asset override wins resolution")
	check(Catalog.profile("city_kit_industrial/building-a", priority_data).calibration_source == "asset override", "Resolution source reported")
	priority_data.asset_overrides["city_kit_industrial/building-a"] = {"scale": 1.0, "yaw_degrees": 90.0, "anchor": Placement.Anchor.SOURCE_ORIGIN, "anchor_position": [2.0, 3.0, 4.0]}
	var catalog_piece := Catalog.place(parent, "city_kit_industrial/building-a", Vector3(10, 0, 0), PI / 2.0, priority_data)
	check(catalog_piece.position.is_equal_approx(Vector3(12, 3, 4)), "Catalog placement applies saved anchor offset")
	check(catalog_piece.basis.x.normalized().is_equal_approx(Vector3.LEFT), "Catalog placement composes saved and requested yaw")
	catalog_piece.free()
	check(records.size() == Catalog.all_ids().size(), "Every catalog asset has measured bounds")
	for id in Catalog.all_ids():
		check(records.has(id), id + " has a measured-bounds record")
		if records.has(id):
			check(vector(records[id].size).x > 0.0 and vector(records[id].size).z > 0.0, id + " has a usable horizontal visual envelope")
		var convention := PlacementConventions.record(id, catalog_data, records)
		check(convention.visual_envelope_cells[0] > 0 and convention.visual_envelope_cells[1] > 0, id + " exposes a positive planning envelope")
		check(convention.tactical_policy in ["none_decorative", "authored_component", "author_before_gameplay", "module_definition_required"], id + " reports a known tactical-authoring policy")
	check(PlacementConventions.record("city_kit_industrial/shipping-container-a", catalog_data, records).authored_tactical_footprint == [2, 5], "Calibrated container keeps an authored obstacle footprint separate from its visual envelope")
	check(PlacementConventions.record("city_kit_roads/construction-barrier", catalog_data, records).authored_tactical_footprint == [1, 1], "Low barrier has a one-cell authored module footprint")
	check(PlacementConventions.record("city_kit_roads/road-straight", catalog_data, records).assembly_pitch == [5.0, 5.0], "Road inspection uses the calibrated five-unit base pitch")
	check(PlacementConventions.record("factory_kit/structure-wall", catalog_data, records).assembly_pitch == [1.5, 1.5], "Factory inspection uses the calibrated 1.5-unit family pitch")
	check(PlacementConventions.record("factory_kit/structure-doorway-wide", catalog_data, records).authored_tactical_footprint == [4, 1], "Doorway keeps its authored tactical footprint independent from visual scale")
	check(PlacementConventions.record("modular_space_kit/template-floor", catalog_data, records).assembly_pitch == [4.0, 4.0], "Space Kit inspection uses its calibrated four-unit family pitch")
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
	check(lab.comparison.scale.is_equal_approx(Vector3.ONE), "Laboratory MIRA reference preserves the intended 1.60 m runtime height")
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
	check(is_equal_approx(lab.factor.value, 5.0), "Industrial chimney selection initializes at the reviewed family scale 5")
	lab.factor.value = 3.25
	lab.reset_button.pressed.emit()
	check(is_equal_approx(lab.factor.value, 5.0), "Catalog reset restores the reviewed chimney family scale 5")
	check(is_equal_approx(float(lab.calibration_record().scale), 5.0), "Calibration JSON exports the reviewed chimney family scale 5")
	lab.select_asset("city_kit_roads/construction-fence")
	check(is_equal_approx(lab.factor.value, 5.0), "Street furniture initializes at scale 5")
	lab.select_asset("factory_kit/oopi")
	check(is_equal_approx(lab.factor.value, 1.5), "Factory selection initializes at the 1.5 category baseline")
	lab.fallback_scale.value = 1.25
	lab._save_fallback()
	check(is_equal_approx(lab.factor.value, 1.5), "Factory category remains higher priority than edited fallback")
	lab.select_asset("city_kit_industrial/building-a")
	check(is_instance_valid(lab.facing_compass_toggle) and lab.facing_compass_toggle.button_pressed, "Facing compass is visible by default")
	for option_index in lab.semantic_front.item_count:
		if str(lab.semantic_front.get_item_metadata(option_index)) == "+z":
			lab.semantic_front.select(option_index)
			break
	lab.rebuild()
	var compass: Node = lab.overlays.get_node_or_null("FacingCompass")
	check(is_instance_valid(compass), "Facing compass is rendered for individual assets")
	check(str(compass.get_meta("working_face", "")) == "+z", "Compass reads the selected semantic working face")
	var working_label: Label3D = compass.get_node_or_null("AxisPlusZ") as Label3D
	check(is_instance_valid(working_label) and working_label.text == "WORKING +Z", "Compass labels the working direction explicitly")
	var direction_before: Vector3 = compass.get_meta("working_direction", Vector3.ZERO)
	lab.angle.value = 90
	compass = lab.overlays.get_node_or_null("FacingCompass")
	var direction_after: Vector3 = compass.get_meta("working_direction", Vector3.ZERO)
	check(direction_after.is_equal_approx(Vector3.BACK.rotated(Vector3.UP, PI / 2.0)) and not direction_after.is_equal_approx(direction_before), "Compass follows calibration yaw")
	lab._select_option_value(lab.semantic_secondary_front, "+x")
	lab.rebuild()
	compass = lab.overlays.get_node_or_null("FacingCompass")
	check(compass.get_meta("working_faces", []) == ["+z", "+x"], "Compass supports two equal corner working faces")
	check((compass.get_node_or_null("AxisPlusX") as Label3D).text == "WORKING +X", "Second working face is highlighted without primary/secondary semantics")
	lab.factor.value = 7.25
	lab.x_offset.value = 0.5
	lab.classification.select(1)
	lab.footprint_x.value = 8
	lab.footprint_z.value = 6
	lab.calibration_notes.text = "Verified against MIRA reference."
	check("UNSAVED CHANGES" in lab.save_status.text, "Unsaved edits are visible")
	lab._save_override()
	var persisted := Catalog.load_calibrations(persistence_path)
	check(is_equal_approx(float(persisted.asset_overrides["city_kit_industrial/building-a"].scale), 7.25), "Asset override persists")
	check(Catalog.profile("city_kit_industrial/building-a", persisted).yaw_degrees == 90, "Override rotation persists")
	check(persisted.asset_overrides["city_kit_industrial/building-a"].classification == "structural", "Human classification persists")
	var saved_footprint: Array = persisted.asset_overrides["city_kit_industrial/building-a"].suggested_footprint
	check(int(saved_footprint[0]) == 8 and int(saved_footprint[1]) == 6, "Suggested planning footprint persists")
	check(persisted.asset_overrides["city_kit_industrial/building-a"].calibration_notes == "Verified against MIRA reference.", "Calibration notes persist")
	check(persisted.asset_overrides["city_kit_industrial/building-a"].measured_native_size.size() == 3, "Measured native dimensions persist")
	check(persisted.asset_overrides["city_kit_industrial/building-a"].measured_calibrated_size.size() == 3, "Measured calibrated dimensions persist")
	lab.calibration_notes.text = "Final reviewed evidence."
	lab.reviewed_toggle.button_pressed = true
	persisted = Catalog.load_calibrations(persistence_path)
	check("city_kit_industrial/building-a" in persisted.reviewed, "Reviewed state persists")
	check(persisted.asset_overrides["city_kit_industrial/building-a"].calibration_notes == "Final reviewed evidence.", "Marking reviewed saves current calibration")
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
	var conveyor_filter_index := -1
	for index in lab.semantic_filter.item_count:
		if lab.semantic_filter.get_item_metadata(index) == "conveyor_modules":
			conveyor_filter_index = index
	check(conveyor_filter_index > 0, "Semantic category filter includes conveyors")
	lab.semantic_filter.select(conveyor_filter_index)
	lab._filter("")
	check(lab.asset_list.item_count > 1, "Semantic category filter groups related models")
	for index in lab.asset_list.item_count:
		check(Catalog.semantic_category(lab.asset_list.get_item_metadata(index)) == "conveyor_modules", "Semantic filter excludes unrelated models")
	lab.semantic_filter.select(0)
	lab._filter("")
	lab.select_asset("city_kit_industrial/building-a")
	lab._reload_calibrations()
	check(is_equal_approx(lab.factor.value, 7.25), "Reload restores saved override")
	lab._clear_override()
	check(is_equal_approx(lab.factor.value, 10.0), "Reset removes override and restores the reviewed building category preset")
	lab.select_asset("city_kit_roads/dumpster")
	lab.category_scale.value = 6.0
	lab._save_category_preset()
	check(is_equal_approx(lab.factor.value, 6.0), "Edited category preset applies")
	lab.fallback_scale.value = 1.0
	lab._save_fallback()
	lab.select_asset("factory_kit/machine")
	check(is_equal_approx(lab.factor.value, 1.5), "Curated Factory selection inherits the 1.5 category preset")
	lab.angle.value = 90
	check(absf(lab.current_bounds.size.x - 2.25) < 0.001, "UI rotation updates dimensions at the inherited scale")
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
	var preview = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	check(is_instance_valid(preview.seed_input) and is_instance_valid(preview.orbit), "Modular preview exposes working seed and camera controls")
	preview._set_seed(940059876)
	check(preview.generation_seed == 940059876 and int(preview.seed_input.value) == 940059876, "Modular preview seed control regenerates requested seed")
	preview.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(persistence_path))
	parent.free()
	print("Asset calibration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
