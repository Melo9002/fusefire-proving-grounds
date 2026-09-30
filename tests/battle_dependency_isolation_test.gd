extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	# Put an unrelated manager first in the global group to detect discovery leaks.
	var unrelated := ObjectiveManager.new()
	unrelated.add_to_group("objective_manager")
	root.add_child(unrelated)
	var levels: Array[BattleLevel] = []
	for index in 2:
		var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		level.configure(1, 1, true, 8100 + index)
		root.add_child(level)
		levels.append(level)
		await create_timer(0.4).timeout
		var controllers := level.find_children("*", "AIController", true, false)
		check(controllers.size() == 2, "Both team AI controllers are exercised")
		for ai in controllers:
			check(ai.objective_manager == level.objective_manager, "AI receives owning battle objectives")
			check(ai._objective_manager == level.objective_manager, "AI initializes without global discovery")
		check(level._replay_recorder != null, "Battle creates its recorder")
		if level._replay_recorder:
			check(level._replay_recorder._objective_manager == level.objective_manager, "Recorder receives owning battle objectives")
	for level in levels:
		level.queue_free()
	unrelated.queue_free()
	await process_frame
	print("Battle dependency isolation: %d failure(s)" % failures)
	quit(1 if failures else 0)
