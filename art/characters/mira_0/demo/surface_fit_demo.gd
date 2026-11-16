extends Node3D
## Isolated proof: geometric fit + the existing LOS routine + authored pose.
const Fit = preload("res://systems/grid/surface_placement.gd")
var grid: GridManager
var wall: MeshInstance3D
var visual: UnitVisualAdapter
var ghost: MeshInstance3D
var contact_marker: MeshInstance3D
var ray: MeshInstance3D
var slider: HSlider
var status: Label
var last_fit: Dictionary = {}
var last_center_blocked := false
var last_resolved_blocked := false

func _mesh(mesh: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.surface_set_material(0, material)
	instance.position = at
	add_child(instance)
	return instance

func _dot(color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	return _mesh(sphere, color, Vector3.ZERO)

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.08, 0.11, 0.14)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	grid = GridManager.new()
	add_child(grid)
	var floor_mesh := CSGBox3D.new()
	floor_mesh.size = Vector3(9, 0.2, 9)
	floor_mesh.position.y = -0.1
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.2, 0.23)
	floor_material.roughness = 1
	floor_mesh.material = floor_material
	grid.add_child(floor_mesh)
	grid.map_floor = floor_mesh
	var box := BoxMesh.new()
	box.size = Vector3(1, 1.6, 0.4)
	wall = _mesh(box, Color(0.3, 0.48, 0.4), Vector3(0.65, 0.8, 0))
	for edge in [Vector3(-0.5, 0.01, 0), Vector3(0.5, 0.01, 0), Vector3(0, 0.01, -0.5), Vector3(0, 0.01, 0.5)]:
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.015, 0.015, 1) if edge.x != 0 else Vector3(1, 0.015, 0.015)
		_mesh(stripe, Color(0.1, 0.8, 1), edge)
	_dot(Color.RED).position = Vector3(0, 0.05, 0)
	ghost = _dot(Color.CYAN)
	contact_marker = _dot(Color.GOLD)
	visual = preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	add_child(visual)
	var camera := Camera3D.new()
	camera.position = Vector3(-4, 4, 5)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	add_child(camera)
	camera.look_at(Vector3(0.2, 0.6, 0))
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(24, 24)
	layer.add_child(panel)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 20)
	panel.add_child(status)
	slider = HSlider.new()
	slider.custom_minimum_size = Vector2(620, 32)
	slider.min_value = 0
	slider.max_value = 1.2
	slider.step = 0.05
	slider.value = 0.65
	panel.add_child(slider)
	var hint := Label.new()
	hint.text = "Slide the object. Red dot: tile center; cyan: tested fit; gold: surface contact.\nThis lab does not unlock partially blocked cells in battles. Authored pose is a placeholder."
	panel.add_child(hint)
	slider.value_changed.connect(func(_value): update_demo())
	await get_tree().process_frame
	await get_tree().process_frame
	update_demo()
	if OS.get_cmdline_user_args().has("capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		get_viewport().get_texture().get_image().save_png("res://artifacts/surface-fit-demo.png")
		get_tree().quit()

func update_demo() -> void:
	wall.position.x = slider.value
	var bounds := AABB(wall.position - Vector3(0.5, 0.8, 0.2), Vector3(1, 1.6, 0.4))
	var preferred := Vector3(bounds.position.x - 0.32, 0, 0)
	last_fit = Fit.resolve(Vector3.ZERO, [bounds], 0.28, 1.8, 0.04, 1, preferred)
	grid.map_data = TacticalMapBuilder.generate(9, 9, 1, 17)
	# The lab deliberately retains a blocked navigation cell. Ground-level shot
	# bounds are independently indexed so they are NOT skipped in the origin cell.
	grid.get_cell_data(Vector3i(4, 0, 4)).can_stop = false
	for x in range(floori(bounds.position.x + 4.5), ceili(bounds.end.x + 4.5)):
		var obstacle := MapCellData.new(Vector3i(x, 0, 4), Vector3(x - 4, 0, 0))
		obstacle.walkable = false
		obstacle.can_stop = false
		obstacle.cover_height = 1.6
		obstacle.blocks_line_of_sight = true
		obstacle.authored_shot_bounds = bounds
		grid.map_data.add_shot_obstacle(obstacle)
	grid.map_data.rebuild_los_index()
	visual.visible = last_fit.fits
	ghost.visible = last_fit.fits
	contact_marker.visible = last_fit.fits
	if is_instance_valid(ray): ray.queue_free()
	if not last_fit.fits:
		status.text = "SURFACE FIT LAB - NO FIT\n" + last_fit.reason
		return
	var point: Vector3 = last_fit.position
	var contact := Fit.contact(point, bounds)
	visual.position = point
	visual.face_world_position(contact.surface_position)
	visual.last_cover_contact = contact
	visual.animation_controller.play(&"cover_high")
	ghost.position = point + Vector3.UP * 0.05
	contact_marker.position = contact.surface_position
	var source := point + Vector3.UP * 1.1
	var target := Vector3(1.4, 1.1, -1.2)
	last_center_blocked = CombatRules.get_blocking_cell(Vector3(0, 1.1, 0), target, grid) != null
	last_resolved_blocked = CombatRules.get_blocking_cell(source, target, grid) != null
	var segment := CylinderMesh.new()
	segment.top_radius = 0.014
	segment.bottom_radius = 0.014
	segment.height = source.distance_to(target)
	ray = _mesh(segment, Color.RED if last_resolved_blocked else Color.GREEN, (source + target) * 0.5)
	ray.quaternion = Quaternion(Vector3.UP, (target - source).normalized())
	status.text = "SURFACE FIT LAB - BODY FITS\nObject X %.2f | stand X %.2f | body gap %.2f\nLOS ray: old center %s -> resolved point %s" % [slider.value, point.x, contact.distance - 0.28, "blocked" if last_center_blocked else "clear", "blocked" if last_resolved_blocked else "clear"]
