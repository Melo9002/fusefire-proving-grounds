extends SceneTree
## Manual seam study for Factory Kit machine-top candidates. Source GLBs are
## instanced at native scale; no calibration or semantic data is modified.

const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")

const SPECS := [
	["REJECTED: generic top + full piston", "machine", "piston-round", Vector3(0, 1.30, 0.36), Vector3.ZERO],
	["REJECTED: generic top + thin piston", "machine", "piston-thin-round", Vector3(0, 1.30, 0.36), Vector3.ZERO],
	["REJECTED: generic top + cog", "machine", "cog-a", Vector3(0, 1.30, 0.36), Vector3.ZERO],
	["REJECTED: receiver + piston", "machine-connection-hole", "piston-round", Vector3(0, 1.293, 0.36), Vector3.ZERO],
	["VERIFIED: receiver + vertical pipe", "machine-connection-hole", "pipe-large", Vector3(0.5, 1.793, 0.36), Vector3(0, 0, 90)],
	["VERIFIED: outlet + vertical pipe", "machine-connection-pipe", "pipe-large", Vector3(0.5, 2.25, 0.36), Vector3(0, 0, 90)],
]
const VIEWS := [
	["DIAGONAL", Vector3(1, 0.72, 1)],
	["TOP", Vector3(0, 1, 0)],
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Machine connection capture requires a graphics run")
		quit()
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Supply an output PNG after --")
		quit(1)
		return
	var page := _build_page()
	root.add_child(page)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := root.get_texture().get_image().save_png(output)
	print("Machine connection capture: ", error_string(error))
	quit(0 if error == OK else 1)

func _build_page() -> Control:
	var background := ColorRect.new()
	background.color = Color("111a24")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	background.add_child(column)
	var heading := Label.new()
	heading.text = "FACTORY MACHINE CONNECTION STUDY  •  native source scale"
	heading.add_theme_font_size_override("font_size", 17)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	for spec in SPECS:
		grid.add_child(_assembly_cell(spec))
	return background

func _assembly_cell(spec: Array) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(526, 420)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var label := Label.new()
	label.text = str(spec[0]) + "  •  origin " + str(spec[3]) + "  •  rot " + str(spec[4])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var views := HBoxContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(views)
	for view_spec in VIEWS:
		views.add_child(_view(spec, view_spec))
	return panel

func _view(spec: Array, view_spec: Array) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = str(view_spec[0])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(255, 365)
	column.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(255, 365)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	container.add_child(viewport)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("253442")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6e2f0")
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var machine := (load(Catalog.path_for("factory_kit/" + str(spec[1]))) as PackedScene).instantiate() as Node3D
	var attachment := (load(Catalog.path_for("factory_kit/" + str(spec[2]))) as PackedScene).instantiate() as Node3D
	attachment.position = spec[3]
	attachment.rotation_degrees = spec[4]
	stage.add_child(machine)
	stage.add_child(attachment)
	var bounds := Placement.mesh_bounds(machine).merge(attachment.transform * Placement.mesh_bounds(attachment))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.45
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	camera.size = span * 1.45
	var direction: Vector3 = view_spec[1]
	var target := bounds.get_center()
	var up := Vector3.BACK if absf(direction.y) > 0.99 else Vector3.UP
	camera.look_at_from_position(target + direction.normalized() * span * 2.5, target, up)
	camera.current = true
	stage.add_child(camera)
	return column
