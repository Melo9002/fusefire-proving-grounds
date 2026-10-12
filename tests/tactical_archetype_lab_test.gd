extends SceneTree

const BattleConfigurationData := preload("res://systems/battle_configuration.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_catalog_and_independent_state()
	_test_base_ap_configuration_and_compatibility()
	_test_configuration_and_replay_data()
	await _test_match_setup_roster_editor()
	await _test_spawned_rosters()
	print("Tactical archetype laboratory: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_catalog_and_independent_state() -> void:
	check(TacticalArchetypeCatalog.validate_catalog().is_empty(), "Archetype catalog definitions are valid and unique")
	check(TacticalArchetypeCatalog.all().size() == 5, "Laboratory exposes five initial archetypes")
	var shield := TacticalArchetypeCatalog.get_definition(&"shieldbearer")
	check(shield != null and shield.shield_capability != null, "Shieldbearer declares shield capability")
	for definition in TacticalArchetypeCatalog.all():
		check(definition.base_ap == 3 and definition.configured_base_ap() == 3, "%s declares the three-AP MIRA baseline" % definition.display_name)
		if definition.archetype_id != &"shieldbearer":
			check(definition.shield_capability == null, "%s does not advertise a shield" % definition.display_name)

	var first := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	var second := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	first.show_world_hud = false
	second.show_world_hud = false
	shield.apply_starting_configuration(first)
	shield.apply_starting_configuration(second)
	check(first.stats != second.stats, "Spawned units own independent runtime stats")
	first.stats.current_hp = 1
	first.stats.current_supply_points = 0
	first.shield_capability = null
	check(second.stats.current_hp != 1, "Changing one unit's HP does not affect another")
	check(second.stats.current_supply_points == 4 and shield.max_supply_points == 4, "Runtime Supply Points stay independent and never mutate the shared archetype")
	check(second.shield_capability != null and shield.shield_capability != null, "Runtime capability changes do not mutate shared Resources")
	var override := TacticalArchetype.new()
	override.max_hp = 140
	override.base_ap = 3
	override.max_supply_points = 7
	override.apply_starting_configuration(first)
	check(first.stats.current_hp == 140 and first.stats.max_hp == 140, "HP overrides initialize both current and maximum HP")
	check(first.stats.current_ap == 3 and first.stats.max_ap == 3, "AP overrides initialize both current and maximum AP")
	check(first.stats.current_supply_points == 7 and first.stats.max_supply_points == 7, "Inspector-authored SP capacity initializes both current and maximum Supply Points")
	first.free()
	second.free()

func _test_base_ap_configuration_and_compatibility() -> void:
	var two_ap := TacticalArchetype.new()
	two_ap.base_ap = 2
	var four_ap := TacticalArchetype.new()
	four_ap.base_ap = 4
	var inherited := TacticalArchetype.new()
	var two_ap_unit := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	var four_ap_unit := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	var inherited_unit := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	for unit in [two_ap_unit, four_ap_unit, inherited_unit]:
		unit.show_world_hud = false
	two_ap.apply_starting_configuration(two_ap_unit)
	four_ap.apply_starting_configuration(four_ap_unit)
	var inherited_fallback := inherited_unit.stats.max_ap
	inherited.apply_starting_configuration(inherited_unit)
	check(two_ap_unit.stats.base_ap == 2 and two_ap_unit.stats.max_ap == 2 and two_ap_unit.stats.current_ap == 2, "Inspector base AP configures a two-AP fixture without identity checks")
	check(four_ap_unit.stats.base_ap == 4 and four_ap_unit.stats.max_ap == 4 and four_ap_unit.stats.current_ap == 4, "Inspector base AP configures a four-AP fixture without identity checks")
	check(inherited.configured_base_ap() == 0 and inherited_unit.stats.max_ap == inherited_fallback, "Zero base AP preserves the TacticalUnit scene fallback")

	var legacy := load("res://tests/fixtures/legacy_max_ap_archetype.tres") as TacticalArchetype
	check(legacy != null and legacy.base_ap == 0 and legacy.max_ap == 2 and legacy.configured_base_ap() == 2, "Legacy serialized max_ap remains readable as a base-AP override")
	legacy.apply_starting_configuration(inherited_unit)
	check(inherited_unit.stats.max_ap == 2 and inherited_unit.stats.current_ap == 2, "Legacy max_ap applies through the same runtime configuration path")
	legacy.base_ap = 4
	check(legacy.configured_base_ap() == 4, "Visible base_ap takes explicit precedence over legacy max_ap")

	var scene_fixture: Node = load("res://tests/fixtures/scene_authored_ap_fixture.tscn").instantiate()
	root.add_child(scene_fixture)
	var scene_stats := scene_fixture.get_node("UnitStats") as UnitStats
	check(scene_stats.max_ap == 4 and scene_stats.current_ap == 4, "Existing scene-authored runtime max_ap remains unchanged")
	var property_usage := {}
	for property in two_ap.get_property_list():
		property_usage[StringName(property.name)] = int(property.usage)
	check((int(property_usage.get(&"base_ap", 0)) & PROPERTY_USAGE_EDITOR) != 0, "base_ap is visible in the Inspector")
	check((int(property_usage.get(&"max_ap", 0)) & PROPERTY_USAGE_STORAGE) != 0 and (int(property_usage.get(&"max_ap", 0)) & PROPERTY_USAGE_EDITOR) == 0, "Legacy max_ap is storage-only and cannot compete in the Inspector")

	for unit in [two_ap_unit, four_ap_unit, inherited_unit]:
		unit.free()
	scene_fixture.free()

func _test_configuration_and_replay_data() -> void:
	var config := BattleConfigurationData.new()
	config.player_count = 3
	config.enemy_count = 2
	config.ally_count = 1
	config.player_archetypes = [&"marksman"]
	config.enemy_archetypes = [&"sentinel", &"missing"]
	config.normalize_rosters()
	check(config.player_archetypes == [&"marksman", &"generic", &"generic"], "Increasing a roster appends Generic slots")
	check(config.enemy_archetypes == [&"sentinel", &"generic"], "Unknown archetypes fall back safely to Generic")
	check(config.ally_archetypes == [&"generic"], "Legacy count-only allies default to Generic")
	config.player_count = 1
	config.normalize_rosters()
	check(config.player_archetypes == [&"marksman"], "Decreasing a roster removes trailing slots")
	var data := config.to_replay()
	var restored := BattleConfigurationData.new()
	restored.apply_replay(data)
	check(restored.player_archetypes == config.player_archetypes, "Archetype roster survives configuration round trip")
	var legacy := BattleConfigurationData.new()
	legacy.apply_replay({"player_count": 2, "enemy_count": 1, "ally_count": 1})
	check(legacy.player_archetypes == [&"generic", &"generic"] and legacy.enemy_archetypes == [&"generic"] and legacy.ally_archetypes == [&"generic"], "Count-only replay configuration remains Generic-compatible")

func _test_match_setup_roster_editor() -> void:
	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	check(setup.get_node("CenterContainer/Panel/Margin/VBox/Body/SetupTabs").get_tab_count() == 4, "Roster editor preserves the four Match Setup tabs")
	check(setup.roster_entries != null and setup.roster_entries.get_child_count() == 2, "Player roster starts with one entry per configured combatant")
	setup.player_archetypes[0] = &"marksman"
	setup.player_count.value = 3
	check(setup.player_archetypes == [&"marksman", &"generic", &"generic"], "UI count increase preserves edited slots and appends Generic")
	setup.enemy_archetypes[0] = &"sentinel"
	check(setup.player_archetypes[0] == &"marksman", "Editing an enemy slot does not change the player roster")
	setup.player_count.value = 1
	check(setup.player_archetypes == [&"marksman"], "UI count decrease removes only trailing entries")
	check(setup.deployment_summary.text.contains("Player-controlled: 1"), "Battle Briefing follows synchronized force totals")
	setup.queue_free()
	await process_frame

func _test_spawned_rosters() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	var config := BattleConfigurationData.new()
	config.player_count = 2
	config.enemy_count = 2
	config.ally_count = 1
	config.player_archetypes = [&"shieldbearer", &"marksman"]
	config.enemy_archetypes = [&"sentinel", &"support"]
	config.ally_archetypes = [&"support"]
	config.generated_map = true
	config.map_size = Vector2i(24, 20)
	config.battle_seed = 3110
	config.include_vip = true
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	check(level.turn_manager.player_units[0].archetype_id == &"shieldbearer", "Player slot 1 spawns as Shieldbearer")
	check(level.turn_manager.player_units[1].archetype_id == &"marksman", "Player slot 2 spawns as Marksman")
	for unit in level.turn_manager.player_units + level.turn_manager.enemy_units + level.turn_manager.allied_units:
		check(unit.stats.max_ap == 3 and unit.stats.current_ap == 3, "%s spawns with the three-AP MIRA baseline" % unit.tactical_id)
	check(level.turn_manager.enemy_units[0].archetype_id == &"sentinel" and level.turn_manager.enemy_units[1].archetype_id == &"support", "Enemy slots preserve independent selections")
	var combat_ally: TacticalUnit
	var vip: TacticalUnit
	for unit in level.turn_manager.allied_units:
		if not unit.mission_actor or not unit.mission_actor.is_vip(): combat_ally = unit
	for unit in level.turn_manager.player_units + level.turn_manager.allied_units:
		if unit.mission_actor and unit.mission_actor.is_vip(): vip = unit
	check(is_instance_valid(combat_ally) and combat_ally.archetype_id == &"support", "AI ally receives its configured archetype")
	check(is_instance_valid(vip) and vip.archetype_id == &"generic", "Mission VIP remains separate from combatant roster configuration")
	check(level.turn_manager.player_units[0].tactical_id == &"PlayerUnit1" and level.turn_manager.enemy_units[1].tactical_id == &"EnemyUnit2", "Archetypes do not change deterministic tactical IDs")
	check(level._replay_configuration.player_archetypes == [&"shieldbearer", &"marksman"], "Replay configuration captures the normalized roster")
	var first_signature := _roster_signature(level)
	level.queue_free()
	await process_frame
	await process_frame

	var replay_config := BattleConfigurationData.new()
	replay_config.apply_replay(config.to_replay())
	var reconstructed := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	reconstructed.configure_battle(replay_config)
	root.add_child(reconstructed)
	await create_timer(0.2).timeout
	check(_roster_signature(reconstructed) == first_signature, "The same seed and replay configuration reproduce equivalent generated-map rosters")
	reconstructed.queue_free()
	await process_frame
	await process_frame

func _roster_signature(level: BattleLevel) -> Array[String]:
	var signature: Array[String] = []
	for unit in level.turn_manager.player_units + level.turn_manager.enemy_units + level.turn_manager.allied_units:
		signature.append("%s:%d:%s" % [unit.tactical_id, unit.faction, unit.archetype_id])
	signature.sort()
	return signature
