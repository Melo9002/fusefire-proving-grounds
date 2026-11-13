extends SubViewportContainer
## Render one selected library asset without touching the editable parcel.
const Library = preload("res://tools/parcel_editor/parcel_placement_library.gd")
var viewport: SubViewport
var model: Node3D
var camera: Camera3D
var asset_id := ""

func setup() -> void:
	custom_minimum_size = Vector2(0, 112)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 160)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("22303b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.8
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.fov = 35
	camera.current = true
	viewport.add_child(camera)

func show_asset(id: String) -> void:
	if is_instance_valid(model):
		model.free()
	asset_id = id
	if id.is_empty():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	model = Library.create(id)
	if model == null:
		return
	viewport.add_child(model)
	var bounds := EnvironmentAssetPlacement.mesh_bounds(model)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.1)
	camera.position = center + Vector3(1, 0.7, 1.2).normalized() * radius / sin(deg_to_rad(camera.fov * 0.5)) * 1.1
	camera.look_at(center)
	camera.far = maxf(camera.position.distance_to(center) + radius * 3, 10)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
