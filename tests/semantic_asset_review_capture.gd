extends SceneTree
## Manual six-sided review sheets for semantic assets with unresolved fields.
## Run graphically and pass an output directory. Optional additional arguments
## are exact asset IDs; without them, every currently flagged asset is rendered.

const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")

const COLUMNS := 3
const ROWS := 2
const PAGE_SIZE := COLUMNS * ROWS
const VIEW_SIZE := Vector2i(248, 104)
const VIEWS := [
	["FROM +Z", Vector3(0, 0, 1)],
	["FROM -Z", Vector3(0, 0, -1)],
	["FROM +X", Vector3(1, 0, 0)],
	["FROM -X", Vector3(-1, 0, 0)],
	["FROM +Y (TOP)", Vector3(0, 1, 0)],
	["FROM -Y (BOTTOM)", Vector3(0, -1, 0)],
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Semantic asset review sheets require a graphics run")
		quit()
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Supply an output directory after --")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var ids: Array[String] = []
	if args.size() > 1:
		for index in range(1, args.size()):
			ids.append(args[index])
	else:
		var data := Semantics.load_data()
		for id in Catalog.all_ids():
			if Semantics.needs_review(id, data):
				ids.append(id)
	var captured := 0
	for start in range(0, ids.size(), PAGE_SIZE):
		var page_ids := ids.slice(start, mini(start + PAGE_SIZE, ids.size()))
		var page := _build_page(start / PAGE_SIZE + 1, page_ids)
		root.add_child(page)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join("semantic-review-%02d.png" % (start / PAGE_SIZE + 1))
		var error := root.get_texture().get_image().save_png(path)
		if error != OK:
			push_error("Semantic review capture failed: %s" % error_string(error))
			quit(1)
			return
		captured += 1
		page.queue_free()
		await process_frame
	print("Semantic asset review sheets: %d pages, %d assets" % [captured, ids.size()])
	quit()

func _build_page(page_number: int, ids: Array) -> Control:
	var background := ColorRect.new()
	background.color = Color("111a24")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	background.add_child(column)
	var heading := Label.new()
	heading.text = "FUSEFIRE SEMANTIC REVIEW  •  local-axis views  •  page %d" % page_number
	heading.add_theme_font_size_override("font_size", 16)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	column.add_child(grid)
	for value in ids:
		grid.add_child(_asset_cell(str(value)))
	return background

func _asset_cell(id: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(526, 420)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var packed := load(Catalog.path_for(id)) as PackedScene
	var measurement := packed.instantiate() as Node3D if packed else null
	var bounds := Placement.mesh_bounds(measurement) if measurement else AABB()
	if measurement:
		measurement.free()
	var record := Semantics.effective(id)
	var label := Label.new()
	label.text = "%s  •  %.2f × %.2f × %.2f native  •  %s" % [id, bounds.size.x, bounds.size.y, bounds.size.z, ", ".join(record.review_flags)]
	label.add_theme_font_size_override("font_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var views := GridContainer.new()
	views.columns = 2
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(views)
	for view_data in VIEWS:
		views.add_child(_view_cell(packed, bounds, str(view_data[0]), view_data[1]))
	return panel

func _view_cell(packed: PackedScene, bounds: AABB, label_text: String, direction: Vector3) -> Control:
	var column := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(VIEW_SIZE)
	column.add_child(container)
	var view := SubViewport.new()
	view.size = VIEW_SIZE
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.own_world_3d = true
	container.add_child(view)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("253442")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6e2f0")
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	view.add_child(world_environment)
	var stage := Node3D.new()
	view.add_child(stage)
	if packed:
		stage.add_child(packed.instantiate())
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	light.light_energy = 1.45
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	span = maxf(span, 0.25)
	camera.size = span * 1.28
	var target := bounds.get_center()
	var vertical := absf(direction.y) > 0.5
	var camera_position := target + direction * span * 2.0
	if not vertical:
		camera_position += Vector3.UP * span * 0.08
	camera.look_at_from_position(camera_position, target, Vector3.BACK if vertical else Vector3.UP)
	camera.current = true
	stage.add_child(camera)
	return column
