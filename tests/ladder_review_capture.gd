extends SceneTree
## Rendered evidence for the ladder (explicit-only: needs a GPU, not part of the standard tiers). MIRA and Small MIRA on the SAME ladder (LadderGeometry.build_visual, the layout every consumer shares),
## seen from the side, the front and a three-quarter view, at the heights given. One row per body and view, one column per height. The camera aims at the knees/hands so the legs and arms are readable.
##   godot --path . --script res://tests/ladder_review_capture.gd -- <output.png> [heights comma separated] [armed|unarmed] [down]
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const TILE := Vector2i(360, 440)
## Camera offsets from the climber (character frame: x left, z toward the ladder) and where each looks.
const VIEWS := {
	"side": Vector3(-3.0, 0.0, 0.0),
	"front": Vector3(0.0, 0.2, 3.0),
	"three_quarter": Vector3(-2.0, 0.3, 2.2),
}
var stage: Node3D
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _grab(host: ExplorationCharacterHost, view: String, plane: float) -> Image:
	var focus := host.global_position + Vector3(0.0, 0.8, plane - 0.15)
	cam.look_at_from_position(focus + VIEWS[view], focus)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	# Crop to the tile's aspect first, then scale uniformly: resizing the whole 16:9 frame into a portrait tile would stretch the bodies.
	var wanted_width := int(round(float(img.get_height()) * TILE.x / TILE.y))
	var left := (img.get_width() - wanted_width) / 2
	img = img.get_region(Rect2i(left, 0, wanted_width, img.get_height()))
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://ladder_review.png"
	var heights: Array[float] = []
	for text in (args[1] if args.size() > 1 else "1.1,1.25,2.0,2.15").split(","):
		heights.append(float(text))
	var armed := not args.has("unarmed")
	var direction := -1 if args.has("down") else 1
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
	cam.fov = 28.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.87, 0.71, 0.3)
	var rows: Array = []
	for key in SCENES:
		var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
		if not armed:
			host.rig.weapon_scene = null
		stage.add_child(host)
		await _frames(30)
		var geometry := LadderGeometry.for_rise(4.0)
		var visual := geometry.build_visual(material)
		stage.add_child(visual)
		host.rig.begin_traversal(&"ladder", 4.0, direction)
		var per_view := {}
		for view in VIEWS:
			per_view[view] = []
		for climbed in heights:
			host.position.y = climbed
			host.rig.set_traversal_progress(climbed)
			await _frames(3)
			for view in VIEWS:
				(per_view[view] as Array).append(await _grab(host, view, geometry.plane_ahead))
		for view in VIEWS:
			rows.append(per_view[view])
		host.rig.end_traversal()
		visual.queue_free()
		host.queue_free()
	var sheet := Image.create(TILE.x * heights.size(), TILE.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in heights.size():
			sheet.blit_rect(rows[r][c], Rect2i(0, 0, TILE.x, TILE.y), Vector2i(c * TILE.x, r * TILE.y))
	sheet.save_png(out)
	print("ladder_review_capture: wrote ", out, " (rows: ", SCENES.keys(), " x ", VIEWS.keys(), ")")
	quit(0)
