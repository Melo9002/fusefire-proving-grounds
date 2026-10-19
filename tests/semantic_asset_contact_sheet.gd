extends SceneTree
## Manual rendered catalog review. Each thumbnail frames native geometry without
## changing calibration data. Run graphically and pass an output directory.

const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")

const COLUMNS := 5
const ROWS := 4
const PAGE_SIZE := COLUMNS * ROWS
const VIEW_SIZE := Vector2i(304, 176)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Semantic asset contact sheets require a graphics run")
		quit()
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Supply an output directory after --")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var captured := 0
	for pack in Catalog.PACKS:
		var ids: Array[String] = []
		for id in Catalog.all_ids():
			if id.begins_with(pack + "/"):
				ids.append(id)
		for start in range(0, ids.size(), PAGE_SIZE):
			var page_ids := ids.slice(start, mini(start + PAGE_SIZE, ids.size()))
			var page := _build_page(pack, start / PAGE_SIZE + 1, page_ids)
			root.add_child(page)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join("%s-%02d.png" % [pack, start / PAGE_SIZE + 1])
			var error := root.get_texture().get_image().save_png(path)
			if error != OK:
				push_error("Contact sheet capture failed: %s" % error_string(error))
				quit(1)
				return
			captured += 1
			page.queue_free()
			await process_frame
	print("Semantic asset contact sheets: %d pages, %d assets" % [captured, Catalog.all_ids().size()])
	quit()

func _build_page(pack: String, page_number: int, ids: Array) -> Control:
	var background := ColorRect.new()
	background.color = Color("111a24")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	background.add_child(column)
	var heading := Label.new()
	heading.text = "%s  •  semantic review page %d" % [pack.replace("_", " ").capitalize(), page_number]
	heading.add_theme_font_size_override("font_size", 18)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for id_value in ids:
		grid.add_child(_asset_cell(str(id_value)))
	return background

func _asset_cell(id: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(312, 204)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var packed := load(Catalog.path_for(id)) as PackedScene
	var model := packed.instantiate() as Node3D if packed else null
	var bounds := Placement.mesh_bounds(model) if model else AABB()
	var label := Label.new()
	label.text = "%s\n%.2f × %.2f × %.2f native" % [id.get_file(), bounds.size.x, bounds.size.y, bounds.size.z]
	label.add_theme_font_size_override("font_size", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 34
	column.add_child(label)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(VIEW_SIZE)
	column.add_child(container)
	var view := SubViewport.new()
	view.size = VIEW_SIZE
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.own_world_3d = true
	container.add_child(view)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("253442")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d6e2f0")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	view.add_child(environment)
	var stage := Node3D.new()
	view.add_child(stage)
	if model:
		stage.add_child(model)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	light.light_energy = 1.35
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	span = maxf(span, 0.25)
	camera.size = span * 1.5
	var target := bounds.get_center()
	var camera_position := target + Vector3(span, span * 0.72, span)
	camera.look_at_from_position(camera_position, target, Vector3.UP)
	camera.current = true
	stage.add_child(camera)
	return panel
