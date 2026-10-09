class_name TacticalActionService
extends Node

signal action_committed(result)
signal action_presented(result)
signal action_rejected(validation: ActionValidationResult)

const ATTACK_AP_COST := 1
const ATTACK_DAMAGE := 25

var actor_registry := TacticalActorRegistry.new()
var state_revision := 0
var last_transaction_id := 0
var last_rejection: ActionValidationResult
var last_result: AttackActionResult
var is_busy := false
var is_committing := false

var _turn_manager: TurnManager
var _grid_manager: GridManager
var _objective_manager: ObjectiveManager
var _combat_rng := RandomNumberGenerator.new()
var _present_attack: Callable
var _query_move: Callable
var _present_move: Callable
var _movement_committed: Callable
var _present_simple: Callable

func setup(
	turn_manager: TurnManager,
	grid_manager: GridManager,
	objective_manager: ObjectiveManager,
	combat_seed: int,
	present_attack: Callable,
	query_move: Callable = Callable(),
	present_move: Callable = Callable(),
	movement_committed: Callable = Callable(),
	present_simple: Callable = Callable()
) -> void:
	_turn_manager = turn_manager
	_grid_manager = grid_manager
	_objective_manager = objective_manager
	_combat_rng.seed = combat_seed
	_present_attack = present_attack
	_query_move = query_move
	_present_move = present_move
	_movement_committed = movement_committed
	_present_simple = present_simple

func register_actor(actor: TacticalUnit) -> bool:
	return actor_registry.register_actor(actor)

func unregister_actor(actor: TacticalUnit) -> void:
	actor_registry.unregister_actor(actor)

func query_attack(actor_id: StringName, target_id: StringName = &"") -> AttackQueryResult:
	var query := AttackQueryResult.new()
	query.actor_id = actor_id
	query.target_id = target_id
	query.state_revision = state_revision
	query.cost = ActionCost.new(ATTACK_AP_COST)
	var actor := actor_registry.resolve(actor_id)
	if target_id.is_empty():
		var actor_check := _validate_actor(actor)
		query.validation = actor_check
		if not actor_check.accepted:
			query.reason = actor_check.message
			return query
		for candidate_id in actor_registry.get_ids():
			if candidate_id == actor_id:
				continue
			var candidate_query := query_attack(actor_id, candidate_id)
			if candidate_query.is_legal():
				query.legal_target_ids.append(candidate_id)
		query.validation = ActionValidationResult.allow(state_revision)
		return query
	var target := actor_registry.resolve(target_id)
	var validation := _validate_attack(actor, target)
	query.validation = validation
	query.reason = validation.message
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return query
	var evaluation := CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d())
	query.evaluation = evaluation
	query.hit_chance = evaluation.hit_chance
	query.cover_type = evaluation.cover_type
	query.reason = evaluation.reason
	query.aim_point = evaluation.aim_point
	query.obstruction = evaluation.obstruction
	return query

func submit_attack(request: TacticalActionRequest, suppress_presentation := false) -> AttackActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	# No await, signal, or random draw occurs before this final validation.
	var actor := actor_registry.resolve(request.actor_id)
	var target := actor_registry.resolve(request.target_id)
	validation = _validate_attack(actor, target)
	if not validation.accepted:
		_reject(validation)
		return null

	is_busy = true
	is_committing = true
	last_transaction_id += 1
	var evaluation := CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d())
	var result := AttackActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.cost = ActionCost.new(ATTACK_AP_COST)
	result.hit_chance = evaluation.hit_chance
	result.roll = _combat_rng.randf() * 100.0
	result.did_hit = AttackActionResult.roll_hits(result.roll, result.hit_chance)
	result.damage = ATTACK_DAMAGE if result.did_hit else 0
	result.actor_ap_before = actor.stats.current_ap
	result.target_hp_before = target.stats.current_hp
	result.battle_result_before = int(_turn_manager.battle_result)
	result.target_position = target.global_position
	result.objective_state_before = _capture_objectives()

	# Commit is deliberately synchronous. Stat signals may update roster/objective
	# owners, but the service remains guarded against nested submissions.
	actor.stats.consume_ap(ATTACK_AP_COST)
	if result.did_hit:
		target.defer_stat_presentation = true
		target.stats.take_damage(ATTACK_DAMAGE)
		target.defer_stat_presentation = false
	if _objective_manager:
		_objective_manager.evaluate_outcome_after_action_commit()
	result.actor_ap_after = actor.stats.current_ap
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
	is_busy = false
	return result

func query_move(actor_id: StringName, target_cell: Vector3i) -> MoveQueryResult:
	var query := MoveQueryResult.new()
	query.actor_id = actor_id
	query.target_cell = target_cell
	query.state_revision = state_revision
	var actor := actor_registry.resolve(actor_id)
	query.validation = _validate_actor(actor)
	if not query.validation.accepted: return query
	query.start_cell = _grid_manager.get_unit_grid(actor)
	if not _query_move.is_valid():
		query.validation = ActionValidationResult.reject(&"service_unavailable", "Movement query is unavailable", state_revision)
		return query
	var data: Dictionary = _query_move.call(actor, target_cell)
	if not data.get("accepted", false):
		query.validation = ActionValidationResult.reject(StringName(data.get("code", "illegal_move")), data.get("message", "Illegal move"), state_revision)
		return query
	query.path = data["path"]
	query.presentation_path = data["presentation_path"]
	query.visual_segments.assign(data["visual_segments"])
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
	is_busy = true
	is_committing = true
	last_transaction_id += 1
	var result := MoveActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.start_cell = query.start_cell
	result.target_cell = query.target_cell
	result.presentation_path = query.presentation_path
	result.visual_segments = query.visual_segments
	result.actor_ap_before = actor.stats.current_ap
	actor.stats.consume_ap(result.cost.ap)
	_grid_manager.update_unit_position(actor, result.start_cell, result.target_cell)
	result.actor_ap_after = actor.stats.current_ap
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	if _movement_committed.is_valid(): _movement_committed.call(actor, result.start_cell, result.target_cell)
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_move.is_valid(): await _present_move.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	is_busy = false
	return result

func make_attack_request(actor: TacticalUnit, target: TacticalUnit, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.attack(
		actor.tactical_id if is_instance_valid(actor) else &"",
		target.tactical_id if is_instance_valid(target) else &"",
		state_revision,
		source
	)

func make_move_request(actor: TacticalUnit, target_cell: Vector3i, source: TacticalActionRequest.Source) -> TacticalActionRequest:
	return TacticalActionRequest.move(actor.tactical_id if is_instance_valid(actor) else &"", target_cell, state_revision, source)

func make_simple_request(kind: StringName, actor: TacticalUnit, source: TacticalActionRequest.Source, details: Dictionary = {}) -> TacticalActionRequest:
	return TacticalActionRequest.simple(kind, actor.tactical_id if is_instance_valid(actor) else &"", state_revision, source, details)

func submit_simple(request: TacticalActionRequest, suppress_presentation := false) -> SimpleActionResult:
	var validation := _validate_request(request)
	if not validation.accepted:
		_reject(validation)
		return null
	if request.kind not in [&"wait", &"defend"]:
		validation = ActionValidationResult.reject(&"unsupported_action", "Expected Wait or Defend", state_revision)
		_reject(validation)
		return null
	var actor := actor_registry.resolve(request.actor_id)
	validation = _validate_actor(actor)
	if not validation.accepted:
		_reject(validation)
		return null
	is_busy = true
	is_committing = true
	last_transaction_id += 1
	var result := SimpleActionResult.new()
	result.transaction_id = last_transaction_id
	result.base_revision = state_revision
	result.request = request
	result.actor_ap_before = actor.stats.current_ap
	result.defending_before = actor.stats.is_defending
	if request.kind == &"wait": actor.stats.current_ap = 0
	else:
		actor.stats.consume_ap(ATTACK_AP_COST)
		actor.stats.is_defending = true
	result.actor_ap_after = actor.stats.current_ap
	result.defending_after = actor.stats.is_defending
	state_revision += 1
	result.committed_revision = state_revision
	is_committing = false
	action_committed.emit(result)
	result.presentation_suppressed = suppress_presentation
	if _present_simple.is_valid(): await _present_simple.call(result)
	result.presentation_completed = true
	action_presented.emit(result)
	is_busy = false
	return result

func get_combat_rng_state() -> int:
	return _combat_rng.state

func _validate_request(request: TacticalActionRequest) -> ActionValidationResult:
	if request == null or request.kind not in [&"attack", &"move", &"wait", &"defend"]:
		return ActionValidationResult.reject(&"unsupported_action", "Action service received an unsupported request", state_revision)
	if get_tree().paused:
		return ActionValidationResult.reject(&"paused", "Battle is paused", state_revision)
	if is_busy or is_committing:
		return ActionValidationResult.reject(&"action_busy", "Another action is already being resolved or presented", state_revision)
	if request.expected_revision != state_revision:
		return ActionValidationResult.reject(&"stale_revision", "Action preview is stale", state_revision)
	return ActionValidationResult.allow(state_revision)

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

func _validate_attack(actor: TacticalUnit, target: TacticalUnit) -> ActionValidationResult:
	var actor_result := _validate_actor(actor)
	if not actor_result.accepted:
		return actor_result
	if not is_instance_valid(target) or not target.stats:
		return ActionValidationResult.reject(&"target_missing", "Target is unavailable", state_revision)
	var evaluation := CombatRules.evaluate_attack(actor, target, _grid_manager, actor.get_world_3d())
	if evaluation.is_legal:
		return ActionValidationResult.allow(state_revision)
	return ActionValidationResult.reject(_code_for_reason(evaluation.reason), evaluation.reason, state_revision)

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
