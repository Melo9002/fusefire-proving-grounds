extends SceneTree
## Rendered evidence for Task 11 (explicit-only: needs a GPU, not part of the standard tiers): MIRA and Small MIRA, armed, on a 4 m ladder, drawn with the same rung heights the solver uses. One row per rig, six frames:
## mid-climb, a hand reaching, the hands letting go near the top, just after the hands let go (the rifle's grip owns the hands again: this frame used to keep a stale ladder contact on the grip), the top, and a
## climb interrupted mid-way (the ordinary pose is back at once).
##   godot --path . --script res://tests/contact_ladder_capture.gd -- <output.png>
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const TILE := Vector2i(300, 400)
const FRAMES := [1.6, 2.1, 3.25, 3.55, 3.95]
var stage: Node3D
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _ladder(profile: TraversalProfile) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.55, 0.2)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 4.0, 0.04)
		rail.mesh = box
		rail.material_override = material
		rail.position = Vector3(0.22 * side, 2.0, profile.ladder_plane_ahead + 0.04)
		stage.add_child(rail)
	for index in TraversalSolver.rung_count_for(profile, 4.0):
		var rung := MeshInstance3D.new()
		var rod := BoxMesh.new()
		rod.size = Vector3(0.44, 0.03, 0.03)
		rung.mesh = rod
		rung.material_override = material
		rung.position = Vector3(0.0, TraversalSolver.rung_height(profile, index, 4.0), profile.ladder_plane_ahead)
		stage.add_child(rung)


func _grab(host: ExplorationCharacterHost) -> Image:
	cam.look_at_from_position(host.global_position + Vector3(1.2, 1.05, 2.0), host.global_position + Vector3(0, 0.9, -0.1))
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://contact_ladder.png"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.21, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	root.add_child(sun)
	stage = Node3D.new()
	root.add_child(stage)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	_ladder(TraversalProfile.new())
	var rows: Array = []
	for key in SCENES:
		var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
		stage.add_child(host)
		await _frames(30)
		var tiles: Array[Image] = []
		host.rig.begin_traversal(&"ladder", 4.0, 1)
		for climbed: float in FRAMES:
			host.position.y = climbed
			host.rig.set_traversal_progress(climbed)
			await _frames(3)
			var grip: HandGripModifier = host.rig.grip_modifier
			print("%s climbed %.2f: grip contact %s orient %.1f" % [key, climbed, grip.contact_weight, grip.orient_weight])
			tiles.append(await _grab(host))
		host.rig.end_traversal()
		host.position.y = 0.0
		host.rig.begin_traversal(&"ladder", 4.0, 1)
		host.position.y = 1.9
		host.rig.set_traversal_progress(1.9)
		await _frames(3)
		host.rig.end_traversal()
		host.position.y = 1.9
		await _frames(3)
		tiles.append(await _grab(host))
		rows.append(tiles)
		host.queue_free()
	var sheet := Image.create(TILE.x * 6, TILE.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 6:
			sheet.blit_rect(rows[r][c], Rect2i(0, 0, TILE.x, TILE.y), Vector2i(c * TILE.x, r * TILE.y))
	sheet.save_png(out)
	print("contact_ladder_capture: wrote ", out)
	quit(0)
