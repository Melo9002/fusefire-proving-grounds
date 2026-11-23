extends SceneTree
## Close-up, annotated captures of the leg-and-ladder relationship, taken IN the animation workbench (the real scene, the real rig, the production solver and contacts, the workbench's own camera and its
## "Ladder collisions" overlay): red = skinned leg vertices inside a rung or rail, yellow = knees, green = pelvis, orange = planned feet, a label at the worst vertex. Explicit only (needs a GPU).
##   godot --path . --resolution 1280x720 --script res://tests/workbench_ladder_closeup_capture.gd -- <out.png> <mira_0|small_mira_0> <armed|unarmed> <up|down> <h1,h2,...> [view=side|front|three_quarter|knee]
## One tile per height, panel hidden, the camera close on the legs. The pose is held (rate 0) at each height and the capture waits until it has settled (PoseSettle), so the frame is reproducible.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const TILE := Vector2i(540, 640)
const VIEWS := {
	"side": [Vector3(1.5, 0.55, -0.05), Vector3(0.0, 0.5, -0.1)],
	"front": [Vector3(0.0, 0.6, 1.5), Vector3(0.0, 0.5, -0.1)],
	"three_quarter": [Vector3(1.1, 0.7, 1.1), Vector3(0.0, 0.5, -0.1)],
	"knee": [Vector3(0.9, 0.55, 0.75), Vector3(0.12, 0.45, -0.1)],
}

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	WorkbenchSession.character = StringName(args[1])
	WorkbenchSession.armed = args[2] == "armed"
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var direction := -1 if args[3] == "down" else 1
	var heights: Array[float] = []
	for text in String(args[4]).split(","):
		heights.append(float(text))
	var view := "side"
	for arg in args:
		if arg.begins_with("view="):
			view = arg.trim_prefix("view=")
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(15)
	bench.panel.visible = false
	var tiles: Array[Image] = []
	for h in heights:
		bench.start_ladder_demo(4.0, direction, 0.0, h)
		bench.diagnostics.set_ladder_overlay(true)
		bench.set_sim_paused(true)
		bench.look_from(VIEWS[view][0], VIEWS[view][1])
		# A pose asked for cold takes a few updates to arrive (ADDA Assignment 3: 23 leg vertices in a rung on the first update, none from the third on, all FRESH): wait for it to SETTLE, not for a fixed number of frames.
		var settle := PoseSettle.new(bench.rig.skeleton)
		var waited := 0
		while not settle.is_settled() and waited < 90:
			await process_frame
			waited += 1
		settle.release()
		await _frames(2)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var wanted_width := int(round(float(img.get_height()) * TILE.x / TILE.y))
		img = img.get_region(Rect2i((img.get_width() - wanted_width) / 2, 0, wanted_width, img.get_height()))
		img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		tiles.append(img)
	var sheet := Image.create(TILE.x * tiles.size(), TILE.y, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, TILE.x, TILE.y), Vector2i(i * TILE.x, 0))
	sheet.save_png(out)
	print("workbench_ladder_closeup_capture: ", out, " (", args[1], " ", args[2], " ", args[3], " ", view, " at ", heights, ")")
	quit(0)
