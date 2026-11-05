extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := CSGBox3D.new()
	stage.add_child(floor_mesh)
	var rig := TacticalCamera.new()
	var camera := Camera3D.new()
	camera.position.z = 42.0
	rig.add_child(camera)
	rig.camera = camera
	rig.map_floor = floor_mesh
	stage.add_child(rig)
	rig.set_process(false)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	rig._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 20)
	rig._unhandled_input(motion)
	check(is_equal_approx(rig.rotation_degrees.x, -51.0), "Dragging down gradually raises the view from 45 to 51 degrees")
	check(is_equal_approx(rig.rotation_degrees.y, -3.0), "Horizontal middle drag retains yaw orbit")
	check(camera.global_position.y > rig.global_position.y, "Low orbit remains above the focus plane")
	var pitch := rig.rotation.x
	rig._set_zoom(12.0)
	check(is_equal_approx(rig.rotation.x, pitch), "Zoom preserves the manually chosen pitch")
	motion.relative = Vector2(0, 10000)
	rig._unhandled_input(motion)
	check(is_equal_approx(rig.rotation_degrees.x, -88.0), "Downward drag stops short of the overhead singularity")
	motion.relative.y = -10000
	rig._unhandled_input(motion)
	check(is_equal_approx(rig.rotation_degrees.x, -2.0), "Upward drag cannot orbit below ground")
	press.pressed = false
	rig._unhandled_input(press)
	pitch = rig.rotation.x
	rig._unhandled_input(motion)
	check(is_equal_approx(rig.rotation.x, pitch), "Releasing middle mouse ends pitch orbit")
	rig._cinematic_active = true
	press.pressed = true
	rig._unhandled_input(press)
	check(not rig._rotating, "Action camera retains input ownership")
	rig.clear_cinematic_view()
	check(is_equal_approx(rig.rotation.x, pitch), "Returning from cinematic view preserves manual pitch")
	stage.free()
	print("Tactical camera pitch: %d failure(s)" % failures)
	quit(1 if failures else 0)
