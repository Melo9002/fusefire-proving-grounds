extends SceneTree
## Rendered evidence for Task 09 (explicit-only: needs a GPU, not part of the standard tiers): MIRA and the small robot, on the SAME presentation stack, doing equivalent things, at their ACTUAL proportions
## (one scene, one camera setup; both characters in the same frame in the first two columns, each alone from the side in the last two).
##   godot --path . --script res://tests/humanoid_portability_capture.gd -- <output_dir>
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const TILE := Vector2i(400, 330)
const DT := 1.0 / 60.0
var armed := {}
var bare := {}
var cam: Camera3D
var rows: Array = []   # each row: Array[Image]
var stage: Node3D
var stairs: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _spawn(x: float, key: String, weapon: bool) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
	if not weapon:
		host.rig.weapon_scene = null
	host.position = Vector3(x, 0, 0)
	stage.add_child(host)
	return host


func _grab(position: Vector3, target: Vector3, fov := 38.0) -> Image:
	cam.fov = fov
	cam.look_at_from_position(position, target)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


## One row: both characters from the front and three-quarter, then each alone from the side. `a` and `b` are the two hosts (MIRA, small).
func _row(a: Node3D, b: Node3D) -> void:
	var tiles: Array[Image] = []
	var mid := (a.global_position + b.global_position) * 0.5 + Vector3(0, 0.62, 0)
	tiles.append(await _grab(mid + Vector3(0, 0.25, 3.3), mid))
	tiles.append(await _grab(mid + Vector3(2.4, 0.5, 2.5), mid))
	tiles.append(await _grab(a.global_position + Vector3(-3.0, 0.9, 0.0), a.global_position + Vector3(0, 0.75, 0)))   # each from its outer side, so neither hides the other
	tiles.append(await _grab(b.global_position + Vector3(3.0, 0.9, 0.0), b.global_position + Vector3(0, 0.75, 0)))
	rows.append(tiles)


func _save(name: String, out: String) -> void:
	var sheet := Image.create(TILE.x * 4, TILE.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 4:
			sheet.blit_rect(rows[r][c], Rect2i(0, 0, TILE.x, TILE.y), Vector2i(c * TILE.x, r * TILE.y))
	sheet.save_png(out.path_join(name))
	print("humanoid_portability_capture: wrote %s (%d rows)" % [name, rows.size()])
	rows.clear()


func _tread_boxes(model: StairModel, origin: Vector3) -> void:
	for k in range(1, model.count + 1):
		var span := model.tread_span(k)
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(model.width, model.tread_top(k) , span.y - span.x)
		box.mesh = mesh
		box.position = origin + model.direction * ((span.x + span.y) * 0.5) + Vector3(0, model.tread_top(k) * 0.5, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.5, 0.42)
		box.material_override = material
		stage.add_child(box)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://task09"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.21, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	stage = Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	armed.mira = _spawn(-0.7, "mira", true)
	armed.small = _spawn(0.7, "small", true)
	bare.mira = _spawn(-0.7, "mira", false)
	bare.small = _spawn(0.7, "small", false)
	bare.mira.position.x += 40.0   # far from the equipped pair, so the frames do not show the other two
	bare.small.position.x += 40.0
	await _wait(1.0)
	# ---- Sheet 1, equipped: standing, turning, crouching, kneeling, aiming.
	await _row(armed.mira, armed.small)
	print("ROW standing")
	armed.mira.face_yaw(deg_to_rad(70.0))
	armed.small.face_yaw(deg_to_rad(70.0))
	await _wait(0.5)
	await _row(armed.mira, armed.small)
	print("ROW turning")
	armed.mira.face_yaw(0.0)
	armed.small.face_yaw(0.0)
	await _wait(0.8)
	for key in armed:
		armed[key].set_crouched(true)
	await _wait(1.3)
	await _row(armed.mira, armed.small)
	for key in armed:
		armed[key].set_crouched(false)
	await _wait(1.0)
	print("ROW crouch")
	armed.mira.enter_cover(0.0, false, 0.55, 0)
	armed.small.enter_cover(0.0, false, 0.32, 0)
	await _wait(1.6)
	await _row(armed.mira, armed.small)
	armed.mira.leave_cover()
	armed.small.leave_cover()
	await _wait(1.0)
	print("ROW kneel")
	for key in armed:
		armed[key].set_aiming(true)
	await _wait(1.4)
	await _row(armed.mira, armed.small)
	print("ROW aim")
	for key in armed:
		armed[key].set_aiming(false)
	await _wait(0.8)
	armed.mira.pick_up(armed.mira.global_position + Vector3(0, 0, 0.6))
	armed.small.pick_up(armed.small.global_position + Vector3(0, 0, 0.6))
	await _wait(3.0)
	await _row(armed.mira, armed.small)
	print("ROW carry")
	armed.mira.put_down()
	armed.small.put_down()
	await _wait(3.0)
	_save("task09-equipped.png", out)
	# ---- Sheet 2, unarmed: standing, walking, running, interaction; then the hands on the weapon and the feet on stairs.
	await _row(bare.mira, bare.small)
	print("ROW unarmed standing")
	for i in 90:
		for key in bare:
			bare[key].report_velocity(Vector3(0, 0, 1.4), DT)
		await process_frame
	await _row(bare.mira, bare.small)
	print("ROW walking")
	for i in 100:
		for key in bare:
			bare[key].report_velocity(Vector3(0, 0, 4.2), DT)
		await process_frame
	await _row(bare.mira, bare.small)
	print("ROW running")
	for key in bare:
		bare[key].report_velocity(Vector3.ZERO, DT)
	await _wait(0.8)
	for key in bare:
		bare[key].inspect(bare[key].global_position + Vector3(0, 0, 1.0), 4.0)
	await _wait(1.6)
	await _row(bare.mira, bare.small)
	print("ROW interaction")
	# hands on the weapon (close-ups of the equipped pair, aimed)
	var fresh := {"mira": _spawn(-80.0, "mira", true), "small": _spawn(-78.6, "small", true)}   # a pair that has not carried anyone
	await _wait(0.8)
	for key in fresh:
		fresh[key].set_aiming(true)
	await _wait(1.6)
	var close: Array[Image] = []
	for key in ["mira", "small"]:
		var k := float(fresh[key].rig.body_ratio())
		var base: Vector3 = fresh[key].global_position
		var chest := base + Vector3(0, 1.28 * k, 0.5 * k)
		close.append(await _grab(base + Vector3(1.1 * k, 1.5 * k, 1.5 * k), chest, 30.0))   # from the shooter's left: the support hand on the handguard
		close.append(await _grab(base + Vector3(-1.1 * k, 1.5 * k, 1.3 * k), chest, 30.0))   # from the right: the firing hand and the stock in the shoulder
	rows.append(close)
	print("ROW hands")
	# stairs: each character on its own stairs, walking and then stopped half way
	var stair_models := {}
	var origins := {"mira": Vector3(-6, 0, 3), "small": Vector3(-6, 0, 12)}
	for key in ["mira", "small"]:
		var model := StairModel.new()
		model.low = origins[key]
		model.direction = Vector3.BACK
		model.tread_depth = 0.4 if key == "mira" else 0.25
		model.tread_rise = 0.2 if key == "mira" else 0.1
		model.count = 10 if key == "mira" else 12
		model.width = 1.6
		stair_models[key] = model
		_tread_boxes(model, origins[key])
	var stair_hosts := {"mira": _spawn(-6, "mira", false), "small": _spawn(-6, "small", false)}
	await _wait(0.6)
	for key in stair_hosts:
		var model: StairModel = stair_models[key]
		var host: ExplorationCharacterHost = stair_hosts[key]
		host.begin_stairs(model, true)
		var s := -0.6
		var half := model.end_s() * 0.5
		while s < half:
			s += 1.4 / 60.0
			host.global_position = model.point_at(s, model.ride_path_height_at(s, host.rig.stair_profile.riser_ramp))
			host.report_velocity(Vector3(0, 0, 1.4), DT)
			host.set_stairs_progress(s, 1.4)
			await process_frame
		for i in 60:
			host.report_velocity(Vector3.ZERO, DT)
			host.set_stairs_progress(s, 0.0)
			await process_frame
	var stair_row: Array[Image] = []
	for key in ["mira", "small"]:
		var host: ExplorationCharacterHost = stair_hosts[key]
		var k := float(host.rig.body_ratio())
		var focus: Vector3 = host.global_position + Vector3(0, 0.45 * k + 0.1, 0)
		stair_row.append(await _grab(focus + Vector3(3.0 * k + 1.0, 0.4, 0.0), focus, 36.0))
		stair_row.append(await _grab(focus + Vector3(1.7 * k + 0.9, 0.5, -1.4 * k - 0.6), focus, 36.0))
	rows.append(stair_row)
	print("ROW stairs")
	_save("task09-unarmed-contacts.png", out)
	quit(0)
