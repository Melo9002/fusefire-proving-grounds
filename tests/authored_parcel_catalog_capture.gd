extends SceneTree
## Visual review of the bounded refinery parcel family.

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("17232d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8c8d8")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.shadow_enabled = true
	stage.add_child(light)
	var parcels := Catalog.all()
	var centres := [Vector3(-20, 0, -14), Vector3(0, 0, -14), Vector3(20, 0, -14), Vector3(-10, 0, 22), Vector3(10, 0, 22)]
	for index in parcels.size():
		var parcel: Node3D = parcels[index].instantiate()
		parcel.position = centres[index] - Vector3(7.5, 0, (parcels[index].size.y - 1) * 0.5)
		stage.add_child(parcel)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 42
	stage.add_child(camera)
	for view in [
		["family-overhead", Vector3(0.01, 72, 4), Vector3(0, 0, 4)],
		["family-oblique", Vector3(52, 38, 54), Vector3(0, 1, 4)],
		["supporting-parcels", Vector3(0, 16, 54), Vector3(0, 2, 20)],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("refinery-parcels-%s.png" % view[0]))
		if error != OK:
			push_error("Parcel capture failed: %s" % error)
			quit(1)
			return
	print("Authored parcel captures saved to " + output)
	quit()
