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
	_test_configuration_and_replay_data()
	await _test_match_setup_roster_editor()
	await _test_spawned_rosters()
	print("Tactical archetype laboratory: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_catalog_and_independent_state() -> void:
	check(TacticalArchetypeCatalog.validate_catalog().is_empty(), "Archetype catalog definitions are valid and unique")
	check(TacticalArchetypeCatalog.all().size() == 5, "Laboratory exposes five initial archetypes")
	var shield := TacticalArchetypeCatalog.get_definition(&"shieldbearer")
	check(shield != null and shield.shield_capable, "Shieldbearer declares shield capability")
	for definition in TacticalArchetypeCatalog.all():
		if definition.archetype_id != &"shieldbearer":
			check(not definition.shield_capable, "%s does not advertise a shield" % definition.display_name)

	var first := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	var second := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	first.show_world_hud = false
	second.show_world_hud = false
	shield.apply_starting_configuration(first)
	shield.apply_starting_configuration(second)
	check(first.stats != second.stats, "Spawned units own independent runtime stats")
	first.stats.current_hp = 1
	first.shield_capable = false
	check(second.stats.current_hp != 1, "Changing one unit's HP does not affect another")
	check(second.shield_capable and shield.shield_capable, "Runtime capability changes do not mutate shared Resources")
	var override := TacticalArchetype.new()
	override.max_hp = 140
	override.max_ap = 3
	override.apply_starting_configuration(first)
	check(first.stats.current_hp == 140 and first.stats.max_hp == 140, "HP overrides initialize both current and maximum HP")
	check(first.stats.current_ap == 3 and first.stats.max_ap == 3, "AP overrides initialize both current and maximum AP")
	first.free()
	second.free()

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
