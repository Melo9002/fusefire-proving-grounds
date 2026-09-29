extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var rig := TacticalCamera.new()
	var floor_mesh := CSGBox3D.new()
	var lens := Camera3D.new()
	rig.add_child(floor_mesh)
	rig.add_child(lens)
	rig.map_floor = floor_mesh
	rig.camera = lens
	root.add_child(rig)
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 2, 2)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	var origin := Vector3(0, 1.5, 0)
	var destination := Vector3(0, 1.5, 4)
	check(not rig._camera_path_clear(origin, destination), "Terrain blocks camera")
	check(rig._safe_camera_position(origin, destination).z < 1.9, "Camera stays before wall with clearance")
	check(rig._camera_path_clear(origin, Vector3(0, 1.5, -4)), "Open camera path is unchanged")
	wall.collision_layer = 4
	await physics_frame
	check(rig._camera_path_clear(origin, destination), "Unit collision layer does not obstruct camera")
	rig.queue_free()
	wall.queue_free()
	await process_frame
	print("Camera obstruction: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
