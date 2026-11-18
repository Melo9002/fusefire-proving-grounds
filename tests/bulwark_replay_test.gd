extends SceneTree
## Real AI battles with Bulwarks or Skirmishers (on either side) are recorded, saved, reloaded and replayed
## through the ordinary service: every action must verify, including weapon-scaled damage and the shield state
## that lives in the fingerprint. Limit, stated plainly: the AI rarely takes the Shield stance, so these matches
## seldom cover an attack; the capacity count itself is proven in bulwark_shield_test, and the covered attacks
## seen here are only reported.

const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
const SEEDS := [16, 17]
const CLASSES := [&"bulwark", &"skirmisher"]

var failures := 0
var checks := 0
var covered_attacks := 0
var overwhelmed_attacks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _on_committed(result: Variant) -> void:
	if result is AttackActionResult:
		if result.shield_applied: covered_attacks += 1
		for note in result.defense_notes:
			if String(note).contains("overwhelmed"): overwhelmed_attacks += 1

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 12.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	for class_id in CLASSES:
		for case_index in SEEDS.size() * 2:
			var bulwarks_are_players := case_index < SEEDS.size()
			var seed_value: int = SEEDS[case_index % SEEDS.size()]
			var label := "%s %s seed %d" % ["player" if bulwarks_are_players else "enemy", class_id, seed_value]
			var result := await simulator.run_match({
				"seed": seed_value,
				"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
				"player_count": 3, "enemy_count": 3,
				"battlefield_id": &"service_depot",
				"map_size": BattlefieldCatalog.map_size(&"service_depot", Vector2i(40, 40)),
				"difficulty": AIDifficultyPolicy.Tier.NORMAL,
				"maximum_rounds": 30, "stall_seconds": 8.0, "timeout_seconds": 60.0,
				"player_archetypes": [String(class_id), String(class_id), String(class_id)] if bulwarks_are_players else [],
				"enemy_archetypes": [] if bulwarks_are_players else [String(class_id), String(class_id), String(class_id)],
			})
			check(result.completed(), "%s: the match completes" % label)
			var recording: BattleReplayRecording = BattleReplaySession.last_recording
			check(recording != null and recording.is_playable(), "%s: the recording is playable" % label)
			if recording == null:
				continue
			var path := "res://.godot/bulwark-replay-test.json"
			check(recording.save_json(path) == OK, "%s: the recording saves" % label)
			var loaded := BattleReplayRecording.load_json(path)
			check(loaded != null and loaded.is_playable() and loaded.shield_capability_signature != "", "%s: it reloads and carries the shield identity" % label)
			DirAccess.remove_absolute(path)
			var replay := BattleScene.instantiate() as BattleLevel
			replay.configure_replay(loaded)
			root.add_child(replay)
			while replay.turn_manager.current_round == 0:
				await process_frame
			replay.battle_controller.action_service.action_committed.connect(_on_committed)
			var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
			player.set_playback_speed(8.0)
			var deadline := Time.get_ticks_msec() + 60000
			while not player.playback_complete and Time.get_ticks_msec() < deadline:
				await process_frame
			check(player.playback_succeeded and player.verified_actions == loaded.actions.size(), "%s: replay verifies %d/%d actions (%s)" % [label, player.verified_actions, loaded.actions.size(), player.last_divergence])
			replay.queue_free()
			await process_frame
			await process_frame
	print("Bulwark replay: %d checks, %d failure(s); %d covered attacks, %d overwhelmed" % [checks, failures, covered_attacks, overwhelmed_attacks])
	Engine.time_scale = previous_time_scale
	quit(1 if failures else 0)
