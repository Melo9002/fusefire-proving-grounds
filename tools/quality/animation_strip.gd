extends SceneTree
## A frame strip of a Workbench scenario for a person to compare before and after a change: the 3D view only, at fixed scenario times, side by side, same camera each frame. Rendered (needs a GPU),
## explicit only. Run it on two checkouts and look at the two images; numbers do not say whether it looks right.
##   godot --path . --resolution 1600x900 --script res://tools/quality/animation_strip.gd -- <out.png> <scenario> <mira_0|small_mira_0> <armed|unarmed> <t1,t2,...> [camera x,y,z:fx,fy,fz]
## With no camera the scenario's own camera is kept. Times are scenario seconds, reached by fixed 1/60 s steps (the same frames every run).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		printerr("usage: <out.png> <scenario> <character> <armed|unarmed> <t1,t2,...> [camera x,y,z:fx,fy,fz]")
		quit(2)
		return
	var out := args[0]
	WorkbenchSession.character = StringName(args[2])
	WorkbenchSession.armed = args[3] == "armed"
	WorkbenchSession.read_drafts = false
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var times: Array[float] = []
	for t in args[4].split(","):
		times.append(float(t))
	var camera := []
	if args.size() > 5:
		for part in args[5].split(":"):
			var c := part.split(",")
			camera.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
	var bench: Node3D = (load("res://tools/animation_workbench/pose_workbench.tscn") as PackedScene).instantiate()
	root.add_child(bench)
	for i in 20:
		await process_frame
	bench.panel.visible = false   # the 3D view only
	bench.status_label.visible = false
	bench.step_seconds = 1.0 / 60.0
	bench.start_scenario(StringName(args[1]))
	bench.set_sim_paused(true)
	var frames: Array[Image] = []
	for t in times:
		bench.step_sim(maxi(int(round((t - bench.scenario_runner.time) / bench.step_seconds)), 0))
		while bench.pending_steps() > 0:
			await process_frame
		if camera.size() == 2:
			bench.look_from(camera[0], camera[1])
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var size := image.get_size()
		var crop := image.get_region(Rect2i(int(size.x * 0.2), int(size.y * 0.1), int(size.x * 0.6), int(size.y * 0.85)))
		crop.resize(crop.get_width() / 2, crop.get_height() / 2)
		frames.append(crop)
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var strip := Image.create(w * frames.size(), h, false, frames[0].get_format())
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	strip.save_png(out)
	print("animation_strip: %s (%s, %s %s, at %s s)" % [out, args[1], args[2], args[3], ", ".join(times.map(func(t: float) -> String: return "%.2f" % t))])
	quit(0)
