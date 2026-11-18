extends RefCounted
## Read-only F3 descriptions. Capture live action queries before pausing.
static func capture(battle: BattleController, destination: Vector3i, allow_actions: bool) -> Dictionary:
	var start := Time.get_ticks_usec()
	var grid := battle.grid_manager
	var actor := battle.turn_manager.active_unit
	var result := {"revision": battle.action_service.state_revision, "unit": "No active unit.", "movement": "Hover a destination before opening F3.", "targets": [], "map": "", "manifest": "", "squad": "No active squad context."}
	if is_instance_valid(actor) and actor.stats:
		var cell := grid.get_cell_data(actor.grid_position)
		var state := actor.tactical_state
		var lines := PackedStringArray([
			"%s · %s · %s" % [actor.tactical_id, TacticalUnit.Faction.keys()[actor.faction], actor.archetype_id],
			"HP %d/%d · AP %d/%d · Ammo/SP %d/%d" % [actor.stats.current_hp, actor.stats.max_hp, actor.stats.current_ap, actor.stats.max_ap, actor.stats.current_supply_points, actor.stats.max_supply_points],
			"Cell %s · move budget %d · weapon range %d" % [actor.grid_position, actor.stats.speed, actor.attack_range],
			"Aim %s · Guard %s · Shield %s" % [state.is_aiming if state else false, state.is_overwatching if state else false, state.is_shielding if state else false],
			"Carrying: %s" % (String(actor.carried_unit.tactical_id) if actor.is_carrying_unit() else "none"),
		])
		if state and state.is_shielding: lines.append("Shield facing %s · fixed world X/Z direction" % state.shield_facing)
		if cell:
			lines.append("Standing point %s
Support center %s
Within-cell offset %s" % [cell.world_position, cell.support_center, cell.world_position - cell.support_center])
			if grid.map_data.surface_placement_enabled:
				lines.append("Body radius %.2f · height %.2f · clearance %.2f" % [grid.map_data.body_radius, grid.map_data.body_height, grid.map_data.body_clearance])
				lines.append("Static body clear: %s · clear of other unit bodies: %s" % [SurfaceNavigation.body_clear(grid.map_data, cell.world_position), SurfaceNavigation.units_clear(grid, cell.world_position, cell.world_position, actor)])
		var conditions: Array[String] = []
		if actor.conditions:
			for condition in actor.conditions.active.values():
				conditions.append("%s (%d beats)" % [condition.definition.condition_id, condition.remaining_beats])
		conditions.sort()
		lines.append("Conditions: " + (", ".join(conditions) if not conditions.is_empty() else "none"))
		result.unit = "\n".join(lines)
		var squad: SquadContext = battle.peek_squad_context(actor)
		if squad:
			result.squad = "Reservations at F3 open · round %d
Destinations %s
Intended targets %s
Objective handlers %s
Corridor owner %s · %d cells
Current expiry: round/unit boundaries; explicit expiry refinement belongs to milestone 05." % [squad.round_number, squad.reserved_destinations, squad.intended_targets, squad.objective_handlers, squad.corridor_owner, squad.reserved_corridor.size()]
		if allow_actions:
			var inventory := battle.query_attack(actor)
			var ids: Array = inventory.candidate_results.keys()
			ids.sort()
			for target_id in ids:
				var target_actor := battle.action_service.actor_registry.resolve(target_id)
				if not is_instance_valid(target_actor) or not FactionRules.are_hostile(actor.faction, target_actor.faction): continue
				if result.targets.size() >= 8: break
				var query: AttackQueryResult = inventory.get_candidate(target_id)
				var text := TacticalFeedbackText.shot(query)
				if query.evaluation:
					text += "\nVisibility sample fraction %.2f · distance %.3f tiles" % [query.visibility_fraction, query.evaluation.distance_tiles]
					if query.evaluation.blocking_cell:
						text += "\nNearest explained blocker %s · highlighted bounds %s" % [query.evaluation.blocking_cell.grid_position, query.evaluation.blocking_bounds]
				result.targets.append({"id": String(target_id), "text": text})
			if destination.x >= 0:
				var move := battle.query_move(actor, destination)
				if move.is_legal():
					var enemies: Array[TacticalUnit] = []
					for candidate in battle.turn_manager.player_units + battle.turn_manager.enemy_units + battle.turn_manager.allied_units:
						if is_instance_valid(candidate) and FactionRules.are_hostile(actor.faction, candidate.faction): enemies.append(candidate)
					result.movement = TacticalFeedbackText.movement(move, actor, enemies, grid, battle.supply_points_enabled, battle.shield_enabled, battle.aim_enabled)
					result.movement += "\nDestination %s\nPath cells %s\nVisual traversal segments %s" % [destination, move.path_cells, move.visual_segments]
				else:
					result.movement = "Destination %s: %s\nBlocking actor: %s" % [destination, move.validation.message, move.blocking_actor_id]
		else:
			result.movement = "Live action snapshot unavailable: replay or battle already paused. Unit/map inspection remains available."
	result.map = "Source %s · %s · map seed %d\nCells %d · occupied %d · zones %d · traversal links %d\nSurface placement %s · resolved points %s\nMovement parts %d · shot obstacles %d\nGeneration errors %s" % [grid.map_data.source_kind, grid.map_data.map_size, grid.map_data.generation_seed, grid.map_data.cells.size(), grid.occupancy_map.size(), grid.map_data.zones.size(), grid.map_data.traversal_links.size(), grid.map_data.surface_placement_enabled, grid.map_data.surface_points_resolved, grid.map_data.movement_parts.size(), grid.map_data.shot_obstacles.size(), grid.map_data.generation_errors]
	if battle.last_map_validation: result.map += "\nTactical validation: %s" % ("passed" if battle.last_map_validation.is_valid() else "FAILED")
	result.map += "\nSurroundings are presentation; tactical cells/zones above define the playable area."
	var manifest := JSON.stringify(grid.map_data.content_manifest, "\t")
	result.manifest = manifest.left(12000) + ("\n… truncated; full manifest remains in the map/replay." if manifest.length() > 12000 else "")
	result.elapsed_ms = float(Time.get_ticks_usec() - start) / 1000
	return result

static func runtime_summary() -> String:
	var lines := PackedStringArray(["Simulation: " + BattleReplayRecording.SIMULATION_VERSION])
	lines.append("LIVE BATTLE · F3 inspection is unavailable during replay playback.")
	lines.append("\nRuntime monitors · last reported values (pause affects frame readings)")
	lines.append("FPS %.0f · process %.2f ms · physics %.2f ms" % [Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000])
	lines.append("Draw calls %.0f · rendered primitives %.0f · static memory %.1f MiB" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576])
	lines.append("AI planning/query latency is not instrumented here yet. Frame time is not AI thinking time.")
	return "\n".join(lines)
