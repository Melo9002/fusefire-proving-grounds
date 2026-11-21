extends Node3D
class_name BattleController

const SquadContextData = preload("res://systems/ai/squad_context.gd")
const AICommanderPolicyData = preload("res://systems/ai/ai_commander_policy.gd")
const ActionCameraDirectorData = preload("res://presentation/camera/action_camera_director.gd")

signal move_mode_toggled(is_active: bool)
signal attack_mode_toggled(is_active: bool)
signal shield_mode_toggled(is_active: bool)
signal overwatch_mode_toggled(is_active: bool)
signal attack_preview_changed(text: String)
signal tactical_preview_changed(text: String)
signal tactical_preview_tint_changed(color: Color)
signal combat_log_changed(text: String)
signal attack_resolved(attacker: TacticalUnit, target: TacticalUnit, did_hit: bool, hit_chance: int)
signal action_state_changed(is_busy: bool)
signal units_registered(player_units: Array[TacticalUnit])
signal debug_enemy_control_changed(enabled: bool)
signal debug_player_ai_changed(enabled: bool)
signal ai_decision_recorded(record: Dictionary)
signal ai_action_outcome_recorded(record: Dictionary)

signal unit_moved(unit: TacticalUnit, from_cell: Vector3i, to_cell: Vector3i)
signal unit_defeated_in_battle(unit: TacticalUnit)

var _ai_decision_sequence := 0
var _pending_ai_moves: Dictionary = {}
var _shot_cell_cache: Dictionary = {}

@export var battle_root: Node3D
@export var tactical_unit: TacticalUnit
@export var mouse_raycaster: MouseRaycaster
@export var grid_cursor: GridCursor
@export var path_visualizer: PathVisualizer
@export var cover_visualizer: CoverVisualizer
@export var shot_trajectory_visualizer: ShotTrajectoryVisualizer
@export var overwatch_range_visualizer: OverwatchRangeVisualizer
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
var _last_tactical_preview := ""
var _last_tactical_preview_tint := Color.WHITE
var _movement_feedback_key := ""
var combat_log := PackedStringArray()
var debug_enemy_control: bool = false
var debug_player_ai: bool = false
var ai_difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.NORMAL
var battle_seed: int = 1
var ai_decision_seed: int = 1
var _squad_contexts: Dictionary[int, SquadContext] = {}
var _commander_policies: Dictionary[int, AICommanderPolicy] = {}
var _commander_profiles := {
	0: AICommanderPolicy.Profile.DEFAULT,
	1: AICommanderPolicy.Profile.DEFAULT,
}
var replay_mode := false
## Disabled only when reconstructing recordings made before Supply Points.
var supply_points_enabled := true
## Disabled only when reconstructing recordings made before Aim.
var aim_enabled := true
var shield_enabled := true
var overwatch_enabled := true
var conditions_enabled := true
var action_camera_director: Node
var action_service: TacticalActionService
var action_confirmation: BattleActionConfirmation
var movement_ghost: MovementGhost
var action_presenter: TacticalActionPresenter
var _objective_manager: ObjectiveManager
var is_action_in_progress: bool:
	get: return is_instance_valid(action_service) and action_service.is_busy
var is_move_mode_active: bool = false:
	set(value):
		if is_move_mode_active != value:
			if value: is_overwatch_mode_active = false
			is_move_mode_active = value
			move_mode_toggled.emit(is_move_mode_active)
			if not is_move_mode_active:
				_clear_destination_preview()
				path_visualizer.clear_path()
				path_visualizer.clear_range_zone()
				cover_visualizer.clear()

var is_attack_mode_active: bool = false:
	set(value):
		if is_attack_mode_active != value:
			if value: is_overwatch_mode_active = false
			is_attack_mode_active = value
			attack_mode_toggled.emit(is_attack_mode_active)
			if not is_attack_mode_active:
				path_visualizer.clear_range_zone()
				if shot_trajectory_visualizer:
					shot_trajectory_visualizer.clear()

var is_shield_mode_active := false:
	set(value):
		if is_shield_mode_active == value: return
		if value: is_overwatch_mode_active = false
		is_shield_mode_active = value
		shield_mode_toggled.emit(value)

var is_overwatch_mode_active := false:
	set(value):
		if is_overwatch_mode_active == value: return
		is_overwatch_mode_active = value
		if value:
			is_move_mode_active = false
			is_attack_mode_active = false
			is_shield_mode_active = false
		_refresh_overwatch_range()
		overwatch_mode_toggled.emit(value)

func _ready() -> void:
	if not mouse_raycaster or not grid_manager or not grid_manager.map_floor or not path_visualizer or not cover_visualizer or not turn_manager or not grid_cursor:
		push_error("Missing critical node assignments on BattleController!")
		return

	turn_manager.turn_phase_changed.connect(_on_turn_phase_changed)
	turn_manager.turn_ended.connect(_on_authoritative_turn_ended)
	turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	turn_manager.player_actions_exhausted.connect(_on_player_actions_exhausted)
	mouse_raycaster.floor_clicked.connect(_on_floor_clicked)
	mouse_raycaster.unit_clicked.connect(_on_unit_clicked)

func initialize_battle(prebuilt_map: MapData = null, mission: MissionDefinition = null) -> bool:
	if prebuilt_map:
		grid_manager.map_data = prebuilt_map
		MapGraphBuilder.build(prebuilt_map, pathfinder)
		pathfinder.live_grid = grid_manager
	else:
		pathfinder.clear()
		MapBuilder.build(grid_manager, pathfinder)
		# Let CSG collision bodies enter the physics world before scanning.
		await get_tree().create_timer(0.05, false).timeout
		MapBuilder.scan_obstacles(get_world_3d(), grid_manager, pathfinder)
	# Unified-layout battles already carry objective zones selected before
	# environment assembly and protected by mission reservations. Replanning here
	# would make gameplay consume mission state that is absent from its document.
	# Legacy and authored maps without the complete default set retain the
	# established runtime planning path.
	if not MissionZonePlanner.has_complete_defaults(grid_manager.map_data):
		MissionZonePlanner.populate_defaults(grid_manager.map_data, pathfinder)
	_apply_authored_tile_hazards()
	preload("res://systems/objectives/extraction_transport_planner.gd").place(grid_manager.map_data, pathfinder, mission)
	pathfinder.live_grid = grid_manager
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
		if not grid_manager.register_unit(unit_item, start_grid): return false
		unit_item.defeated.connect(_on_unit_defeated)
	_orient_units_toward_opposition(battle_units)
	units_registered.emit(turn_manager.player_units)

	turn_manager.start_battle()
	return true

func _apply_authored_tile_hazards() -> void:
	if not is_instance_valid(battle_root): return
	for node in get_tree().get_nodes_in_group("tile_hazards"):
		if not battle_root.is_ancestor_of(node): continue
		# Plot scenery is presentation only, even when a reused component carries
		# a hazard marker over a valid tactical cell.
		var ancestor := node.get_parent()
		var scenery := false
		while ancestor != null and ancestor != battle_root:
			if ancestor.is_in_group("peripheral_scenery") or ancestor.is_in_group("distant_scenery"):
				scenery = true
				break
			ancestor = ancestor.get_parent()
		if scenery: continue
		var definition: ConditionDefinition = node.get("condition") if node is Node3D else null
		if definition == null: continue
		var cell := grid_manager.map_data.get_cell(grid_manager.world_to_grid((node as Node3D).global_position))
		if cell: cell.hazard_condition = definition

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
		func(attacker, target, did_hit, hit_chance): attack_resolved.emit(attacker, target, did_hit, hit_chance)
	)
	turn_manager.action_completion_barrier = func() -> bool: return action_service.is_busy
	_configure_action_service(null)
	action_service.busy_changed.connect(_on_action_service_busy_changed)
	action_service.action_committed.connect(_on_action_committed)

func _configure_action_service(objectives: ObjectiveManager) -> void:
	action_service.setup(
		turn_manager,
		grid_manager,
		objectives,
		ai_decision_seed * 2147483647 + 104729,
		action_presenter.present_attack,
		action_presenter.present_reload,
		action_presenter.present_aim,
		action_presenter.present_shield,
		action_presenter.present_overwatch,
		_query_move_data,
		action_presenter.present_move,
		_on_movement_committed,
		action_presenter.present_simple,
		_validate_mission_action,
		_commit_mission_action,
		action_presenter.present_mission
	)
	action_service.supply_points_enabled = supply_points_enabled
	action_service.aim_enabled = aim_enabled
	action_service.shield_enabled = shield_enabled
	action_service.overwatch_enabled = overwatch_enabled
	action_service.conditions_enabled = conditions_enabled

func bind_objective_manager(manager: ObjectiveManager) -> void:
	_objective_manager = manager
	turn_manager.free_objective_action_available = _has_free_objective_action
	if not is_instance_valid(action_service):
		_initialize_action_service()
	_configure_action_service(manager)

func _ensure_tactical_id(unit: TacticalUnit) -> void:
	if unit.tactical_id.is_empty():
		unit.tactical_id = StringName(unit.name)
	if unit.tactical_state:
		var callback := _on_stances_expired.bind(unit.tactical_id)
		if not unit.tactical_state.stances_expired.is_connected(callback):
			unit.tactical_state.stances_expired.connect(callback)

func _on_action_service_busy_changed(is_busy: bool) -> void:
	action_state_changed.emit(is_busy)

func _on_action_committed(result) -> void:
	if result.request.source == TacticalActionRequest.Source.AI:
		var actor_id: StringName = result.request.actor_id
		ai_action_outcome_recorded.emit({"actor_id": String(actor_id), "action": String(result.request.kind),
			"stage": "committed", "decision_id": _pending_ai_moves.get(actor_id, 0) if result.request.kind == &"move" else 0,
			"transaction_id": result.transaction_id, "base_revision": result.base_revision,
			"committed_revision": result.committed_revision})
		if result.request.kind == &"move": _pending_ai_moves.erase(actor_id)
	_refresh_overwatch_range()
	_append_combat_entries(TacticalFeedbackText.committed(result))

func _on_stances_expired(names: PackedStringArray, actor_id: StringName) -> void:
	_append_combat_entries(PackedStringArray(["%s: %s expired at next activation" % [actor_id, ", ".join(names)]]))

func _append_combat_entries(entries: PackedStringArray) -> void:
	for entry in entries:
		combat_log.append(entry)
	while combat_log.size() > 5:
		combat_log.remove_at(0)
	combat_log_changed.emit("\n".join(combat_log))

func _refresh_overwatch_range() -> void:
	if not is_instance_valid(overwatch_range_visualizer):
		return
	var committed_guarded := {}
	var enemy_guarded := {}
	var watchers: Array[TacticalUnit] = []
	watchers.assign(turn_manager.player_units + turn_manager.allied_units + turn_manager.enemy_units)
	for watcher in watchers:
		if not is_instance_valid(watcher) or not watcher.stats or watcher.stats.is_defeated \
		or not watcher.tactical_state or not watcher.tactical_state.is_overwatching:
			continue
		var coverage := enemy_guarded if watcher.faction == TacticalUnit.Faction.ENEMY else committed_guarded
		for cell in _legal_shot_cells(watcher): coverage[cell] = true
	var committed_cells: Array[Vector3i] = []
	for cell: Vector3i in committed_guarded.keys(): committed_cells.append(cell)
	var enemy_cells: Array[Vector3i] = []
	enemy_cells.assign(enemy_guarded.keys())
	var preview_cells: Array[Vector3i] = []
	if is_overwatch_mode_active and is_instance_valid(tactical_unit):
		preview_cells.assign(_legal_shot_cells(tactical_unit))
	overwatch_range_visualizer.show_ranges(preview_cells, committed_cells, enemy_cells)

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
	if pathfinder.get_path_cost(path, world_to_grid) > movement_budget:
		return {"accepted": false, "code": "unreachable", "message": "Safe route exceeds movement budget"}
	var path_cells: Array[Vector3i] = []
	for point in path:
		path_cells.append(world_to_grid(point))
	return {"accepted": true, "movement_budget": movement_budget, "legal_destinations": legal_destinations, "path_cells": path_cells, "path": path, "path_cost": pathfinder.get_path_cost(path, world_to_grid), "presentation_path": _build_movement_path(unit, path), "visual_segments": preload("res://presentation/tactical/tactical_pose_context.gd").path_poses(grid_manager, path)}

func _on_movement_committed(unit: TacticalUnit, start_cell: Vector3i, target_cell: Vector3i) -> void:
	unit_moved.emit(unit, start_cell, target_cell)

func _validate_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit, revision: int, target_id: StringName = &"") -> ActionValidationResult:
	if not is_instance_valid(_objective_manager):
		return ActionValidationResult.reject(&"mission_unavailable", "Mission rules are unavailable", revision)
	if kind == &"rescue":
		return ActionValidationResult.allow(revision) if _objective_manager.can_rescue(actor, target) else ActionValidationResult.reject(&"illegal_rescue", "Rescue target is not currently reachable", revision)
	if kind == &"extract":
		return ActionValidationResult.allow(revision) if _objective_manager.can_extract(actor) else ActionValidationResult.reject(&"illegal_extract", "Unit cannot extract now", revision)
	if kind == &"interact_terminal":
		var validation := _objective_manager.can_activate_terminal(actor, target_id)
		return ActionValidationResult.allow(revision) if validation.accepted else ActionValidationResult.reject(validation.code, validation.message, revision)
	return ActionValidationResult.reject(&"unsupported_action", "Unknown mission action", revision)

func _commit_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit, target_id: StringName = &"") -> bool:
	if kind == &"rescue": return _objective_manager.complete_rescue(actor, target)
	if kind == &"extract": return _objective_manager.complete_extraction(actor)
	if kind == &"interact_terminal":
		var committed := _objective_manager.activate_terminal(actor, target_id)
		if committed: _objective_manager.evaluate_outcome_after_action_commit()
		return committed
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
			is_shield_mode_active = false
			update_unit_movement_zone()

func toggle_attack_mode() -> void:
	if not is_current_phase_manually_controlled() or is_action_in_progress:
		return
	if not tactical_unit or not tactical_unit.stats or tactical_unit.stats.current_ap < UNIFORM_AP_COST:
		return
	if supply_points_enabled and tactical_unit.stats.current_supply_points < TacticalActionService.ATTACK_SUPPLY_COST:
		return

	if is_attack_mode_active:
		is_attack_mode_active = false
		return

	if is_move_mode_active:
		is_move_mode_active = false
	is_shield_mode_active = false
	is_attack_mode_active = true
	update_attack_range()

func toggle_shield_mode() -> void:
	if not is_current_phase_manually_controlled() or is_action_in_progress or not is_instance_valid(tactical_unit):
		return
	if not tactical_unit.shield_capability:
		return
	is_shield_mode_active = not is_shield_mode_active
	if is_shield_mode_active:
		is_move_mode_active = false
		is_attack_mode_active = false

func toggle_overwatch_mode() -> void:
	if not is_current_phase_manually_controlled() or is_action_in_progress or not is_instance_valid(tactical_unit):
		return
	if not is_overwatch_mode_active and not query_overwatch(tactical_unit).is_legal():
		return
	is_overwatch_mode_active = not is_overwatch_mode_active

func _process(_delta: float) -> void:
	if not turn_manager or not is_current_phase_manually_controlled():
		_set_tactical_preview("")
		_clear_destination_preview()
		if shot_trajectory_visualizer: shot_trajectory_visualizer.clear()
		if path_visualizer: path_visualizer.clear_path()
		return

	var floor_hit = mouse_raycaster.get_floor_raycast_result() if mouse_raycaster else {}
	if grid_cursor:
		if floor_hit.is_empty():
			grid_cursor.clear_hover()
		else:
			grid_cursor.update_hover_position(floor_hit.position)
	if not is_move_mode_active or not is_instance_valid(tactical_unit) or tactical_unit.is_moving:
		path_visualizer.clear_path()
		_movement_feedback_key = ""
	else:
		_update_movement_preview(floor_hit)

	if shot_trajectory_visualizer and (not is_move_mode_active or _movement_feedback_key.is_empty()):
		shot_trajectory_visualizer.clear_destination_options()
	_update_attack_preview()

func _update_movement_preview(floor_hit: Dictionary) -> void:
	if not floor_hit.is_empty():
		var hover_grid = world_to_grid(floor_hit.position)
		if current_movement_zone.has(hover_grid):
			var query := query_move(tactical_unit, hover_grid)
			if query.is_legal() and query.path.size() > 1:
				path_visualizer.draw_path(query.path, Color(0.0, 0.5, 1.0, 0.4))
				var feedback_key := "%s:%s:%d" % [tactical_unit.tactical_id, hover_grid, action_service.state_revision]
				if feedback_key != _movement_feedback_key:
					_movement_feedback_key = feedback_key
					var opponents: Array[TacticalUnit] = []
					opponents.assign(turn_manager.enemy_units + turn_manager.player_units + turn_manager.allied_units)
					var options := TacticalFeedbackText.movement_options(query, tactical_unit, opponents, grid_manager, supply_points_enabled, shield_enabled, aim_enabled)
					_set_tactical_preview(TacticalFeedbackText.movement_description(query, tactical_unit, options, grid_manager, supply_points_enabled))
					if shot_trajectory_visualizer: shot_trajectory_visualizer.draw_destination_options(tactical_unit, hover_grid, options)
					if not is_instance_valid(movement_ghost):
						movement_ghost = MovementGhost.new()
						add_child(movement_ghost)
					movement_ghost.show_destination(tactical_unit, hover_grid, grid_manager)
				return
	path_visualizer.clear_path()
	_clear_destination_preview()
	_movement_feedback_key = ""
	_set_tactical_preview("")

func _clear_destination_preview() -> void:
	_movement_feedback_key = ""
	if is_instance_valid(movement_ghost): movement_ghost.clear()
	if is_instance_valid(shot_trajectory_visualizer): shot_trajectory_visualizer.clear_destination_options()

func _set_tactical_preview(text: String, tint := Color.WHITE) -> void:
	if tint != _last_tactical_preview_tint:
		_last_tactical_preview_tint = tint
		tactical_preview_tint_changed.emit(tint)
	if text != _last_tactical_preview:
		_last_tactical_preview = text
		tactical_preview_changed.emit(text)

func _update_attack_preview() -> void:
	var preview = ""
	var trajectory_drawn := false
	var feedback_shown := false
	var inspect_shot := is_attack_mode_active or (not is_move_mode_active and not is_shield_mode_active and not is_overwatch_mode_active)
	if inspect_shot and not is_action_in_progress and is_instance_valid(tactical_unit):
		var hovered = mouse_raycaster.get_unit_under_mouse()
		if is_instance_valid(hovered) and FactionRules.are_hostile(tactical_unit.faction, hovered.faction):
			var query := query_attack(tactical_unit, hovered)
			_set_tactical_preview(TacticalFeedbackText.shot(query), TacticalFeedbackText.chance_color(query.hit_chance, query.is_legal()))
			feedback_shown = true
			preview = "%d%% HIT" % query.hit_chance if query.is_legal() else query.reason.to_upper()
			if query.is_legal() and query.obstruction != "Clear":
				preview += " — %s" % query.obstruction.to_upper()
			if shot_trajectory_visualizer and query.evaluation != null:
				shot_trajectory_visualizer.draw_trajectory(
					CombatRules.get_shot_origin(tactical_unit, grid_manager),
					query.aim_point,
					query.evaluation,
					true,
					query.is_legal()
				)
				trajectory_drawn = true
	if not trajectory_drawn and shot_trajectory_visualizer:
		shot_trajectory_visualizer.clear()
	if not feedback_shown and not is_move_mode_active:
		_set_tactical_preview("")
	if preview != _last_attack_preview:
		_last_attack_preview = preview
		attack_preview_changed.emit(preview)

func _on_unit_clicked(unit: TacticalUnit) -> void:
	if is_action_in_progress or not is_instance_valid(unit) or not unit.stats or unit.stats.is_defeated:
		return
	if is_attack_mode_active and is_instance_valid(tactical_unit) \
		and FactionRules.are_hostile(tactical_unit.faction, unit.faction):
		await confirm_player_action(&"attack", tactical_unit, unit)
		return
	if is_shield_mode_active and is_instance_valid(tactical_unit) \
		and FactionRules.are_hostile(tactical_unit.faction, unit.faction):
		await confirm_player_action(&"shield", tactical_unit, unit)
		return

	if not debug_player_ai and turn_manager.select_player_unit(unit):
		is_move_mode_active = false
		is_attack_mode_active = false
		is_shield_mode_active = false

func _on_floor_clicked(raw_position: Vector3) -> void:
	if is_action_in_progress or not is_move_mode_active or not is_instance_valid(tactical_unit):
		return

	var clicked_grid = world_to_grid(raw_position)
	if not current_movement_zone.has(clicked_grid):
		return

	if not query_move(tactical_unit, clicked_grid).is_legal():
		return

	await confirm_player_action(&"move", tactical_unit, null, clicked_grid)

func _on_turn_phase_changed(_new_phase: TurnManager.TurnPhase) -> void:
	var is_player_control = is_current_phase_manually_controlled()
	grid_cursor.visible = is_player_control
	if not is_player_control:
		is_move_mode_active = false
		is_attack_mode_active = false
		is_shield_mode_active = false
		is_overwatch_mode_active = false
	_refresh_overwatch_range()

func _on_authoritative_turn_ended(_record: Dictionary) -> void:
	if is_instance_valid(action_service): action_service.advance_external_revision()

func _on_active_unit_changed(unit: TacticalUnit) -> void:
	tactical_unit = unit
	is_move_mode_active = false
	is_attack_mode_active = false
	is_shield_mode_active = false
	is_overwatch_mode_active = false
	_refresh_overwatch_range()

func _on_player_actions_exhausted() -> void:
	# A defeated or extracted automated actor cannot finish its own AI callback.
	# The roster owner reports exhaustion after the action barrier; battle-level
	# orchestration then advances the phase exactly once.
	if debug_player_ai and turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN \
	and turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		turn_manager.end_current_turn()

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

	current_attack_zone.assign(_legal_shot_cells(tactical_unit))
	path_visualizer.draw_range_zone(current_attack_zone, Color(0.95, 0.2, 0.2, 0.3))

func _legal_shot_cells(attacker: TacticalUnit) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if not is_instance_valid(attacker) or not attacker.stats:
		return cells
	var attacker_grid = grid_manager.get_unit_grid(attacker)
	var data := grid_manager.map_data
	var heights := {}
	# An empty cell uses the shooter's height, so equal-height occupants do not
	# change this geometric overlay when they move. Actual attacks still query live state.
	for occupant in grid_manager.occupancy_map.values():
		if is_instance_valid(occupant) and occupant.standing_height != attacker.standing_height:
			heights[occupant.grid_position] = occupant.standing_height
	var signature: Array = [data.get_instance_id(), data.los_revision, pathfinder._graph_revision,
		attacker_grid, grid_manager.grid_to_world(attacker_grid), attacker.standing_height, attacker.attack_range,
		attacker.is_carrying_unit(), grid_manager.cell_size, grid_manager.elevation_step, heights]
	var key := attacker.get_instance_id()
	var cached: Dictionary = _shot_cell_cache.get(key, {})
	if cached.get("signature") == signature:
		cells.assign(cached.cells)
		return cells
	if _shot_cell_cache.size() >= 32: _shot_cell_cache.clear()
	for grid_pos in pathfinder.grid_to_id_map.keys():
		var point_id = pathfinder.grid_to_id_map[grid_pos]
		if pathfinder.astar.is_point_disabled(point_id):
			continue

		var distance = CombatRules.attack_distance(attacker_grid, grid_pos, grid_manager)
		if distance == 0 or distance > attacker.attack_range:
			continue

		if CombatRules.has_firing_lane_to_cell(attacker, grid_pos, grid_manager):
			cells.append(grid_pos)
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x < b.x or (a.x == b.x and (a.z < b.z or (a.z == b.z and a.y < b.y))))
	_shot_cell_cache[key] = {"signature": signature, "cells": cells.duplicate()}
	return cells

func world_to_grid(pos: Vector3) -> Vector3i:
	return grid_manager.world_to_grid(pos)

func can_attack(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	return evaluate_attack(attacker, target).is_legal

func evaluate_attack(attacker: TacticalUnit, target: TacticalUnit) -> CombatRules.AttackEvaluation:
	var bonus: int = CombatRules.cover_tuning.aim_accuracy_bonus if aim_enabled and is_instance_valid(attacker) and attacker.tactical_state and attacker.tactical_state.is_aiming else 0
	return CombatRules.evaluate_attack(attacker, target, grid_manager, get_world_3d(), bonus, shield_enabled)

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

func query_reload(actor: TacticalUnit) -> ReloadQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := ReloadQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_reload(actor.tactical_id if is_instance_valid(actor) else &"")

func query_aim(actor: TacticalUnit) -> AimQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := AimQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_aim(actor.tactical_id if is_instance_valid(actor) else &"")

func query_shield(actor: TacticalUnit, threat: TacticalUnit = null) -> ShieldQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := ShieldQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_shield(actor.tactical_id if is_instance_valid(actor) else &"", threat.tactical_id if is_instance_valid(threat) else &"")

func query_overwatch(actor: TacticalUnit) -> OverwatchQueryResult:
	return action_service.query_overwatch(actor.tactical_id if is_instance_valid(actor) else &"")

func query_simple(kind: StringName, actor: TacticalUnit) -> SimpleActionQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := SimpleActionQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_simple(kind, actor.tactical_id if is_instance_valid(actor) else &"")

func query_mission(kind: StringName, actor: TacticalUnit, target: TacticalUnit = null) -> MissionActionQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := MissionActionQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_mission(kind, actor.tactical_id if is_instance_valid(actor) else &"", target.tactical_id if is_instance_valid(target) else &"")

func query_terminal(actor: TacticalUnit, terminal_id: StringName = &"") -> MissionActionQueryResult:
	if not is_instance_valid(action_service):
		var unavailable := MissionActionQueryResult.new()
		unavailable.validation = ActionValidationResult.reject(&"service_unavailable", "Action service is unavailable", 0)
		return unavailable
	return action_service.query_mission(&"interact_terminal", actor.tactical_id if is_instance_valid(actor) else &"", terminal_id)

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

func peek_squad_context(unit: TacticalUnit) -> SquadContext:
	return _squad_contexts.get(_ai_team_id(unit))

func get_squad_context(unit: TacticalUnit) -> SquadContext:
	var team_id := _ai_team_id(unit)
	if not _squad_contexts.has(team_id):
		_squad_contexts[team_id] = SquadContextData.new()
	var context: SquadContext = _squad_contexts[team_id]
	context.begin_round(turn_manager.current_round)
	var actors: Array[TacticalUnit] = []
	actors.append_array(turn_manager.player_units + turn_manager.allied_units + turn_manager.enemy_units)
	context.prune(actors)
	return context

func get_commander_policy(unit: TacticalUnit) -> AICommanderPolicy:
	var team_id := _ai_team_id(unit)
	if not _commander_policies.has(team_id):
		_commander_policies[team_id] = AICommanderPolicyData.create(_commander_profiles.get(team_id, AICommanderPolicy.Profile.DEFAULT))
	return _commander_policies[team_id]

func configure_commander_profiles(player_team: AICommanderPolicy.Profile, enemy_team: AICommanderPolicy.Profile) -> void:
	_commander_profiles[0] = player_team
	_commander_profiles[1] = enemy_team
	_commander_policies.clear()

func _ai_team_id(unit: TacticalUnit) -> int:
	return 0 if unit.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY] else 1

## Publishes one AI decision. The caller supplies the decision facts; the battle adds what
## it owns (id, state revision, difficulty, commander) and emits the established trace shape.
func record_ai_decision(actor: TacticalUnit, record: AIDecisionRecord) -> int:
	_ai_decision_sequence += 1
	var actor_valid := is_instance_valid(actor)
	record.actor = String(actor.name) if actor_valid else "Unknown"
	record.decision_id = _ai_decision_sequence
	record.state_revision = action_service.state_revision
	record.difficulty = AIDifficultyPolicy.get_label(ai_difficulty)
	if actor_valid:
		var commander := get_commander_policy(actor)
		record.has_commander = true
		record.commander_policy = AICommanderPolicy.get_label(commander.profile)
		record.commander_policy_id = String(commander.get_policy_id())
		record.strategic_intent = commander.get_strategic_intent_label()
	if actor_valid and record.is_selected_move():
		_pending_ai_moves[actor.tactical_id] = _ai_decision_sequence
	ai_decision_recorded.emit(record.to_dictionary())
	return _ai_decision_sequence

## UI-only entry. AI/replay keep submitting through the ordinary action service.
func confirm_player_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit = null, destination := Vector3i(-1, -1, -1)) -> void:
	if not is_current_phase_manually_controlled() or is_action_in_progress or get_tree().paused: return
	if not is_instance_valid(actor): return
	var text := ""
	match kind:
		&"attack":
			var query := query_attack(actor, target)
			if not query.is_legal(): return
			text = TacticalFeedbackText.shot(query)
		&"aim":
			var query := query_aim(actor)
			if not query.is_legal(): return
			text = "%s: spend %d AP now for +%d accuracy on the next Attack. No damage bonus.\nMove, Reload, Skip or incompatible stance changes cancel Aim. Expires next activation.\nReplaces active Shield or Guard." % [actor.tactical_id, query.cost.ap, query.accuracy_bonus]
		&"shield":
			var query := query_shield(actor, target)
			if not query.is_legal(): return
			text = "%s: spend %d AP to face %s.\nFixed %.0f° front arc; %+d incoming accuracy; ×%.2f hit damage.\nAim is canceled. Skip keeps Shield; Move ends it after route reactions. Expires next activation." % [actor.tactical_id, query.cost.ap, target.tactical_id, query.protected_arc_degrees, query.accuracy_modifier, query.damage_multiplier]
		&"wait":
			if not query_simple(&"wait", actor).is_legal(): return
			text = "%s: skip %d remaining AP. Active Shield is kept; Aim is canceled." % [actor.tactical_id, actor.stats.current_ap]
		&"move":
			var query := query_move(actor, destination)
			if not query.is_legal(): return
			# A click may arrive before the next hover frame. Freeze the chosen preview.
			_update_movement_preview({"position": grid_manager.grid_to_world(destination)})
			var opponents: Array[TacticalUnit] = []
			opponents.assign(turn_manager.enemy_units + turn_manager.player_units + turn_manager.allied_units)
			text = TacticalFeedbackText.movement(query, actor, opponents, grid_manager, supply_points_enabled, shield_enabled, aim_enabled)
		_: return
	var revision := action_service.state_revision
	# Capture stable IDs, not nodes that may be removed while the dialog is open.
	var actor_id := actor.tactical_id
	var target_id := target.tactical_id if is_instance_valid(target) else &""
	var commit := func():
		if not is_inside_tree() or is_queued_for_deletion(): return
		var current_actor := action_service.actor_registry.resolve(actor_id)
		var current_target := action_service.actor_registry.resolve(target_id) if not target_id.is_empty() else null
		if action_service.state_revision != revision or not is_instance_valid(current_actor) or turn_manager.active_unit != current_actor:
			_set_tactical_preview("Battle state changed. Review the action again.")
			return
		if kind in [&"attack", &"shield"] and not is_instance_valid(current_target):
			_set_tactical_preview("Target is no longer available. Review the action again.")
			return
		match kind:
			&"attack": await try_attack(current_actor, current_target)
			&"aim": await try_aim(current_actor)
			&"shield": await try_shield(current_actor, current_target)
			&"wait": await try_end_unit_turn(current_actor, "Skipped manually by the player.")
			&"move": await try_move(current_actor, destination)
	await _confirmation_dialog().request("Confirm " + ("Skip" if kind == &"wait" else String(kind).capitalize()), text, commit, kind == &"move")

func _confirmation_dialog() -> BattleActionConfirmation:
	if not is_instance_valid(action_confirmation):
		action_confirmation = BattleActionConfirmation.new()
		action_confirmation.name = "ActionConfirmation"
		add_child(action_confirmation)
	return action_confirmation

func confirm_player_end_turn() -> void:
	if not is_current_phase_manually_controlled() or is_action_in_progress or get_tree().paused: return
	var remaining := 0
	var roster: Array[TacticalUnit] = turn_manager.enemy_units if debug_enemy_control and turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN else turn_manager.player_units
	for actor in roster:
		if is_instance_valid(actor) and actor.stats and not actor.stats.is_defeated: remaining += actor.stats.current_ap
	if remaining == 0:
		turn_manager.end_current_turn()
		return
	var revision := action_service.state_revision
	var phase := turn_manager.current_phase
	var round_number := turn_manager.current_round
	var commit := func():
		if is_inside_tree() and not is_queued_for_deletion() and action_service.state_revision == revision and turn_manager.current_phase == phase and turn_manager.current_round == round_number and not is_action_in_progress:
			turn_manager.end_current_turn()
	await _confirmation_dialog().request("End turn?", "%d AP remain across your units. End this phase without using them?" % remaining, commit)

func try_attack(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	if not is_instance_valid(action_service):
		return false
	var query := query_attack(attacker, target)
	if debug_shots:
		print("[Shot] ", attacker.name, " -> ", target.name, " legal=", query.is_legal(), " chance=", query.hit_chance, " visibility=", query.obstruction, " reason=", query.reason)
	if not query.is_legal():
		return false
	var source := _action_source()
	var request := action_service.make_attack_request(attacker, target, source)
	var result := await action_service.submit_attack(request)
	is_attack_mode_active = false
	is_move_mode_active = false
	return result != null

func try_reload(unit: TacticalUnit) -> bool:
	if not is_instance_valid(action_service):
		return false
	var result := await action_service.submit_reload(action_service.make_reload_request(unit, _action_source()))
	is_attack_mode_active = false
	is_move_mode_active = false
	return result != null

func try_aim(unit: TacticalUnit) -> bool:
	if not is_instance_valid(action_service):
		return false
	var result := await action_service.submit_aim(action_service.make_aim_request(unit, _action_source()))
	is_attack_mode_active = false
	is_move_mode_active = false
	return result != null

func try_shield(unit: TacticalUnit, threat: TacticalUnit) -> bool:
	if not is_instance_valid(action_service):
		return false
	var result := await action_service.submit_shield(action_service.make_shield_request(unit, threat, _action_source()))
	is_attack_mode_active = false
	is_move_mode_active = false
	is_shield_mode_active = false
	return result != null

func try_overwatch(unit: TacticalUnit) -> bool:
	if not is_instance_valid(action_service): return false
	var result := await action_service.submit_overwatch(action_service.make_overwatch_request(unit, _action_source()))
	is_attack_mode_active = false
	is_move_mode_active = false
	is_shield_mode_active = false
	is_overwatch_mode_active = false
	if result != null and turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN \
	and not turn_manager.player_units.any(func(candidate: TacticalUnit) -> bool:
		return is_instance_valid(candidate) and candidate.stats and not candidate.stats.is_defeated and candidate.stats.current_ap > 0):
		turn_manager.end_current_turn()
	return result != null

func try_defend(unit: TacticalUnit) -> bool:
	# Legacy replay compatibility. Prototype 1 gameplay uses try_end_unit_turn().
	var result := await action_service.submit_simple(action_service.make_simple_request(&"defend", unit, _action_source()))
	is_move_mode_active = false
	is_attack_mode_active = false
	return result != null

func try_end_unit_turn(unit: TacticalUnit, reason := "No useful action available.") -> bool:
	var result := await action_service.submit_simple(action_service.make_simple_request(&"wait", unit, _action_source(), {"reason": reason}))
	is_move_mode_active = false
	is_attack_mode_active = false
	return result != null

func try_emergency_seal(unit: TacticalUnit) -> bool:
	if not is_instance_valid(action_service): return false
	var request := action_service.make_simple_request(&"emergency_seal", unit, _action_source())
	return await action_service.submit_simple(request) != null

func try_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit = null) -> bool:
	if not is_instance_valid(action_service): return false
	var result := await action_service.submit_mission(action_service.make_mission_request(kind, actor, target, _action_source()))
	if result != null and turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		turn_manager.complete_free_objective_action(actor)
	return result != null

func try_terminal(actor: TacticalUnit, terminal_id: StringName) -> bool:
	if not is_instance_valid(action_service): return false
	var request := action_service.make_terminal_request(actor, terminal_id, _action_source())
	var result := await action_service.submit_mission(request)
	if result != null and turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		turn_manager.complete_free_objective_action(actor)
	return result != null

func _has_free_objective_action(actor: TacticalUnit) -> bool:
	if not is_instance_valid(_objective_manager) or not is_instance_valid(actor):
		return false
	if _objective_manager.can_extract(actor):
		return true
	for terminal_id in _objective_manager.get_terminal_ids():
		if _objective_manager.can_activate_terminal(actor, terminal_id).accepted:
			return true
	var rescue := _objective_manager.get_objective(&"rescue")
	if rescue and rescue.is_active():
		var target := _objective_manager.find_mission_actor(rescue.definition.target_ids)
		return target != null and _objective_manager.can_rescue(actor, target)
	return false

func _action_source() -> TacticalActionRequest.Source:
	if replay_mode: return TacticalActionRequest.Source.REPLAY
	return TacticalActionRequest.Source.PLAYER if is_current_phase_manually_controlled() else TacticalActionRequest.Source.AI

func try_move(unit: TacticalUnit, target_cell: Vector3i) -> bool:
	if not is_instance_valid(action_service):
		return false
	is_move_mode_active = false
	is_attack_mode_active = false
	var source := _action_source()
	var request := action_service.make_move_request(unit, target_cell, source)
	var result := await action_service.submit_move(request)
	if result == null and source == TacticalActionRequest.Source.AI:
		ai_action_outcome_recorded.emit({"actor_id": String(request.actor_id), "action": "move", "stage": "rejected",
			"decision_id": _pending_ai_moves.get(request.actor_id, 0), "base_revision": request.expected_revision,
			"state_revision": action_service.state_revision, "reason": action_service.last_rejection.message if action_service.last_rejection else "Move rejected"})
		_pending_ai_moves.erase(request.actor_id)
	return result != null

func _build_movement_path(unit: TacticalUnit, path: PackedVector3Array) -> PackedVector3Array:
	var animated_path := PackedVector3Array()
	for point in path:
		var cell = grid_manager.get_cell_data(world_to_grid(point))
		var standing_height = unit.standing_height
		if cell and cell.cover_type == MapCellData.CoverType.LOW and not cell.is_vault_transit:
			standing_height += cell.cover_height
		animated_path.append(point + Vector3.UP * standing_height)
	return animated_path

func _on_unit_defeated(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit):
		return

	unit_defeated_in_battle.emit(unit)
	var fall_cell := grid_manager.get_unit_grid(unit)
	grid_manager.unregister_unit_at(fall_cell)
	turn_manager.remove_unit(unit)
	# A carried VIP must not be stranded with its carrier: put it down where the carrier fell.
	if is_instance_valid(_objective_manager):
		_objective_manager.release_carried_unit(unit, fall_cell)
	if tactical_unit == unit:
		tactical_unit = null
	is_move_mode_active = false
	is_attack_mode_active = false
	if not unit.defer_stat_presentation:
		unit.finish_defeat_presentation()

func register_mission_unit(unit: TacticalUnit, grid_position: Vector3i) -> bool:
	if not grid_manager.register_unit(unit, grid_position): return false
	_ensure_tactical_id(unit)
	if is_instance_valid(action_service):
		action_service.register_actor(unit)
	unit.defeated.connect(_on_unit_defeated)
	return true
