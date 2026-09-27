extends SceneTree

var failures := 0
var scored_record: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, true, 24104, 0, Vector2i(24, 20), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(0, 1))
	root.add_child(level)
	await create_timer(0.25).timeout
	level.battle_controller.ai_decision_recorded.connect(_capture_scored_record)
	var debug_tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	debug_tools.set_auto_battle(true)
	for tick in 140:
		if not scored_record.is_empty():
			break
		await create_timer(0.1).timeout
	debug_tools.set_auto_battle(false)
	check(not scored_record.is_empty(), "AI publishes a decision with scored movement candidates")
	if not scored_record.is_empty():
		var positions: Array = scored_record.position_candidates
		var legal: Array = positions.filter(func(candidate: Dictionary): return candidate.get("status", "") != "rejected")
		var rejected: Array = positions.filter(func(candidate: Dictionary): return candidate.get("status", "") == "rejected")
		check(not legal.is_empty(), "Scoring record contains legal movement candidates")
		check(legal.all(func(candidate: Dictionary): return candidate.has("score") and candidate.has("summary")), "Every legal movement candidate exposes a total and component summary")
		check(legal.filter(func(candidate: Dictionary): return candidate.get("chosen", false)).size() == 1, "Exactly one evaluated movement tile is marked as chosen")
		check(rejected.all(func(candidate: Dictionary): return candidate.has("reason")), "Rejected movement candidates expose reasons")
		check(scored_record.has("target_candidates"), "Decision record includes considered and rejected targets")
		debug_tools._set_ai_scoring_visible(true)
		debug_tools._ai_scoring_overlay.display(scored_record)
		await process_frame
		check(debug_tools._ai_scoring_overlay._score_labels.get_child_count() == legal.size(), "Overlay displays one numeric label per legal movement tile")
		check(debug_tools._ai_scoring_label.text.contains("CHOSEN") and debug_tools._ai_scoring_label.text.contains("Movement:"), "F3 details identify the chosen plan and movement totals")
	print("AI scoring overlay smoke: %d failure(s)" % failures)
	level.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _capture_scored_record(record: Dictionary) -> void:
	if not record.get("position_candidates", []).is_empty():
		scored_record = record.duplicate(true)

