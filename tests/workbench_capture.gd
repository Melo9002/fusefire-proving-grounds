extends SceneTree
## Rendered evidence for Task 12 (explicit-only: needs a GPU, not part of the standard tiers): the real animation workbench, full window, each tab and the three scenarios, on both humanoids.
## Scenarios are played in fixed paused steps so each frame is reproducible. Writes PNGs into the folder given (default docs/claude/images/task12).
##   godot --path . --script res://tests/workbench_capture.gd -- <output-folder> [<window-width> <window-height>]
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
var out_dir := "res://docs/claude/images/task12"
var bench: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _open(character: StringName, armed: bool, tab: int) -> void:
	WorkbenchSession.character = character
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = tab
	bench = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(20)
	bench.step_seconds = 1.0 / 30.0

func _close() -> void:
	bench.queue_free()
	await _frames(3)

func _shot(name: String) -> void:
	await _frames(3)
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	image.save_png(path)
	print("saved %s (%dx%d)" % [path, image.get_width(), image.get_height()])

## Plays a scenario in paused steps up to `seconds`, leaving it paused there.
func _scrub(id: StringName, seconds: float) -> void:
	bench.start_scenario(id)
	bench.set_sim_paused(true)
	while bench.scenario_runner.running and bench.scenario_runner.time < seconds:
		bench.step_sim()
		await process_frame
	await _frames(3)

func _tab(index: int) -> void:
	bench.panel.tabs.current_tab = index
	bench.panel._refresh_left = 0.0
	await _frames(4)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 2:
		root.size = Vector2i(int(args[1]), int(args[2]))
		await _frames(3)
	# Character tab, MIRA armed and Small MIRA unarmed.
	await _open(&"mira_0", true, 0)
	await _shot("01-character-mira")
	bench.panel.tab_nodes[0]._check_broken()
	await _frames(3)
	(bench.panel.tab_nodes[0].get_parent().get_parent() as ScrollContainer).scroll_vertical = 100000   # the result is at the bottom of the tab
	await _shot("02-incompatible-profile")
	await _close()
	await _open(&"small_mira_0", false, 0)
	await _shot("03-character-small-unarmed")
	await _close()
	# A: tactical-style (MIRA armed), Diagnostics tab with the live state, the history and the pose stages.
	await _open(&"mira_0", true, 2)
	await _scrub(WorkbenchScenarios.TACTICAL, 7.2)
	await _shot("04-scenario-a-aim")
	await _scrub(WorkbenchScenarios.TACTICAL, 8.6)
	await _shot("05-scenario-a-fire")
	# Scenario tab.
	await _tab(1)
	await _shot("06-scenario-tab")
	await _close()
	# B: exploration-style on Small MIRA unarmed.
	await _open(&"small_mira_0", false, 2)
	await _scrub(WorkbenchScenarios.EXPLORATION, 8.4)
	await _shot("07-scenario-b-gesture")
	await _scrub(WorkbenchScenarios.EXPLORATION, 15.2)
	await _shot("08-scenario-b-interrupted")
	await _close()
	# C: stairs then ladder on both humanoids, contact overlays on.
	for entry in [[&"mira_0", true, "09-scenario-c-mira"], [&"small_mira_0", false, "10-scenario-c-small"]]:
		await _open(entry[0], entry[1], 2)
		await _scrub(WorkbenchScenarios.CONTACTS, 2.4)
		await _shot(entry[2] + "-stairs")
		await _scrub(WorkbenchScenarios.CONTACTS, 8.3)
		bench.look_from(Vector3(3.2, 1.7, 0.6), Vector3(0, 1.3, 0.3))   # the ladder slides past the fixed character: look at the upper body
		await _shot(entry[2] + "-ladder")
		await _close()
	# Evidence tab.
	await _open(&"mira_0", true, 3)
	await _shot("11-evidence-tab")
	await _close()
	print("workbench_capture: done")
	quit()
