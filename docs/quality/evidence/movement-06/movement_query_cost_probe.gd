extends "res://tests/combat_real_map_closure_test.gd"
## Measure the same warmed movement queries visible to the player on each case.
## Timings are synchronous elapsed time; these are not rendered frame intervals.

func _capture(name: String, level: BattleLevel, focus: Vector3) -> void:
	if name.ends_with("-move"):
		var battle := level.battle_controller
		var actor: TacticalUnit = level.turn_manager.player_units[0]
		var inventory := battle.query_move(actor)
		var destination := Vector3i(-1, -1, -1)
		for offset in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]:
			if battle.query_move(actor, actor.grid_position + offset).is_legal():
				destination = actor.grid_position + offset
				break
		check(destination.x >= 0, "Movement timing requires a legal adjacent target")
		if destination.x >= 0:
			var state := BattleStateFingerprint.capture(level.turn_manager, battle.grid_manager, level.objective_manager)
			var rng := battle.action_service.get_combat_rng_state()
			var range_cost := _timing(func(): return battle.query_move(actor))
			var route_cost := _timing(func(): return battle.query_move(actor, destination))
			check(state == BattleStateFingerprint.capture(level.turn_manager, battle.grid_manager, level.objective_manager)
				and rng == battle.action_service.get_combat_rng_state(), "Movement timings do not mutate tactical state or combat RNG")
			print("[MoveCost] ", JSON.stringify({"case": name, "actor": actor.tactical_id,
				"start": str(actor.grid_position), "target": str(destination), "options": inventory.legal_destination_cells.size(),
				"inventory": range_cost, "targeted": route_cost}))
	await super._capture(name, level, focus)
