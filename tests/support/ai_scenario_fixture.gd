extends RefCounted
## Controlled AI decision fixture (milestone 05 step 3). Not a test itself.
## A clean flat map (no random cover), exact unit placement, explicit cover, the
## legal options the shared queries report, and real AI decisions with their traces.
## Scenario files assert hard rules (legality) strictly and preferences as properties
## ("no worse than N of the best legal option"), never as one arbitrary tile.

var level: BattleLevel
var battle: BattleController
var grid: GridManager
var turns: TurnManager
var decisions: Array[Dictionary] = []
var outcomes: Array[Dictionary] = []

## Builds the battle. Difficulty defaults to HARD, which has no seeded lapses, so
## preference scenarios are deterministic; legality scenarios may use any tier.
func setup(host: SceneTree, players: int, enemies: int, allies := 0, mission: MissionDefinition = null,
		difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.HARD, enemy_archetypes: Array[StringName] = [],
		use_range := false) -> void:
	var config := BattleConfiguration.new()
	config.player_count = players
	config.enemy_count = enemies
	config.ally_count = allies
	config.battle_seed = 1
	# The flat fixture has no surface placement, so the AI's route-to-hostile movement does not
	# run on it (it paths to the occupied hostile cell). Movement scenarios use the Tactical Test
	# Range, which has surface placement like the current sites.
	if use_range:
		config.generated_map = true
		config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	else:
		config.generated_map = false
		config.map_size = Vector2i(32, 24)
	config.mission = mission
	config.difficulty = difficulty
	config.enemy_archetypes = enemy_archetypes
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	host.root.add_child(level)
	await host.create_timer(0.2).timeout
	battle = level.battle_controller
	grid = battle.grid_manager
	turns = level.turn_manager
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	if not use_range: clear_arena()
	battle.ai_decision_recorded.connect(func(record: Dictionary): decisions.append(record.duplicate(true)))
	battle.ai_action_outcome_recorded.connect(func(record: Dictionary): outcomes.append(record.duplicate(true)))

## The battle scene scatters cover on the flat map. Scenarios need exactly the cover they
## add themselves, so reset every cell to open ground first.
func clear_arena() -> void:
	for cell: MapCellData in grid.map_data.cells.values():
		cell.cover_type = MapCellData.CoverType.NONE
		cell.cover_height = 0.0
		cell.blocks_line_of_sight = false
		cell.walkable = true
		cell.can_stop = true
		cell.authored_shot_parts.clear()
		cell.authored_shot_bounds = AABB()
	grid.map_data.rebuild_los_index()
	rebuild_graph()

func dispose(host: SceneTree) -> void:
	level.queue_free()
	await host.process_frame
	await host.process_frame

func ai_of(unit: TacticalUnit) -> AIController:
	var parent := level.player_units_parent
	if unit.faction == TacticalUnit.Faction.ENEMY: parent = level.enemy_units_parent
	elif unit.faction == TacticalUnit.Faction.ALLY: parent = level.allied_units_parent
	return parent.get_node("%sAI" % unit.name) as AIController

func place(unit: TacticalUnit, cell: Vector3i) -> void:
	# A scenario that stands a unit on a solid or occupied cell proves nothing about the AI.
	if not grid.can_unit_occupy_cell(unit, cell):
		var data := grid.get_cell_data(cell)
		var holder := grid.get_unit_at(cell)
		push_error("Fixture places %s on an unusable cell %s (cell %s walkable %s can_stop %s occupied by %s)" % [unit.name, cell,
			data != null, data.walkable if data else "-", data.can_stop if data else "-", holder.name if holder else "nobody"])
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

## Nearest cell (same level) the unit can actually stand on, searching outward from `preferred`.
func free_cell_near(unit: TacticalUnit, preferred: Vector3i, radius := 6) -> Vector3i:
	for ring in range(0, radius + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring: continue
				var candidate := preferred + Vector3i(dx, 0, dz)
				if grid.can_unit_occupy_cell(unit, candidate): return candidate
	return Vector3i(-1, -1, -1)

## Real, physical cover that the shot geometry honors (same shape the combat tests use).
func set_cover(cell: Vector3i, type: MapCellData.CoverType, height: float) -> void:
	_apply_cover(cell, type, height)
	grid.map_data.rebuild_los_index()
	rebuild_graph()

func _apply_cover(cell: Vector3i, type: MapCellData.CoverType, height: float) -> void:
	var data := grid.get_cell_data(cell)
	data.cover_height = height
	data.cover_type = type
	data.walkable = type == MapCellData.CoverType.LOW
	data.can_stop = false
	data.blocks_line_of_sight = type == MapCellData.CoverType.FULL
	var part := AABB(data.world_position + Vector3(-0.45, 0, -0.45), Vector3(0.9, height, 0.9))
	data.authored_shot_parts.assign([part])
	data.authored_shot_bounds = part

## Impassable walls: not walkable, block sight. One graph rebuild for the whole set.
func set_walls(cells: Array[Vector3i]) -> void:
	for cell in cells:
		_apply_cover(cell, MapCellData.CoverType.FULL, 2.0)
		grid.get_cell_data(cell).walkable = false
	grid.map_data.rebuild_los_index()
	rebuild_graph()

## A full-height wall across the whole map for columns x_from..x_to, with one gap row at
## ground level. Every level in the band is walled so nothing can cross over or around.
func wall_band(x_from: int, x_to: int, gap_z: int) -> void:
	for cell: MapCellData in grid.map_data.cells.values():
		var p := cell.grid_position
		if p.x < x_from or p.x > x_to or (p.z == gap_z and p.y == 0): continue
		_apply_cover(p, MapCellData.CoverType.FULL, 2.0)
		cell.walkable = false
	grid.map_data.rebuild_los_index()
	rebuild_graph()

## Gives the activation to a unit (phase follows its faction), as the turn flow would.
func act_as(unit: TacticalUnit) -> void:
	if unit.faction == TacticalUnit.Faction.ENEMY: turns.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	elif unit.faction == TacticalUnit.Faction.ALLY: turns.current_phase = TurnManager.TurnPhase.ALLY_TURN
	else: turns.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	turns.active_unit = unit

func rebuild_graph() -> void:
	MapGraphBuilder.build(grid.map_data, battle.pathfinder)

## Makes one unit the only one acting: full AP and ammo, active, AI-controlled.
func ready_actor(unit: TacticalUnit, ap := 3, supply := 4) -> void:
	unit.tactical_state.reset()
	unit.stats.set_available_ap_for_setup(ap)
	unit.stats.current_supply_points = supply
	unit.attack_range = 10

# ---- Legal options, from the same shared queries the player and AI use ----

## {target_name: AttackQueryResult} for every hostile with a legal shot right now.
func legal_attacks(unit: TacticalUnit) -> Dictionary:
	var result := {}
	for hostile in turns.player_units + turns.allied_units + turns.enemy_units:
		if not is_instance_valid(hostile) or hostile == unit or not FactionRules.are_hostile(unit.faction, hostile.faction): continue
		var query := battle.query_attack(unit, hostile)
		if query.is_legal(): result[String(hostile.name)] = query
	return result

func best_expected_damage(unit: TacticalUnit) -> float:
	var best := 0.0
	for query in legal_attacks(unit).values():
		best = maxf(best, query.expected_damage)
	return best

func legal_moves(unit: TacticalUnit) -> Array[Vector3i]:
	var query := battle.query_move(unit)
	var cells: Array[Vector3i] = []
	if query.is_legal(): cells.assign(query.legal_destination_cells)
	return cells

# ---- Decisions ----

## Which hostile the AI would shoot first, without executing anything.
func choose_target(unit: TacticalUnit) -> TacticalUnit:
	var ai := ai_of(unit)
	ai._ensure_policy()
	ai._squad_context = battle.get_squad_context(unit)
	ai.current_mission_intent = ai._get_ai_mission_intent()
	return ai._find_attack_target()


## Runs the real activation (every AP the unit can spend) and returns what it did.
## Everything committed goes through the authoritative action service.
func activate(unit: TacticalUnit, host: SceneTree) -> Dictionary:
	decisions.clear()
	outcomes.clear()
	var ai := ai_of(unit)
	ai.current_mission_intent = ai._get_ai_mission_intent()
	var start := grid.get_unit_grid(unit)
	var ap_before := unit.stats.current_ap
	act_as(unit)
	if unit.faction == TacticalUnit.Faction.PLAYER: battle.set_debug_player_ai(true)
	await ai._run_activation()
	# A unit that extracted is removed from the battle; report that instead of reading a freed node.
	var present := is_instance_valid(unit) and not unit.is_queued_for_deletion()
	return {
		"start": start, "present": present,
		"end": grid.get_unit_grid(unit) if present else Vector3i(-1, -1, -1),
		"ap_spent": ap_before - unit.stats.current_ap if present else ap_before,
		"actions": decisions.map(func(r): return String(r.action)),
		"decisions": decisions.duplicate(true), "outcomes": outcomes.duplicate(true),
		"committed": outcomes.filter(func(o): return o.stage == "committed").map(func(o): return String(o.action)),
		"rejected": outcomes.filter(func(o): return o.stage == "rejected"),
	}
