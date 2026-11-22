extends SceneTree
## Rendered check of small_mira_0 on the REAL rig stack (exploration host, unarmed), next to MIRA for scale. Needs a display:
##   godot_console --path . --script res://art/characters/small_mira_0/tools/rig_capture.gd -- <out_dir>
## Nothing in production references this; the small_mira_0 model/profile are swapped into the MIRA host scene in memory only.
const HOST := "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn"
const MODEL := "res://art/characters/small_mira_0/models/small_mira_0.glb"
const PROFILE := "res://art/characters/small_mira_0/small_mira_0_rig_profile.tres"
const TILE := Vector2i(640, 520)
var small: ExplorationCharacterHost
var mira: ExplorationCharacterHost
var cam: Camera3D
var tiles: Array[Image] = []
var velocity := Vector3.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _process(delta: float) -> bool:
	if small != null and velocity != Vector3.ZERO:
		small.report_velocity(velocity, delta); mira.report_velocity(velocity, delta)
	return false

func _host(x: float, use_small: bool) -> ExplorationCharacterHost:
	var h: ExplorationCharacterHost = load(HOST).instantiate()
	var rig: CharacterRig = h.get_node("Rig")
	rig.weapon_scene = null
	if use_small:
		rig.character_scene = load(MODEL)
		rig.character_scale = 1.0
		rig.rig_profile = load(PROFILE)
	h.position = Vector3(x, 0, 0)
	root.add_child(h)
	return h

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _snap(label: String) -> void:
	for view in [[Vector3(0.9, 1.3, 3.6), Vector3(0.0, 0.75, 0.0), 45.0], [Vector3(1.6, 0.9, 1.6), Vector3(0.55, 0.5, 0.0), 30.0]]:
		cam.fov = view[2]
		cam.look_at_from_position(view[0], view[1])
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS); img.convert(Image.FORMAT_RGBA8)
		tiles.append(img)
	print("SNAP ", label)

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.2, 0.21, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 35, 0); sun.shadow_enabled = true; root.add_child(sun)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); floor.mesh = pm; root.add_child(floor)
	cam = Camera3D.new(); root.add_child(cam); cam.current = true
	mira = _host(-0.6, false)
	small = _host(0.55, true)
	await _wait(1.0)
	var r: CharacterRig = small.get_node("Rig")
	print("ABSENT ", r.bones.absent, " DEGRADED ", r.bones.degraded)
	print("FOOT_POINT ", small.presenter.foot_point_problems())
	await _snap("idle")
	velocity = Vector3(0, 0, 1.2)
	await _wait(1.3); await _snap("walk")
	velocity = Vector3.ZERO
	await _wait(0.8)
	small.set_crouched(true); mira.set_crouched(true)
	await _wait(1.2); await _snap("crouch")
	small.set_crouched(false); mira.set_crouched(false)
	await _wait(1.0)
	small.face_yaw(PI); mira.face_yaw(PI)
	await _wait(1.0)
	small.begin_climb(2.0); mira.begin_climb(2.0)
	for i in 30:
		small.set_climb_height(0.4 * i / 30.0); mira.set_climb_height(0.4 * i / 30.0)
		await process_frame
	await _wait(0.3); await _snap("climb (from behind)")
	small.end_climb(); mira.end_climb()
	small.face_yaw(0.0); mira.face_yaw(0.0)
	await _wait(1.0)
	small.react_hit(); mira.react_hit()
	await _wait(0.25); await _snap("hit")
	await _wait(1.0)
	small.defeat(); mira.defeat()
	await _wait(2.0); await _snap("defeat")
	var cols := 4
	var sheet := Image.create(TILE.x * cols, TILE.y * ceili(tiles.size() / float(cols)), false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, TILE), Vector2i((i % cols) * TILE.x, (i / cols) * TILE.y))
	sheet.save_png(out.path_join("rig_sheet.png"))
	print("WROTE ", out.path_join("rig_sheet.png"))
	quit(0)
