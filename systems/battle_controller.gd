extends Node3D
class_name BattleController

const SquadContextData = preload("res://systems/ai/squad_context.gd")
const ActionCameraDirectorData = preload("res://systems/camera/action_camera_director.gd")

signal move_mode_toggled(is_active: bool)
signal attack_mode_toggled(is_active: bool)
signal attack_preview_changed(text: String)
signal attack_resolved(attacker: TacticalUnit, target: TacticalUnit, did_hit: bool, hit_chance: int)
signal action_state_changed(is_busy: bool)
signal units_registered(player_units: Array[TacticalUnit])
signal debug_enemy_control_changed(enabled: bool)
signal debug_player_ai_changed(enabled: bool)
signal ai_decision_recorded(record: Dictionary)
signal unit_moved(unit: TacticalUnit, from_cell: Vector3i, to_cell: Vector3i)
signal unit_defeated_in_battle(unit: TacticalUnit)
signal replay_action_committed(record: Dictionary)

@export var tactical_unit: TacticalUnit
@export var mouse_raycaster: MouseRaycaster
@export var grid_cursor: GridCursor
@export var path_visualizer: PathVisualizer
@export var cover_visualizer: CoverVisualizer
@export var shot_trajectory_visualizer: ShotTrajectoryVisualizer
@export var grid_manager: GridManager
@export var turn_manager: TurnManager
@export var debug_shots: bool = false

const UNIFORM_AP_COST = 1

var pathfinder := Pathfinder.new()
var last_map_validation: MapValidationResult
var last_map_quality: MapQualityReport
var current_movement_zone: Array[Vector3i] = []
var current_attack_zone: Array[Vector3i] = []
var _last_attack_preview := ""
var debug_enemy_control: bool = false
var debug_player_ai: bool = false
var ai_difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.NORMAL
var battle_seed: int = 1
var ai_decision_seed: int = 1
var _combat_rng := RandomNumberGenerator.new()
var _squad_contexts: Dictionary[int, SquadContext] = {}
var replay_mode := false
var action_camera_director: Node
var is_action_in_progress: bool = false:
	set(value):
		if is_action_in_progress != value:
			is_action_in_progress = value
			action_state_changed.emit(value)
var is_move_mode_active: bool = false:
	set(value):
		if is_move_mode_active != value:
			is_move_mode_active = value
			move_mode_toggled.emit(is_move_mode_active)
			if not is_move_mode_active:
				path_visualizer.clear_path()
				path_visualizer.clear_range_zone()
				cover_visualizer.clear()

var is_attack_mode_active: bool = false:
	set(value):
		if is_attack_mode_active != value:
			is_attack_mode_active = value
			attack_mode_toggled.emit(is_attack_mode_active)
			if not is_attack_mode_active:
				path_visualizer.clear_range_zone()
				if shot_trajectory_visualizer:
					shot_trajectory_visualizer.clear()

func _ready() -> void:
	if not mouse_raycaster or not grid_manager or not grid_manager.map_floor or not path_visualizer or not cover_visualizer or not turn_manager or not grid_cursor:
		push_error("Missing critical node assignments on BattleController!")
		return

	turn_manager.turn_phase_changed.connect(_on_turn_phase_changed)
	turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	mouse_raycaster.floor_clicked.connect(_on_floor_clicked)
	mouse_raycaster.unit_clicked.connect(_on_unit_clicked)

func initialize_battle(prebuilt_map: MapData = null) -> bool:
	_combat_rng.seed = ai_decision_seed * 2147483647 + 104729
	if prebuilt_map:
		grid_manager.map_data = prebuilt_map
		MapGraphBuilder.build(prebuilt_map, pathfinder)
	else:
		pathfinder.clear()
		MapBuilder.build(grid_manager, pathfinder)
		# Let CSG collision bodies enter the physics world before scanning.
		await get_tree().create_timer(0.05).timeout
		MapBuilder.scan_obstacles(get_world_3d(), grid_manager, pathfinder)
	MissionZonePlanner.populate_defaults(grid_manager.map_data, pathfinder)
	var faction_counts := {
		TacticalUnit.Faction.PLAYER: 0,
		TacticalUnit.Faction.ALLY: 0,
		TacticalUnit.Faction.ENEMY: 0,
	}
	for roster_unit in turn_manager.player_units + turn_manager.allied_units + turn_manager.enemy_units:
		faction_counts[roster_unit.faction] = faction_counts.get(roster_unit.faction, 0) + 1
	last_map_validation = MapValidator.validate(grid_manager.map_data, pathfinder, faction_counts)
	if not last_map_validation.is_valid():
		push_error("Battlefield validation failed:\n%s" % last_map_validation.describe())
		return false
	print_rich("[color=green][MapValidator][/color] PASSED — %d cells, %d traversal links, %d spawn cells" % [
		grid_manager.map_data.cells.size(),
		grid_manager.map_data.traversal_links.size(),
		grid_manager.map_data.get_total_spawn_count(),
	])
	last_map_quality = MapQualityEvaluator.evaluate(grid_manager.map_data, pathfinder)
	print_rich("[color=medium_purple][MapQuality][/color] battle seed %d | map %s%s — %s" % [
		battle_seed,
		last_map_quality.source_kind.to_upper(),
		" seed %d" % last_map_quality.map_seed if grid_manager.map_data.source_kind.begins_with("generated") else "",
		last_map_quality.summary(),
	])

	var battle_units: Array[TacticalUnit] = turn_manager.player_units + turn_manager.allied_units + turn_manager.enemy_units
	for unit_item in battle_units:
		var start_grid = world_to_grid(unit_item.global_position - Vector3.UP * unit_item.standing_height)
		grid_manager.register_unit(unit_item, start_grid)
		unit_item.defeated.connect(_on_unit_defeated)
	_orient_units_toward_opposition(battle_units)
	units_registered.emit(turn_manager.player_units)

	turn_manager.start_battle()
	return true

func _orient_units_toward_opposition(units: Array[TacticalUnit]) -> void:
	# Generated deployments have no authored facing. Use the opposing team's
	# center so each formation begins with a coherent, combat-ready direction.
	for unit_item in units:
		if not is_instance_valid(unit_item):
			continue
		var hostile_center := Vector3.ZERO
		var hostile_count := 0
		for other in units:
			if is_instance_valid(other) and FactionRules.are_hostile(unit_item.faction, other.faction):
				hostile_center += other.global_position
				hostile_count += 1
		if hostile_count > 0:
			unit_item.face_world_position(hostile_center / float(hostile_count))

func toggle_move_mode() -> void:
	if is_current_phase_manually_controlled() and not is_action_in_progress:
		is_move_mode_active = not is_move_mode_active
		if is_move_mode_active:
			is_attack_mode_active = false
			update_unit_movement_zone()

func toggle_attack_mode() -> void:
	if not is_current_phase_manually_controlled() or is_action_in_progress:
		return
	if not tactical_unit or not tactical_unit.stats or tactical_unit.stats.current_ap < UNIFORM_AP_COST:
		return

	if is_attack_mode_active:
		is_attack_mode_active = false
		return

	if is_move_mode_active:
		is_move_mode_active = false
	is_attack_mode_active = true
	update_attack_range()

func _process(_delta: float) -> void:
	if not turn_manager or not is_current_phase_manually_controlled():
		return

	var floor_hit = mouse_raycaster.get_floor_raycast_result() if mouse_raycaster else {}
	if not floor_hit.is_empty() and grid_cursor:
		grid_cursor.update_hover_position(floor_hit.position)
	if not is_move_mode_active or not is_instance_valid(tactical_unit) or tactical_unit.is_moving:
		path_visualizer.clear_path()
	else:
		_update_movement_preview(floor_hit)

	_update_attack_preview()

func _update_movement_preview(floor_hit: Dictionary) -> void:
	if not floor_hit.is_empty():
		var hover_grid = world_to_grid(floor_hit.position)
		if current_movement_zone.has(hover_grid):
			var path = _get_path_to_position(floor_hit.position)
			if path.size() > 1:
				path_visualizer.draw_path(path, Color(0.0, 0.5, 1.0, 0.4))
				return
	path_visualizer.clear_path()

func _update_attack_preview() -> void:
	var preview = ""
	var trajectory_drawn := false
	if is_attack_mode_active and is_instance_valid(tactical_unit):
		var hovered = mouse_raycaster.get_unit_under_mouse()
		if is_instance_valid(hovered) and hovered != tactical_unit:
			var evaluation = evaluate_attack(tactical_unit, hovered)
			preview = "%d%% HIT" % evaluation.hit_chance if evaluation.is_legal else evaluation.reason.to_upper()
			if evaluation.is_legal and evaluation.obstruction != "Clear":
				preview += " — %s" % evaluation.obstruction.to_upper()
			if shot_trajectory_visualizer:
				shot_trajectory_visualizer.draw_trajectory(
					CombatRules.get_shot_origin(tactical_unit, grid_manager),
					evaluation.aim_point,
					evaluation
				)
				trajectory_drawn = true
	if not trajectory_drawn and shot_trajectory_visualizer:
		shot_trajectory_visualizer.clear()
	if preview != _last_attack_preview:
		_last_attack_preview = preview
		attack_preview_changed.emit(preview)

func _on_unit_clicked(unit: TacticalUnit) -> void:
	if is_action_in_progress or not is_instance_valid(unit) or not unit.stats or unit.stats.is_defeated:
		return
	if is_attack_mode_active and is_instance_valid(tactical_unit) \
		and FactionRules.are_hostile(tactical_unit.faction, unit.faction):
		await try_attack(tactical_unit, unit)
		return

	if not debug_player_ai and turn_manager.select_player_unit(unit):
		is_move_mode_active = false
		is_attack_mode_active = false

func _on_floor_clicked(raw_position: Vector3) -> void:
	if is_action_in_progress or not is_move_mode_active or not is_instance_valid(tactical_unit):
		return

	var clicked_grid = world_to_grid(raw_position)
	if not current_movement_zone.has(clicked_grid):
		return

	var path = _get_path_to_position(raw_position)
	if path.is_empty():
		return

	await try_move(tactical_unit, clicked_grid)

func _on_turn_phase_changed(_new_phase: TurnManager.TurnPhase) -> void:
	var is_player_control = is_current_phase_manually_controlled()
	grid_cursor.visible = is_player_control
	if not is_player_control:
		is_move_mode_active = false
		is_attack_mode_active = false

func _on_active_unit_changed(unit: TacticalUnit) -> void:
	tactical_unit = unit
	is_move_mode_active = false
	is_attack_mode_active = false

func update_unit_movement_zone() -> void:
	if not tactical_unit or tactical_unit.is_moving:
		return

	var movement_budget = tactical_unit.stats.speed if tactical_unit.stats else 6
	var unit_grid = grid_manager.get_unit_grid(tactical_unit)
	var raw_reachable = pathfinder.get_reachable_cells(unit_grid, movement_budget)

	current_movement_zone = raw_reachable.filter(
		func(cell: Vector3i) -> bool:
			if cell == unit_grid:
				return true
			return grid_manager.can_unit_occupy_cell(tactical_unit, cell)
	)

	path_visualizer.draw_range_zone(current_movement_zone)
	cover_visualizer.draw_for_cells(current_movement_zone)

func update_attack_range() -> void:
	current_attack_zone.clear()
	if not tactical_unit or not tactical_unit.stats:
		path_visualizer.clear_range_zone()
		return

	var attacker_grid = grid_manager.get_unit_grid(tactical_unit)
	for grid_pos in pathfinder.grid_to_id_map.keys():
		var point_id = pathfinder.grid_to_id_map[grid_pos]
		if pathfinder.astar.is_point_disabled(point_id):
			continue

		var distance = CombatRules.attack_distance(attacker_grid, grid_pos, grid_manager)
		if distance == 0 or distance > tactical_unit.attack_range:
			continue

		var world_pos = grid_manager.grid_to_world(grid_pos)
		if CombatRules.has_line_of_sight_to_position(tactical_unit, world_pos, grid_manager, get_world_3d()):
			current_attack_zone.append(grid_pos)

	path_visualizer.draw_range_zone(current_attack_zone, Color(0.95, 0.2, 0.2, 0.3))

func _get_path_to_position(target_world_pos: Vector3) -> PackedVector3Array:
	var start_grid = grid_manager.get_unit_grid(tactical_unit)
	var end_grid = world_to_grid(target_world_pos)
	return pathfinder.calculate_3d_path(start_grid, end_grid)

func world_to_grid(pos: Vector3) -> Vector3i:
	return grid_manager.world_to_grid(pos)

func can_attack(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	return evaluate_attack(attacker, target).is_legal

func evaluate_attack(attacker: TacticalUnit, target: TacticalUnit) -> CombatRules.AttackEvaluation:
	return CombatRules.evaluate_attack(attacker, target, grid_manager, get_world_3d())

func set_debug_enemy_control(enabled: bool) -> void:
	if debug_enemy_control == enabled:
		return
	debug_enemy_control = enabled
	is_move_mode_active = false
	is_attack_mode_active = false
	debug_enemy_control_changed.emit(enabled)
	_on_turn_phase_changed(turn_manager.current_phase)

func set_debug_player_ai(enabled: bool) -> void:
	if debug_player_ai == enabled:
		return
	debug_player_ai = enabled
	is_move_mode_active = false
	is_attack_mode_active = false
	debug_player_ai_changed.emit(enabled)
	_on_turn_phase_changed(turn_manager.current_phase)

func is_current_phase_manually_controlled() -> bool:
	if not turn_manager:
		return false
	if replay_mode:
		return false
	return (not debug_player_ai and turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN) \
		or (debug_enemy_control and turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN)

func get_squad_context(unit: TacticalUnit) -> SquadContext:
	var team_id := 0 if unit.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY] else 1
	if not _squad_contexts.has(team_id):
		_squad_contexts[team_id] = SquadContextData.new()
	var context: SquadContext = _squad_contexts[team_id]
	context.begin_round(turn_manager.current_round)
	return context

func record_ai_decision(actor: TacticalUnit, action: String, subject: String, reason: String, alternatives: String, mission_goal := "None", squad_adjustments := "None", position_scores := "None", target_scores := "None", position_candidates: Array[Dictionary] = [], target_candidates: Array[Dictionary] = []) -> void:
	var actor_name := "Unknown"
	if is_instance_valid(actor):
		actor_name = String(actor.name)
	ai_decision_recorded.emit({
		"actor": actor_name,
		"action": action,
		"subject": subject,
		"reason": reason,
		"alternatives": alternatives,
		"mission_goal": mission_goal,
		"squad_adjustments": squad_adjustments,
		"position_scores": position_scores,
		"target_scores": target_scores,
		"position_candidates": position_candidates.duplicate(true),
		"target_candidates": target_candidates.duplicate(true),
		"difficulty": AIDifficultyPolicy.get_label(ai_difficulty),
	})

func try_attack(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	if is_action_in_progress or not turn_manager.can_unit_act(attacker):
		return false
	var evaluation = evaluate_attack(attacker, target)
	if debug_shots:
		var blocker = evaluation.blocking_cell
		print("[Shot] ", attacker.name, " ", grid_manager.get_unit_grid(attacker), " -> ", target.name, " ", grid_manager.get_unit_grid(target), " legal=", evaluation.is_legal, " chance=", evaluation.hit_chance, " visibility=", evaluation.obstruction, " reason=", evaluation.reason)
		if blocker:
			print("[Shot] blocker=", blocker.grid_position, " cover=", blocker.cover_type, " height=", blocker.cover_height, " walkable=", blocker.walkable)
	if not evaluation.is_legal:
		return false

	var attack_cmd = AttackAction.new(attacker, target, UNIFORM_AP_COST, evaluation.hit_chance, _combat_rng.randf() * 100.0)
	if not attack_cmd.is_valid():
		return false
	var will_defeat: bool = attack_cmd.roll_override < float(attack_cmd.hit_chance) and target.stats.current_hp <= 25
	is_action_in_progress = true
	var camera_presented := false
	if not replay_mode and action_camera_director:
		camera_presented = await action_camera_director.present(attacker, &"attack", target.global_position, attacker.stats.current_ap - UNIFORM_AP_COST, will_defeat)
	if not attack_cmd.execute():
		is_action_in_progress = false
		return false
	attacker.present_attack(target.global_position)
	attack_resolved.emit(attacker, target, attack_cmd.did_hit, evaluation.hit_chance)
	record_replay_action("attack", attacker, {
		"target": String(target.name),
		"did_hit": attack_cmd.did_hit,
		"hit_chance": evaluation.hit_chance,
	})

	is_attack_mode_active = false
	is_move_mode_active = false
	if camera_presented:
		await get_tree().create_timer(0.42).timeout
		await action_camera_director.finish_live_presentation(true)
	is_action_in_progress = false
	return true

func try_defend(unit: TacticalUnit) -> bool:
	if is_action_in_progress or not turn_manager.can_unit_act(unit):
		return false
	var action = DefendAction.new(unit, UNIFORM_AP_COST)
	if not action.is_valid():
		return false
	is_action_in_progress = true
	var camera_presented := false
	if not replay_mode and action_camera_director:
		var facing := unit.visual_adapter.global_basis.z if is_instance_valid(unit.visual_adapter) else Vector3.FORWARD
		camera_presented = await action_camera_director.present(unit, &"defend", unit.global_position + facing * 3.0, unit.stats.current_ap - UNIFORM_AP_COST)
	if not action.execute():
		is_action_in_progress = false
		return false
	record_replay_action("defend", unit)
	is_move_mode_active = false
	is_attack_mode_active = false
	if camera_presented:
		await get_tree().create_timer(0.25).timeout
		await action_camera_director.finish_live_presentation(true)
	is_action_in_progress = false
	return true

func try_move(unit: TacticalUnit, target_cell: Vector3i) -> bool:
	if is_action_in_progress or not turn_manager.can_unit_act(unit):
		return false
	var movement_budget = unit.stats.speed if unit.stats else 0
	var start_cell = grid_manager.get_unit_grid(unit)
	if not pathfinder.get_reachable_cells(start_cell, movement_budget).has(target_cell):
		return false
	var path = pathfinder.calculate_3d_path(start_cell, target_cell)
	if path.is_empty():
		return false
	var action = MoveAction.new(unit, target_cell, _build_movement_path(unit, path), grid_manager, UNIFORM_AP_COST)
	if not action.is_valid():
		return false
	is_action_in_progress = true
	is_move_mode_active = false
	is_attack_mode_active = false
	var camera_presented := false
	if not replay_mode and action_camera_director:
		camera_presented = await action_camera_director.present(unit, &"move", grid_manager.grid_to_world(target_cell), unit.stats.current_ap - UNIFORM_AP_COST)
	if not action.execute():
		is_action_in_progress = false
		return false
	await unit.movement_finished
	unit_moved.emit(unit, start_cell, target_cell)
	record_replay_action("move", unit, {
		"from": [start_cell.x, start_cell.y, start_cell.z],
		"to": [target_cell.x, target_cell.y, target_cell.z],
	})
	if camera_presented:
		await action_camera_director.finish_live_presentation(true)
	is_action_in_progress = false
	return true

func record_replay_action(kind: String, actor: TacticalUnit, details: Dictionary = {}) -> void:
	var record := {
		"kind": kind,
		"actor": String(actor.name) if is_instance_valid(actor) else "",
		"round": turn_manager.current_round if turn_manager else 0,
		"phase": int(turn_manager.current_phase) if turn_manager else -1,
	}
	for key in details:
		record[key] = details[key]
	replay_action_committed.emit(record)

func _build_movement_path(unit: TacticalUnit, path: PackedVector3Array) -> PackedVector3Array:
	var animated_path := PackedVector3Array()
	for point in path:
		var cell = grid_manager.get_cell_data(world_to_grid(point))
		var standing_height = unit.standing_height
		if cell and cell.cover_type == MapCellData.CoverType.LOW:
			standing_height += cell.cover_height
		animated_path.append(point + Vector3.UP * standing_height)
	return animated_path

func _on_unit_defeated(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit):
		return

	unit_defeated_in_battle.emit(unit)
	grid_manager.unregister_unit_at(grid_manager.get_unit_grid(unit))
	turn_manager.remove_unit(unit)
	if tactical_unit == unit:
		tactical_unit = null
	is_move_mode_active = false
	is_attack_mode_active = false
	unit.finish_defeat_presentation()

func register_mission_unit(unit: TacticalUnit, grid_position: Vector3i) -> void:
	grid_manager.register_unit(unit, grid_position)
	unit.defeated.connect(_on_unit_defeated)

func extract_unit(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit):
		return
	grid_manager.unregister_unit_at(grid_manager.get_unit_grid(unit))
	turn_manager.remove_extracted_unit(unit)
	unit.queue_free()
