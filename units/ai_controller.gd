extends Node
class_name AIController

const MissionIntentData = preload("res://systems/objectives/mission_intent.gd")

@export var unit: TacticalUnit
@export var turn_manager: TurnManager
@export var battle_controller: BattleController
## Supplied by the owning battle; null means a battle without objectives.
@export var objective_manager: ObjectiveManager

var _is_executing: bool = false
var _last_move_destination := Vector3i.ZERO
var _recent_move_origins: Array[Vector3i] = []
var _objective_manager: ObjectiveManager
var _squad_context: SquadContext
var _squad_notes: Array[String] = []
var _pending_target_note := ""
var _pending_target_scores := "None"
var _policy: AIDifficultyPolicy
var _decision_rng := RandomNumberGenerator.new()
var _last_position_scores := "None"
var _last_position_candidates: Array[Dictionary] = []
var _last_target_candidates: Array[Dictionary] = []
var current_mission_intent := MissionIntentData.new()

enum MissionStepResult {
	NONE,
	MOVED,
	INTERACTED,
	EXTRACTED,
}

func _ready() -> void:
	if not _validate_dependencies():
		return
	turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	battle_controller.debug_enemy_control_changed.connect(_on_debug_enemy_control_changed)
	battle_controller.debug_player_ai_changed.connect(_on_debug_player_ai_changed)
	unit.defeated.connect(_on_unit_defeated)
	_objective_manager = objective_manager
	_policy = AIDifficultyPolicy.create(battle_controller.ai_difficulty)
	_decision_rng.seed = battle_controller.ai_decision_seed * 1000003 + String(unit.name).hash()

func _validate_dependencies() -> bool:
	var valid := true
	if not unit:
		push_error("AIController on '%s' is missing its 'unit' target reference!" % get_path())
		valid = false
	if not turn_manager:
		push_error("AIController on '%s' is missing its 'turn_manager' reference!" % get_path())
		valid = false
	if not battle_controller:
		push_error("AIController on '%s' is missing its 'battle_controller' reference!" % get_path())
		valid = false
	return valid

func _on_active_unit_changed(new_active_unit: TacticalUnit) -> void:
	if new_active_unit != unit:
		return

	if not _should_control_unit():
		return
	current_mission_intent = _objective_manager.get_mission_intent(unit) if _objective_manager else MissionIntentData.new()
	_squad_context = battle_controller.get_squad_context(unit)
	_squad_context.begin_unit(unit)
	_squad_notes.clear()
	_last_position_scores = "None"
	_last_position_candidates.clear()
	_last_target_candidates.clear()
	if current_mission_intent.is_actionable():
		var existing_handlers := _squad_context.reserve_objective(unit, current_mission_intent.objective_id)
		_squad_notes.append("Objective handler: first" if existing_handlers == 0 else "Objective already handled by %d ally: spread/support" % existing_handlers)
	print_rich("[color=medium_purple][AI Goal][/color] %s — %s: %s" % [unit.name, current_mission_intent.get_debug_label(), current_mission_intent.reason])

	print_rich("[color=magenta][AI][/color] Activated unit: [b]%s[/b]" % unit.name)
	_execute_turn()

func _execute_turn() -> void:
	if _is_executing:
		return
	_is_executing = true
	# Brief pause makes the enemy activation visible before it acts.
	await get_tree().create_timer(0.6).timeout
	if not _should_control_unit():
		_is_executing = false
		return
	if unit.mission_actor and unit.mission_actor.is_vip():
		await _execute_vip_turn()
		_is_executing = false
		return
	var has_moved := false
	current_mission_intent = _objective_manager.get_mission_intent(unit) if _objective_manager else MissionIntentData.new()
	if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _objective_manager.can_extract(unit):
		if await _try_mission_step(false) == MissionStepResult.EXTRACTED:
			_is_executing = false
			return
	while is_instance_valid(unit) and unit.stats.current_ap > 0 \
		and turn_manager.battle_result == TurnManager.BattleResult.ONGOING \
		and _should_control_unit():
		current_mission_intent = _objective_manager.get_mission_intent(unit) if _objective_manager else MissionIntentData.new()
		var mission_step := await _try_mission_step(has_moved)
		if mission_step == MissionStepResult.EXTRACTED:
			_is_executing = false
			return
		if mission_step == MissionStepResult.MOVED:
			has_moved = true
			continue
		if mission_step == MissionStepResult.INTERACTED:
			continue
		if unit.is_carrying_unit():
			# Never chase hostiles when the casualty cannot reach an exit this AP.
			await battle_controller.try_defend(unit)
			break
		var attack_target = _find_attack_target()
		if attack_target and await battle_controller.try_attack(unit, attack_target):
			# A cinematic kill can keep this coroutine suspended until the defeated
			# target has finished its presentation and left the tree.
			if is_instance_valid(attack_target):
				_squad_context.reserve_target(unit, attack_target)
			if not _pending_target_note.is_empty(): _squad_notes.append(_pending_target_note)
			_record_ai_decision("Attack", attack_target.name if is_instance_valid(attack_target) else "defeated target", "Legal shot; target score balances vulnerability with allied focus.", "Move, Defend")
			await get_tree().create_timer(0.25).timeout
			continue
		if current_mission_intent.kind in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT]:
			await battle_controller.try_defend(unit)
			_record_ai_decision("Defend", unit.name, "Hold the objective route when no useful advance or supporting shot is available; do not chase enemies.", "Move, Attack")
			break
		var movement_target = _find_nearest_hostile()
		var protected_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
		if protected_carrier and protected_carrier != unit:
			await battle_controller.try_defend(unit)
			_record_ai_decision("Defend", protected_carrier.name, "Hold escort position rather than abandon the carrier to chase enemies.", "Move, Extract")
			break
		if not has_moved and movement_target and await _move_toward(movement_target):
			has_moved = true
			_record_ai_decision("Move", str(_last_move_destination), "No legal shot; approached the nearest hostile unit.", "Attack, Defend")
			continue
		if has_moved and await _try_safe_second_advance(movement_target):
			_record_ai_decision("Move", str(_last_move_destination), "No legal shot; spent remaining AP advancing to a safe tile.", "Attack, Defend")
			continue
		if await battle_controller.try_defend(unit):
			var reason := "No legal shot or safe second advance." if has_moved else "No legal shot or reachable approach."
			_record_ai_decision("Defend", unit.name, reason, "Attack, Move")
		break

	var should_advance := _should_control_unit()
	# Queue changes emit active_unit_changed synchronously. Clear this guard first
	# so a partially spent automated player can be selected again immediately.
	_is_executing = false
	if should_advance:
		if turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN:
			turn_manager.advance_automated_player(unit)
		else:
			turn_manager.end_current_turn()

func _try_mission_step(has_moved: bool) -> MissionStepResult:
	if not current_mission_intent.is_actionable():
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.RESCUE:
		var rescue_target := _objective_manager.find_mission_actor(current_mission_intent.target_ids)
		if rescue_target and _objective_manager.can_rescue(unit, rescue_target):
			_record_ai_decision("Rescue", rescue_target.name, "Rescue target is adjacent.", "Attack, Move, Defend")
			if await _objective_manager.try_rescue(unit, rescue_target):
				return MissionStepResult.INTERACTED
		if not has_moved and rescue_target and await _move_toward(rescue_target):
			_record_ai_decision("Move", str(_last_move_destination), "Approached the rescue target.", "Attack, Defend")
			return MissionStepResult.MOVED
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.PROTECT:
		var protected_actor := _objective_manager.find_mission_actor(current_mission_intent.target_ids)
		if not has_moved and protected_actor and _grid_distance_to(protected_actor) > 3 and await _move_toward_range(protected_actor, 3):
			_record_ai_decision("Move", str(_last_move_destination), "Returned to the protected actor's escort radius.", "Attack, Defend")
			return MissionStepResult.MOVED
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.SURVIVE:
		if not has_moved:
			var survival_position := _best_survival_position()
			if survival_position.x >= 0 and await _move_toward_cell(survival_position):
				_record_ai_decision("Move", str(_last_move_destination), "Improved cover and separation while the survival timer is active.", "Attack, Defend")
				return MissionStepResult.MOVED
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _objective_manager.can_extract(unit):
		var carrier := _objective_manager.find_rescue_carrier(unit.faction)
		if carrier and carrier != unit:
			if await _clear_carrier_route(carrier): return MissionStepResult.MOVED
			return MissionStepResult.NONE
		_record_ai_decision("Extract", current_mission_intent.zone_id, "Unit reached its mission extraction zone.", "Attack, Move, Defend")
		if await _objective_manager.try_extract(unit):
			await get_tree().process_frame
			if turn_manager.battle_result == TurnManager.BattleResult.ONGOING and turn_manager.active_unit == null:
				turn_manager.end_current_turn()
			return MissionStepResult.EXTRACTED
	if current_mission_intent.kind not in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT]:
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT:
		var rescue_carrier := _objective_manager.find_rescue_carrier(unit.faction)
		if rescue_carrier and rescue_carrier != unit:
			if has_moved: return MissionStepResult.NONE
			if await _clear_carrier_route(rescue_carrier): return MissionStepResult.MOVED
			if _grid_distance_to(rescue_carrier) > 2 and await _move_toward_range(rescue_carrier, 2):
				_squad_notes.append("Mobile objective support: +30")
				_record_ai_decision("Support", rescue_carrier.name, "Escorted the teammate carrying the rescued VIP.", "Attack, Extract, Defend")
				return MissionStepResult.MOVED
			return MissionStepResult.NONE

	var destination := _nearest_reachable_zone_cell(current_mission_intent.zone_id)
	if destination.x < 0:
		return MissionStepResult.NONE
	if await _move_toward_cell(destination, has_moved):
		_record_ai_decision("Move", str(_last_move_destination), current_mission_intent.reason, "Attack, Defend")
		if is_instance_valid(unit) and current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _objective_manager.can_extract(unit):
			_record_ai_decision("Extract", current_mission_intent.zone_id, "Unit reached its mission extraction zone.", "Attack, Defend")
			if await _objective_manager.try_extract(unit):
				await get_tree().process_frame
				if turn_manager.battle_result == TurnManager.BattleResult.ONGOING and turn_manager.active_unit == null:
					turn_manager.end_current_turn()
				return MissionStepResult.EXTRACTED
		if current_mission_intent.kind == MissionIntentData.Kind.REACH:
			# Objective outcomes are deferred so movement signals finish cleanly.
			await get_tree().process_frame
		return MissionStepResult.MOVED
	return MissionStepResult.NONE

func _carrier_route(carrier: TacticalUnit) -> Dictionary:
	var reserved := {}
	var best := PackedVector3Array()
	for destination in battle_controller.grid_manager.map_data.get_objective_zone(&"extract"):
		var path := battle_controller.pathfinder.calculate_3d_path(carrier.grid_position, destination)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
	for point in best:
		reserved[battle_controller.world_to_grid(point)] = true
	return reserved

func _clear_carrier_route(carrier: TacticalUnit) -> bool:
	var route := _carrier_route(carrier)
	if not route.has(unit.grid_position): return false
	for candidate in battle_controller.pathfinder.get_reachable_cells(unit.grid_position, unit.stats.speed):
		if not route.has(candidate) and candidate.distance_to(carrier.grid_position) <= 3.0 and battle_controller.grid_manager.can_unit_occupy_cell(unit, candidate):
			if await battle_controller.try_move(unit, candidate):
				_record_ai_decision("Support", carrier.name, "Cleared the carrier's evacuation route.", "Attack, Defend")
				return true
	return false

func _on_debug_enemy_control_changed(enabled: bool) -> void:
	if not enabled and turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN \
		and turn_manager.active_unit == unit:
		_execute_turn()

func _on_debug_player_ai_changed(enabled: bool) -> void:
	if enabled and turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN \
		and turn_manager.active_unit == unit:
		_execute_turn()

func _should_control_unit() -> bool:
	if battle_controller.replay_mode:
		return false
	if not is_instance_valid(unit) or turn_manager.active_unit != unit:
		return false
	if turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN:
		return unit.faction == TacticalUnit.Faction.PLAYER and battle_controller.debug_player_ai
	if turn_manager.current_phase == TurnManager.TurnPhase.ALLY_TURN:
		return turn_manager.allied_units.has(unit)
	if turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN:
		return unit.faction == TacticalUnit.Faction.ENEMY and not battle_controller.debug_enemy_control
	return false

func _execute_vip_turn() -> void:
	if unit.mission_actor.vip_behavior == MissionActor.VIPBehavior.FOLLOW_ESCORT:
		var escorts := turn_manager.player_units.filter(func(candidate: TacticalUnit): return candidate.mission_actor == null or not candidate.mission_actor.is_vip())
		if not escorts.is_empty():
			await _move_toward(escorts[0])
	if unit.stats.current_ap > 0:
		await battle_controller.try_defend(unit)
	if _should_control_unit():
		turn_manager.end_current_turn()

func _try_safe_second_advance(movement_target: TacticalUnit) -> bool:
	if unit.stats.current_ap < 1:
		return false
	match current_mission_intent.kind:
		MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT:
			if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT:
				var carrier := _objective_manager.find_rescue_carrier(unit.faction)
				if carrier and carrier != unit:
					return _grid_distance_to(carrier) > 2 and await _move_toward_range(carrier, 2, true)
			var destination := _nearest_reachable_zone_cell(current_mission_intent.zone_id)
			return destination.x >= 0 and await _move_toward_cell(destination, true)
		MissionIntentData.Kind.RESCUE:
			var rescue_target := _objective_manager.find_mission_actor(current_mission_intent.target_ids)
			return rescue_target != null and await _move_toward(rescue_target, true)
		MissionIntentData.Kind.ELIMINATE, MissionIntentData.Kind.NONE:
			return movement_target != null and await _move_toward(movement_target, true)
	return false

func _is_safe_advance_cell(candidate: Vector3i) -> bool:
	var current := battle_controller.grid_manager.get_unit_grid(unit)
	return _policy.permits_advance(_advance_exposure(current), _advance_exposure(candidate))

func _advance_exposure(candidate: Vector3i) -> float:
	var grid := battle_controller.grid_manager
	var destination := grid.grid_to_world(candidate)
	var exposure := 0.0
	for hostile in _get_hostile_units():
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var hostile_cell := grid.get_unit_grid(hostile)
		var distance := CombatRules.attack_distance(hostile_cell, candidate, grid)
		if distance <= hostile.attack_range and CombatRules.has_line_of_sight_to_position(hostile, destination, grid, unit.get_world_3d()):
			match CombatRules.get_directional_cover(hostile_cell, candidate, grid):
				MapCellData.CoverType.FULL:
					exposure += 0.35
				MapCellData.CoverType.LOW:
					exposure += 0.65
				_:
					exposure += 1.0
			if distance <= 2:
				exposure += 0.5
	return exposure

func _move_toward(target: TacticalUnit, safe_only := false) -> bool:
	return await _move_toward_range(target, 1, safe_only)

func _move_toward_range(target: TacticalUnit, desired_distance: int, safe_only := false) -> bool:
	var start_cell = battle_controller.grid_manager.get_unit_grid(unit)
	var target_cell = battle_controller.grid_manager.get_unit_grid(target)
	var path = battle_controller.pathfinder.calculate_3d_path(start_cell, target_cell)
	if path.size() <= 1:
		return false

	# Leave the requested path distance between the mover and an occupied target.
	for step in mini(desired_distance, path.size() - 1):
		path.remove_at(path.size() - 1)
	if path.size() <= 1:
		return false
	return await _move_along_goal_path(path, start_cell, target_cell, safe_only)

func _grid_distance_to(target: TacticalUnit) -> int:
	var from := battle_controller.grid_manager.get_unit_grid(unit)
	var to := battle_controller.grid_manager.get_unit_grid(target)
	return absi(from.x - to.x) + absi(from.y - to.y) + absi(from.z - to.z)

func _move_toward_cell(target_cell: Vector3i, safe_only := false) -> bool:
	var start_cell := battle_controller.grid_manager.get_unit_grid(unit)
	var path := battle_controller.pathfinder.calculate_3d_path(start_cell, target_cell)
	if path.size() <= 1: return false
	return await _move_along_goal_path(path, start_cell, target_cell, safe_only)

func _move_along_goal_path(path: PackedVector3Array, start_cell: Vector3i, goal_cell: Vector3i, safe_only: bool) -> bool:
	var reachable := battle_controller.pathfinder.get_reachable_cells(start_cell, unit.stats.speed)
	var best_candidate := Vector3i(-1, -1, -1)
	var best_adjustment := 0.0
	var best_score := -INF
	var best_summary := "None"
	var options: Array[Dictionary] = []
	var hostiles := _get_hostile_units()
	var carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	var escort_route := _carrier_route(carrier) if carrier and carrier != unit else {}
	var objective_route := current_mission_intent.kind in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT, MissionIntentData.Kind.RESCUE]
	var route_end := battle_controller.world_to_grid(path[path.size() - 1])
	var initial_cost := _route_cost(path)
	var hold := AIPositionScorer.evaluate(unit, start_cell, start_cell, goal_cell, 0.0, objective_route, hostiles, battle_controller.grid_manager, _policy, null)
	best_score = hold.total + 1.0
	_last_position_candidates.clear()
	for candidate in reachable:
		if candidate == start_cell: continue
		if escort_route.has(candidate): continue
		if not battle_controller.grid_manager.can_unit_occupy_cell(unit, candidate):
			var occupant := battle_controller.grid_manager.get_unit_at(candidate)
			_last_position_candidates.append({"cell": candidate, "status": "rejected", "reason": "Occupied by %s" % occupant.name if is_instance_valid(occupant) else "Illegal stopping cell"})
			continue
		if safe_only and not _is_safe_advance_cell(candidate):
			_last_position_candidates.append({"cell": candidate, "status": "rejected", "reason": "Unsafe second advance"})
			continue
		var route_index := -1
		var route_distance := INF
		for index in range(1, path.size()):
			var route_cell := battle_controller.world_to_grid(path[index])
			var distance := candidate.distance_to(route_cell)
			if distance <= 2.0 and (distance < route_distance or (is_equal_approx(distance, route_distance) and index > route_index)):
				route_distance = distance
				route_index = index
		if route_index < 0:
			_last_position_candidates.append({"cell": candidate, "status": "rejected", "reason": "Outside useful route"})
			continue
		var remaining := battle_controller.pathfinder.calculate_3d_path(candidate, route_end)
		if remaining.is_empty(): continue
		var progress := initial_cost - _route_cost(remaining)
		var scored := AIPositionScorer.evaluate(unit, candidate, start_cell, goal_cell, progress, objective_route, hostiles, battle_controller.grid_manager, _policy, _squad_context)
		var revisit_penalty := 0.0
		for index in _recent_move_origins.size():
			if _recent_move_origins[index] == candidate:
				revisit_penalty += 6.0 * (index + 1)
		scored.total -= revisit_penalty
		scored.summary += "; revisit %+.0f" % -revisit_penalty
		var score: float = scored.total
		var candidate_record := {"cell": candidate, "score": score, "status": "considered", "summary": scored.summary}
		for component in ["progress", "cover", "exposure", "firing", "danger", "squad"]:
			if scored.has(component):
				candidate_record[component] = scored[component]
		if score > hold.total + 1.0:
			options.append({"cell": candidate, "score": score, "scored": scored})
		else:
			candidate_record.status = "rejected"
			candidate_record.reason = scored.summary
		_last_position_candidates.append(candidate_record)
		if score > best_score:
			best_candidate = candidate
			best_adjustment = _squad_context.destination_adjustment(unit, candidate) if _squad_context else 0.0
			best_score = score
			best_summary = scored.summary
	if options.size() > 1 and best_candidate != goal_cell and not unit.is_carrying_unit():
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
		var scores: Array[float] = [options[0].score]
		var eligible: Array[Dictionary] = [options[0]]
		var top: Dictionary = options[0].scored
		for option in options.slice(1):
			var detail: Dictionary = option.scored
			if detail.progress >= top.progress - 8.0 and detail.exposure >= top.exposure - 4.0 and detail.danger >= top.danger - 3.0:
				eligible.append(option)
				scores.append(option.score)
		var choice := _policy.choose_near_best_index(scores, _decision_rng)
		if choice > 0:
			var selected := eligible[choice]
			best_candidate = selected.cell
			best_adjustment = _squad_context.destination_adjustment(unit, best_candidate) if _squad_context else 0.0
			best_summary = "%s; %s lapse: near-best tile %.1f vs %.1f" % [selected.scored.summary, AIDifficultyPolicy.get_label(_policy.tier), selected.score, scores[0]]
	for candidate_record in _last_position_candidates:
		candidate_record["chosen"] = candidate_record.get("cell", Vector3i(-1, -1, -1)) == best_candidate
	if best_candidate.x >= 0 and await battle_controller.try_move(unit, best_candidate):
		_recent_move_origins.append(start_cell)
		if _recent_move_origins.size() > 4: _recent_move_origins.pop_front()
		_last_move_destination = best_candidate
		_last_position_scores = best_summary
		_reserve_destination(best_candidate, best_adjustment)
		return true
	return false

func _route_cost(path: PackedVector3Array) -> float:
	var cost := 0.0
	for index in range(1, path.size()):
		cost += battle_controller.pathfinder.get_step_cost(battle_controller.world_to_grid(path[index - 1]), battle_controller.world_to_grid(path[index]))
	return cost

func _nearest_reachable_zone_cell(zone_id: StringName) -> Vector3i:
	var grid := battle_controller.grid_manager
	var start := grid.get_unit_grid(unit)
	var best := Vector3i(-1, -1, -1)
	var best_cost := INF
	for cell in grid.map_data.get_objective_zone(zone_id):
		if cell != start and not grid.can_unit_occupy_cell(unit, cell):
			continue
		var path := battle_controller.pathfinder.calculate_3d_path(start, cell)
		if cell == start:
			return cell
		var squad_adjustment := _squad_context.destination_adjustment(unit, cell) if _squad_context else 0.0
		var cost := path.size() - squad_adjustment
		if not path.is_empty() and cost < best_cost:
			best_cost = cost
			best = cell
	return best

func _best_survival_position() -> Vector3i:
	var grid := battle_controller.grid_manager
	var start := grid.get_unit_grid(unit)
	var best := start
	var best_score := _survival_position_score(start, start)
	for candidate in battle_controller.pathfinder.get_reachable_cells(start, unit.stats.speed):
		if candidate != start and not grid.can_unit_occupy_cell(unit, candidate):
			continue
		var score := _survival_position_score(candidate, start)
		if score > best_score:
			best_score = score
			best = candidate
	return best if best != start else Vector3i(-1, -1, -1)

func _survival_position_score(candidate: Vector3i, start: Vector3i) -> float:
	var grid := battle_controller.grid_manager
	var scored := AIPositionScorer.evaluate(unit, candidate, start, Vector3i(-1, -1, -1), 0, false, _get_hostile_units(), grid, _policy, _squad_context)
	var score: float = scored.total - 0.15 * start.distance_to(candidate)
	var nearest_hostile := INF
	for hostile in _get_hostile_units():
		if not is_instance_valid(hostile):
			continue
		var hostile_cell := grid.get_unit_grid(hostile)
		nearest_hostile = minf(nearest_hostile, candidate.distance_to(hostile_cell))
	if nearest_hostile < INF:
		score += minf(nearest_hostile, 12.0) * 1.5 * _policy.survival_separation_weight
	var extraction := grid.map_data.get_objective_zone(&"extract")
	if not extraction.is_empty():
		var nearest_exit := INF
		for exit_cell in extraction:
			nearest_exit = minf(nearest_exit, candidate.distance_to(exit_cell))
		score -= nearest_exit * 0.2
	return score

func _find_attack_target() -> TacticalUnit:
	var best_target: TacticalUnit
	var best_score := -INF
	var options: Array[Dictionary] = []
	_pending_target_note = ""
	_pending_target_scores = "None"
	_last_target_candidates.clear()
	var friendlies := _get_friendly_units()
	var targets := _get_hostile_units()
	var carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	if carrier and carrier != unit:
		var threats: Array[TacticalUnit] = []
		for hostile in targets:
			if battle_controller.evaluate_attack(unit, hostile).is_legal and battle_controller.evaluate_attack(hostile, carrier).is_legal:
				threats.append(hostile)
		if not threats.is_empty(): targets = threats
	for candidate in targets:
		if not is_instance_valid(candidate) or not candidate.stats or candidate.stats.is_defeated:
			continue
		var attack_evaluation := battle_controller.evaluate_attack(unit, candidate)
		if attack_evaluation.is_legal:
			var scored := AITargetScorer.evaluate(unit, candidate, friendlies, current_mission_intent, _objective_manager, battle_controller.grid_manager, _policy, _squad_context)
			var score: float = scored.total
			var target_record := {"target": String(candidate.name), "cell": candidate.grid_position, "score": score, "status": "considered", "summary": scored.summary, "hit_chance": attack_evaluation.hit_chance}
			for component in ["vulnerability", "focus", "vip", "threat", "mission", "focus_count"]:
				target_record[component] = scored[component]
			_last_target_candidates.append(target_record)
			options.append({"target": candidate, "score": score, "scored": scored})
			if score > best_score:
				best_target = candidate
				best_score = score
				_pending_target_note = "Target focus: %+.0f (%d allies engaged)" % [scored.focus, scored.focus_count]
				_pending_target_scores = scored.summary
		else:
			_last_target_candidates.append({"target": String(candidate.name), "cell": candidate.grid_position, "status": "rejected", "reason": attack_evaluation.reason})
	if options.size() > 1:
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
		var scores: Array[float] = [options[0].score]
		var eligible: Array[Dictionary] = [options[0]]
		var top: Dictionary = options[0].scored
		for option in options.slice(1):
			if option.scored.mission >= top.mission - 8.0:
				eligible.append(option)
				scores.append(option.score)
		var choice := _policy.choose_near_best_index(scores, _decision_rng)
		if choice > 0:
			var selected := eligible[choice]
			best_target = selected.target
			_pending_target_note = "Target focus: %+.0f (%d allies engaged)" % [selected.scored.focus, selected.scored.focus_count]
			_pending_target_scores = "%s; %s lapse: near-best target %.1f vs %.1f" % [selected.scored.summary, AIDifficultyPolicy.get_label(_policy.tier), selected.score, scores[0]]
	for target_record in _last_target_candidates:
		target_record["chosen"] = is_instance_valid(best_target) and target_record.get("target", "") == String(best_target.name)
	return best_target

func _reserve_destination(cell: Vector3i, adjustment: float) -> void:
	if not _squad_context:
		return
	_squad_context.reserve_destination(unit, cell)
	if adjustment < 0.0:
		_squad_notes.append("Nearby destination reservation: %+.0f" % adjustment)
	else:
		_squad_notes.append("Destination reserved for later allies")

func _record_ai_decision(action: String, subject: String, reason: String, alternatives: String) -> void:
	var notes := "None" if _squad_notes.is_empty() else "; ".join(_squad_notes)
	battle_controller.record_ai_decision(unit, action, subject, reason, alternatives, current_mission_intent.get_debug_label(), notes, _last_position_scores, _pending_target_scores if action == "Attack" else "None", _last_position_candidates, _last_target_candidates)

func _get_friendly_units() -> Array[TacticalUnit]:
	var friendlies: Array[TacticalUnit] = []
	for candidate in turn_manager.player_units + turn_manager.allied_units + turn_manager.enemy_units:
		if is_instance_valid(candidate) and candidate.faction != TacticalUnit.Faction.NEUTRAL and not FactionRules.are_hostile(unit.faction, candidate.faction):
			friendlies.append(candidate)
	return friendlies

func _find_nearest_hostile() -> TacticalUnit:
	var nearest: TacticalUnit
	var nearest_distance := INF
	for candidate in _get_hostile_units():
		if not is_instance_valid(candidate) or not candidate.stats or candidate.stats.is_defeated:
			continue
		var distance = unit.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest

func _get_hostile_units() -> Array[TacticalUnit]:
	var hostile_units: Array[TacticalUnit] = []
	for candidate in turn_manager.player_units + turn_manager.allied_units + turn_manager.enemy_units:
		if is_instance_valid(candidate) and FactionRules.are_hostile(unit.faction, candidate.faction):
			hostile_units.append(candidate)
	return hostile_units

func _on_unit_defeated(_defeated_unit: TacticalUnit) -> void:
	queue_free()
