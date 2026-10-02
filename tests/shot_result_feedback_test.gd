extends SceneTree

const ShotResultFeedbackData := preload("res://presentation/overlays/shot_result_feedback.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	var feedback = level.get_node("Visualizers/ShotResultFeedback")
	var attacker := level.turn_manager.player_units[0]
	var target := level.turn_manager.enemy_units[0]
	check(level.battle_controller.attack_resolved.is_connected(feedback._on_attack_resolved), "Feedback listens to the shared attack result")
	feedback._on_attack_resolved(attacker, target, false, 50)
	check(feedback.last_result_text == "MISS", "Misses create an explicit result")
	check(feedback._active_cues.size() == 1 and feedback._active_cues[0]["label"].text == "MISS", "Miss cue appears beside the target")
	feedback._on_attack_resolved(attacker, target, true, 50)
	check(feedback.last_result_text == "HIT", "Hits create an explicit result")
	check(feedback._active_cues.size() == 2 and feedback._active_cues[1]["label"].text == "HIT", "Hit cue uses the same presentation path")
	level.battle_controller.replay_mode = true
	feedback._on_attack_resolved(attacker, target, true, 50)
	check(feedback._active_cues.size() == 2, "Replay hides shot feedback by default")
	await create_timer(feedback.lifetime_seconds + 0.1).timeout
	check(feedback._active_cues.is_empty(), "Shot result cues clean themselves up")
	level.queue_free()
	await process_frame
	print("Shot result feedback: %d failure(s)" % failures)
	quit(1 if failures else 0)
