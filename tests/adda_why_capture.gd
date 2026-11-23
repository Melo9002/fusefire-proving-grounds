extends SceneTree
## A readable capture of ADDA's "Why?" workflow in the Workbench: play a scenario, ask "What happened?", pick the first finding of a kind, replay to its moment, show it on the body. The picture is the whole window: the
## panel with the finding in words, and the 3D view with the marker (cyan cross = where the pose put it, yellow diamond = what was asked, red line = the error, magenta = the bones, orange = the environment's own bar,
## green = its surface normal). Explicit only (needs a GPU).
##   godot --path . --resolution 1600x900 --script res://tests/adda_why_capture.gd -- <out.png> <mira_0|small_mira_0> <armed|unarmed> <scenario> <finding kind> [index] [mesh]
## Finding kinds: pose_snap, reach_exceeded, target_error, plant_slide, plant_settle, mesh_overlap.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"

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
	WorkbenchSession.start_tab = 4
	var scenario := StringName(args[3])
	var kind := String(args[4])
	var index := int(args[5]) if args.size() > 5 and String(args[5]).is_valid_int() else 0
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(15)
	var tab: WhyTab = bench.panel.tab_nodes[4]
	tab._mesh_check.button_pressed = "mesh" in args
	bench.step_seconds = 1.0 / 60.0
	bench.start_scenario(scenario)
	if "mesh" in args:
		bench.diagnostics.begin_recording(func() -> float: return float(bench.scenario_runner.time) if bench.scenario_runner.running else -1.0, true)
	bench.set_sim_paused(true)
	while bench.scenario_runner.running:
		bench.step_sim()
		await process_frame
	tab._analyze()
	var picked := []
	for finding: Dictionary in tab._report.findings:
		if finding.kind == kind:
			picked.append(finding)
	if picked.size() <= index:
		printerr("adda_why_capture: no %s finding #%d (%d found)" % [kind, index, picked.size()])
		quit(2)
		return
	tab._select(picked[index])
	tab._replay()
	while bench.pending_steps() > 0:
		await process_frame
	await _frames(3)
	tab._show_it()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out)
	print("adda_why_capture: %s (%s)" % [out, picked[index].title])
	quit(0)
