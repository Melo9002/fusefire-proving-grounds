extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene := load("res://units/tactical_unit.tscn") as PackedScene
	var unit := scene.instantiate() as TacticalUnit
	check(unit.mission_actor != null, "Every tactical unit has mission-actor metadata")
	check(unit.get_mission_actor_kind() == MissionActor.Kind.COMBATANT, "Existing units default to combatants")
	unit.faction = TacticalUnit.Faction.NEUTRAL
	unit.mission_actor.kind = MissionActor.Kind.RESCUABLE
	check(unit.mission_actor.is_rescuable() and unit.faction == TacticalUnit.Faction.NEUTRAL, "Mission role is independent from faction")
	unit.faction = TacticalUnit.Faction.ENEMY
	unit.mission_actor.kind = MissionActor.Kind.VIP
	check(unit.mission_actor.is_vip() and FactionRules.are_hostile(TacticalUnit.Faction.PLAYER, unit.faction), "An enemy VIP retains normal faction relationships")
	unit.mission_actor.extraction_capable = true
	check(unit.can_extract_others(), "Extraction is an independent actor capability")
	unit.free()

	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(2, 2, true, 12345, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	var all_units: Array[TacticalUnit] = level.turn_manager.player_units + level.turn_manager.allied_units + level.turn_manager.enemy_units
	var ids: Dictionary = {}
	for spawned in all_units:
		check(spawned.mission_actor != null and spawned.mission_actor.is_combatant(), "Spawned Beans preserve the default combat role")
		check(not spawned.get_mission_id().is_empty(), "Spawned mission actor receives a stable ID")
		check(not ids.has(spawned.get_mission_id()), "Spawned mission IDs are unique")
		ids[spawned.get_mission_id()] = true
	check(level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING, "Actor metadata does not alter existing battle results")
	level.queue_free()
	await process_frame

	var vip_level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	vip_level.configure(2, 1, true, 12345, 0, Vector2i(32, 24), true, MissionActor.VIPBehavior.HOLD_POSITION)
	root.add_child(vip_level)
	await create_timer(0.2).timeout
	var vip := vip_level.turn_manager.allied_units[0]
	var vip_start := vip.grid_position
	check(vip.name == "FriendlyVIP" and vip.mission_actor.is_vip(), "Setup adds a distinct friendly VIP")
	check(vip.faction == TacticalUnit.Faction.ALLY, "Automated VIP remains friendly")
	check(vip_level.turn_manager.player_units.size() == 2, "VIP does not replace a selected player combatant")
	vip_level.turn_manager.end_current_turn()
	await create_timer(1.5).timeout
	check(vip.grid_position == vip_start and vip.stats.current_ap == 0 and not vip.stats.is_defending, "Hold-position VIP stays put and ends its activation")
	vip_level.queue_free()
	await process_frame

	print("Mission actor roles: %d failure(s)" % failures)
	quit(1 if failures else 0)
