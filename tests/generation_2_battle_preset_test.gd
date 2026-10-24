extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const SETUP_SCENE := preload("res://ui/match_setup.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_configuration_contract()
	await _test_match_setup_selection()
	var generation_2_level := await _test_generation_2_battle()
	if generation_2_level != null:
		_test_stale_dependency_rejection(generation_2_level)
		generation_2_level.queue_free()
		await process_frame
	await _test_invalid_runtime_selection()
	await _test_legacy_generated_isolation()
	print("Generation 2.0 battle preset: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_configuration_contract() -> void:
	var config := BattleConfiguration.new()
	check(config.battlefield_preset == BattleConfiguration.BattlefieldPreset.LEGACY, "legacy battlefield generation remains the configuration default")
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	check(config.validate_generation_selection().is_empty(), "the explicit Generation 2.0 industrial configuration is supported")
	var unsupported_size := BattleConfiguration.new()
	unsupported_size.apply_replay(config.to_replay())
	unsupported_size.map_size = Vector2i(40, 30)
	check(_has_code(unsupported_size.validate_generation_selection(), "UNSUPPORTED_GENERATION_2_MAP_SIZE"), "Generation 2.0 rejects unsupported map dimensions explicitly")
	var replay := config.to_replay()
	var restored := BattleConfiguration.new()
	restored.apply_replay(replay)
	check(restored.battlefield_preset == config.battlefield_preset and restored.battle_seed == 17 and restored.map_size == BattleConfiguration.GENERATION_2_MAP_SIZE, "replay configuration preserves Generation 2.0 identity, seed, and size")
	var historical := BattleConfiguration.new()
	historical.apply_replay({"generated_map": true, "seed": 4, "map_size": Vector2i(24, 20)})
	check(historical.battlefield_preset == BattleConfiguration.BattlefieldPreset.LEGACY, "historical replay data without a preset remains legacy")

func _test_match_setup_selection() -> void:
	var setup := SETUP_SCENE.instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	check(setup.generation_preset_option.selected == 0 and setup._selected_generation_preset() == BattleConfiguration.BattlefieldPreset.LEGACY, "Match Setup visibly defaults to the legacy generator")
	setup.generated_map_toggle.button_pressed = true
	setup.generation_preset_option.select(1)
	setup._on_generation_preset_selected(1)
	setup.seed_input.value = 17
	var selected := setup._build_battle_configuration()
	check(selected.uses_generation_2() and selected.generated_map, "Match Setup provides a deliberate Generation 2.0 opt-in")
	check(selected.map_size == BattleConfiguration.GENERATION_2_MAP_SIZE and selected.battle_seed == 17, "the opt-in carries its supported map size and explicit seed")
	check(setup.map_size_option.disabled, "Generation 2.0 disables the incompatible legacy size selector")
	check("60" in setup.map_size_option.get_item_text(setup.map_size_option.selected) and "50" in setup.map_size_option.get_item_text(setup.map_size_option.selected), "the disabled size control describes the active 60 x 50 Generation 2.0 contract")
	setup.generated_map_toggle.button_pressed = false
	check(setup._selected_generation_preset() == BattleConfiguration.BattlefieldPreset.LEGACY, "disabling generated maps visibly returns Match Setup to the legacy preset")
	setup.queue_free()
	await process_frame

func _test_generation_2_battle() -> BattleLevel:
	var config := _generation_2_config()
	config.mission = MissionCatalog.create_mission(0, config.enemy_count, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	var result := await _add_and_wait(level)
	check(result.success, "the real BattleLevel reaches a playable state through Generation 2.0: %s" % str(result.errors))
	if not result.success:
		level.queue_free()
		await process_frame
		return null
	check(level.active_battlefield_document != null, "BattleLevel retains the validated unified layout document")
	check(level.active_battlefield_document.validate().is_empty() and level.active_battlefield_document.provenance.generator_id == "coherent_environment_assembler", "runtime uses a dependency-valid coherent-generation document")
	check(level.active_battlefield_document.environment_id == String(BattleConfiguration.GENERATION_2_ENVIRONMENT), "runtime document preserves the industrial environment identity")
	check(level.active_battlefield_document.provenance.generation_seed == 17, "runtime document preserves the selected seed")
	check(level.active_generated_map == level.battle_controller.grid_manager.map_data and level.active_generated_map.source_kind == "layout_document_generated", "battle tactics consume the MapData compiled from that document")
	check(level.battle_controller.last_map_validation != null and level.battle_controller.last_map_validation.is_valid(), "the normal battle validation accepts the compiled tactical map")
	check(level.turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN and level.turn_manager.current_round == 1, "the initialized battle reaches a controllable player turn")
	check(level.turn_manager.player_units.size() == 2 and level.turn_manager.enemy_units.size() == 2, "document deployments spawn the requested combatants")
	check(level.objective_manager.get_objective(&"eliminate") != null, "the requested mission objective is initialized on the compiled battlefield")
	check(level._replay_recorder != null and level._replay_configuration.battlefield_preset == BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL, "replay initialization records the selected battlefield preset")
	var modular := level.get_node_or_null("GeneratedTerrain/ModularEnvironment")
	check(modular != null and modular.get_meta("environment_identity", &"") == BattleConfiguration.GENERATION_2_ENVIRONMENT and modular.get_meta("environment_identity_source", "") == "layout_document", "shared presentation selects the document's industrial identity")
	return level

func _test_stale_dependency_rejection(level: BattleLevel) -> void:
	var stale := BattlefieldLayoutDocument.from_dictionary(level.active_battlefield_document.to_dictionary())
	var changed := false
	for dependency in stale.dependencies:
		if dependency.get("kind", "") == "asset":
			dependency["geometry_sha256"] = "stale-runtime-fixture"
			changed = true
			break
	check(changed, "runtime document contains a concrete imported-asset dependency")
	var result := Generation2BattlefieldBuilder.compile_document(stale, _generation_2_config(), 1.0)
	check(not result.ok and _has_code(result.errors, "STALE_GEOMETRY_DEPENDENCY"), "stale runtime geometry dependencies fail visibly before battle activation")

func _test_invalid_runtime_selection() -> void:
	var config := _generation_2_config()
	config.generated_map = false
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	var result := await _add_and_wait(level)
	check(not result.success and _has_code(result.errors, "GENERATION_2_REQUIRES_GENERATED_MAP"), "unsupported Generation 2.0 configuration is rejected explicitly")
	check(level.get_node_or_null("GeneratedTerrain") == null and level.turn_manager.current_round == 0 and level.turn_manager.player_units.is_empty(), "configuration failure leaves no terrain, combatants, or playable turn behind")
	level.queue_free()
	await process_frame
	var incompatible := _generation_2_config()
	incompatible.refinery = true
	var builder_result := Generation2BattlefieldBuilder.build(incompatible, 1.0)
	check(not builder_result.ok and _has_code(builder_result.errors, "INCOMPATIBLE_GENERATION_PRESET"), "legacy special-map flags are rejected instead of silently changing Generation 2.0 content")

func _test_legacy_generated_isolation() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.LEGACY
	config.map_size = Vector2i(24, 20)
	config.battle_seed = 29
	config.player_count = 1
	config.enemy_count = 1
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	var result := await _add_and_wait(level)
	check(result.success, "explicit legacy generated battles still initialize")
	check(level.active_battlefield_document == null and level.active_generated_map != null and level.active_generated_map.source_kind == "generated_cover", "legacy generation remains isolated from the document-driven preset")
	level.queue_free()
	await process_frame

func _generation_2_config() -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	config.player_count = 2
	config.enemy_count = 2
	return config

func _add_and_wait(level: BattleLevel) -> Dictionary:
	var completed: Array = []
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors.duplicate(true)}), CONNECT_ONE_SHOT)
	root.add_child(level)
	var deadline := Time.get_ticks_msec() + 30000
	while completed.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if completed.is_empty(): return {"success": false, "errors": [{"code": "TEST_TIMEOUT", "message": "battle initialization did not finish within 30 seconds"}]}
	return completed[0]

func _has_code(errors: Array, code: String) -> bool:
	return errors.any(func(error): return error.get("code", "") == code)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
