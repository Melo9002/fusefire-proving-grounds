class_name TacticalActionService
extends Node

signal action_committed(result)
signal action_presented(result)
signal action_rejected(validation: ActionValidationResult)
signal busy_changed(is_busy: bool)

const ATTACK_AP_COST := 1
const ATTACK_DAMAGE := 25
const ATTACK_SUPPLY_COST := 1
const RELOAD_AP_COST := 1
const AIM_AP_COST := 1
const OVERWATCH_SUPPLY_COST := 1
const OVERWATCH_ACCURACY_MODIFIER := -15

var actor_registry := TacticalActorRegistry.new()
var state_revision := 0
var last_transaction_id := 0
var last_rejection: ActionValidationResult
var last_result: AttackActionResult
var is_busy := false
var is_committing := false
## False only while reproducing recordings created before Supply Points existed.
var supply_points_enabled := true
## False only while reproducing recordings created before Aim existed.
var aim_enabled := true
var shield_enabled := true
## False only while reproducing recordings created before Overwatch existed.
var overwatch_enabled := true
## False while reconstructing recordings authored before conditions existed.
var conditions_enabled := true
var last_beat_events: Array[Dictionary] = []

var _turn_manager: TurnManager
var _grid_manager: GridManager
var _objective_manager: ObjectiveManager
var _combat_rng := RandomNumberGenerator.new()
var _present_attack: Callable
var _present_reload: Callable
var _present_aim: Callable
var _present_shield: Callable
var _present_overwatch: Callable
var _query_move: Callable
var _present_move: Callable
var _movement_committed: Callable
var _present_simple: Callable
var _validate_mission: Callable
var _commit_mission: Callable
var _present_mission: Callable

func setup(
	turn_manager: TurnManager,
	grid_manager: GridManager,
	objective_manager: ObjectiveManager,
	combat_seed: int,
	present_attack: Callable,
	present_reload: Callable = Callable(),
	present_aim: Callable = Callable(),
	present_shield: Callable = Callable(),
	present_overwatch: Callable = Callable(),
	move_query_callback: Callable = Callable(),
	present_move: Callable = Callable(),
	movement_committed: Callable = Callable(),
	present_simple: Callable = Callable(),
	validate_mission: Callable = Callable(),
	commit_mission: Callable = Callable(),
	present_mission: Callable = Callable()
) -> void:
	_turn_manager = turn_manager
	_grid_manager = grid_manager
	_objective_manager = objective_manager
	if _turn_manager and not _turn_manager.tactical_beat_ended.is_connected(_on_tactical_beat_ended):
		_turn_manager.tactical_beat_ended.connect(_on_tactical_beat_ended)
	_combat_rng.seed = combat_seed
	_present_attack = present_attack
	_present_reload = present_reload
	_present_aim = present_aim
	_present_shield = present_shield
	_present_overwatch = present_overwatch
	_query_move = move_query_callback
	_present_move = present_move
	_movement_committed = movement_committed
	_present_simple = present_simple
	_validate_mission = validate_mission
	_commit_mission = commit_mission
	_present_mission = present_mission

func register_actor(actor: TacticalUnit) -> bool:
	return actor_registry.register_actor(actor)

func _set_busy(value: bool) -> void:
	if is_busy == value:
		return
	is_busy = value
	busy_changed.emit(value)

func unregister_actor(actor: TacticalUnit) -> void:
	actor_registry.unregister_actor(actor)

func query_attack(actor_id: StringName, target_id: StringName = &"") -> AttackQueryResult:
	var query := AttackQueryResult.new()
	query.actor_id = actor_id
	query.target_id = target_id
	query.state_revision = state_revision
	query.cost = ActionCost.new(ATTACK_AP_COST)
	var actor := actor_registry.resolve(actor_id)
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		query.actor_ap_after = maxi(0, actor.stats.current_ap - ATTACK_AP_COST)
		query.supply_points_before = actor.stats.current_supply_points
		query.max_supply_points = actor.stats.max_supply_points
		query.supply_points_cost = ATTACK_SUPPLY_COST if supply_points_enabled else 0
		query.supply_points_after = maxi(0, query.supply_points_before - query.supply_points_cost)
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		query.reason = service_check.message
		return query
	if target_id.is_empty():
		var actor_check := _validate_actor(actor)
		query.validation = actor_check
		if not actor_check.accepted:
			query.reason = actor_check.message
			return query
		if supply_points_enabled and not actor.stats.has_supply_points(ATTACK_SUPPLY_COST):
			query.validation = ActionValidationResult.reject(&"insufficient_supply_points", "Not enough Supply Points", state_revision)
			query.reason = query.validation.message
			return query
		for candidate_id in actor_registry.get_ids():
			if candidate_id == actor_id:
				continue
			var candidate_query := query_attack(actor_id, candidate_id)
			query.candidate_results[candidate_id] = candidate_query
			if candidate_query.is_legal():
				query.legal_target_ids.append(candidate_id)
		query.validation = ActionValidationResult.allow(state_revision)
		return query
	var target := actor_registry.resolve(target_id)
	var evaluation: CombatRules.AttackEvaluation
	if is_instance_valid(actor) and is_instance_valid(target):
		var base_evaluation := CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d(), 0, shield_enabled)
		query.base_hit_chance = base_evaluation.hit_chance
		query.aim_bonus = _aim_bonus(actor)
		query.aim_applied = query.aim_bonus > 0
		evaluation = CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d(), query.aim_bonus, shield_enabled)
	var validation := _validate_attack(actor, target, evaluation, supply_points_enabled)
	query.validation = validation
	query.reason = validation.message
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return query
	query.evaluation = evaluation
	query.hit_chance = evaluation.hit_chance
	query.damage_on_hit = maxi(1, roundi(float(ATTACK_DAMAGE) * evaluation.shield_damage_multiplier))
	query.minimum_damage = 0
	query.maximum_damage = query.damage_on_hit
	query.expected_damage = float(query.damage_on_hit) * float(evaluation.hit_chance) / 100.0
	query.distance = CombatRules.attack_distance(_grid_manager.get_unit_grid(actor), _grid_manager.get_unit_grid(target), _grid_manager)
	query.cover_type = evaluation.cover_type
	query.shield_applied = evaluation.shield_applied
	query.shield_accuracy_modifier = evaluation.shield_accuracy_modifier
	query.shield_damage_multiplier = evaluation.shield_damage_multiplier
	query.reason = evaluation.reason if validation.accepted else validation.message
	query.aim_point = evaluation.aim_point
	query.obstruction = evaluation.obstruction
	query.visibility_fraction = evaluation.visibility_fraction
	if evaluation.blocking_cell:
		query.blocking_cell = evaluation.blocking_cell.grid_position
	return query

func submit_attack(request: TacticalActionRequest, suppress_presentation := false) -> AttackActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	# No await, signal, or random draw occurs before this final validation.
	var actor := actor_registry.resolve(request.actor_id)
	var target := actor_registry.resolve(request.target_id)
	var aim_bonus := _aim_bonus(actor)
	var base_evaluation := CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d(), 0, shield_enabled) if is_instance_valid(actor) and is_instance_valid(target) else null
	var evaluation := CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d(), aim_bonus, shield_enabled) if is_instance_valid(actor) and is_instance_valid(target) else null
	# Supply semantics belong to the reconstructed battle rules, never to caller-
	# controlled request details. Historical replay setup disables them globally.
	var uses_supply := supply_points_enabled
	validation = _validate_attack(actor, target, evaluation, uses_supply)
	if not validation.accepted:
		_reject(validation)
		return null

	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := AttackActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.cost = ActionCost.new(ATTACK_AP_COST)
	result.hit_chance = evaluation.hit_chance
	result.base_hit_chance = base_evaluation.hit_chance
	result.aim_bonus = aim_bonus
	result.aim_applied = aim_bonus > 0
	result.roll = _combat_rng.randf() * 100.0
	result.did_hit = AttackActionResult.roll_hits(result.roll, result.hit_chance)
	result.environmental_cover = evaluation.cover_type
	result.shield_applied = evaluation.shield_applied
	result.shield_accuracy_modifier = evaluation.shield_accuracy_modifier
	result.shield_damage_multiplier = evaluation.shield_damage_multiplier
	result.damage = maxi(1, roundi(float(ATTACK_DAMAGE) * evaluation.shield_damage_multiplier)) if result.did_hit else 0
	result.actor_ap_before = actor.stats.current_ap
	result.supply_points_before = actor.stats.current_supply_points
	result.max_supply_points = actor.stats.max_supply_points
	result.supply_points_cost = ATTACK_SUPPLY_COST if uses_supply else 0
	result.target_hp_before = target.stats.current_hp
	result.battle_result_before = int(_turn_manager.battle_result)
	result.target_position = target.global_position
	result.objective_state_before = _capture_objectives()

	# Commit is deliberately synchronous. Stat signals may update roster/objective
	# owners, but the service remains guarded against nested submissions.
	actor.stats.consume_ap(ATTACK_AP_COST)
	if uses_supply:
		actor.stats.consume_supply_points(ATTACK_SUPPLY_COST)
	if result.aim_applied:
		actor.tactical_state.clear_aim()
	_cancel_overwatch(actor)
	result.aiming_after = actor.tactical_state.is_aiming if actor.tactical_state else false
	if result.did_hit:
		target.defer_stat_presentation = true
		target.stats.take_damage(result.damage)
		target.defer_stat_presentation = false
		if result.damage > 0 and not target.stats.is_defeated and conditions_enabled and actor.attack_condition:
			var condition_event := _apply_condition(target, actor.attack_condition, actor.tactical_id, &"attack")
			if condition_event.get("applied", false): result.condition_events.append(condition_event)
	_resolve_attack_retaliation(actor, target, result)
	if _objective_manager:
		_objective_manager.evaluate_outcome_after_action_commit()
	result.actor_ap_after = actor.stats.current_ap
	result.supply_points_after = actor.stats.current_supply_points
	result.target_hp_after = target.stats.current_hp
	result.target_defeated = target.stats.is_defeated
	result.battle_result_after = int(_turn_manager.battle_result)
	result.objective_state_after = _capture_objectives()
	state_revision += 1
	result.committed_revision = state_revision
	last_result = result
	is_committing = false
	action_committed.emit(result)

	result.presentation_suppressed = suppress_presentation
	if _present_attack.is_valid():
		await _present_attack.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func query_reload(actor_id: StringName) -> ReloadQueryResult:
	var query := ReloadQueryResult.new()
	query.actor_id = actor_id
	query.state_revision = state_revision
	query.cost = ActionCost.new(RELOAD_AP_COST)
	var actor := actor_registry.resolve(actor_id)
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		query.actor_ap_after = maxi(0, actor.stats.current_ap - RELOAD_AP_COST)
		query.supply_points_before = actor.stats.current_supply_points
		query.max_supply_points = actor.stats.max_supply_points
		query.supply_points_after = actor.stats.max_supply_points
		query.supply_points_restored = actor.stats.max_supply_points - actor.stats.current_supply_points
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	query.validation = _validate_reload(actor)
	return query

func query_aim(actor_id: StringName) -> AimQueryResult:
	var query := AimQueryResult.new()
	query.actor_id = actor_id
	query.state_revision = state_revision
	query.cost = ActionCost.new(AIM_AP_COST)
	var actor := actor_registry.resolve(actor_id)
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		query.actor_ap_after = maxi(0, actor.stats.current_ap - AIM_AP_COST)
		query.aiming_before = actor.tactical_state.is_aiming if actor.tactical_state else false
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	query.validation = _validate_aim(actor)
	return query

func query_shield(actor_id: StringName, threat_id: StringName = &"") -> ShieldQueryResult:
	var query := ShieldQueryResult.new()
	query.actor_id = actor_id
	query.threat_id = threat_id
	query.state_revision = state_revision
	var actor := actor_registry.resolve(actor_id)
	var threat := actor_registry.resolve(threat_id) if not threat_id.is_empty() else null
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		if actor.shield_capability:
			query.cost = ActionCost.new(actor.shield_capability.stance_ap_cost)
			query.actor_ap_after = maxi(0, actor.stats.current_ap - query.cost.ap)
			query.protected_arc_degrees = actor.shield_capability.protected_arc_degrees
			query.accuracy_modifier = actor.shield_capability.accuracy_modifier
			query.damage_multiplier = actor.shield_capability.damage_multiplier
		if is_instance_valid(threat):
			var actor_cell := _grid_manager.get_unit_grid(actor)
			var threat_cell := _grid_manager.get_unit_grid(threat)
			query.facing = Vector2(float(threat_cell.x - actor_cell.x), float(threat_cell.z - actor_cell.z)).normalized()
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	if threat_id.is_empty():
		query.validation = _validate_shield_actor(actor)
		if not query.validation.accepted:
			return query
		for candidate_id in actor_registry.get_ids():
			if candidate_id == actor_id: continue
			var candidate_query := query_shield(actor_id, candidate_id)
			query.candidate_results[candidate_id] = candidate_query
			if candidate_query.is_legal(): query.legal_threat_ids.append(candidate_id)
		if query.legal_threat_ids.is_empty():
			query.validation = ActionValidationResult.reject(&"no_hostile_targets", "No living hostile is available to face", state_revision)
		return query
	query.validation = _validate_shield(actor, threat)
	return query

func submit_shield(request: TacticalActionRequest, suppress_presentation := false) -> ShieldActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if request.kind != &"shield":
		validation = ActionValidationResult.reject(&"unsupported_action", "Expected a Shield Stance request", state_revision)
		_reject(validation)
		return null
	var query := query_shield(request.actor_id, request.target_id)
	if not query.is_legal():
		_reject(query.validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := ShieldActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.cost = query.cost
	result.actor_ap_before = actor.stats.current_ap
	result.aiming_before = actor.tactical_state.is_aiming
	result.shielding_before = actor.tactical_state.is_shielding
	result.facing = query.facing
	result.protected_arc_degrees = query.protected_arc_degrees
	result.accuracy_modifier = query.accuracy_modifier
	result.damage_multiplier = query.damage_multiplier
	actor.stats.consume_ap(query.cost.ap)
	actor.tactical_state.clear_aim()
	actor.tactical_state.clear_overwatch()
	actor.tactical_state.establish_shield(query.facing)
	result.actor_ap_after = actor.stats.current_ap
	result.aiming_after = actor.tactical_state.is_aiming
	result.shielding_after = actor.tactical_state.is_shielding
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_shield.is_valid(): await _present_shield.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func query_overwatch(actor_id: StringName) -> OverwatchQueryResult:
	var query := OverwatchQueryResult.new()
	query.actor_id = actor_id
	query.state_revision = state_revision
	var actor := actor_registry.resolve(actor_id)
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		query.actor_ap_after = 0
		query.cost = ActionCost.new(actor.stats.current_ap, true, true)
		query.supply_points_before = actor.stats.current_supply_points
		query.overwatching_before = actor.tactical_state.is_overwatching if actor.tactical_state else false
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	query.validation = _validate_overwatch(actor)
	return query

func submit_overwatch(request: TacticalActionRequest, suppress_presentation := false) -> OverwatchActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if request.kind != &"overwatch":
		validation = ActionValidationResult.reject(&"unsupported_action", "Expected an Overwatch request", state_revision)
		_reject(validation)
		return null
	var query := query_overwatch(request.actor_id)
	if not query.is_legal():
		_reject(query.validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := OverwatchActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.cost = query.cost
	result.actor_ap_before = actor.stats.current_ap
	result.supply_points_before = actor.stats.current_supply_points
	result.overwatching_before = actor.tactical_state.is_overwatching
	actor.stats.current_ap = 0
	_cancel_aim(actor)
	_cancel_shield(actor)
	actor.tactical_state.establish_overwatch()
	result.actor_ap_after = actor.stats.current_ap
	result.overwatching_after = actor.tactical_state.is_overwatching
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_overwatch.is_valid(): await _present_overwatch.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func submit_aim(request: TacticalActionRequest, suppress_presentation := false) -> AimActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if request.kind != &"aim":
		validation = ActionValidationResult.reject(&"unsupported_action", "Expected an Aim request", state_revision)
		_reject(validation)
		return null
	var query := query_aim(request.actor_id)
	if not query.is_legal():
		_reject(query.validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := AimActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.cost = ActionCost.new(AIM_AP_COST)
	result.actor_ap_before = actor.stats.current_ap
	result.aiming_before = actor.tactical_state.is_aiming
	actor.stats.consume_ap(AIM_AP_COST)
	_cancel_shield(actor)
	_cancel_overwatch(actor)
	actor.tactical_state.establish_aim()
	result.actor_ap_after = actor.stats.current_ap
	result.aiming_after = actor.tactical_state.is_aiming
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_aim.is_valid(): await _present_aim.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func submit_reload(request: TacticalActionRequest, suppress_presentation := false) -> ReloadActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if request.kind != &"reload":
		validation = ActionValidationResult.reject(&"unsupported_action", "Expected a Reload request", state_revision)
		_reject(validation)
		return null
	var query := query_reload(request.actor_id)
	if not query.is_legal():
		_reject(query.validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := ReloadActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.cost = ActionCost.new(RELOAD_AP_COST)
	result.actor_ap_before = actor.stats.current_ap
	result.supply_points_before = actor.stats.current_supply_points
	result.max_supply_points = actor.stats.max_supply_points
	actor.stats.consume_ap(RELOAD_AP_COST)
	result.supply_points_restored = actor.stats.reload_supply_points()
	_cancel_aim(actor)
	_cancel_overwatch(actor)
	result.actor_ap_after = actor.stats.current_ap
	result.supply_points_after = actor.stats.current_supply_points
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_reload.is_valid(): await _present_reload.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func query_move(actor_id: StringName, target_cell := Vector3i(-1, -1, -1)) -> MoveQueryResult:
	var query := MoveQueryResult.new()
	query.actor_id = actor_id
	query.target_cell = target_cell
	query.state_revision = state_revision
	var actor := actor_registry.resolve(actor_id)
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		query.actor_ap_after = maxi(0, actor.stats.current_ap - query.cost.ap)
		query.movement_budget = actor.stats.speed
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	query.validation = _validate_actor(actor)
	if not query.validation.accepted: return query
	query.start_cell = _grid_manager.get_unit_grid(actor)
	if not _query_move.is_valid():
		query.validation = ActionValidationResult.reject(&"service_unavailable", "Movement query is unavailable", state_revision)
		return query
	var data: Dictionary = _query_move.call(actor, target_cell)
	if not data.get("accepted", false):
		query.validation = ActionValidationResult.reject(StringName(data.get("code", "illegal_move")), data.get("message", "Illegal move"), state_revision)
		query.blocking_actor_id = StringName(data.get("blocking_actor_id", ""))
		return query
	query.movement_budget = data.get("movement_budget", query.movement_budget)
	query.legal_destination_cells.assign(data.get("legal_destinations", []))
	if query.has_destination():
		query.path_cells.assign(data["path_cells"])
		query.path = data["path"]
		query.presentation_path = data["presentation_path"]
		query.visual_segments.assign(data["visual_segments"])
		query.path_cost = data.get("path_cost", 0.0)
		query.elevation_change = target_cell.y - query.start_cell.y
	query.validation = ActionValidationResult.allow(state_revision)
	return query

func submit_move(request: TacticalActionRequest, suppress_presentation := false) -> MoveActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if request.kind != &"move":
		validation = ActionValidationResult.reject(&"unsupported_action", "Expected a move request", state_revision)
		_reject(validation)
		return null
	var query := query_move(request.actor_id, request.destination)
	if not query.is_legal():
		_reject(query.validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := MoveActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.start_cell = query.start_cell
	result.target_cell = query.target_cell
	result.path_cells.assign(query.path_cells)
	result.presentation_path = query.presentation_path
	result.visual_segments = query.visual_segments
	result.actor_ap_before = actor.stats.current_ap
	result.objective_state_before = _capture_objectives()
	actor.stats.consume_ap(result.cost.ap)
	_resolve_overwatch_reactions(actor, result)
	if not actor.stats.is_defeated:
		_grid_manager.update_unit_position(actor, result.start_cell, result.target_cell)
	else:
		actor.grid_position = result.target_cell
	_cancel_aim(actor)
	_cancel_shield(actor)
	_cancel_overwatch(actor)
	result.actor_ap_after = actor.stats.current_ap
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	if not actor.stats.is_defeated and _movement_committed.is_valid(): _movement_committed.call(actor, result.start_cell, result.target_cell)
	result.objective_state_after = _capture_objectives()
	result.carried_actor_id = actor.carried_unit.tactical_id if actor.is_carrying_unit() else &""
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_move.is_valid(): await _present_move.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func make_attack_request(actor: TacticalUnit, target: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.attack(
		actor.tactical_id if is_instance_valid(actor) else &"",
		target.tactical_id if is_instance_valid(target) else &"",
		state_revision,
		source
	)

func make_reload_request(actor: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.simple(&"reload", actor.tactical_id if is_instance_valid(actor) else &"", state_revision, source)

func make_aim_request(actor: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.simple(&"aim", actor.tactical_id if is_instance_valid(actor) else &"", state_revision, source)

func make_shield_request(actor: TacticalUnit, threat: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.new(&"shield", actor.tactical_id if is_instance_valid(actor) else &"", threat.tactical_id if is_instance_valid(threat) else &"", state_revision, source)

func make_overwatch_request(actor: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.simple(&"overwatch", actor.tactical_id if is_instance_valid(actor) else &"", state_revision, source)

func make_move_request(actor: TacticalUnit, target_cell: Vector3i, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.move(actor.tactical_id if is_instance_valid(actor) else &"", target_cell, state_revision, source)

func make_simple_request(kind: StringName, actor: TacticalUnit, source: TacticalActionRequest.Source, details: Dictionary = {}) -> TacticalActionRequest:
	return TacticalActionRequest.simple(kind, actor.tactical_id if is_instance_valid(actor) else &"", state_revision, source, details)

func make_mission_request(kind: StringName, actor: TacticalUnit, target: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.mission(kind, actor.tactical_id if is_instance_valid(actor) else &"", target.tactical_id if is_instance_valid(target) else &"", state_revision, source)

func make_terminal_request(actor: TacticalUnit, terminal_id: StringName, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.mission(&"interact_terminal", actor.tactical_id if is_instance_valid(actor) else &"", terminal_id, state_revision, source)

func query_simple(kind: StringName, actor_id: StringName) -> SimpleActionQueryResult:
	var query := SimpleActionQueryResult.new()
	query.kind = kind
	query.actor_id = actor_id
	query.state_revision = state_revision
	var actor := actor_registry.resolve(actor_id)
	if is_instance_valid(actor) and actor.stats:
		query.actor_ap_before = actor.stats.current_ap
		query.cost = ActionCost.new(
			actor.stats.current_ap if kind == &"wait" else ATTACK_AP_COST,
			kind == &"wait",
			kind == &"wait"
		)
		query.actor_ap_after = 0 if kind == &"wait" else maxi(0, actor.stats.current_ap - ATTACK_AP_COST)
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	if kind not in [&"wait", &"defend", &"emergency_seal"]:
		query.validation = ActionValidationResult.reject(&"unsupported_action", "Unsupported simple action", state_revision)
		return query
	query.validation = _validate_emergency_seal(actor) if kind == &"emergency_seal" else _validate_actor(actor)
	return query

func query_mission(kind: StringName, actor_id: StringName, target_id: StringName = &"") -> MissionActionQueryResult:
	var query := MissionActionQueryResult.new()
	query.kind = kind
	query.actor_id = actor_id
	query.target_id = target_id
	query.state_revision = state_revision
	query.cost = ActionCost.new(0, false, false, false)
	var service_check := _validate_action_window()
	if not service_check.accepted:
		query.validation = service_check
		return query
	if kind not in [&"rescue", &"extract", &"interact_terminal"] or not _validate_mission.is_valid():
		query.validation = ActionValidationResult.reject(&"unsupported_action", "Mission action is unavailable", state_revision)
		return query
	var actor := actor_registry.resolve(actor_id)
	if not is_instance_valid(actor) or not actor.stats:
		query.validation = ActionValidationResult.reject(&"actor_missing", "Acting unit is unavailable", state_revision)
		return query
	if actor.stats.is_defeated:
		query.validation = ActionValidationResult.reject(&"actor_defeated", "Acting unit is defeated", state_revision)
		return query
	query.actor_ap_before = actor.stats.current_ap
	query.actor_ap_after = query.actor_ap_before
	if kind == &"interact_terminal":
		var actor_check := _validate_free_objective_actor(actor)
		if not actor_check.accepted:
			query.validation = actor_check
			return query
		if target_id.is_empty():
			for candidate_id in _objective_manager.get_terminal_ids() if is_instance_valid(_objective_manager) else []:
				var candidate_query := query_mission(kind, actor_id, candidate_id)
				query.candidate_results[candidate_id] = candidate_query
				if candidate_query.is_legal(): query.legal_target_ids.append(candidate_id)
			query.validation = ActionValidationResult.allow(state_revision) if not query.legal_target_ids.is_empty() else ActionValidationResult.reject(&"no_terminal_in_range", "No inactive terminal is in interaction range", state_revision)
			return query
		var terminal := _objective_manager.get_terminal_state(target_id) if is_instance_valid(_objective_manager) else null
		if terminal:
			query.terminal_position = terminal.definition.grid_position
			query.terminal_activated = terminal.is_activated
			query.objective_id = terminal.definition.objective_id
		query.validation = _validate_mission.call(kind, actor, null, state_revision, target_id)
		return query
	if kind == &"rescue" and target_id.is_empty():
		for candidate_id in actor_registry.get_ids():
			if candidate_id == actor_id: continue
			var candidate_query := query_mission(kind, actor_id, candidate_id)
			query.candidate_results[candidate_id] = candidate_query
			if candidate_query.is_legal(): query.legal_target_ids.append(candidate_id)
		query.validation = ActionValidationResult.allow(state_revision)
		return query
	var target := actor_registry.resolve(target_id) if not target_id.is_empty() else null
	query.validation = _validate_mission.call(kind, actor, target, state_revision, target_id)
	return query

func submit_simple(request: TacticalActionRequest, suppress_presentation := false) -> SimpleActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	var query := query_simple(request.kind, request.actor_id)
	validation = query.validation
	if not validation.accepted:
		_reject(validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := SimpleActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.actor_ap_before = actor.stats.current_ap
	result.defending_before = actor.stats.is_defending
	result.charges_before = actor.emergency_seal_charges
	if request.kind == &"wait": actor.stats.current_ap = 0
	elif request.kind == &"emergency_seal":
		actor.stats.consume_ap(1)
		actor.emergency_seal_charges -= 1
		result.condition_id = &"leaking"
		result.condition_removed = actor.conditions.remove(&"leaking")
	else:
		actor.stats.consume_ap(ATTACK_AP_COST)
		actor.stats.is_defending = true
	_cancel_aim(actor)
	_cancel_shield(actor)
	_cancel_overwatch(actor)
	result.actor_ap_after = actor.stats.current_ap
	result.defending_after = actor.stats.is_defending
	result.charges_after = actor.emergency_seal_charges
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_simple.is_valid(): await _present_simple.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func submit_mission(request: TacticalActionRequest, suppress_presentation := false) -> MissionActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if not _commit_mission.is_valid():
		validation = ActionValidationResult.reject(&"unsupported_action", "Mission action is unavailable", state_revision)
		_reject(validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	var target := actor_registry.resolve(request.target_id) if not request.target_id.is_empty() else null
	validation = query_mission(request.kind, request.actor_id, request.target_id).validation
	if not validation.accepted:
		_reject(validation)
		return null
	_set_busy(true)
	is_committing = true
	last_transaction_id += 1
	var result := MissionActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.actor_position = actor.global_position
	result.target_position = target.global_position if is_instance_valid(target) else actor.global_position
	result.actor_ap_before = actor.stats.current_ap
	if request.kind == &"interact_terminal":
		var terminal_before := _objective_manager.get_terminal_state(request.target_id) if is_instance_valid(_objective_manager) else null
		if terminal_before:
			result.terminal_position = terminal_before.definition.grid_position
			result.target_position = _grid_manager.grid_to_world(result.terminal_position)
			result.terminal_activated_before = terminal_before.is_activated
	result.objective_state_before = _capture_objectives()
	result.mission_counters_before = _capture_mission_counters()
	if not _commit_mission.call(request.kind, actor, target, request.target_id):
		is_committing = false
		_set_busy(false)
		validation = ActionValidationResult.reject(&"commit_failed", "Mission action failed during authoritative commit", state_revision)
		_reject(validation)
		return null
	_cancel_aim(actor)
	_cancel_shield(actor)
	_cancel_overwatch(actor)
	result.objective_state_after = _capture_objectives()
	result.mission_counters_after = _capture_mission_counters()
	result.actor_removed_from_roster = not _actor_is_in_roster(actor)
	result.actor_ap_after = actor.stats.current_ap
	if request.kind == &"interact_terminal":
		var terminal_after := _objective_manager.get_terminal_state(request.target_id) if is_instance_valid(_objective_manager) else null
		result.terminal_activated_after = terminal_after.is_activated if terminal_after else false
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_mission.is_valid(): await _present_mission.call(result, actor, target)
	result.presentation_completed = true
	action_presented.emit(result)
	_set_busy(false)
	return result

func get_combat_rng_state() -> int:
	return _combat_rng.state

## Dedicated authoritative systems use this when a turn or mission command
## changes legality without being a unit action. It invalidates old queries
## without forcing those systems into the action-handler abstraction.
func advance_external_revision() -> int:
	if not is_committing:
		state_revision += 1
	return state_revision

func _validate_request(request: TacticalActionRequest) -> ActionValidationResult:
	if request == null or request.kind not in [&"attack", &"move", &"wait", &"defend", &"reload", &"aim", &"shield", &"overwatch", &"emergency_seal", &"rescue", &"extract", &"interact_terminal"]:
		return ActionValidationResult.reject(&"unsupported_action", "Action service received an unsupported request", state_revision)
	var service_check := _validate_action_window()
	if not service_check.accepted:
		return service_check
	if request.expected_revision != state_revision:
		return ActionValidationResult.reject(&"stale_revision", "Action preview is stale", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_action_window() -> ActionValidationResult:
	if get_tree().paused:
		return ActionValidationResult.reject(&"paused", "Battle is paused", state_revision)
	if is_busy or is_committing:
		return ActionValidationResult.reject(&"action_busy", "Another action is already being resolved or presented", state_revision)
	return ActionValidationResult.allow(state_revision)

func _capture_mission_counters() -> Dictionary:
	if not is_instance_valid(_objective_manager): return {}
	return {"extracted_vips": _objective_manager.extracted_vips, "extracted_units": _objective_manager.extracted_units, "escaped_enemies": _objective_manager.escaped_enemies, "left_behind": _objective_manager.left_behind}

func _actor_is_in_roster(actor: TacticalUnit) -> bool:
	return is_instance_valid(actor) and is_instance_valid(_turn_manager) and (_turn_manager.player_units.has(actor) or _turn_manager.allied_units.has(actor) or _turn_manager.enemy_units.has(actor))

func _validate_actor(actor: TacticalUnit) -> ActionValidationResult:
	if not is_instance_valid(actor) or not actor.stats:
		return ActionValidationResult.reject(&"actor_missing", "Acting unit is unavailable", state_revision)
	if actor.stats.is_defeated:
		return ActionValidationResult.reject(&"actor_defeated", "Acting unit is defeated", state_revision)
	if not _turn_manager or not _turn_manager.can_unit_act(actor):
		return ActionValidationResult.reject(&"wrong_activation", "Unit is not allowed to act now", state_revision)
	if not actor.stats.has_enough_ap(ATTACK_AP_COST):
		return ActionValidationResult.reject(&"insufficient_ap", "Not enough AP", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_free_objective_actor(actor: TacticalUnit) -> ActionValidationResult:
	if not is_instance_valid(actor) or not actor.stats:
		return ActionValidationResult.reject(&"actor_missing", "Acting unit is unavailable", state_revision)
	if actor.stats.is_defeated:
		return ActionValidationResult.reject(&"actor_defeated", "Acting unit is defeated", state_revision)
	if not _turn_manager or not _turn_manager.can_unit_act(actor):
		return ActionValidationResult.reject(&"wrong_activation", "Unit is not allowed to act now", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_attack(actor: TacticalUnit, target: TacticalUnit, evaluation: CombatRules.AttackEvaluation = null, require_supply := true) -> ActionValidationResult:
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if shield_enabled and actor.tactical_state and actor.tactical_state.is_shielding and actor.shield_capability and not actor.shield_capability.attacks_allowed:
		return ActionValidationResult.reject(&"shield_stance_restriction", "Cannot Attack while Shield Stance is active", state_revision)
	if require_supply and not actor.stats.has_supply_points(ATTACK_SUPPLY_COST):
		return ActionValidationResult.reject(&"insufficient_supply_points", "Not enough Supply Points", state_revision)
	if not is_instance_valid(target) or not target.stats:
		return ActionValidationResult.reject(&"target_missing", "Target is unavailable", state_revision)
	if evaluation == null:
		evaluation = CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d())
	if evaluation.is_legal:
		return ActionValidationResult.allow(state_revision)
	return ActionValidationResult.reject(_code_for_reason(evaluation.reason), evaluation.reason, state_revision)

func _validate_reload(actor: TacticalUnit) -> ActionValidationResult:
	if not supply_points_enabled:
		return ActionValidationResult.reject(&"unsupported_action", "Reload is unavailable in this historical replay", state_revision)
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if shield_enabled and actor.tactical_state and actor.tactical_state.is_shielding and actor.shield_capability and not actor.shield_capability.reload_allowed:
		return ActionValidationResult.reject(&"shield_stance_restriction", "Cannot Reload while Shield Stance is active", state_revision)
	if actor.stats.current_supply_points >= actor.stats.max_supply_points:
		return ActionValidationResult.reject(&"resource_full", "Supply Points are already full", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_aim(actor: TacticalUnit) -> ActionValidationResult:
	if not aim_enabled:
		return ActionValidationResult.reject(&"unsupported_action", "Aim is unavailable in this historical replay", state_revision)
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if not actor.tactical_state:
		return ActionValidationResult.reject(&"state_unavailable", "Actor has no tactical-state component", state_revision)
	if actor.tactical_state.is_aiming:
		return ActionValidationResult.reject(&"already_aiming", "Actor is already Aimed", state_revision)
	if conditions_enabled and actor.conditions and actor.conditions.restricts(&"aim"):
		return ActionValidationResult.reject(&"condition_restriction", "Jammed units cannot Aim", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_emergency_seal(actor: TacticalUnit) -> ActionValidationResult:
	if not conditions_enabled:
		return ActionValidationResult.reject(&"unsupported_action", "Emergency Seal is unavailable in this historical replay", state_revision)
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted: return actor_result
	if actor.conditions == null or not actor.conditions.has(&"leaking"):
		return ActionValidationResult.reject(&"condition_missing", "Unit is not Leaking", state_revision)
	if actor.emergency_seal_charges <= 0:
		return ActionValidationResult.reject(&"no_charges", "No Emergency Seal charges remain", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_shield(actor: TacticalUnit, threat: TacticalUnit) -> ActionValidationResult:
	var actor_result := _validate_shield_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if not is_instance_valid(threat) or not threat.stats or threat.stats.is_defeated:
		return ActionValidationResult.reject(&"target_missing", "Choose a living hostile to face", state_revision)
	if not FactionRules.are_hostile(actor.faction, threat.faction):
		return ActionValidationResult.reject(&"target_not_hostile", "Shield Stance must face a hostile threat", state_revision)
	if _grid_manager.get_unit_grid(actor) == _grid_manager.get_unit_grid(threat):
		return ActionValidationResult.reject(&"invalid_direction", "Shield direction could not be determined", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_shield_actor(actor: TacticalUnit) -> ActionValidationResult:
	if not shield_enabled:
		return ActionValidationResult.reject(&"unsupported_action", "Shield Stance is unavailable in this historical replay", state_revision)
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if not actor.shield_capability:
		return ActionValidationResult.reject(&"missing_capability", "Unit has no shield capability", state_revision)
	var capability_error := actor.shield_capability.validation_message()
	if not capability_error.is_empty():
		return ActionValidationResult.reject(&"invalid_capability", capability_error, state_revision)
	if actor.stats.current_ap < actor.shield_capability.stance_ap_cost:
		return ActionValidationResult.reject(&"insufficient_ap", "Not enough AP", state_revision)
	if not actor.tactical_state:
		return ActionValidationResult.reject(&"state_unavailable", "Actor has no tactical-state component", state_revision)
	if actor.tactical_state.is_shielding:
		return ActionValidationResult.reject(&"already_shielding", "Shield Stance is already active", state_revision)
	if actor.tactical_state.is_overwatching:
		return ActionValidationResult.reject(&"overwatch_restriction", "Cannot enter Shield Stance while Overwatch is active", state_revision)
	return ActionValidationResult.allow(state_revision)

func _validate_overwatch(actor: TacticalUnit) -> ActionValidationResult:
	if not overwatch_enabled:
		return ActionValidationResult.reject(&"unsupported_action", "Overwatch is unavailable in this historical replay", state_revision)
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if not actor.tactical_state:
		return ActionValidationResult.reject(&"state_unavailable", "Actor has no tactical-state component", state_revision)
	if actor.tactical_state.is_overwatching:
		return ActionValidationResult.reject(&"already_overwatching", "Overwatch is already active", state_revision)
	if actor.tactical_state.is_shielding:
		return ActionValidationResult.reject(&"shield_stance_restriction", "Cannot enter Overwatch while Shield Stance is active", state_revision)
	if not actor.stats.has_supply_points(OVERWATCH_SUPPLY_COST):
		return ActionValidationResult.reject(&"insufficient_supply_points", "Overwatch requires at least 1 Supply Point", state_revision)
	return ActionValidationResult.allow(state_revision)

func _aim_bonus(actor: TacticalUnit) -> int:
	if not aim_enabled or not is_instance_valid(actor) or not actor.tactical_state:
		return 0
	return TacticalState.AIM_ACCURACY_BONUS if actor.tactical_state.is_aiming else 0

func _cancel_aim(actor: TacticalUnit) -> bool:
	return actor.tactical_state.clear_aim() if is_instance_valid(actor) and actor.tactical_state else false

func _cancel_shield(actor: TacticalUnit) -> bool:
	return actor.tactical_state.clear_shield() if shield_enabled and is_instance_valid(actor) and actor.tactical_state else false

func _cancel_overwatch(actor: TacticalUnit) -> bool:
	return actor.tactical_state.clear_overwatch() if overwatch_enabled and is_instance_valid(actor) and actor.tactical_state else false

func _resolve_overwatch_reactions(mover: TacticalUnit, result: MoveActionResult) -> void:
	if result.path_cells.size() <= 1:
		return
	var watcher_ids := actor_registry.get_ids()
	watcher_ids.sort_custom(func(first: StringName, second: StringName) -> bool:
		var a := actor_registry.resolve(first)
		var b := actor_registry.resolve(second)
		var faction_a := int(a.faction) if is_instance_valid(a) else 999
		var faction_b := int(b.faction) if is_instance_valid(b) else 999
		return String(first) < String(second) if faction_a == faction_b else faction_a < faction_b
	)
	var final_index := result.path_cells.size() - 1
	for checkpoint_index in range(1, result.path_cells.size()):
		var checkpoint := result.path_cells[checkpoint_index]
		if conditions_enabled:
			var cell := _grid_manager.map_data.get_cell(checkpoint) if _grid_manager and _grid_manager.map_data else null
			if cell and cell.hazard_condition:
				var exposure := _apply_condition(mover, cell.hazard_condition, StringName("hazard:%s" % checkpoint), &"hazard")
				exposure["checkpoint_index"] = checkpoint_index
				exposure["checkpoint_cell"] = [checkpoint.x, checkpoint.y, checkpoint.z]
				if exposure.get("applied", false): result.condition_events.append(exposure)
		if not overwatch_enabled:
			continue
		for watcher_id in watcher_ids:
			var watcher := actor_registry.resolve(watcher_id)
			if not _watcher_can_react(watcher, mover):
				continue
			var evaluation := CombatRules.evaluate_attack_at_cell(watcher, mover, checkpoint, _grid_manager, mover.get_world_3d(), OVERWATCH_ACCURACY_MODIFIER, shield_enabled)
			if not evaluation.is_legal:
				continue
			var event := OverwatchReactionEvent.new()
			event.watcher_id = watcher.tactical_id
			event.checkpoint_cell = checkpoint
			event.checkpoint_index = checkpoint_index
			event.hit_chance = evaluation.hit_chance
			event.roll = _combat_rng.randf() * 100.0
			event.did_hit = AttackActionResult.roll_hits(event.roll, event.hit_chance)
			event.environmental_cover = evaluation.cover_type
			event.shield_applied = evaluation.shield_applied
			event.shield_accuracy_modifier = evaluation.shield_accuracy_modifier
			event.shield_damage_multiplier = evaluation.shield_damage_multiplier
			event.supply_points_before = watcher.stats.current_supply_points
			event.target_hp_before = mover.stats.current_hp
			watcher.stats.consume_supply_points(OVERWATCH_SUPPLY_COST)
			watcher.tactical_state.clear_overwatch()
			if event.did_hit:
				var requested_damage := maxi(1, roundi(float(ATTACK_DAMAGE) * evaluation.shield_damage_multiplier))
				mover.defer_stat_presentation = true
				mover.stats.take_damage(requested_damage)
				mover.defer_stat_presentation = false
			event.supply_points_after = watcher.stats.current_supply_points
			event.target_hp_after = mover.stats.current_hp
			event.damage = event.target_hp_before - event.target_hp_after
			event.target_defeated = mover.stats.is_defeated
			result.reaction_events.append(event)
			if event.target_defeated:
				final_index = checkpoint_index
				result.movement_interrupted = true
				break
		if result.movement_interrupted:
			break
	if final_index < result.path_cells.size() - 1:
		result.path_cells = result.path_cells.slice(0, final_index + 1)
		result.presentation_path = result.presentation_path.slice(0, final_index + 1)
		result.visual_segments = result.visual_segments.slice(0, final_index + 1)
		result.target_cell = result.path_cells[-1]

func _apply_condition(target: TacticalUnit, definition: ConditionDefinition, source_id: StringName, source_kind: StringName) -> Dictionary:
	var event := {
		"condition_id": String(definition.condition_id) if definition else "",
		"source_id": String(source_id),
		"source_kind": String(source_kind),
		"target_id": String(target.tactical_id) if is_instance_valid(target) else "",
		"applied": false,
		"refreshed": false,
		"remaining_beats": 0,
	}
	if not conditions_enabled or not is_instance_valid(target) or not target.stats or target.stats.is_defeated \
	or target.conditions == null or definition == null or not target.can_receive_condition(definition):
		return event
	var application := target.conditions.apply(definition, _turn_manager.current_round, source_id)
	event.merge(application, true)
	if event.get("applied", false) and definition.restricted_action == &"aim" and target.tactical_state:
		target.tactical_state.clear_aim()
	return event

func apply_condition(target: TacticalUnit, definition: ConditionDefinition, source_id: StringName = &"system") -> Dictionary:
	return _apply_condition(target, definition, source_id, &"system")

func _on_tactical_beat_ended(beat_number: int) -> void:
	if not conditions_enabled: return
	last_beat_events.clear()
	var actor_ids := actor_registry.get_ids()
	actor_ids.sort_custom(func(a: StringName, b: StringName): return String(a) < String(b))
	for actor_id in actor_ids:
		var actor := actor_registry.resolve(actor_id)
		if not is_instance_valid(actor) or not actor.stats or actor.stats.is_defeated or actor.conditions == null:
			continue
		for tick in actor.conditions.tick(beat_number):
			var event: Dictionary = tick.duplicate(true)
			event["target_id"] = String(actor.tactical_id)
			event["beat"] = beat_number
			event["hp_before"] = actor.stats.current_hp
			var damage := int(event.get("damage", 0))
			if damage > 0:
				actor.stats.take_damage(damage)
			event["hp_after"] = actor.stats.current_hp
			event["defeated"] = actor.stats.is_defeated
			last_beat_events.append(event)
			if actor.stats.is_defeated: break

func _resolve_attack_retaliation(attacker: TacticalUnit, watcher: TacticalUnit, result: AttackActionResult) -> void:
	if not overwatch_enabled or not _watcher_can_react(watcher, attacker):
		return
	var evaluation := CombatRules.evaluate_attack(watcher, attacker, _grid_manager, watcher.get_world_3d(), OVERWATCH_ACCURACY_MODIFIER, shield_enabled)
	if not evaluation.is_legal:
		return
	var event := OverwatchReactionEvent.new()
	event.watcher_id = watcher.tactical_id
	event.checkpoint_cell = _grid_manager.get_unit_grid(attacker)
	event.hit_chance = evaluation.hit_chance
	event.roll = _combat_rng.randf() * 100.0
	event.did_hit = AttackActionResult.roll_hits(event.roll, event.hit_chance)
	event.environmental_cover = evaluation.cover_type
	event.shield_applied = evaluation.shield_applied
	event.shield_accuracy_modifier = evaluation.shield_accuracy_modifier
	event.shield_damage_multiplier = evaluation.shield_damage_multiplier
	event.supply_points_before = watcher.stats.current_supply_points
	event.target_hp_before = attacker.stats.current_hp
	watcher.stats.consume_supply_points(OVERWATCH_SUPPLY_COST)
	watcher.tactical_state.clear_overwatch()
	if event.did_hit:
		var requested_damage := maxi(1, roundi(float(ATTACK_DAMAGE) * evaluation.shield_damage_multiplier))
		attacker.defer_stat_presentation = true
		attacker.stats.take_damage(requested_damage)
		attacker.defer_stat_presentation = false
	event.supply_points_after = watcher.stats.current_supply_points
	event.target_hp_after = attacker.stats.current_hp
	event.damage = event.target_hp_before - event.target_hp_after
	event.target_defeated = attacker.stats.is_defeated
	result.reaction_events.append(event)

func _watcher_can_react(watcher: TacticalUnit, mover: TacticalUnit) -> bool:
	return is_instance_valid(watcher) and watcher != mover and watcher.stats and not watcher.stats.is_defeated \
		and watcher.tactical_state and watcher.tactical_state.is_overwatching \
		and watcher.stats.has_supply_points(OVERWATCH_SUPPLY_COST) \
		and FactionRules.are_hostile(watcher.faction, mover.faction)

func _code_for_reason(reason: String) -> StringName:
	match reason:
		"Cannot shoot while carrying": return &"actor_carrying"
		"Unit defeated": return &"unit_defeated"
		"Not hostile": return &"target_not_hostile"
		"Out of range": return &"out_of_range"
		"Blocked": return &"blocked_los"
		"Invalid target": return &"target_missing"
		_: return &"illegal_attack"

func _reject(validation: ActionValidationResult) -> void:
	last_rejection = validation
	action_rejected.emit(validation)

func _capture_objectives() -> Dictionary:
	var snapshot := {}
	if not _objective_manager or not _objective_manager.mission:
		return snapshot
	for state: MissionObjectiveState in _objective_manager.get_objectives():
		snapshot[String(state.definition.objective_id)] = {
			"status": int(state.status),
			"progress": state.progress,
		}
	return snapshot
