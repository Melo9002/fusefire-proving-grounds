extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_feature_gate_and_hidden_state_fingerprints()
	await _check_hud_observers()
	print("Tactical tempo replay/HUD integration: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_feature_gate_and_hidden_state_fingerprints() -> void:
	var current := BattleConfiguration.new()
	var replay_data := current.to_replay()
	check(replay_data.tactical_tempo_enabled, "New recordings opt into tactical-tempo fingerprints")
	var restored := BattleConfiguration.new()
	restored.apply_replay(replay_data)
	check(restored.tactical_tempo_enabled, "The tactical-tempo feature gate survives configuration round trip")
	var historical := BattleConfiguration.new()
	historical.apply_replay({"player_count": 1, "enemy_count": 1})
	check(not historical.tactical_tempo_enabled, "Historical configurations without the gate retain their old fingerprint shape")

	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	actor.stats.consume_ap(1)
	var old_shape_a := _capture(level, false)
	var tempo_shape_a := _capture(level, true)
	check(tempo_shape_a.contains("tempo=%s,3,3,3,1,2" % actor.tactical_id), "New fingerprints include Base, effective, capacity, spent, and current AP")

	actor.stats.set_ap_modifier(&"condition:test", -1)
	actor.stats.set_available_ap_for_setup(2)
	actor.stats.remove_ap_modifier(&"condition:test")
	check(actor.stats.current_ap == 2 and actor.stats.effective_max_ap == 3 and actor.stats.activation_capacity_ap == 2 and actor.stats.spent_ap == 0, "Fixture creates a second 2/3 display with different hidden tempo state")
	var old_shape_b := _capture(level, false)
	var tempo_shape_b := _capture(level, true)
	check(old_shape_a == old_shape_b, "Historical fingerprints intentionally cannot distinguish identical visible AP")
	check(tempo_shape_a != tempo_shape_b, "Feature-gated fingerprints detect hidden capacity and expenditure divergence")

	actor.stats.set_ap_modifier(&"z:test", -1)
	actor.stats.set_ap_modifier(&"a:test", -1)
	var ordered := _capture(level, true)
	check(ordered.find("ap_modifier=%s,a:test,-1" % actor.tactical_id) < ordered.find("ap_modifier=%s,z:test,-1" % actor.tactical_id), "AP modifier evidence uses stable canonical source ordering")
	level.queue_free()
	await process_frame

func _check_hud_observers() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var shared_label := Label.new()
	var shared_hud := APHUDController.new()
	shared_hud.add_child(shared_label)
	shared_hud.ap_label = shared_label
	root.add_child(shared_hud)
	shared_hud.call("_on_active_unit_changed", actor)

	var portrait := UnitPortrait.new()
	portrait.name_label = Label.new()
	portrait.hp_label = Label.new()
	portrait.ap_label = Label.new()
	portrait.state_label = Label.new()
	portrait.add_child(portrait.name_label)
	portrait.add_child(portrait.hp_label)
	portrait.add_child(portrait.ap_label)
	portrait.add_child(portrait.state_label)
	root.add_child(portrait)
	portrait.setup(actor)

	var world_label := Label.new()
	var world_bar := UnitWorldBar.new()
	world_bar.add_child(world_label)
	world_bar.ap_label = world_label
	root.add_child(world_bar)
	world_bar.setup(actor, actor.stats, actor.faction)
	check(shared_label.text == "AP: 3 / 3" and portrait.ap_label.text == "AP  3 / 3" and world_label.text == "3/3 AP", "All AP presentations initialize from the authoritative snapshot")

	actor.stats.set_ap_modifier(&"condition:test", -1)
	check(shared_label.text == "AP: 2 / 2" and portrait.ap_label.text == "AP  2 / 2" and world_label.text == "2/2 AP", "Capacity reduction updates HUD, portrait, and world display")
	actor.stats.remove_ap_modifier(&"condition:test")
	check(shared_label.text == "AP: 2 / 3" and portrait.ap_label.text == "AP  2 / 3" and world_label.text == "2/3 AP", "Modifier removal updates effective maximum without refunding current AP")
	actor.stats.consume_ap(1)
	check(shared_label.text == "AP: 1 / 3" and portrait.ap_label.text == "AP  1 / 3" and world_label.text == "1/3 AP", "Ordinary expenditure propagates through the same AP signal")
	actor.stats.refresh_activation()
	check(shared_label.text == "AP: 3 / 3" and portrait.ap_label.text == "AP  3 / 3" and world_label.text == "3/3 AP", "Legitimate refresh restores every AP presentation")

	shared_hud.queue_free()
	portrait.queue_free()
	world_bar.queue_free()
	level.queue_free()
	await process_frame

func _capture(level: BattleLevel, tempo: bool) -> String:
	return BattleStateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager, true, true, true, true, true, tempo)

func _create_battle() -> BattleLevel:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = 13135
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0:
		await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level
