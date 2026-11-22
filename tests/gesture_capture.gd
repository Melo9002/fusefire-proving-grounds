extends SceneTree
## Rendered evidence for Task 10 (explicit-only: needs a GPU, not part of the standard tiers): the &"acknowledge" gesture on MIRA and the small robot, side by side, requested through ExplorationCharacterHost.gesture (the same call the
## workbench's F key makes on the presenter). One sheet, one row per scenario, time left to right:
##   1 unarmed, to completion      2 armed (the hand stays with the weapon)      3 armed and crouched      4 armed and aiming
##   5 interrupted by walking (and the walk that follows)      6 interrupted by a hit (and the recovery)
##   godot --path . --script res://tests/gesture_capture.gd -- <output_dir>
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const TILE := Vector2i(330, 330)
const DT := 1.0 / 60.0
var stage: Node3D
var cam: Camera3D
var rows: Array = []
var columns := 6


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _pair(x: float, armed: bool) -> Array:
	var hosts: Array = []
	var offset := -0.55
	for key in ["mira", "small"]:
		var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
		if not armed:
			host.rig.weapon_scene = null
		host.position = Vector3(x + offset, 0, 0)
		stage.add_child(host)
		hosts.append(host)
		offset = 0.55
	return hosts


func _grab(hosts: Array) -> Image:
	var heights := []
	for host in hosts:
		var sk: Skeleton3D = host.rig.skeleton
		var hand := sk.find_bone(host.rig.bones.right_arm[2])
		heights.append("%.2f" % (sk.global_transform * sk.get_bone_global_pose(hand).origin).y)
	print("  tile: ", hosts[0].get_presentation_state(), " / ", hosts[1].get_presentation_state(), " hand y ", heights)
	var mid: Vector3 = (hosts[0].global_position + hosts[1].global_position) * 0.5
	cam.fov = 32.0
	cam.look_at_from_position(mid + Vector3(0.9, 1.15, 2.3), mid + Vector3(0, 0.95, 0))
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


## A timeline: [{"t": seconds, "do": Callable (optional), "shot": true (optional)}, ...] in order, from the moment the row starts.
func _row(hosts: Array, timeline: Array) -> void:
	var tiles: Array[Image] = []
	var clock := 0.0
	for step: Dictionary in timeline:
		if float(step.t) > clock:
			await _wait(float(step.t) - clock)
			clock = float(step.t)
		if step.has("do"):
			(step.do as Callable).call()
		if step.get("shot", false):
			tiles.append(await _grab(hosts))
	while tiles.size() < columns:
		tiles.append(tiles.back())
	rows.append(tiles)


func _each(hosts: Array, action: Callable) -> void:
	for host in hosts:
		action.call(host)


func _walk(hosts: Array, frames: int) -> void:
	for i in frames:
		for host in hosts:
			host.report_velocity(Vector3(0, 0, 1.4), DT)
		await process_frame


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://task10"
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
	plane.size = Vector2(300, 300)
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true

	var bare := _pair(0.0, false)
	var armed := _pair(25.0, true)
	var crouched := _pair(50.0, true)
	var aiming := _pair(75.0, true)
	var walking := _pair(-90.0, false)
	var struck := _pair(-120.0, true)
	await _wait(1.0)
	var gesture := func(host: ExplorationCharacterHost) -> void: host.gesture(&"acknowledge")

	await _row(bare, [{"t": 0.0, "shot": true}, {"t": 0.0, "do": func() -> void: _each(bare, gesture)}, {"t": 0.25, "shot": true}, {"t": 0.6, "shot": true}, {"t": 1.0, "shot": true}, {"t": 1.45, "shot": true}, {"t": 2.6, "shot": true}])
	print("ROW unarmed")
	await _row(armed, [{"t": 0.0, "shot": true}, {"t": 0.0, "do": func() -> void: _each(armed, gesture)}, {"t": 0.25, "shot": true}, {"t": 0.6, "shot": true}, {"t": 1.0, "shot": true}, {"t": 1.45, "shot": true}, {"t": 2.6, "shot": true}])
	print("ROW armed")
	_each(crouched, func(host: ExplorationCharacterHost) -> void: host.set_crouched(true))
	await _wait(1.6)
	await _row(crouched, [{"t": 0.0, "shot": true}, {"t": 0.0, "do": func() -> void: _each(crouched, gesture)}, {"t": 0.25, "shot": true}, {"t": 0.6, "shot": true}, {"t": 1.0, "shot": true}, {"t": 1.45, "shot": true}, {"t": 2.6, "shot": true}])
	print("ROW crouched")
	_each(aiming, func(host: ExplorationCharacterHost) -> void: host.set_aiming(true))
	await _wait(1.6)
	await _row(aiming, [{"t": 0.0, "shot": true}, {"t": 0.0, "do": func() -> void: _each(aiming, gesture)}, {"t": 0.25, "shot": true}, {"t": 0.6, "shot": true}, {"t": 1.0, "shot": true}, {"t": 1.45, "shot": true}, {"t": 2.6, "shot": true}])
	print("ROW aiming")
	# Interrupted by walking at 0.6 s: the frames after are the walk.
	_each(walking, gesture)
	var tiles: Array[Image] = []
	await _wait(0.1)
	tiles.append(await _grab(walking))
	await _wait(0.5)
	tiles.append(await _grab(walking))
	for i in 3:
		await _walk(walking, 14)
		tiles.append(await _grab(walking))
	await _walk(walking, 40)
	tiles.append(await _grab(walking))
	rows.append(tiles)
	print("ROW interrupted by walking")
	# Interrupted by a hit at 0.6 s: the hit clip, then back to idle.
	_each(struck, gesture)
	tiles = []
	await _wait(0.1)
	tiles.append(await _grab(struck))
	await _wait(0.5)
	tiles.append(await _grab(struck))
	_each(struck, func(host: ExplorationCharacterHost) -> void: host.react_hit())
	await _wait(0.1)
	tiles.append(await _grab(struck))
	await _wait(0.2)
	tiles.append(await _grab(struck))
	await _wait(0.5)
	tiles.append(await _grab(struck))
	await _wait(1.0)
	tiles.append(await _grab(struck))
	rows.append(tiles)
	print("ROW interrupted by a hit")

	var sheet := Image.create(TILE.x * columns, TILE.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in columns:
			sheet.blit_rect(rows[r][c], Rect2i(0, 0, TILE.x, TILE.y), Vector2i(c * TILE.x, r * TILE.y))
	sheet.save_png(out.path_join("gesture-sheet.png"))
	print("gesture_capture: wrote gesture-sheet.png (%d rows)" % rows.size())
	quit(0)
