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
	await _check_environment_isolation()
	print("Battle dependency isolation: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_environment_isolation() -> void:
	var outside := Node3D.new()
	var external_environment := WorldEnvironment.new()
	external_environment.name = "WorldEnvironment"
	external_environment.environment = Environment.new()
	external_environment.environment.background_color = Color(0.12, 0.34, 0.56)
	outside.add_child(external_environment)
	var external_geometry := CSGBox3D.new()
	external_geometry.use_collision = true
	external_geometry.add_to_group("terrain_features")
	outside.add_child(external_geometry)
	var external_hazard := TileHazardMarker.new()
	external_hazard.position = Vector3(0.5, 0, 0.5)
	outside.add_child(external_hazard)
	root.add_child(outside)
	var original_environment := external_environment.environment
	var battles: Array[BattleLevel] = []
	var first_environment: Environment
	for index in 2:
		var config := BattleConfiguration.new()
		config.generated_map = true
		config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
		config.battle_seed = 16 + index
		var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		level.configure_battle(config)
		root.add_child(level)
		await process_frame
		await process_frame
		battles.append(level)
		check(level.battle_initialization_succeeded, "Overlapping Depot battle %d initializes" % index)
		var local_environment := level.get_node("Environment/WorldEnvironment") as WorldEnvironment
		check(local_environment.environment.fog_enabled, "Depot atmosphere is applied to its own battle %d" % index)
		check(external_environment.environment == original_environment and original_environment.background_color == Color(0.12, 0.34, 0.56), "Building a battle leaves an unrelated environment unchanged")
		check(external_geometry.visible and external_geometry.use_collision, "Building a battle leaves unrelated group-member visibility and collision unchanged")
		check(level.active_generated_map.get_cell(Vector3i(20, 0, 20)).hazard_condition == null, "Unrelated scene hazard cannot stamp this battlefield")
		if index == 0:
			first_environment = local_environment.environment
			first_environment.fog_light_color = Color(0.9, 0.1, 0.2)
			level._set_authored_geometry_enabled(true)
			var hazard := TileHazardMarker.new()
			hazard.position = Vector3(-9.5, 0, 15.5) # Depot cell (10, 0, 35).
			level.get_node("GeneratedTerrain").add_child(hazard)
			level.battle_controller._apply_authored_tile_hazards()
			check(level.active_generated_map.get_cell(Vector3i(10, 0, 35)).hazard_condition == hazard.condition, "A battle's own generated-environment hazard still stamps its tactical map")
		else:
			check((battles[0].get_node("Environment/WorldEnvironment") as WorldEnvironment).environment == first_environment and first_environment.fog_light_color == Color(0.9, 0.1, 0.2), "Replacement battle does not rewrite original atmosphere")
			var original_feature := battles[0].get_node("Environment/Obstacles/CentralLowBlock") as CSGShape3D
			check(original_feature.visible and original_feature.use_collision, "Replacement battle does not disable the original battle's geometry")
			check(level.active_generated_map.get_cell(Vector3i(10, 0, 35)).hazard_condition == null, "A hazard in another battle cannot leak into a replacement map")
	for level in battles:
		level.queue_free()
	outside.queue_free()
	await process_frame
