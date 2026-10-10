extends Node
class_name AIController

## Repeated low-value turns gradually loosen movement conservatism so a battle
## cannot remain in a passive wait loop. These limits deliberately preserve
## caution for carriers, VIPs, and critically injured units.
const URGENCY_START_ACTIONS := 3
const URGENCY_PER_ACTION := 3.0
const URGENCY_MAX_SCORE := 18.0
const ROUTE_CORRIDOR_BASE := 2.0
const ROUTE_CORRIDOR_MAX_BONUS := 2.0

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
var _committed_carrier_route: Array[Vector3i] = []
var _last_hold_score := NAN
var _last_move_threshold := NAN
var _last_urgency_bonus := 0.0
var _last_route_corridor := ROUTE_CORRIDOR_BASE
var _consecutive_low_value_actions := 0
var _movement_preview_pending_completion := false
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
	current_mission_intent = _get_ai_mission_intent()
	_squad_context = battle_controller.get_squad_context(unit)
	_squad_context.begin_unit(unit)
	var active_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	if active_carrier:
		_squad_context.reserve_corridor(active_carrier, _carrier_route(active_carrier))
	_squad_notes.clear()
	_last_position_scores = "None"
	_last_position_candidates.clear()
	_last_target_candidates.clear()
	_last_hold_score = NAN
	_last_move_threshold = NAN
	_last_urgency_bonus = 0.0
	_last_route_corridor = ROUTE_CORRIDOR_BASE
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
	await get_tree().create_timer(0.6, false).timeout
	if not _should_control_unit():
		_is_executing = false
		return
	if unit.mission_actor and unit.mission_actor.is_vip():
		await _execute_vip_turn()
		_is_executing = false
		return
	var has_moved := false
	current_mission_intent = _get_ai_mission_intent()
	if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _can_use_mission_action(&"extract", unit):
		if await _try_mission_step(false) == MissionStepResult.EXTRACTED:
			_is_executing = false
			return
	while is_instance_valid(unit) and unit.stats.current_ap > 0 \
		and turn_manager.battle_result == TurnManager.BattleResult.ONGOING \
		and _should_control_unit():
		current_mission_intent = _get_ai_mission_intent()
		var escorted_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
		# An escort already clear of the evacuation lane may engage immediate
		# threats before repositioning. A blocker clears the lane first.
		if escorted_carrier and escorted_carrier != unit and not _carrier_route(escorted_carrier).has(unit.grid_position):
			var escort_target := _find_attack_target()
			if escort_target and await battle_controller.try_attack(unit, escort_target):
				if is_instance_valid(escort_target):
					_squad_context.reserve_target(unit, escort_target)
				_record_ai_decision("Attack", String(escort_target.name) if is_instance_valid(escort_target) else "defeated target", "Protected the VIP carrier from a legal threat.", "Clear route, Reposition, Wait")
				await get_tree().create_timer(0.25, false).timeout
				continue
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
			_wait_for_next_turn(_movement_wait_reason("Carrier cannot advance toward extraction."), "Move")
			break
		var attack_target = _find_attack_target()
		if attack_target and await _try_aim_for_attack(attack_target):
			_record_ai_decision("Aim", attack_target.name, "Improved a legal shot through the authoritative Aim query.", "Attack, Move, Wait")
			continue
		if attack_target and await battle_controller.try_attack(unit, attack_target):
			# A cinematic kill can keep this coroutine suspended until the defeated
			# target has finished its presentation and left the tree.
			if is_instance_valid(attack_target):
				_squad_context.reserve_target(unit, attack_target)
			if not _pending_target_note.is_empty(): _squad_notes.append(_pending_target_note)
			_record_ai_decision("Attack", attack_target.name if is_instance_valid(attack_target) else "defeated target", "Legal shot; target score balances vulnerability with allied focus.", "Move, Wait")
			await get_tree().create_timer(0.25, false).timeout
			continue
		if await _try_reload_if_useful():
			_record_ai_decision("Reload", "%d/%d SP" % [unit.stats.current_supply_points, unit.stats.max_supply_points], "Restored attack supply through the authoritative Reload query.", "Move, Wait")
			continue
		if current_mission_intent.kind in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT]:
			_wait_for_next_turn(_movement_wait_reason("No useful objective advance or supporting shot."), "Move, Attack")
			break
		var movement_target = _find_nearest_hostile()
		var protected_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
		if protected_carrier and protected_carrier != unit:
			if not has_moved and await _clear_carrier_route(protected_carrier):
				has_moved = true
				continue
			if not has_moved and _grid_distance_to(protected_carrier) > 5 \
			and await _move_toward_range(protected_carrier, 4):
				has_moved = true
				_record_ai_decision("Support", protected_carrier.name, "Closed into escort range while respecting the carrier corridor.", "Attack, Clear route, Wait")
				continue
			if not has_moved and await _move_to_escort_position(protected_carrier):
				has_moved = true
				continue
			_wait_for_next_turn(_movement_wait_reason("No useful escort move or legal shot."), "Move, Extract")
			break
		if not has_moved and movement_target and await _move_toward(movement_target):
			has_moved = true
			_record_ai_decision("Move", str(_last_move_destination), "No legal shot; approached the nearest hostile unit.", "Attack, Wait")
			continue
		if has_moved and await _try_safe_second_advance(movement_target):
			_record_ai_decision("Move", str(_last_move_destination), "No legal shot; spent remaining AP advancing to a safe tile.", "Attack, Wait")
			continue
		var reason := "No legal shot or safe second advance." if has_moved else "No legal shot or reachable approach."
		_wait_for_next_turn(_movement_wait_reason(reason), "Attack, Move")
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
		if rescue_target and _can_use_mission_action(&"rescue", unit, rescue_target):
			_record_ai_decision("Rescue", rescue_target.name, "Rescue target is adjacent.", "Attack, Move, Wait")
			if await _objective_manager.try_rescue(unit, rescue_target):
				return MissionStepResult.INTERACTED
		if not has_moved and rescue_target and await _move_toward(rescue_target):
			_record_ai_decision("Move", str(_last_move_destination), "Approached the rescue target.", "Attack, Wait")
			return MissionStepResult.MOVED
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.PROTECT:
		var protected_actor := _objective_manager.find_mission_actor(current_mission_intent.target_ids)
		if not has_moved and protected_actor and _grid_distance_to(protected_actor) > 3 and await _move_toward_range(protected_actor, 3):
			_record_ai_decision("Move", str(_last_move_destination), "Returned to the protected actor's escort radius.", "Attack, Wait")
			return MissionStepResult.MOVED
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.SURVIVE:
		if not has_moved:
			var survival_position := _best_survival_position()
			if survival_position.x >= 0 and await _move_toward_cell(survival_position):
				_record_ai_decision("Move", str(_last_move_destination), "Improved cover and separation while the survival timer is active.", "Attack, Wait")
				return MissionStepResult.MOVED
		return MissionStepResult.NONE
	if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _can_use_mission_action(&"extract", unit):
		var carrier := _objective_manager.find_rescue_carrier(unit.faction)
		if carrier and carrier != unit:
			if await _clear_carrier_route(carrier): return MissionStepResult.MOVED
			return MissionStepResult.NONE
		_record_ai_decision("Extract", current_mission_intent.zone_id, "Unit reached its mission extraction zone.", "Attack, Move, Wait")
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
				_record_ai_decision("Support", rescue_carrier.name, "Escorted the teammate carrying the rescued VIP.", "Attack, Extract, Wait")
				return MissionStepResult.MOVED
			if await _move_to_escort_position(rescue_carrier):
				return MissionStepResult.MOVED
			return MissionStepResult.NONE

	var destination := _nearest_reachable_zone_cell(current_mission_intent.zone_id)
	if destination.x < 0:
		return MissionStepResult.NONE
	var moved_toward_objective := await _move_carrier_along_committed_route(has_moved) \
		if unit.is_carrying_unit() and current_mission_intent.kind == MissionIntentData.Kind.EXTRACT \
		else await _move_toward_cell(destination, has_moved)
	if moved_toward_objective:
		_record_ai_decision("Move", str(_last_move_destination), current_mission_intent.reason, "Attack, Wait")
		if is_instance_valid(unit) and current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _can_use_mission_action(&"extract", unit):
			_record_ai_decision("Extract", current_mission_intent.zone_id, "Unit reached its mission extraction zone.", "Attack, Wait")
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

func _can_use_mission_action(kind: StringName, actor: TacticalUnit, target: TacticalUnit = null) -> bool:
	if not is_instance_valid(battle_controller):
		return false
	return battle_controller.query_mission(kind, actor, target).is_legal()

func _try_reload_if_useful() -> bool:
	if not is_instance_valid(unit) or not unit.stats:
		return false
	if unit.stats.current_supply_points >= unit.stats.max_supply_points:
		return false
	# Depleted units always restore their attack supply. A unit on its final AP
	# may also top up a nearly empty reserve instead of entering a Wait loop.
	if unit.stats.current_supply_points > 0 and not (unit.stats.current_supply_points <= 1 and unit.stats.current_ap == 1):
		return false
	var query := battle_controller.query_reload(unit)
	return query.is_legal() and await battle_controller.try_reload(unit)

func _try_aim_for_attack(target: TacticalUnit) -> bool:
	if not is_instance_valid(unit) or not is_instance_valid(target) or not unit.stats:
		return false
	var aim_query := battle_controller.query_aim(unit)
	if not aim_query.is_legal():
		return false
	var attack_query := battle_controller.query_attack(unit, target)
	if unit.stats.current_ap < aim_query.cost.ap + attack_query.cost.ap \
	or not attack_query.is_legal() or attack_query.hit_chance >= 100:
		return false
	return await battle_controller.try_aim(unit)

## Policy integration is intentionally deferred to 01.11.7. This adapter keeps
## AI legality and orientation on the same authoritative path as player input.
func _try_shield_against(threat: TacticalUnit) -> bool:
	if not is_instance_valid(unit) or not is_instance_valid(threat):
		return false
	var query := battle_controller.query_shield(unit, threat)
	return query.is_legal() and await battle_controller.try_shield(unit, threat)

func _get_ai_mission_intent() -> MissionIntentData:
	if not _objective_manager:
		return MissionIntentData.new()
	var intent := _objective_manager.get_mission_intent(unit)
	var carrier := _objective_manager.find_rescue_carrier(unit.faction)
	if carrier and carrier != unit and intent.kind == MissionIntentData.Kind.EXTRACT:
		# Boarding remains available to human-controlled escorts, but automated
		# escorts protect the required payload instead of racing it to the exit.
		return MissionIntentData.new()
	return intent

func _carrier_route(carrier: TacticalUnit) -> Dictionary:
	if not is_instance_valid(carrier):
		return {}
	if carrier != unit and _squad_context \
	and _squad_context.corridor_owner == StringName(carrier.name) \
	and not _squad_context.reserved_corridor.is_empty():
		return _squad_context.reserved_corridor.duplicate()
	var carrier_cell := battle_controller.grid_manager.get_unit_grid(carrier)
	if carrier == unit and _committed_carrier_route.has(carrier_cell):
		var reached_index := _committed_carrier_route.find(carrier_cell)
		if reached_index > 0:
			_committed_carrier_route = _committed_carrier_route.slice(reached_index)
		return _route_dictionary(_committed_carrier_route)
	var reserved := {}
	var best := PackedVector3Array()
	for destination in battle_controller.grid_manager.map_data.get_objective_zone(&"extract"):
		var path := battle_controller.pathfinder.calculate_3d_path(carrier_cell, destination)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
	for point in best:
		var route_cell := battle_controller.world_to_grid(point)
		reserved[route_cell] = true
	if carrier == unit:
		_committed_carrier_route.clear()
		for point in best:
			_committed_carrier_route.append(battle_controller.world_to_grid(point))
	return reserved

func _route_dictionary(route: Array[Vector3i]) -> Dictionary:
	var cells := {}
	for route_cell in route:
		cells[route_cell] = true
	return cells

func _move_carrier_along_committed_route(safe_only: bool) -> bool:
	_carrier_route(unit)
	if _committed_carrier_route.size() <= 1:
		return false
	var path := PackedVector3Array()
	for route_cell in _committed_carrier_route:
		var cell := battle_controller.grid_manager.get_cell_data(route_cell)
		if not cell:
			_committed_carrier_route.clear()
			return false
		path.append(cell.world_position)
	return await _move_along_goal_path(
		path,
		battle_controller.grid_manager.get_unit_grid(unit),
		_committed_carrier_route[-1],
		safe_only
	)

func _clear_carrier_route(carrier: TacticalUnit) -> bool:
	var route := _carrier_route(carrier)
	var start := battle_controller.grid_manager.get_unit_grid(unit)
	if not route.has(start): return false
	var grid := battle_controller.grid_manager
	var hostiles := _get_hostile_units()
	var best := Vector3i(-1, -1, -1)
	var best_score := -INF
	var fallback := Vector3i(-1, -1, -1)
	var fallback_score := -INF
	var start_carrier_distance := start.distance_to(carrier.grid_position)
	_last_position_candidates.clear()
	for candidate in _legal_move_destinations():
		if candidate == start:
			continue
		var remains_on_route := route.has(candidate)
		# Some stairs and bridges have no side tile within one move. In that case
		# the blocker may continue ahead through the bottleneck, creating room for
		# the carrier behind it. A real off-route clearing position always wins.
		if remains_on_route and candidate.distance_to(carrier.grid_position) <= start_carrier_distance + 0.5:
			continue
		if candidate.distance_to(carrier.grid_position) > 6.0:
			if not remains_on_route:
				continue
		var scored := AIPositionScorer.evaluate(unit, candidate, start, carrier.grid_position, 0.0, false, hostiles, grid, _policy, _squad_context)
		var score: float = scored.total - candidate.distance_to(carrier.grid_position)
		var summary := "%s; %s" % [scored.summary, "bottleneck advance" if remains_on_route else "route clearance"]
		_last_position_candidates.append({"cell": candidate, "score": score, "status": "considered", "summary": summary})
		if remains_on_route and score > fallback_score:
			fallback_score = score
			fallback = candidate
		elif not remains_on_route and score > best_score:
			best_score = score
			best = candidate
	if best.x < 0:
		best = fallback
		best_score = fallback_score
	for candidate_record in _last_position_candidates:
		candidate_record["chosen"] = candidate_record.cell == best
	if best.x < 0:
		return false
	_publish_movement_preview(best, "Carrier route clearance %.1f" % best_score)
	if not await battle_controller.try_move(unit, best):
		_movement_preview_pending_completion = false
		return false
	_movement_preview_pending_completion = false
	_recent_move_origins.append(start)
	if _recent_move_origins.size() > 4: _recent_move_origins.pop_front()
	_last_move_destination = best
	_reserve_destination(best, _squad_context.destination_adjustment(unit, best) if _squad_context else 0.0)
	_record_ai_decision("Support", carrier.name, "Cleared the carrier's reserved evacuation route.", "Attack, Wait")
	return true

func _move_to_escort_position(carrier: TacticalUnit) -> bool:
	var grid := battle_controller.grid_manager
	var start := grid.get_unit_grid(unit)
	var route := _carrier_route(carrier)
	var hostiles := _get_hostile_units()
	var best := Vector3i(-1, -1, -1)
	var best_score := -INF
	_last_position_candidates.clear()
	for candidate in _legal_move_destinations():
		if candidate == start or route.has(candidate):
			continue
		var carrier_distance := candidate.distance_to(carrier.grid_position)
		if carrier_distance < 2.0 or carrier_distance > 5.0:
			continue
		var scored := AIPositionScorer.evaluate(unit, candidate, start, carrier.grid_position, 0.0, false, hostiles, grid, _policy, _squad_context)
		var score: float = scored.total - absf(carrier_distance - 3.0) * 2.0
		var candidate_record := {"cell": candidate, "score": score, "status": "considered", "summary": "%s; escort spacing %+.0f" % [scored.summary, -absf(carrier_distance - 3.0) * 2.0]}
		_last_position_candidates.append(candidate_record)
		if score > best_score:
			best_score = score
			best = candidate
	for candidate_record in _last_position_candidates:
		candidate_record["chosen"] = candidate_record.cell == best
	if best.x < 0:
		return false
	_publish_movement_preview(best, "Escort position %.1f" % best_score)
	if not await battle_controller.try_move(unit, best):
		_movement_preview_pending_completion = false
		return false
	_movement_preview_pending_completion = false
	_recent_move_origins.append(start)
	if _recent_move_origins.size() > 4: _recent_move_origins.pop_front()
	_last_move_destination = best
	_reserve_destination(best, _squad_context.destination_adjustment(unit, best) if _squad_context else 0.0)
	_record_ai_decision("Support", carrier.name, "Spread into a useful escort position while keeping the carrier route clear.", "Attack, Extract, Wait")
	return true

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
			if await _move_toward(escorts[0]):
				_record_ai_decision("Move", str(_last_move_destination), "Followed the nearest available escort.", "Wait")
	if unit.stats.current_ap > 0:
		_wait_for_next_turn("VIP has no useful follow movement.", "Move")
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
	var reachable := _legal_move_destinations()
	var best_candidate := Vector3i(-1, -1, -1)
	var best_adjustment := 0.0
	var best_score := -INF
	var best_summary := "None"
	var best_route_candidate := Vector3i(-1, -1, -1)
	var best_route_score := -INF
	var best_route_summary := "None"
	var options: Array[Dictionary] = []
	var hostiles := _get_hostile_units()
	var carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	var escort_route := _carrier_route(carrier) if carrier and carrier != unit else {}
	var objective_route := current_mission_intent.kind in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT, MissionIntentData.Kind.RESCUE]
	var route_end := battle_controller.world_to_grid(path[path.size() - 1])
	var initial_cost := _route_cost(path)
	var hold := AIPositionScorer.evaluate(unit, start_cell, start_cell, goal_cell, 0.0, objective_route, hostiles, battle_controller.grid_manager, _policy, null)
	_last_urgency_bonus = _get_movement_urgency_bonus()
	_last_route_corridor = ROUTE_CORRIDOR_BASE + minf(ROUTE_CORRIDOR_MAX_BONUS, floorf(float(_consecutive_low_value_actions) / 3.0))
	# Once repeated waits reach maximum urgency, the corridor may no longer veto
	# every pathfinder-valid detour. A second advance still has to pass the
	# exposure check above, so this relaxes route shape without relaxing safety.
	var allow_route_detour := _last_urgency_bonus >= URGENCY_MAX_SCORE
	_last_hold_score = hold.total
	_last_move_threshold = hold.total + 1.0 - _last_urgency_bonus
	best_score = -INF if unit.is_carrying_unit() else _last_move_threshold
	_last_position_candidates.clear()
	for candidate in reachable:
		if candidate == start_cell: continue
		if escort_route.has(candidate): continue
		if safe_only and not _is_safe_advance_cell(candidate):
			_last_position_candidates.append({"cell": candidate, "status": "rejected", "reason": "Unsafe second advance"})
			continue
		var route_index := -1
		var route_distance := INF
		for index in range(1, path.size()):
			var route_cell := battle_controller.world_to_grid(path[index])
			var distance := candidate.distance_to(route_cell)
			if distance <= _last_route_corridor and (distance < route_distance or (is_equal_approx(distance, route_distance) and index > route_index)):
				route_distance = distance
				route_index = index
		if route_index < 0 and not allow_route_detour:
			_last_position_candidates.append({"cell": candidate, "status": "rejected", "reason": "Outside useful route"})
			continue
		var remaining := battle_controller.pathfinder.calculate_3d_path(candidate, route_end)
		if remaining.is_empty() and not allow_route_detour:
			continue
		# A hypothetical route from the candidate can be cut off by the actor's
		# still-occupied origin in a one-cell passage. At maximum urgency, score the
		# already-legal first step by geometric progress so the actor can leave the
		# pocket; the committed Move still uses its authoritative path from origin.
		var progress := (
			float(start_cell.distance_to(goal_cell) - candidate.distance_to(goal_cell))
			if remaining.is_empty()
			else initial_cost - _route_cost(remaining)
		)
		var scored := AIPositionScorer.evaluate(unit, candidate, start_cell, goal_cell, progress, objective_route, hostiles, battle_controller.grid_manager, _policy, _squad_context)
		var revisit_penalty := 0.0
		for index in _recent_move_origins.size():
			if _recent_move_origins[index] == candidate:
				revisit_penalty += 6.0 * (index + 1)
		scored.total -= revisit_penalty
		scored.summary += "; revisit %+.0f" % -revisit_penalty
		var score: float = scored.total
		if route_index < 0:
			scored.summary += "; maximum urgency allowed route detour"
		if remaining.is_empty():
			scored.summary += "; occupied-origin recovery estimate"
		if score > best_route_score:
			best_route_candidate = candidate
			best_route_score = score
			best_route_summary = scored.summary
		var candidate_record := {"cell": candidate, "score": score, "status": "considered", "summary": scored.summary}
		for component in ["progress", "cover", "exposure", "firing", "danger", "squad"]:
			if scored.has(component):
				candidate_record[component] = scored[component]
		# A carrier must be allowed to take the least-bad valid route step. Stairs,
		# platforms, and congestion can require a locally negative detour even while
		# the complete path still leads toward extraction.
		if score > _last_move_threshold or unit.is_carrying_unit():
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
	# Mission movement must eventually accept the least-bad valid route step.
	# This only applies after the ordinary urgency ramp has reached its cap;
	# immediate and cautious choices still use the normal position threshold.
	if best_candidate.x < 0 and objective_route and not safe_only \
	and _last_urgency_bonus >= URGENCY_MAX_SCORE and best_route_candidate.x >= 0:
		best_candidate = best_route_candidate
		best_adjustment = _squad_context.destination_adjustment(unit, best_candidate) if _squad_context else 0.0
		best_score = best_route_score
		best_summary = "%s; maximum mission urgency accepted least-bad route step" % best_route_summary
	# Prefer actual progress for the carrier. Negative-progress detours remain
	# available only when congestion or level geometry leaves no forward option.
	if unit.is_carrying_unit():
		var forward_options: Array[Dictionary] = options.filter(
			func(option: Dictionary) -> bool: return float(option.scored.progress) > 0.01
		)
		if not forward_options.is_empty():
			forward_options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
			var selected_forward: Dictionary = forward_options[0]
			best_candidate = selected_forward.cell
			best_adjustment = _squad_context.destination_adjustment(unit, best_candidate) if _squad_context else 0.0
			best_score = selected_forward.score
			best_summary = "%s; carrier forward progress required" % selected_forward.scored.summary
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
	if best_candidate.x >= 0:
		_publish_movement_preview(best_candidate, best_summary)
	if best_candidate.x >= 0 and await battle_controller.try_move(unit, best_candidate):
		_recent_move_origins.append(start_cell)
		if _recent_move_origins.size() > 4: _recent_move_origins.pop_front()
		_last_move_destination = best_candidate
		_last_position_scores = best_summary
		_reserve_destination(best_candidate, best_adjustment)
		return true
	_movement_preview_pending_completion = false
	return false

func _get_movement_urgency_bonus() -> float:
	var carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	if carrier and carrier != unit and current_mission_intent.kind == MissionIntentData.Kind.EXTRACT:
		# Extraction escorts cannot spend several exposed rounds waiting for a
		# perfect tile. Each previous wait progressively accepts a worse move.
		return minf(URGENCY_MAX_SCORE, float(_consecutive_low_value_actions + 1) * 6.0)
	if _consecutive_low_value_actions < URGENCY_START_ACTIONS:
		return 0.0
	if unit.is_carrying_unit() or (unit.mission_actor and unit.mission_actor.is_vip()):
		return 0.0
	if unit.stats and unit.stats.current_hp <= 25:
		return 0.0
	return minf(URGENCY_MAX_SCORE, float(_consecutive_low_value_actions - URGENCY_START_ACTIONS + 1) * URGENCY_PER_ACTION)

func _route_cost(path: PackedVector3Array) -> float:
	return battle_controller.pathfinder.get_path_cost(path, battle_controller.world_to_grid)

func _legal_move_destinations() -> Array[Vector3i]:
	var query := battle_controller.query_move(unit)
	var destinations: Array[Vector3i] = []
	if query.is_legal():
		destinations.assign(query.legal_destination_cells)
	return destinations

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
	for candidate in _legal_move_destinations():
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
	var attack_inventory := battle_controller.query_attack(unit)
	var carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	if carrier and carrier != unit:
		var threats: Array[TacticalUnit] = []
		for hostile in targets:
			var hostile_query := attack_inventory.get_candidate(hostile.tactical_id)
			if hostile_query != null and hostile_query.is_legal() and CombatRules.evaluate_attack(hostile, carrier, battle_controller.grid_manager, hostile.get_world_3d()).is_legal:
				threats.append(hostile)
		if not threats.is_empty(): targets = threats
	for candidate in targets:
		if not is_instance_valid(candidate) or not candidate.stats or candidate.stats.is_defeated:
			continue
		var attack_query := attack_inventory.get_candidate(candidate.tactical_id)
		if attack_query == null:
			attack_query = battle_controller.query_attack(unit, candidate)
		if attack_query.is_legal():
			var scored := AITargetScorer.evaluate(unit, candidate, friendlies, current_mission_intent, _objective_manager, battle_controller.grid_manager, _policy, _squad_context, attack_query)
			var score: float = scored.total
			var target_record := {"target": String(candidate.name), "cell": candidate.grid_position, "score": score, "status": "considered", "summary": scored.summary, "hit_chance": attack_query.hit_chance, "expected_damage": attack_query.expected_damage}
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
			_last_target_candidates.append({"target": String(candidate.name), "cell": candidate.grid_position, "status": "rejected", "reason": attack_query.reason, "code": String(attack_query.validation.code)})
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
	if action == "Wait":
		_consecutive_low_value_actions += 1
	elif action in ["Move", "Attack", "Rescue", "Extract", "Support"]:
		_consecutive_low_value_actions = 0
	# Movement scoring is published as soon as the destination is selected so the
	# heatmap appears with the first movement frame. Avoid publishing it again after
	# the movement coroutine completes.
	if action == "Move" and _movement_preview_pending_completion:
		_movement_preview_pending_completion = false
		return
	var notes := "None" if _squad_notes.is_empty() else "; ".join(_squad_notes)
	var context := _decision_context()
	battle_controller.record_ai_decision(unit, action, subject, reason, alternatives, current_mission_intent.get_debug_label(), notes, _last_position_scores, _pending_target_scores if action == "Attack" else "None", _last_position_candidates, _last_target_candidates, context)

func _publish_movement_preview(destination: Vector3i, summary: String) -> void:
	_last_position_scores = summary
	_movement_preview_pending_completion = true
	var notes := "None" if _squad_notes.is_empty() else "; ".join(_squad_notes)
	battle_controller.record_ai_decision(unit, "Move", str(destination), "Selected destination; movement is beginning.", "Attack, Wait", current_mission_intent.get_debug_label(), notes, _last_position_scores, "None", _last_position_candidates, _last_target_candidates, _decision_context())

func _wait_for_next_turn(reason: String, alternatives: String) -> bool:
	_record_ai_decision("Wait", unit.name, reason, alternatives)
	return await battle_controller.try_end_unit_turn(unit, reason)

func _movement_wait_reason(prefix: String) -> String:
	var occupied_by: Array[String] = []
	var outside_route := 0
	var unsafe := 0
	var below_threshold := 0
	for candidate in _last_position_candidates:
		if candidate.get("status", "") != "rejected":
			continue
		var reason := String(candidate.get("reason", ""))
		if reason.begins_with("Occupied by "):
			var blocker := reason.trim_prefix("Occupied by ")
			if not occupied_by.has(blocker): occupied_by.append(blocker)
		elif reason == "Outside useful route":
			outside_route += 1
		elif reason == "Unsafe second advance":
			unsafe += 1
		else:
			below_threshold += 1
	var details: Array[String] = []
	if not occupied_by.is_empty(): details.append("route blocked by %s" % ", ".join(occupied_by.slice(0, 3)))
	if outside_route > 0: details.append("%d cells outside route" % outside_route)
	if unsafe > 0: details.append("%d unsafe cells" % unsafe)
	if below_threshold > 0: details.append("%d moves below threshold" % below_threshold)
	if details.is_empty(): details.append("no reachable legal destination")
	return "%s %s" % [prefix, "; ".join(details)]

func _decision_context() -> Dictionary:
	return {
		"grid_position": unit.grid_position if is_instance_valid(unit) else Vector3i(-1, -1, -1),
		"remaining_ap": unit.stats.current_ap if is_instance_valid(unit) and unit.stats else -1,
		"recent_move_origins": _recent_move_origins.duplicate(),
		"consecutive_low_value_actions": _consecutive_low_value_actions,
		"hold_score": _optional_score(_last_hold_score),
		"move_acceptance_threshold": _optional_score(_last_move_threshold),
		"urgency_bonus": _last_urgency_bonus,
		"route_corridor": _last_route_corridor,
	}

func _optional_score(value: float) -> Variant:
	if is_nan(value):
		return null
	return value

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
