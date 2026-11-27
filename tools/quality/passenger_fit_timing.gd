extends SceneTree
## What the passenger fit costs: building a carried body of another size the first time (the search runs) and every time after (it does not), and starting a loaded climb the first time and after. Wall time in the
## headless dummy renderer; compare with the same call for a body of the carrier's own kind (no fit), which is what every carry cost before.
##
##   godot_console --headless --path . --script res://tools/quality/passenger_fit_timing.gd

const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _bench(carrier: StringName) -> Node3D:
	WorkbenchSession.character = carrier
	WorkbenchSession.passenger = &""
	WorkbenchSession.armed = false
	WorkbenchSession.autostart_scenario = &""
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	for i in 10:
		await process_frame
	return bench


func _run() -> void:
	for pair in [[&"mira_0", &"mira_0"], [&"mira_0", &"small_mira_0"], [&"small_mira_0", &"mira_0"], [&"small_mira_0", &"small_mira_0"]]:
		PassengerFit.clear_cache()
		var line := "FIT %-13s carries %-13s" % [pair[0], pair[1]]
		for attempt in ["first (search)", "again (cached)"]:
			var bench := await _bench(pair[0])
			var rig: CharacterRig = bench.rig
			rig.passenger_definition = PassengerDefinition.for_character(pair[1])
			var start := Time.get_ticks_usec()
			rig.begin_carry()
			var carry_ms := (Time.get_ticks_usec() - start) / 1000.0
			await process_frame
			start = Time.get_ticks_usec()
			rig.begin_traversal(&"ladder", 3.0, 1, null, true)
			var ladder_ms := (Time.get_ticks_usec() - start) / 1000.0
			line += " | %s: carry %.1f ms, loaded climb start %.1f ms" % [attempt, carry_ms, ladder_ms]
			bench.queue_free()
			await process_frame
		print(line)
	quit()
