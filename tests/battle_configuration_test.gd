extends SceneTree
var failures := 0

func _initialize() -> void:
	var config := BattleConfiguration.new()
	config.apply_replay({"generated_map": true, "battlefield_id": &"service_depot", "industrial_warehouse": true, "player_count": 99, "enemy_count": -1})
	check(config.resolved_battlefield_id() == BattlefieldCatalog.SERVICE_DEPOT, "A named current map cannot be overridden by a stale legacy flag")
	var normalized := config.normalized()
	check(normalized.player_count == 5 and normalized.enemy_count == 1 and normalized.map_size == Vector2i(40, 40), "Configuration is normalized once before battle and replay")
	check(not normalized.aim_enabled and not normalized.shield_enabled and not normalized.supply_points_enabled, "Old missing feature flags keep their historical rules through normalization")
	check(config.player_count == 99, "Normalizing makes an independent snapshot")
	check(not normalized.get_property_list().any(func(property): return property.name in ["refinery", "industrial_warehouse", "refinery_2", "loading_yard"]), "Runtime configuration has one map selection representation")
	var old := BattleConfiguration.new()
	old.apply_replay({"industrial_warehouse": true})
	check(old.battlefield_id == BattlefieldCatalog.INDUSTRIAL_WAREHOUSE, "Old flag-only input is translated at the compatibility boundary")
	var modern := BattleConfiguration.new()
	modern.generated_map = true
	modern.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var copy := modern.normalized()
	copy.mission.title = "Changed copy"
	check(modern.mission.title != copy.mission.title and copy.aim_enabled and copy.shield_enabled, "Current rules and mission ownership survive the shared configuration codec")
	check(BattlefieldCatalog.id_from_configuration({"battlefield_id": &"service_depot", "loading_yard": true}) == BattlefieldCatalog.SERVICE_DEPOT, "Simulation and replay decode share canonical ID precedence")
	print("Battle configuration: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
