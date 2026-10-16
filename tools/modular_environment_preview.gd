extends Node3D

@export var generation_seed := 2202
var content: Node3D
var status: Label

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int():
		generation_seed = int(args[0])
	_build_ui()
	_rebuild()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rebuild()
		elif event.keycode == KEY_BRACKETRIGHT:
			generation_seed += 1
			_rebuild()
		elif event.keycode == KEY_BRACKETLEFT:
			generation_seed -= 1
			_rebuild()

func _rebuild() -> void:
	if content:
		content.free()
	content = Node3D.new()
	content.name = "PreviewContent"
	add_child(content)
	var data := FlatMapGenerator.generate_modular_industrial_sample(40, 30, 1.0, generation_seed)
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 30)
	ground_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("303a3f")
	floor_material.roughness = 1.0
	ground_mesh.material_override = floor_material
	content.add_child(ground_mesh)
	GeneratedTerrainPresenter.build(data, content, 1.0)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var validation := MapValidator.validate(data, graph, {
		TacticalUnit.Faction.PLAYER: 5,
		TacticalUnit.Faction.ENEMY: 5,
	})
	status.text = "MODULAR INDUSTRIAL PREVIEW  |  seed %d  |  %d components  |  %s\nR regenerate  [ / ] change seed" % [
		generation_seed, data.environment_modules.size(), "VALID" if validation.is_valid() else validation.describe()
	]

func _build_ui() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(34, 19, 34)
	camera.fov = 55.0
	camera.look_at_from_position(camera.position, Vector3(20, 0, 19))
	add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("18232d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9fb5c2")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	add_child(environment)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(18, 18)
	status.add_theme_font_size_override("font_size", 18)
	layer.add_child(status)
