extends SceneTree
## Explicit rendered evidence for Task 5.3. The first views use the real Map
## Editor generation path. The rejected view deliberately presents the same
## imported shell with a real cargo container occupying its required apron.

const CAPTURE_SIZE := Vector2i(1600, 900)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = CAPTURE_SIZE
	await _capture_generated(output)
	await _capture_rejected_frontage(output)
	print("Parcel functional relationship captures saved to " + output)
	quit()

func _capture_generated(output: String) -> void:
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.layout_preset = &"industrial_district"
	editor.generation_seed = 2208
	for index in editor.preset_picker.item_count:
		if editor.preset_picker.get_item_metadata(index) == &"industrial_district": editor.preset_picker.select(index)
	editor._rebuild()
	editor._set_plan_overlay_visible(false)
	for view in [["accepted-overhead", 0.0, 1.50, true], ["accepted-frontage", 0.35, 0.14, false], ["accepted-service", 0.70, 0.20, false]]:
		if view[0] == "accepted-frontage":
			_focus_first_shell(editor)
		elif view[0] == "accepted-service":
			if not editor._focus_component(&"factory_pipe_receiver_unit", "validated equipment service area"):
				editor._focus_component(&"industrial_loading_canopy", "validated loading approach")
		else: editor._frame_camera()
		editor._set_camera_view(view[1], view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("parcel-relationships-%s.png" % view[0]))
		if error != OK: push_error("Relationship capture failed: %s" % error)
	editor.queue_free()
	await process_frame

func _capture_rejected_frontage(output: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var data := FlatMapGenerator.generate(40, 40, 1.0, 5303)
	var catalog := IndustrialModuleCatalog.create()
	var placements: Array[EnvironmentModulePlacement] = []
	for offset in [Vector2i.ZERO, Vector2i(10, 0), Vector2i(0, 10), Vector2i(10, 10)]: placements.append(EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(10, 10) + offset))
	placements.append(EnvironmentModulePlacement.new(&"industrial_shell_i", Vector2i(14, 10)))
	placements.append(EnvironmentModulePlacement.new(&"cargo_container", Vector2i(19, 23)))
	data.environment_modules.assign(placements)
	data.environment_module_seed = 5303
	data.source_kind = "relationship_rejection_fixture"
	EnvironmentModuleMapWriter.apply(data, _unsafe_layout(placements), catalog, 1.0)
	ModularEnvironmentPresenter.build(data, stage, 1.0)
	_add_floor_and_light(stage, data)
	var camera := Camera3D.new()
	camera.fov = 42.0
	stage.add_child(camera)
	var world_origin := data.get_cell(Vector3i.ZERO).world_position
	var target := world_origin + Vector3(20, 1.2, 22)
	camera.look_at_from_position(target + Vector3(10, 7, 12), target)
	camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join("parcel-relationships-rejected-blocked-frontage.png"))
	if error != OK: push_error("Rejected relationship capture failed: %s" % error)
	stage.queue_free()
	await process_frame

func _unsafe_layout(placements: Array[EnvironmentModulePlacement]) -> EnvironmentModuleLayout:
	# Presentation evidence intentionally bypasses placement acceptance so the
	# rejected obstruction can be seen. Tactical validation is covered by the
	# automated suite and this fixture is never used by generation.
	var result := EnvironmentModuleLayout.new(&"rejected_relationship_capture", 5303)
	result.placements.assign(placements)
	return result

func _focus_first_shell(editor: Node) -> bool:
	for placement in editor.displayed_data.environment_modules:
		if String(placement.component_id).begins_with("industrial_shell_"):
			return editor._focus_component(placement.component_id, "validated building frontage")
	return false

func _add_floor_and_light(parent: Node3D, data: MapData) -> void:
	var origin := data.get_cell(Vector3i.ZERO).world_position
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(42, 42)
	floor.mesh = plane
	floor.position = origin + Vector3(19.5, -0.04, 19.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29343a")
	floor.material_override = material
	parent.add_child(floor)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101b24")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7d3e4")
	environment.ambient_light_energy = 0.82
	environment_node.environment = environment
	parent.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	parent.add_child(sun)
