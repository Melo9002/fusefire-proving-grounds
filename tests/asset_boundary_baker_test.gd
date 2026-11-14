extends SceneTree
const Baker = preload("res://tools/asset_lab/mesh_boundary_baker.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	if OS.get_cmdline_user_args().has("capture") and DisplayServer.get_name() == "headless":
		push_error("Boundary capture requires a renderer")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var lab = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	lab.select_asset("car_kit/delivery")
	lab.workspace_tabs.current_tab = 4
	var panel = lab.boundary_panel
	panel.part_name.text = "Truck"
	panel.role.select(1)
	panel.bake_part()
	check(panel.parts.size() == 1 and panel.parts[0].points.size() > 8, "Fits actual calibrated imported vertices, rather than an eight-corner AABB")
	var first: PackedVector3Array = panel.parts[0].points
	panel.bake_part()
	check(panel.parts[0].points == first, "Refitting ignores diagnostic hull meshes and is deterministic")
	panel.limits[1].value = 500
	check(panel.export_button.disabled, "Unfitted clipping changes block export")
	panel.reset_region()
	check(panel.limits[1].value < 2 and not panel.export_button.disabled, "Whole-model reset excludes the large clipping preview and restores the fitted state")
	check(panel.parts[0].bounds.size.is_equal_approx(lab.current_bounds.size), "Whole-model clipping preserves the calibrated source bounds")
	var cropped := Baker.bake(panel.source, AABB(Vector3(-1, 0, 1.4), Vector3(2, 1, 0.7)))
	check(cropped.error.is_empty() and cropped.bounds.end.y <= 1.00001 and cropped.bounds.position.z >= 1.39999, "Triangle clipping fits a low front region independently of the tall cargo")
	check(not Baker.bake(panel.source, AABB(Vector3.ONE * 100, Vector3.ONE)).error.is_empty(), "Empty clipping regions fail explicitly")
	check(not Baker.bake(panel.source, AABB(Vector3.ZERO, Vector3(-1, 1, 1))).error.is_empty(), "Reversed clipping limits fail explicitly")
	var path := "res://.godot/test_boundary_profile.tscn"
	panel.save_profile(path)
	check(FileAccess.file_exists(path) and panel.status.text.contains("Unregistered"), "Exports a named editable authoring scene without registering it")
	var restored := Baker.read_profile(path, panel.dependency)
	check(restored.error.is_empty() and restored.parts[0].points == first and restored.parts[0].role == "solid", "Reopening preserves mesh-derived points and authored roles")
	var stale: Dictionary = panel.dependency.duplicate(true)
	stale.geometry_sha256 = "changed"
	check(not Baker.read_profile(path, stale).error.is_empty(), "Geometry dependency changes reject old candidates")
	stale = panel.dependency.duplicate(true)
	stale.placement.scale = 99
	check(not Baker.read_profile(path, stale).error.is_empty(), "Calibration changes reject old candidates")
	panel.remove_part()
	check(panel.parts.is_empty(), "Candidate removal works")
	panel.undo()
	check(panel.parts.size() == 1, "Candidate removal is undoable")
	lab.select_asset("city_kit_industrial/building-i")
	check(panel.parts.is_empty(), "A new model does not inherit another asset's boundaries")
	panel.open_profile(path)
	check(panel.parts.is_empty() and panel.status.text.contains("preserved"), "Wrong-asset loading preserves the current draft")
	lab.select_asset("car_kit/delivery")
	check(panel.parts.size() == 1, "Returning to an asset restores its in-memory boundary draft")
	panel._select_part(0)
	panel._change_role(0)
	check(panel.export_button.disabled and Baker.export_profile(panel.parts, panel.asset_id, panel.dependency, "res://.godot/unclassified_boundary.tscn") == ERR_INVALID_DATA, "Unclassified roles cannot be exported as ready profiles")
	panel._change_role(1)
	lab.mira_toggle.button_pressed = true
	lab.rebuild()
	panel._select_part(0)
	panel.bake_part()
	check(panel.parts[0].points == first, "The MIRA reference is excluded from source baking")
	lab.duplicate_piece.button_pressed = true
	lab.rebuild()
	check(panel.export_button.disabled, "Comparison assemblies cannot silently bake multiple asset instances")
	lab.duplicate_piece.button_pressed = false
	lab.rebuild()
	if OS.get_cmdline_user_args().has("capture"):
		panel._select_part(0)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://artifacts/asset-boundary-authoring.png") == OK, "Rendered boundary authoring inspection saved")
	lab.queue_free()
	await process_frame
	print("Asset boundary authoring: %d failure(s)" % failures)
	quit(1 if failures else 0)
