extends SceneTree
## Presentation cost of the ladder and the carry, per simulation step, for the cases that exist on `main` (so the same script runs in both trees and the numbers can be compared): an unloaded character standing, an
## unloaded climb, a character carrying someone standing, and (only when the loaded-ladder presentation exists) a loaded climb. The time is wall time per `step_sim()` plus one engine frame in the headless dummy renderer,
## median of the second half of the run; it includes everything a frame runs (animation, modifiers, IK, the passenger's follow), not only the rig. A machine-dependent figure: compare two runs on one machine.
##
##   godot_console --headless --path . --script res://tools/quality/ladder_presentation_timing.gd -- [steps=240] [json=<path>]

const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
var _steps := 240


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "steps":
			_steps = int(parts[1])
		elif parts.size() == 2 and parts[0] == "json":
			output = parts[1]
	var result := {}
	for carrier in [&"mira_0", &"small_mira_0"]:
		result["%s standing" % carrier] = await _time(carrier, "stand")
		result["%s climbing, unloaded" % carrier] = await _time(carrier, "climb")
		result["%s carrying, standing" % carrier] = await _time(carrier, "carry")
		if ClassDB.class_exists(&"Node") and ResourceLoader.exists("res://presentation/characters/rig/loaded_ladder_carry.gd"):
			result["%s climbing, loaded" % carrier] = await _time(carrier, "loaded")
	for key in result:
		print("TIMING %-34s %.2f ms per step (p90 %.2f)" % [key, result[key].median, result[key].p90])
	if output != "":
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	quit()


func _time(carrier: StringName, mode: String) -> Dictionary:
	WorkbenchSession.character = carrier
	WorkbenchSession.armed = false
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	for i in 10:
		await process_frame
	var rig: CharacterRig = bench.rig
	if mode in ["carry", "loaded"]:
		rig.begin_carry()
		rig.animation_controller.play(&"carry_idle")
		for i in 20:
			await process_frame
	if mode in ["climb", "loaded"]:
		bench.start_ladder_demo(3.0, 1, 0.5, -1.0, "rails")
	bench.step_seconds = 1.0 / 60.0
	bench.set_sim_paused(true)
	var samples: Array[float] = []
	for step in _steps:
		var start := Time.get_ticks_usec()
		bench.step_sim()
		await process_frame
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	var second_half := samples.slice(_steps / 2)
	second_half.sort()
	bench.queue_free()
	await process_frame
	return {"median": second_half[second_half.size() / 2], "p90": second_half[int(second_half.size() * 0.9)]}
