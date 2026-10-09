extends Node3D
class_name BattleController

const SquadContextData = preload("res://systems/ai/squad_context.gd")
const ActionCameraDirectorData = preload("res://presentation/camera/action_camera_director.gd")

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
signal tactical_action_committed(result)

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
var _squad_contexts: Dictionary[int, SquadContext] = {}
var replay_mode := false
var action_camera_director: Node
var action_service: TacticalActionService
var action_presenter: TacticalActionPresenter
var _objective_manager: ObjectiveManager
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
	turn_manager.turn_ended.connect(_on_authoritative_turn_ended)
	turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	mouse_raycaster.floor_clicked.connect(_on_floor_clicked)
	mouse_raycaster.unit_clicked.connect(_on_unit_clicked)

func initialize_battle(prebuilt_map: MapData = null, mission: MissionDefinition = null) -> bool:
	if prebuilt_map:
		grid_manager.map_data = prebuilt_map
		MapGraphBuilder.build(prebuilt_map, pathfinder)
	else:
		pathfinder.clear()
		MapBuilder.build(grid_manager, pathfinder)
		# Let CSG collision bodies enter the physics world before scanning.
		await get_tree().create_timer(0.05, false).timeout
		MapBuilder.scan_obstacles(get_world_3d(), grid_manager, pathfinder)
	MissionZonePlanner.populate_defaults(grid_manager.map_data, pathfinder)
	preload("res://systems/objectives/extraction_transport_planner.gd").place(grid_manager.map_data, pathfinder, mission)
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
	_initialize_action_service()
	for unit_item in battle_units:
		_ensure_tactical_id(unit_item)
		if not action_service.register_actor(unit_item):
			return false
		var start_grid = world_to_grid(unit_item.global_position - Vector3.UP * unit_item.standing_height)
		grid_manager.register_unit(unit_item, start_grid)
		unit_item.defeated.connect(_on_unit_defeated)
	_orient_units_toward_opposition(battle_units)
	units_registered.emit(turn_manager.player_units)

	turn_manager.start_battle()
	return true

func _initialize_action_service() -> void:
	if is_instance_valid(action_service):
		return
	action_service = TacticalActionService.new()
	action_service.name = "TacticalActionService"
	add_child(action_service)
	action_presenter = TacticalActionPresenter.new()
	action_presenter.name = "TacticalActionPresenter"
	add_child(action_presenter)
	action_presenter.setup(
		action_service.actor_registry,
		grid_manager,
		action_camera_director,
		func() -> bool: return replay_mode,
		func(attacker, target, did_hit, hit_chance): attack_resolved.emit(attacker, target, did_hit, hit_chance),
		finalize_extracted_unit
	)
	turn_manager.action_completion_barrier = func() -> bool: return action_service.is_busy
	_configure_action_service(null)
	action_service.action_committed.connect(_on_tactical_action_committed)

func _configure_action_service(objectives: ObjectiveManager) -> void:
	action_service.setup(
		turn_manager,
		grid_manager,
		objectives,
		ai_decision_seed * 2147483647 + 104729,
		action_presenter.present_attack,
		_query_move_data,
		action_presenter.present_move,
		_on_movement_committed,
		action_presenter.present_simple,
		_validate_mission_action,
		_commit_mission_action,
		action_presenter.present_mission
	)

func bind_objective_manager(manager: ObjectiveManager) -> void:
	_objective_manager = manager
	if not is_instance_valid(action_service):
		_initialize_action_service()
	_configure_action_service(manager)

func _ensure_tactical_id(unit: TacticalUnit) -> void:
	if unit.tactical_id.is_empty():
		unit.tactical_id = StringName(unit.name)

func _on_tactical_action_committed(result) -> void:
	tactical_action_committed.emit(result)

func _query_move_data(unit: TacticalUnit, target_cell: Vector3i) -> Dictionary:
	var start_cell := grid_manager.get_unit_grid(unit)
	var movement_budget := unit.stats.speed if unit.stats else 0
	var reachable := pathfinder.get_reachable_cells(start_cell, movement_budget)
	var legal_destinations: Array[Vector3i] = []
	for candidate in reachable:
		if grid_manager.can_unit_occupy_cell(unit, candidate):
			legal_destinations.append(candidate)
	if target_cell == Vector3i(-1, -1, -1):
		return {"accepted": true, "movement_budget": movement_budget, "legal_destinations": legal_destinations}
	if not reachable.has(target_cell):
		return {"accepted": false, "code": "unreachable", "message": "Destination is unreachable"}
	if not grid_manager.can_unit_occupy_cell(unit, target_cell):
		var blocker := grid_manager.get_unit_at(target_cell)
		return {"accepted": false, "code": "occupied", "message": "Destination cannot be occupied", "blocking_actor_id": String(blocker.tactical_id) if is_instance_valid(blocker) else ""}
	var path := pathfinder.calculate_3d_path(start_cell, target_cell)
	if path.is_empty():
		return {"accepted": false, "code": "path_unavailable", "message": "No path reaches the destination"}
	var path_cells: Array[Vector3i] = []
	for point in path:
		path_cells.append(world_to_grid(point))
	return {"accepted": true, "movement_budget": movement_budget, "legal_destinations": legal_destinations, "path_cells": path_cells, "path": path, "path_cost": pathfinder.get_path_cost(path, world_to_grid), "presentation_path": _build_movement_path(unit, path), "visual_segments": preload("res://presentation/characters/runtime/tactical_pose_context.gd").path_poses(grid_manager, path)}

func _on_movement_committed(unit: TacticalUnit, start_cell: Vector3i, target_cell: Vector3i) -> void:
	unit_moved.emit(unit, start_cell, target_cell)

func _validate_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit, revision: int) -> ActionValidationResult:
	if not is_instance_valid(_objective_manager):
		return ActionValidationResult.reject(&"mission_unavailable", "Mission rules are unavailable", revision)
	if kind == &"rescue":
		return ActionValidationResult.allow(revision) if _objective_manager.can_rescue(actor, target) else ActionValidationResult.reject(&"illegal_rescue", "Rescue target is not currently reachable", revision)
	if kind == &"extract":
		return ActionValidationResult.allow(revision) if _objective_manager.can_extract(actor) else ActionValidationResult.reject(&"illegal_extract", "Unit cannot extract now", revision)
	return ActionValidationResult.reject(&"unsupported_action", "Unknown mission action", revision)

func _commit_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit) -> bool:
	if kind == &"rescue": return _objective_manager.complete_rescue(actor, target)
	if kind == &"extract": return _objective_manager.complete_extraction(actor)
	return false

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
			var query := query_move(tactical_unit, hover_grid)
			if query.is_legal() and query.path.size() > 1:
				path_visualizer.draw_path(query.path, Color(0.0, 0.5, 1.0, 0.4))
				return
	path_visualizer.clear_path()

func _update_attack_preview() -> void:
	var preview = ""
	var trajectory_drawn := false
	if is_attack_mode_active and is_instance_valid(tactical_unit):
		var hovered = mouse_raycaster.get_unit_under_mouse()
		if is_instance_valid(hovered) and hovered != tactical_unit:
			var query := query_attack(tactical_unit, hovered)
			preview = "%d%% HIT" % query.hit_chance if query.is_legal() else query.reason.to_upper()
			if query.is_legal() and query.obstruction != "Clear":
				preview += " — %s" % query.obstruction.to_upper()
			if shot_trajectory_visualizer and query.evaluation != null:
				shot_trajectory_visualizer.draw_trajectory(
					CombatRules.get_shot_origin(tactical_unit, grid_manager),
					query.aim_point,
					query.evaluation
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

	if not query_move(tactical_unit, clicked_grid).is_legal():
		return

	await try_move(tactical_unit, clicked_grid)

func _on_turn_phase_changed(_new_phase: TurnManager.TurnPhase) -> void:
	var is_player_control = is_current_phase_manually_controlled()
	grid_cursor.visible = is_player_control
	if not is_player_control:
		is_move_mode_active = false
		is_attack_mode_active = false

func _on_authoritative_turn_ended(_record: Dictionary) -> void:
	if is_instance_valid(action_service): action_service.advance_external_revision()

func _on_active_unit_changed(unit: TacticalUnit) -> void:
	tactical_unit = unit
	is_move_mode_active = false
	is_attack_mode_active = false

func update_unit_movement_zone() -> void:
	if not tactical_unit or tactical_unit.is_moving:
		return

	var query := query_move(tactical_unit)
	current_movement_zone.clear()
	if query.is_legal():
		current_movement_zone.assign(query.legal_destination_cells)

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

func world_to_grid(pos: Vector3) -> Vector3i:
	return grid_manager.world_to_grid(pos)

func can_attack(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	return evaluate_attack(attacker, target).is_legal

func evaluate_attack(attacker: TacticalUnit, target: TacticalUnit) -> CombatRules.AttackEvaluation:
	return CombatRules.evaluate_attack(attacker, target, grid_manager, get_world_3d())

func query_attack(attacker: TacticalUnit, target: TacticalUnit = null) -> AttackQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := AttackQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_attack(
		attacker.tactical_id if is_instance_valid(attacker) else &"",
		target.tactical_id if is_instance_valid(target) else &""
	)

func query_move(actor: TacticalUnit, target_cell := Vector3i(-1, -1, -1)) -> MoveQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := MoveQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_move(actor.tactical_id if is_instance_valid(actor) else &"", target_cell)

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

func record_ai_decision(actor: TacticalUnit, action: String, subject: String, reason: String, alternatives: String, mission_goal := "None", squad_adjustments := "None", position_scores := "None", target_scores := "None", position_candidates: Array[Dictionary] = [], target_candidates: Array[Dictionary] = [], context: Dictionary = {}) -> void:
	var actor_name := "Unknown"
	if is_instance_valid(actor):
		actor_name = String(actor.name)
	var record := {
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
	}
	record.merge(context, true)
	ai_decision_recorded.emit(record)

func try_attack(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	if not is_instance_valid(action_service):
		return false
	var query := query_attack(attacker, target)
	if debug_shots:
		print("[Shot] ", attacker.name, " -> ", target.name, " legal=", query.is_legal(), " chance=", query.hit_chance, " visibility=", query.obstruction, " reason=", query.reason)
	if not query.is_legal():
		return false
	is_action_in_progress = true
	var source := TacticalActionRequest.Source.REPLAY if replay_mode else TacticalActionRequest.Source.AI
	if is_current_phase_manually_controlled():
		source = TacticalActionRequest.Source.PLAYER
	var request := action_service.make_attack_request(attacker, target, source)
	var result := await action_service.submit_attack(request)
	is_attack_mode_active = false
	is_move_mode_active = false
	is_action_in_progress = false
	return result != null

func try_defend(unit: TacticalUnit) -> bool:
	# Legacy replay compatibility. Prototype 1 gameplay uses try_end_unit_turn().
	is_action_in_progress = true
	var result := await action_service.submit_simple(action_service.make_simple_request(&"defend", unit, _action_source()))
	is_move_mode_active = false
	is_attack_mode_active = false
	is_action_in_progress = false
	return result != null

func try_end_unit_turn(unit: TacticalUnit, reason := "No useful action available.") -> bool:
	is_action_in_progress = true
	var result := await action_service.submit_simple(action_service.make_simple_request(&"wait", unit, _action_source(), {"reason": reason}))
	is_move_mode_active = false
	is_attack_mode_active = false
	is_action_in_progress = false
	return result != null

func try_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit = null) -> bool:
	if not is_instance_valid(action_service): return false
	is_action_in_progress = true
	var result := await action_service.submit_mission(action_service.make_mission_request(kind, actor, target, _action_source()))
	is_action_in_progress = false
	return result != null

func _action_source() -> TacticalActionRequest.Source:
	if replay_mode: return TacticalActionRequest.Source.REPLAY
	return TacticalActionRequest.Source.PLAYER if is_current_phase_manually_controlled() else TacticalActionRequest.Source.AI

func try_move(unit: TacticalUnit, target_cell: Vector3i) -> bool:
	if not is_instance_valid(action_service):
		return false
	is_action_in_progress = true
	is_move_mode_active = false
	is_attack_mode_active = false
	var source := TacticalActionRequest.Source.REPLAY if replay_mode else TacticalActionRequest.Source.AI
	if is_current_phase_manually_controlled(): source = TacticalActionRequest.Source.PLAYER
	var result := await action_service.submit_move(action_service.make_move_request(unit, target_cell, source))
	is_action_in_progress = false
	return result != null

func record_replay_action(kind: String, actor: TacticalUnit, details: Dictionary = {}) -> void:
	var record := {
		"kind": kind,
		"actor": String(actor.tactical_id) if is_instance_valid(actor) else "",
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
	if not unit.defer_stat_presentation:
		unit.finish_defeat_presentation()

func register_mission_unit(unit: TacticalUnit, grid_position: Vector3i) -> void:
	_ensure_tactical_id(unit)
	if is_instance_valid(action_service):
		action_service.register_actor(unit)
	grid_manager.register_unit(unit, grid_position)
	unit.defeated.connect(_on_unit_defeated)

func extract_unit(unit: TacticalUnit, finalize_visual := true) -> void:
	if not is_instance_valid(unit):
		return
	grid_manager.unregister_unit_at(grid_manager.get_unit_grid(unit))
	turn_manager.remove_extracted_unit(unit)
	if finalize_visual: finalize_extracted_unit(unit)

func finalize_extracted_unit(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit): return
	if is_instance_valid(action_service):
		action_service.unregister_actor(unit)
	unit.queue_free()
