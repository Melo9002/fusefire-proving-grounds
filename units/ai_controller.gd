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
const ACTIVATION_PRESENTATION_DELAY_SECONDS := 0.6
const ACTION_PRESENTATION_DELAY_SECONDS := 0.25
const MOVEMENT_SCORING_SLICE_USEC := 5000
const RECENT_MOVE_HISTORY_LIMIT := 4
const MAX_ATTACK_PLAN_AP := 3
## Move then Attack: a reposition must be worth clearly more than shooting from where the unit stands,
## by this fraction of that value and at least this much, so two similar cells never cause dithering.
const REPOSITION_MIN_GAIN_FRACTION := 0.25
const REPOSITION_MIN_GAIN := 3.0
## At most this many cells with the best shots are checked for safety.
const REPOSITION_CANDIDATE_LIMIT := 12
## A Shield stance must be expected to prevent at least this much damage to be worth the AP.
const SHIELD_MIN_PREVENTED := 2.0
## Holding a Shield stance must beat firing one more shot by this factor before the unit gives the shot up.
const SHIELD_OVER_SHOT_MARGIN := 1.25
const ESCORT_REJOIN_DISTANCE := 5
const ESCORT_APPROACH_RANGE := 4
const ESCORT_POSITION_MIN_DISTANCE := 2.0
const ESCORT_POSITION_MAX_DISTANCE := 5.0
const ESCORT_POSITION_IDEAL_DISTANCE := 3.0
const ESCORT_POSITION_DISTANCE_WEIGHT := 2.0

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
var _difficulty_policy: AIDifficultyPolicy
var _commander_policy: AICommanderPolicy
var _decision_rng := RandomNumberGenerator.new()
var _last_position_scores := "None"
var _last_movement_profile := "None"
## Layer choices by (objective route, carrying) for the current activation step, so scoring loops do not rebuild them.
var _movement_layer_cache := {}
var _last_position_candidates: Array[AIPositionCandidate] = []
var _last_target_candidates: Array[AITargetCandidate] = []
## Why the last approach could not even start: a named blocker on the way, or no route at all.
## Empty when an approach ran and was merely not worth taking. Read by _movement_wait_reason.
var _route_block_note := ""
var _committed_carrier_route: Array[Vector3i] = []
## The walkable graph the committed route was planned on (Pathfinder.graph_revision): a route over a graph that has since changed is planned again.
var _committed_route_graph := -1
var _last_attack_plan: Dictionary = {}
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
	_ensure_policy()
	_decision_rng.seed = battle_controller.ai_decision_seed * 1000003 + String(unit.name).hash()

## Composes the policy once. Direct action helpers may run before _ready().
func _ensure_policy() -> AIDifficultyPolicy:
	if _policy == null:
		_commander_policy = battle_controller.get_commander_policy(unit)
		_difficulty_policy = AIDifficultyPolicy.create(battle_controller.ai_difficulty)
		_policy = _commander_policy.compose(_difficulty_policy)
	return _policy

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
	_squad_notes.clear()
	_last_position_scores = "None"
	_last_movement_profile = "None"
	_movement_layer_cache.clear()
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
	var should_advance := await _run_activation()
	# Queue changes emit active_unit_changed synchronously. Clear this guard first
	# so a partially spent automated player can be selected again immediately.
	_is_executing = false
	if should_advance and _should_control_unit():
		if turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN:
			turn_manager.advance_automated_player(unit)
		else:
			turn_manager.end_current_turn()

func _run_activation() -> bool:
	if not _battle_is_live(): return false
	# Brief pause makes the enemy activation visible before it acts.
	await get_tree().create_timer(ACTIVATION_PRESENTATION_DELAY_SECONDS, false).timeout
	if not _should_control_unit():
		return false
	if unit.mission_actor and unit.mission_actor.is_vip():
		await _execute_vip_turn()
		return false
	var has_moved := false
	_route_block_note = ""
	current_mission_intent = _get_ai_mission_intent()
	_squad_context = battle_controller.get_squad_context(unit)
	var active_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	if active_carrier:
		_squad_context.reserve_corridor(active_carrier, _carrier_route(active_carrier, true))
	# TurnManager may select a zero-AP actor only when a legal free objective
	# action exists. Give that action one deterministic submission opportunity.
	if unit.stats.current_ap <= 0:
		var free_step := await _try_mission_step(false)
		if not _battle_is_live(): return false
		if free_step == MissionStepResult.EXTRACTED:
			return false
	if current_mission_intent.kind == MissionIntentData.Kind.EXTRACT and _can_use_mission_action(&"extract", unit):
		if await _try_mission_step(false) == MissionStepResult.EXTRACTED:
			return false
	while is_instance_valid(unit) and unit.stats.current_ap > 0 \
		and turn_manager.battle_result == TurnManager.BattleResult.ONGOING \
		and _should_control_unit():
		_squad_context = battle_controller.get_squad_context(unit)
		current_mission_intent = _get_ai_mission_intent()
		_squad_context.reserve_objective(unit, current_mission_intent.objective_id)
		var sealed := await _try_emergency_seal()
		if not _battle_is_live(): return false
		if sealed:
			_record_ai_decision("Emergency Seal", unit.name, "Stopped authoritative Leaking damage.", "Attack, Move, Objective")
			continue
		var escorted_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
		if not has_moved and escorted_carrier and escorted_carrier != unit and await _clear_carrier_route(escorted_carrier):
			if not _battle_is_live(): return false
			has_moved = true
			continue
		if not _battle_is_live(): return false
		# An escort already clear of the evacuation lane may engage immediate
		# threats before repositioning. A blocker clears the lane first.
		if escorted_carrier and escorted_carrier != unit and not _carrier_route(escorted_carrier).has(unit.grid_position):
			var escort_target := _find_attack_target()
			var escort_shot := escort_target != null and await battle_controller.try_attack(unit, escort_target)
			if not _battle_is_live(): return false
			if escort_shot:
				if is_instance_valid(escort_target):
					_squad_context.reserve_target(unit, escort_target)
				_record_ai_decision("Attack", String(escort_target.name) if is_instance_valid(escort_target) else "defeated target", "Protected the VIP carrier from a legal threat.", "Clear route, Reposition, Wait")
				await get_tree().create_timer(ACTION_PRESENTATION_DELAY_SECONDS, false).timeout
				continue
		var mission_step := await _try_mission_step(has_moved)
		if not _battle_is_live(): return false
		if mission_step == MissionStepResult.EXTRACTED:
			return false
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
		# Move then Attack: a legal shot is not always the best use of the turn. If one move reaches a
		# cell whose shots are clearly worth more, and the unit can still fire afterwards, move first.
		if attack_target != null and not has_moved and _reposition_allowed():
			var reposition := await _best_reposition_plan(attack_target)
			if not _battle_is_live(): return false
			if reposition != null:
				var start_cell := battle_controller.grid_manager.get_unit_grid(unit)
				if await battle_controller.try_move(unit, reposition.destination):
					has_moved = true
					_recent_move_origins.append(start_cell)
					if _recent_move_origins.size() > RECENT_MOVE_HISTORY_LIMIT: _recent_move_origins.pop_front()
					_last_move_destination = reposition.destination
					_reserve_destination(reposition.destination, 0.0)
					# This decision is explained by the plan, not by an earlier movement heatmap.
					_last_position_candidates.clear()
					_last_position_scores = reposition.summary
					_record_ai_decision("Move", str(reposition.destination), "Repositioned for a better shot: %s." % reposition.summary, "Attack, Aim, Wait")
					continue
		# The last action of the activation: one more shot, or hold the stance through the enemy turn?
		var held_plan := _shield_instead_of_final_shot(attack_target) if attack_target != null else null
		var held_threat := _hostile_with_id(held_plan.target_id) if held_plan != null else null
		var held := held_threat != null and await _try_shield_against(held_threat)
		if not _battle_is_live(): return false
		if held:
			_record_ai_decision("Shield", held_threat.name, "Held the stance instead of a last shot: %s." % held_plan.summary, "Attack, Aim, Wait")
			continue
		var aimed := attack_target != null and await _try_aim_for_attack(attack_target)
		if not _battle_is_live(): return false
		if aimed:
			_record_ai_decision("Aim", attack_target.name, "Improved a legal shot through the authoritative Aim query.", "Attack, Move, Wait")
			continue
		var attacked := attack_target != null and await battle_controller.try_attack(unit, attack_target)
		if not _battle_is_live(): return false
		if attacked:
			# A cinematic kill can keep this coroutine suspended until the defeated
			# target has finished its presentation and left the tree.
			if is_instance_valid(attack_target):
				_squad_context.reserve_target(unit, attack_target)
			if not _pending_target_note.is_empty(): _squad_notes.append(_pending_target_note)
			_record_ai_decision("Attack", attack_target.name if is_instance_valid(attack_target) else "defeated target", "Legal shot; target score balances vulnerability with allied focus.", "Move, Wait")
			await get_tree().create_timer(ACTION_PRESENTATION_DELAY_SECONDS, false).timeout
			continue
		var reloaded := await _try_reload_if_useful()
		if not _battle_is_live(): return false
		if reloaded:
			_record_ai_decision("Reload", "%d/%d SP" % [unit.stats.current_supply_points, unit.stats.max_supply_points], "Restored attack supply through the authoritative Reload query.", "Move, Wait")
			continue
		if current_mission_intent.kind in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT]:
			_wait_for_next_turn(_movement_wait_reason("No useful objective advance or supporting shot."), "Move, Attack")
			break
		var protected_carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
		if protected_carrier and protected_carrier != unit:
			var rejoined := not has_moved and _grid_distance_to(protected_carrier) > ESCORT_REJOIN_DISTANCE \
			and await _move_toward_range(protected_carrier, ESCORT_APPROACH_RANGE)
			if not _battle_is_live(): return false
			if rejoined:
				has_moved = true
				_record_ai_decision("Support", protected_carrier.name, "Closed into escort range while respecting the carrier corridor.", "Attack, Clear route, Wait")
				continue
			var escorted := not has_moved and await _move_to_escort_position(protected_carrier)
			if not _battle_is_live(): return false
			if escorted:
				has_moved = true
				continue
			_wait_for_next_turn(_movement_wait_reason("No useful escort move or legal shot."), "Move, Extract")
			break
		var intercept := _evacuation_intercept()
		if not intercept.is_empty():
			var intercepted := await _move_toward_cell(intercept.cell, has_moved, intercept.reason)
			if not _battle_is_live(): return false
			if intercepted:
				has_moved = true
				_record_ai_decision("Move", str(_last_move_destination), intercept.reason, "Attack, Guard, Wait")
				continue
		var movement_target = _find_nearest_hostile()
		var approached := not has_moved and movement_target != null and await _move_toward(movement_target)
		if not _battle_is_live(): return false
		if approached:
			has_moved = true
			_record_ai_decision("Move", str(_last_move_destination), "No legal shot; approached the nearest hostile unit.", "Attack, Wait")
			continue
		var advanced := has_moved and await _try_safe_second_advance(movement_target)
		if not _battle_is_live(): return false
		if advanced:
			_record_ai_decision("Move", str(_last_move_destination), "No legal shot; spent remaining AP advancing to a safe tile.", "Attack, Wait")
			continue
		var shield_plan := _worthwhile_shield_plan()
		var shield_threat := _hostile_with_id(shield_plan.target_id) if shield_plan != null else null
		var shielded := shield_threat != null and await _try_shield_against(shield_threat)
		if not _battle_is_live(): return false
		if shielded:
			_record_ai_decision("Shield", shield_threat.name, "%s." % shield_plan.summary, "Guard, Wait")
			continue
		var guarded := await _try_guard_if_useful()
		if not _battle_is_live(): return false
		if guarded:
			_record_ai_decision("Guard", unit.name, "Reserved a reaction because a hostile can plausibly move or attack.", "Shield, Wait")
			break
		var reason := "No legal shot or safe second advance." if has_moved else "No legal shot or reachable approach."
		_wait_for_next_turn(_movement_wait_reason(reason), "Attack, Move")
		break

	return _should_control_unit()

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
	if current_mission_intent.kind == MissionIntentData.Kind.INTERACT_TERMINAL:
		var terminal := _objective_manager.get_inactive_terminal_for_objective(current_mission_intent.objective_id)
		if not terminal:
			return MissionStepResult.NONE
		var terminal_query := battle_controller.query_terminal(unit, terminal.definition.terminal_id)
		if terminal_query.is_legal():
			if await battle_controller.try_terminal(unit, terminal.definition.terminal_id):
				_record_ai_decision("Interact", String(terminal.definition.terminal_id), "Activated the required adjacent mission terminal.", "Attack, Move, Wait")
				return MissionStepResult.INTERACTED
		var approach := _nearest_terminal_approach_cell(terminal)
		if approach.x >= 0 and await _move_toward_cell(approach, has_moved):
			if not _dependencies_alive(): return MissionStepResult.NONE
			_record_ai_decision("Move", str(_last_move_destination), "Approached the required mission terminal.", "Attack, Interact, Wait")
			# Terminal interactions are free and intentionally remain available at
			# zero AP. Complete the objective now rather than relying on another loop.
			var arrived_query := battle_controller.query_terminal(unit, terminal.definition.terminal_id)
			if arrived_query.is_legal() and await battle_controller.try_terminal(unit, terminal.definition.terminal_id):
				_record_ai_decision("Interact", String(terminal.definition.terminal_id), "Activated the terminal after the final movement AP.", "Attack, Wait")
				return MissionStepResult.INTERACTED
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

	var carrying := unit.is_carrying_unit() and current_mission_intent.kind == MissionIntentData.Kind.EXTRACT
	var destination := _nearest_reachable_zone_cell(current_mission_intent.zone_id) if not carrying else Vector3i(-1, -1, -1)
	if not carrying and destination.x < 0:
		return MissionStepResult.NONE
	var moved_toward_objective := await _move_carrier_along_committed_route(has_moved) \
		if carrying \
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

func _try_emergency_seal() -> bool:
	if not is_instance_valid(unit) or unit.conditions == null or not unit.conditions.has(&"leaking"):
		return false
	var query := battle_controller.query_simple(&"emergency_seal", unit)
	return query.is_legal() and await battle_controller.try_emergency_seal(unit)

## Repositioning is a combat choice for a free unit: not a carrier or VIP, and not an escort bound to a
## rescue carrier's corridor.
func _reposition_allowed() -> bool:
	if not is_instance_valid(unit) or not unit.stats or unit.is_carrying_unit() or not _ensure_policy().plans_repositioning:
		return false
	if unit.mission_actor and unit.mission_actor.is_vip():
		return false
	var carrier := _objective_manager.find_rescue_carrier(unit.faction) if _objective_manager else null
	return carrier == null

## The best "move, then fire" plan for the chosen target's turn, or null when shooting from here is
## good enough. Both sides are valued the same way (AIPlanEvaluator.best_attack_from): the sequence
## of shots the unit can afford, at the authoritative chance and damage for that standing cell. A move
## costs its real AP, so the unit must still be able to fire afterwards. Candidates are bounded and
## the destination must pass the same exposure check as any other advance.
func _best_reposition_plan(target: TacticalUnit) -> AIActionPlan:
	var move_query := battle_controller.query_move(unit)
	if not move_query.is_legal():
		return null
	var attack_query := battle_controller.query_attack(unit, target)
	var attack_ap := maxi(1, attack_query.cost.ap)
	var supply_cost := maxi(0, attack_query.supply_points_cost)
	var move_ap := move_query.cost.ap
	if unit.stats.current_ap - move_ap < attack_ap:
		return null
	var uses_supply := battle_controller.supply_points_enabled
	var moved_shots := AIPlanEvaluator.shots_with(unit.stats.current_ap - move_ap, unit.stats.current_supply_points, attack_ap, supply_cost, uses_supply, MAX_ATTACK_PLAN_AP)
	if moved_shots < 1:
		return null
	var grid := battle_controller.grid_manager
	var start := grid.get_unit_grid(unit)
	var hostiles := _get_hostile_units()
	var kill_bonus := 20.0 * _ensure_policy().finishing_bonus_weight
	var aim_bonus: int = CombatRules.cover_tuning.aim_accuracy_bonus if battle_controller.aim_enabled and unit.tactical_state and unit.tactical_state.is_aiming else 0
	var now_shots := AIPlanEvaluator.shots_with(unit.stats.current_ap, unit.stats.current_supply_points, attack_ap, supply_cost, uses_supply, MAX_ATTACK_PLAN_AP)
	var now := AIPlanEvaluator.best_attack_from(unit, start, hostiles, battle_controller, now_shots, kill_bonus, aim_bonus)
	var required: float = float(now.value) + maxf(REPOSITION_MIN_GAIN, float(now.value) * REPOSITION_MIN_GAIN_FRACTION)
	var snapshot := AIPlanningSnapshot.capture(battle_controller)
	var scored: Array[Dictionary] = []
	var slice_start := Time.get_ticks_usec()
	for cell in move_query.legal_destination_cells:
		if Time.get_ticks_usec() - slice_start >= MOVEMENT_SCORING_SLICE_USEC:
			await get_tree().process_frame
			if not is_inside_tree() or not _should_control_unit() or snapshot.is_stale(battle_controller):
				return null
			slice_start = Time.get_ticks_usec()
		if cell == start or (_squad_context and not _squad_context.block_reason(unit, cell).is_empty()):
			continue
		var shot := AIPlanEvaluator.best_attack_from(unit, cell, hostiles, battle_controller, moved_shots, kill_bonus)
		if shot.target != null and float(shot.value) >= required:
			scored.append({"cell": cell, "shot": shot})
	if scored.is_empty():
		return null
	# Best shots first; equal shots go to the lower cell so the choice never depends on iteration order.
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.shot.value), float(b.shot.value)):
			return float(a.shot.value) > float(b.shot.value)
		return _cell_less(a.cell, b.cell))
	var current_exposure := _advance_exposure(start)
	for entry in scored.slice(0, REPOSITION_CANDIDATE_LIMIT):
		if snapshot.is_stale(battle_controller):
			return null
		if _is_safe_advance_cell(entry.cell, current_exposure):
			var plan := AIPlanEvaluator.move_then_attack(entry.cell, entry.shot, move_ap, attack_ap, supply_cost)
			plan.summary += "; shooting from here is worth %.1f, from there %.1f" % [float(now.value), plan.value]
			return plan
	return null

func _try_aim_for_attack(target: TacticalUnit) -> bool:
	if not is_instance_valid(unit) or not is_instance_valid(target) or not unit.stats:
		return false
	var comparison := AIPlanEvaluator.compare_aim(unit, target, battle_controller, 20.0 * _ensure_policy().finishing_bonus_weight, MAX_ATTACK_PLAN_AP)
	if comparison.is_empty():
		return false
	_last_attack_plan = comparison.trace
	return comparison.choose_aim and await battle_controller.try_aim(unit)

## Policy integration is intentionally deferred to 01.11.7. This adapter keeps
## AI legality and orientation on the same authoritative path as player input.
func _try_shield_against(threat: TacticalUnit) -> bool:
	if not is_instance_valid(unit) or not is_instance_valid(threat):
		return false
	var query := battle_controller.query_shield(unit, threat)
	return query.is_legal() and await battle_controller.try_shield(unit, threat)

func _try_guard_if_useful() -> bool:
	if not is_instance_valid(unit) or not unit.stats or _consecutive_low_value_actions > 0:
		return false
	var query := battle_controller.query_overwatch(unit)
	if not query.is_legal() or not _guard_has_plausible_trigger():
		return false
	return await battle_controller.try_overwatch(unit)

func _guard_has_plausible_trigger() -> bool:
	var actor_cell := battle_controller.grid_manager.get_unit_grid(unit)
	for hostile in _get_hostile_units():
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		if battle_controller.query_attack(unit, hostile).is_legal():
			return true
		var hostile_cell := battle_controller.grid_manager.get_unit_grid(hostile)
		if CombatRules.attack_distance(actor_cell, hostile_cell, battle_controller.grid_manager) <= unit.attack_range + hostile.stats.speed:
			return true
	return false

## The Shield plan, if the stance is worth its AP now. Shield lasts until the unit's next activation and
## only lowers damage taken, so it is judged by the damage it is expected to prevent. A unit that has
## just been waiting does not start a defensive loop.
func _worthwhile_shield_plan() -> AIActionPlan:
	if not is_instance_valid(unit) or unit.shield_capability == null or _consecutive_low_value_actions > 0:
		return null
	var plan := AIPlanEvaluator.best_shield_plan(unit, _get_hostile_units(), battle_controller)
	return plan if plan != null and plan.value >= SHIELD_MIN_PREVENTED else null

## With only the stance's AP left and a legal shot available, compares the two plans in the same terms:
## the shot is worth its HP-capped expected damage (plus the kill value), the stance the expected damage it
## prevents. Holding the stance wins only by a clear margin, so a unit does not flip between the two.
## Earlier AP are still spent shooting, which gives "attack, attack, Shield" when that is the better plan.
func _shield_instead_of_final_shot(target: TacticalUnit) -> AIActionPlan:
	if not is_instance_valid(unit) or not is_instance_valid(target) or unit.shield_capability == null:
		return null
	if unit.stats.current_ap != unit.shield_capability.stance_ap_cost:
		return null
	var plan := _worthwhile_shield_plan()
	if plan == null:
		return null
	var aim_bonus: int = CombatRules.cover_tuning.aim_accuracy_bonus if battle_controller.aim_enabled and unit.tactical_state and unit.tactical_state.is_aiming else 0
	var kill_bonus := 20.0 * _ensure_policy().finishing_bonus_weight
	var shot := AIPlanEvaluator.best_attack_from(unit, battle_controller.grid_manager.get_unit_grid(unit), [target] as Array[TacticalUnit], battle_controller, 1, kill_bonus, aim_bonus)
	if plan.value <= float(shot.value) * SHIELD_OVER_SHOT_MARGIN:
		return null
	plan.summary += " against about %.1f from the last shot" % float(shot.value)
	return plan

func _hostile_with_id(tactical_id: StringName) -> TacticalUnit:
	for hostile in _get_hostile_units():
		if is_instance_valid(hostile) and hostile.tactical_id == tactical_id:
			return hostile
	return null

func _most_relevant_defensive_threat() -> TacticalUnit:
	if not is_instance_valid(unit) or unit.shield_capability == null or _consecutive_low_value_actions > 0:
		return null
	var best: TacticalUnit = null
	var best_score := -INF
	for hostile in _get_hostile_units():
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var incoming := CombatRules.evaluate_attack(hostile, unit, battle_controller.grid_manager, hostile.get_world_3d())
		if not incoming.is_legal:
			continue
		# Current attacks share one prototype damage value, so hit chance is the
		# meaningful threat discriminator without duplicating service damage rules.
		var score := float(incoming.hit_chance)
		if score > best_score or (is_equal_approx(score, best_score) and (best == null or String(hostile.tactical_id) < String(best.tactical_id))):
			best = hostile
			best_score = score
	return best

func _nearest_terminal_approach_cell(terminal: MissionTerminalState) -> Vector3i:
	if not terminal or not is_instance_valid(battle_controller):
		return Vector3i(-1, -1, -1)
	var grid := battle_controller.grid_manager
	var start := grid.get_unit_grid(unit)
	var terminal_cell := terminal.definition.grid_position
	var best := Vector3i(-1, -1, -1)
	var best_path_size := INF
	for x in range(-1, 2):
		for z in range(-1, 2):
			var candidate := terminal_cell + Vector3i(x, 0, z)
			if candidate == terminal_cell or not grid.map_data.has_cell(candidate):
				continue
			if candidate != start and not grid.can_unit_occupy_cell(unit, candidate):
				continue
			if not CombatRules.can_reach_adjacent(candidate, terminal_cell, grid):
				continue
			var path := battle_controller.pathfinder.calculate_3d_path(start, candidate)
			if candidate == start:
				return candidate
			if path.is_empty():
				continue
			if path.size() < best_path_size or (path.size() == best_path_size and _cell_less(candidate, best)):
				best = candidate
				best_path_size = path.size()
	return best

func _cell_less(left: Vector3i, right: Vector3i) -> bool:
	return right.x < 0 or left.x < right.x or (left.x == right.x and (left.y < right.y or (left.y == right.y and left.z < right.z)))

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

func _carrier_route(carrier: TacticalUnit, recheck_occupancy := false) -> Dictionary:
	if not is_instance_valid(carrier):
		return {}
	var grid := battle_controller.grid_manager
	var pathfinder := battle_controller.pathfinder
	var carrier_cell := grid.get_unit_grid(carrier)
	var zone := grid.map_data.get_objective_zone(&"extract")
	if carrier != unit and _squad_context \
	and _squad_context.corridor_owner == SquadContext._actor_id(carrier) \
	and not _squad_context.reserved_corridor.is_empty():
		var lane := _squad_context.reserved_corridor
		if not recheck_occupancy or pathfinder.is_route_clear(_carrier_route_points(lane.keys()), carrier, grid):
			return lane.duplicate()
	if carrier == unit and _committed_route_graph == pathfinder.graph_revision() \
	and _committed_carrier_route.has(carrier_cell) and zone.has(_committed_carrier_route[-1]):
		var reached_index := _committed_carrier_route.find(carrier_cell)
		if reached_index > 0:
			_committed_carrier_route = _committed_carrier_route.slice(reached_index)
		if pathfinder.is_route_clear(_carrier_route_points(_committed_carrier_route), carrier, grid):
			return _route_dictionary(_committed_carrier_route)
	var reserved := {}
	var best := PackedVector3Array()
	for destination in zone:
		var path := pathfinder.calculate_3d_path(carrier_cell, destination)
		if not path.is_empty() and not pathfinder.is_route_clear(path, carrier, grid):
			path = pathfinder.calculate_path_with_occupancy(carrier_cell, destination, grid, carrier)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
	if carrier == unit:
		_committed_carrier_route.clear()
		_committed_route_graph = pathfinder.graph_revision()
		for point in best:
			_committed_carrier_route.append(battle_controller.world_to_grid(point))
	# Only look for help when there is no live route. The hint is never stored
	# as the carrier's movement route or passed to the action service.
	if best.is_empty():
		for destination in zone:
			var path := pathfinder.calculate_friendly_yield_path(carrier_cell, destination, grid, carrier)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
	for point in best:
		reserved[battle_controller.world_to_grid(point)] = true
	return reserved

func _carrier_route_points(cells: Array) -> PackedVector3Array:
	var path := PackedVector3Array()
	for route_cell: Vector3i in cells:
		var cell := battle_controller.grid_manager.get_cell_data(route_cell)
		if not cell:
			return PackedVector3Array()
		path.append(cell.world_position)
	return path

func _route_dictionary(route: Array[Vector3i]) -> Dictionary:
	var cells := {}
	for route_cell in route:
		cells[route_cell] = true
	return cells

func _move_carrier_along_committed_route(safe_only: bool) -> bool:
	var lane := _carrier_route(unit)
	_squad_context.reserve_corridor(unit, lane)
	if _committed_carrier_route.size() <= 1:
		_route_block_note = "No reachable extraction route." if lane.is_empty() else "Extraction lane occupied by allies; waiting for passage."
		return false
	var path := _carrier_route_points(_committed_carrier_route)
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
	var route_order := route.keys()
	var start_index := route_order.find(start)
	_last_position_candidates.clear()
	for candidate in _legal_move_destinations():
		if candidate == start:
			continue
		var remains_on_route := route.has(candidate)
		# Some stairs and bridges have no side tile within one move. In that case
		# the blocker may continue ahead through the bottleneck, creating room for
		# the carrier behind it. A real off-route clearing position always wins.
		if remains_on_route and route_order.find(candidate) <= start_index:
			continue
		var destination_owner: StringName = _squad_context.reserved_destinations.get(candidate, &"")
		if not destination_owner.is_empty() and destination_owner != SquadContext._actor_id(unit):
			continue
		var scored := AIPositionScorer.evaluate(unit, candidate, start, carrier.grid_position, 0.0, _movement_layers(false), hostiles, grid, _policy, _squad_context)
		var score: float = scored.total - candidate.distance_to(carrier.grid_position)
		var summary := "%s; %s" % [scored.summary, "bottleneck advance" if remains_on_route else "route clearance"]
		_last_position_candidates.append(AIPositionCandidate.considered(candidate, score, summary))
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
		candidate_record.mark_chosen(candidate_record.cell == best)
	if best.x < 0:
		return false
	_publish_movement_preview(best, "Carrier route clearance %.1f" % best_score)
	if not await battle_controller.try_move(unit, best):
		_movement_preview_pending_completion = false
		return false
	_movement_preview_pending_completion = false
	_recent_move_origins.append(start)
	if _recent_move_origins.size() > RECENT_MOVE_HISTORY_LIMIT: _recent_move_origins.pop_front()
	_last_move_destination = best
	_reserve_destination(best, _squad_context.destination_adjustment(unit, best) if _squad_context else 0.0)
	var reason := "Advanced through the bottleneck to give the carrier room." if route.has(best) else "Yielded the carrier's evacuation route."
	_record_ai_decision("Support", carrier.name, reason, "Attack, Wait")
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
		if carrier_distance < ESCORT_POSITION_MIN_DISTANCE or carrier_distance > ESCORT_POSITION_MAX_DISTANCE:
			continue
		var scored := AIPositionScorer.evaluate(unit, candidate, start, carrier.grid_position, 0.0, _movement_layers(false), hostiles, grid, _policy, _squad_context)
		var spacing_penalty := absf(carrier_distance - ESCORT_POSITION_IDEAL_DISTANCE) * ESCORT_POSITION_DISTANCE_WEIGHT
		var score: float = scored.total - spacing_penalty
		var candidate_record := AIPositionCandidate.considered(candidate, score, "%s; escort spacing %+.0f" % [scored.summary, -spacing_penalty])
		_last_position_candidates.append(candidate_record)
		if score > best_score:
			best_score = score
			best = candidate
	for candidate_record in _last_position_candidates:
		candidate_record.mark_chosen(candidate_record.cell == best)
	if best.x < 0:
		return false
	_publish_movement_preview(best, "Escort position %.1f" % best_score)
	if not await battle_controller.try_move(unit, best):
		_movement_preview_pending_completion = false
		return false
	_movement_preview_pending_completion = false
	_recent_move_origins.append(start)
	if _recent_move_origins.size() > RECENT_MOVE_HISTORY_LIMIT: _recent_move_origins.pop_front()
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

func _battle_is_live() -> bool:
	# Awaited decisions may resume after their owning scene has been removed.
	if not is_inside_tree() or is_queued_for_deletion(): return false
	return _dependencies_alive()

## The battle side still exists. Unlike _battle_is_live this does not require the controller
## itself to be in the tree: helpers are also used as adapters outside it (tests, tools).
func _dependencies_alive() -> bool:
	for dependency in [unit, turn_manager, battle_controller]:
		if not is_instance_valid(dependency) or not dependency.is_inside_tree() or dependency.is_queued_for_deletion(): return false
	return true

func _should_control_unit() -> bool:
	if not _battle_is_live(): return false
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
		var escort := _nearest_vip_escort()
		if escort and await _move_toward(escort):
			_record_ai_decision("Move", str(_last_move_destination), "Followed the nearest available escort.", "Wait")
	if not _should_control_unit(): return
	if unit.stats.current_ap > 0:
		_wait_for_next_turn("VIP has no useful follow movement.", "Move")
	if _should_control_unit():
		turn_manager.end_current_turn()

func _nearest_vip_escort() -> TacticalUnit:
	var best: TacticalUnit = null
	var best_distance := INF
	for candidate in turn_manager.player_units:
		if not is_instance_valid(candidate) or candidate == unit or not candidate.stats or candidate.stats.is_defeated: continue
		if candidate.mission_actor and candidate.mission_actor.is_vip(): continue
		var distance := unit.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (best == null or String(candidate.tactical_id) < String(best.tactical_id))):
			best = candidate
			best_distance = distance
	return best

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

func _is_safe_advance_cell(candidate: Vector3i, current_exposure := NAN) -> bool:
	if is_nan(current_exposure):
		current_exposure = _advance_exposure(battle_controller.grid_manager.get_unit_grid(unit))
	return _policy.permits_advance(current_exposure, _advance_exposure(candidate))

func _advance_exposure(candidate: Vector3i) -> float:
	var grid := battle_controller.grid_manager
	var exposure := 0.0
	for hostile in _get_hostile_units():
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var hostile_cell := grid.get_unit_grid(hostile)
		var distance := CombatRules.attack_distance(hostile_cell, candidate, grid)
		if distance <= hostile.attack_range and CombatRules.evaluate_attack_after_move(hostile, unit, candidate, grid, unit.get_world_3d()).is_legal:
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
	_route_block_note = ""
	var path := PackedVector3Array()
	var leave_steps := desired_distance
	if battle_controller.grid_manager.map_data.surface_placement_enabled:
		# An occupied opponent is a goal to approach, never a legal body destination.
		path = _path_to_target_neighbor(start_cell, target_cell)
		leave_steps = maxi(0, desired_distance - 1)
	else:
		path = battle_controller.pathfinder.calculate_3d_path(start_cell, target_cell)
	if path.size() <= 1:
		# An empty route means blocked, not "already there": name what is in the way.
		if path.is_empty():
			_route_block_note = _explain_blocked_route(start_cell, target_cell, String(target.name))
		return false

	# Leave the requested path distance between the mover and an occupied target.
	for step in mini(leave_steps, path.size() - 1):
		path.remove_at(path.size() - 1)
	if path.size() <= 1:
		return false
	return await _move_along_goal_path(path, start_cell, target_cell, safe_only)

## Says why no usable route to `goal` exists, naming the units standing on the walkable route when
## they are the cause. Uses the same walkable-route query the planner does, without occupancy.
func _explain_blocked_route(start: Vector3i, goal: Vector3i, label: String) -> String:
	if start == goal:
		return ""
	var grid := battle_controller.grid_manager
	var walkable := battle_controller.pathfinder.calculate_3d_path(start, goal)
	if walkable.size() <= 1:
		return "no walkable route to %s" % label
	var blockers: Array[String] = []
	for index in range(1, walkable.size() - 1):
		var cell := battle_controller.world_to_grid(walkable[index])
		var occupant := grid.get_unit_at(cell)
		if occupant != null and occupant != unit:
			var entry := "%s at %s" % [occupant.name, cell]
			if not blockers.has(entry):
				blockers.append(entry)
	if not blockers.is_empty():
		return "route to %s is blocked by %s" % [label, ", ".join(blockers.slice(0, 3))]
	return "route to %s is closed to this unit (body clearance or occupied approach cells)" % label

func _path_to_target_neighbor(start: Vector3i, target: Vector3i) -> PackedVector3Array:
	var grid := battle_controller.grid_manager
	var graph := battle_controller.pathfinder
	var best := PackedVector3Array()
	var best_cost := INF
	for x in range(-1, 2):
		for z in range(-1, 2):
			var candidate := target + Vector3i(x, 0, z)
			if not grid.can_unit_occupy_cell(unit, candidate) or not CombatRules.can_reach_adjacent(candidate, target, grid): continue
			var route := graph.calculate_path_with_occupancy(start, candidate, grid, unit)
			var cost := _route_cost(route) if not route.is_empty() else INF
			if cost < best_cost:
				best = route
				best_cost = cost
	return best

func _grid_distance_to(target: TacticalUnit) -> int:
	var from := battle_controller.grid_manager.get_unit_grid(unit)
	var to := battle_controller.grid_manager.get_unit_grid(target)
	return absi(from.x - to.x) + absi(from.y - to.y) + absi(from.z - to.z)

## When there is no shot, make room to meet an enemy that can escape on its
## next activation. This is one estimate based on a live route and move budget.
## The enemy can change route. The defender still uses the normal move planner.
func _evacuation_intercept() -> Dictionary:
	if current_mission_intent.objective_id != &"stop_enemy_evacuation":
		return {}
	var grid := battle_controller.grid_manager
	var exits := grid.map_data.get_objective_zone(&"enemy_extract")
	var move_ap := MoveQueryResult.new().cost.ap
	var reach := unit.attack_range + unit.stats.speed * floori(float(unit.stats.current_ap) / move_ap)
	var start := grid.get_unit_grid(unit)
	var best := {}
	var best_cost := INF
	var best_distance := INF
	for runner in _get_hostile_units():
		if not is_instance_valid(runner) or not runner.stats or runner.stats.is_defeated:
			continue
		var origin := grid.get_unit_grid(runner)
		var budget := runner.stats.speed * floori(float(runner.stats.effective_max_ap) / move_ap)
		var route := PackedVector3Array()
		var route_cost := INF
		for exit in exits:
			if origin.distance_to(exit) > budget:
				continue
			var candidate := battle_controller.pathfinder.calculate_path_with_occupancy(origin, exit, grid, runner)
			if candidate.size() <= 1:
				continue
			var cost := _route_cost(candidate)
			if cost <= budget and cost < route_cost:
				route = candidate
				route_cost = cost
		# Look ahead of the runner on its route. Avoid committing to a lane
		# outside the distance this defender can plausibly influence.
		for index in range(route.size() - 1, 0, -1):
			var cell := battle_controller.world_to_grid(route[index])
			var distance := start.distance_to(cell)
			if distance > reach or not grid.can_unit_occupy_cell(unit, cell):
				continue
			if route_cost < best_cost or (is_equal_approx(route_cost, best_cost) and distance < best_distance):
				best_cost = route_cost
				best_distance = distance
				best = {"cell": cell, "reason": "Intercept %s near %s (exit route %.1f / %d movement)" % [
					runner.name, cell, route_cost, budget]}
			break
	return best

func _move_toward_cell(target_cell: Vector3i, safe_only := false, route_reason := "") -> bool:
	var start_cell := battle_controller.grid_manager.get_unit_grid(unit)
	_route_block_note = ""
	var path := battle_controller.pathfinder.calculate_3d_path(start_cell, target_cell)
	if path.size() <= 1:
		if path.is_empty():
			_route_block_note = _explain_blocked_route(start_cell, target_cell, str(target_cell))
		return false
	return await _move_along_goal_path(path, start_cell, target_cell, safe_only, route_reason)

func _move_along_goal_path(path: PackedVector3Array, start_cell: Vector3i, goal_cell: Vector3i, safe_only: bool, route_reason := "") -> bool:
	var profiling := OS.get_cmdline_user_args().has("profile-ai")
	var inventory_start := Time.get_ticks_usec() if profiling else 0
	var reachable := _legal_move_destinations()
	var inventory_usec := Time.get_ticks_usec() - inventory_start if profiling else 0
	var plan_start := Time.get_ticks_usec() if profiling else 0
	var yield_usec := 0
	var safety_usec := 0
	var route_checks := {}
	var route_usec := 0
	var score_usec := 0
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
	var objective_route := not route_reason.is_empty() or current_mission_intent.kind in [MissionIntentData.Kind.REACH, MissionIntentData.Kind.EXTRACT, MissionIntentData.Kind.RESCUE, MissionIntentData.Kind.INTERACT_TERMINAL]
	var movement_context := AIMovementContext.build(unit, _get_friendly_units(), hostiles, battle_controller.grid_manager)
	var profile_choice := AIMovementProfiles.select(unit, objective_route, current_mission_intent.get_debug_label(), _movement_situation(movement_context, hostiles, carrier))
	var movement_layers: Array = profile_choice.layers
	_last_movement_profile = String(profile_choice.reason)
	var route_cells: Array[Vector3i] = []
	for point in path:
		route_cells.append(battle_controller.world_to_grid(point))
	var route_end := route_cells.back() as Vector3i
	var initial_cost := _route_cost(path)
	var planning := AIPlanningSnapshot.capture(battle_controller)
	var use_goal_field := battle_controller.grid_manager.map_data.surface_placement_enabled and battle_controller.grid_manager.map_data.traversal_links.is_empty()
	var field_start := Time.get_ticks_usec() if profiling else 0
	var goal_costs := battle_controller.pathfinder.planning_costs_to_goal(route_end, reachable, battle_controller.grid_manager, unit) if use_goal_field else {}
	if profiling: route_usec += Time.get_ticks_usec() - field_start
	var hold := AIPositionScorer.evaluate(unit, start_cell, start_cell, goal_cell, 0.0, movement_layers, hostiles, battle_controller.grid_manager, _policy, null, movement_context)
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
	var current_exposure := _advance_exposure(start_cell) if safe_only else NAN
	var slice_start := Time.get_ticks_usec()
	for candidate in reachable:
		# Yield between candidates. Wall-clock time controls scheduling only.
		if Time.get_ticks_usec() - slice_start >= MOVEMENT_SCORING_SLICE_USEC:
			var yield_start := Time.get_ticks_usec() if profiling else 0
			await get_tree().process_frame
			if profiling: yield_usec += Time.get_ticks_usec() - yield_start
			while is_inside_tree() and get_tree().paused:
				await get_tree().process_frame
			if not is_inside_tree() or not _should_control_unit():
				return false
			if planning.is_stale(battle_controller):
				return false
			if route_checks.size() > 16384: route_checks.clear()
			slice_start = Time.get_ticks_usec()
		if candidate == start_cell: continue
		if escort_route.has(candidate): continue
		var safety_start := Time.get_ticks_usec() if profiling else 0
		var safe := not safe_only or _is_safe_advance_cell(candidate, current_exposure)
		if profiling: safety_usec += Time.get_ticks_usec() - safety_start
		if not safe:
			_last_position_candidates.append(AIPositionCandidate.rejected_before_scoring(candidate, "Unsafe second advance"))
			continue
		var route_index := -1
		var route_distance := INF
		for index in range(1, route_cells.size()):
			var route_cell := route_cells[index]
			var distance := candidate.distance_to(route_cell)
			if distance <= _last_route_corridor and (distance < route_distance or (is_equal_approx(distance, route_distance) and index > route_index)):
				route_distance = distance
				route_index = index
		if route_index < 0 and not allow_route_detour:
			_last_position_candidates.append(AIPositionCandidate.rejected_before_scoring(candidate, "Outside useful route"))
			continue
		var route_start := Time.get_ticks_usec() if profiling else 0
		var remaining_cost: float = goal_costs.get(candidate, INF)
		if not use_goal_field:
			var remaining := battle_controller.pathfinder.calculate_path_with_occupancy(candidate, route_end, battle_controller.grid_manager, unit, route_checks)
			remaining_cost = _route_cost(remaining) if not remaining.is_empty() else INF
		if profiling: route_usec += Time.get_ticks_usec() - route_start
		if is_inf(remaining_cost) and not allow_route_detour:
			continue
		# A hypothetical route from the candidate can be cut off by the actor's
		# still-occupied origin in a one-cell passage. At maximum urgency, score the
		# already-legal first step by geometric progress so the actor can leave the
		# pocket; the committed Move still uses its authoritative path from origin.
		var progress := (
			float(start_cell.distance_to(goal_cell) - candidate.distance_to(goal_cell))
			if is_inf(remaining_cost)
			else initial_cost - remaining_cost
		)
		var score_start := Time.get_ticks_usec() if profiling else 0
		var scored := AIPositionScorer.evaluate(unit, candidate, start_cell, goal_cell, progress, movement_layers, hostiles, battle_controller.grid_manager, _policy, _squad_context, movement_context)
		if profiling: score_usec += Time.get_ticks_usec() - score_start
		if not is_finite(float(scored.total)):
			_last_position_candidates.append(AIPositionCandidate.rejected_before_scoring(candidate, scored.summary))
			continue
		var revisit_penalty := 0.0
		for index in _recent_move_origins.size():
			if _recent_move_origins[index] == candidate:
				revisit_penalty += 6.0 * (index + 1)
		scored.total -= revisit_penalty
		scored.summary += "; revisit %+.0f" % -revisit_penalty
		var score: float = scored.total
		if route_index < 0:
			scored.summary += "; maximum urgency allowed route detour"
		if is_inf(remaining_cost):
			scored.summary += "; occupied-origin recovery estimate"
		if score > best_route_score:
			best_route_candidate = candidate
			best_route_score = score
			best_route_summary = scored.summary
		var candidate_components := {}
		for component in ["progress", "cover", "exposure", "firing", "danger", "squad", "flank", "cohesion"]:
			if scored.has(component):
				candidate_components[component] = scored[component]
		var candidate_record := AIPositionCandidate.considered(candidate, score, scored.summary, candidate_components)
		# A carrier must be allowed to take the least-bad valid route step. Stairs,
		# platforms, and congestion can require a locally negative detour even while
		# the complete path still leads toward extraction.
		if score > _last_move_threshold or unit.is_carrying_unit():
			options.append({"cell": candidate, "score": score, "scored": scored})
		else:
			candidate_record.reject(scored.summary)
		_last_position_candidates.append(candidate_record)
		if score > best_score:
			best_candidate = candidate
			best_adjustment = _squad_context.destination_adjustment(unit, candidate) if _squad_context else 0.0
			best_score = score
			best_summary = scored.summary
	if profiling:
		print("[AIPlan] %s candidates=%d inventory_ms=%.3f routes_ms=%.3f scores_ms=%.3f safety_ms=%.3f yields_ms=%.3f wall_ms=%.3f" % [unit.tactical_id, reachable.size(), inventory_usec / 1000.0, route_usec / 1000.0, score_usec / 1000.0, safety_usec / 1000.0, yield_usec / 1000.0, (Time.get_ticks_usec() - plan_start) / 1000.0])
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
	# Difficulty can vary close combat choices. Mission routes already balance
	# progress, movement profiles and safety, and do not spend a lapse roll.
	if options.size() > 1 and not objective_route and best_candidate != goal_cell and not unit.is_carrying_unit():
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
		candidate_record.mark_chosen(candidate_record.cell == best_candidate)
	if best_candidate.x >= 0:
		if not route_reason.is_empty():
			best_summary = "%s; %s" % [route_reason, best_summary]
		_publish_movement_preview(best_candidate, best_summary)
	if best_candidate.x >= 0 and await battle_controller.try_move(unit, best_candidate):
		_recent_move_origins.append(start_cell)
		if _recent_move_origins.size() > RECENT_MOVE_HISTORY_LIMIT: _recent_move_origins.pop_front()
		_last_move_destination = best_candidate
		_last_position_scores = best_summary
		_reserve_destination(best_candidate, best_adjustment)
		return true
	_movement_preview_pending_completion = false
	return false

## The facts the movement-profile stance rules read, from the shared queries (see AIMovementProfiles.select).
func _movement_situation(context: AIMovementContext, hostiles: Array[TacticalUnit], carrier: TacticalUnit) -> Dictionary:
	var grid := battle_controller.grid_manager
	var my_cell := grid.get_unit_grid(unit)
	var threats := 0
	var wounded_target := false
	for hostile in hostiles:
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var distance := CombatRules.attack_distance(my_cell, grid.get_unit_grid(hostile), grid)
		if distance <= hostile.attack_range and CombatRules.evaluate_attack(hostile, unit, grid, hostile.get_world_3d()).is_legal:
			threats += 1
		if float(hostile.stats.current_hp) <= float(hostile.stats.max_hp) * AIMovementProfiles.WOUNDED_FRACTION and distance <= float(unit.attack_range + unit.stats.speed):
			wounded_target = true
	var nearby_allies := 0
	var wounded_ally := false
	for ally in context.allies:
		var ally_distance := CombatRules.attack_distance(my_cell, grid.get_unit_grid(ally), grid)
		if ally_distance <= AIMovementContext.COHESION_RANGE:
			nearby_allies += 1
		if ally_distance <= 10.0 and float(ally.stats.current_hp) <= float(ally.stats.max_hp) * AIMovementProfiles.WOUNDED_ALLY_FRACTION:
			wounded_ally = true
	return {
		"hp_fraction": float(unit.stats.current_hp) / float(maxi(1, unit.stats.max_hp)),
		"out_of_ammo": battle_controller.supply_points_enabled and unit.stats.current_supply_points <= 0,
		"threats": threats,
		"nearby_allies": nearby_allies,
		"wounded_target": wounded_target,
		"escorting": carrier != null and carrier != unit,
		"flank_possible": is_instance_valid(context.focus_target),
		"wounded_ally": wounded_ally,
		"support_unit": unit.archetype_id == &"support",
	}

## The movement profile layers for a position score outside the main route planner (escort, carrier-route
## and survival scoring): the carrier layer still applies to a unit carrying someone.
func _movement_layers(objective_route: bool) -> Array:
	var key := "%s|%s" % [objective_route, unit.is_carrying_unit()]
	if not _movement_layer_cache.has(key):
		_movement_layer_cache[key] = AIMovementProfiles.select(unit, objective_route, current_mission_intent.get_debug_label()).layers
	return _movement_layer_cache[key]

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
	# Wounded combatants retain the normal early caution, but repeated idle
	# turns must still recover. A permanent HP veto can deadlock both sides.
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
	var profiling := OS.get_cmdline_user_args().has("profile-ai")
	var begin := Time.get_ticks_usec() if profiling else 0
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
	if profiling: print("[AIPlanGoal] %s ms=%.3f" % [unit.tactical_id, (Time.get_ticks_usec() - begin) / 1000.0])
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
	var scored := AIPositionScorer.evaluate(unit, candidate, start, Vector3i(-1, -1, -1), 0, _movement_layers(false), _get_hostile_units(), grid, _policy, _squad_context)
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
	_last_attack_plan.clear()
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
			var affordable := AIPlanEvaluator.affordable_attack_shots(unit, attack_query, battle_controller, MAX_ATTACK_PLAN_AP)
			var scored := AITargetScorer.evaluate(unit, candidate, friendlies, current_mission_intent, _objective_manager, battle_controller.grid_manager, _policy, _squad_context, attack_query, affordable)
			var score: float = scored.total
			var target_components := {}
			for component in ["vulnerability", "focus", "vip", "threat", "mission", "focus_count", "damage_value", "damage_on_hit"]:
				target_components[component] = scored[component]
			_last_target_candidates.append(AITargetCandidate.considered(String(candidate.name), candidate.grid_position, score, scored.summary,
				attack_query.hit_chance, attack_query.expected_damage, target_components))
			options.append({"target": candidate, "score": score, "scored": scored})
			if score > best_score:
				best_target = candidate
				best_score = score
				_pending_target_note = "Target focus: %+.0f (%d allies engaged)" % [scored.focus, scored.focus_count]
				_pending_target_scores = scored.summary
		else:
			_last_target_candidates.append(AITargetCandidate.rejected(String(candidate.name), candidate.grid_position, attack_query.reason, String(attack_query.validation.code)))
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
		target_record.mark_chosen(is_instance_valid(best_target) and target_record.target == String(best_target.name))
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
	# Work resumed after the battle, scene or unit went away is discarded, as in the main loop.
	if not _dependencies_alive(): return
	if action == "Wait":
		_consecutive_low_value_actions += 1
	elif action in ["Move", "Attack", "Rescue", "Extract", "Interact", "Support"]:
		_consecutive_low_value_actions = 0
	elif action in ["Guard", "Shield"]:
		_consecutive_low_value_actions += 1
	# Movement scoring is published as soon as the destination is selected so the
	# heatmap appears with the first movement frame. Avoid publishing it again after
	# the movement coroutine completes.
	if action == "Move" and _movement_preview_pending_completion:
		_movement_preview_pending_completion = false
		return
	var record := _build_decision_record(action, subject, reason, alternatives)
	record.target_scores = _pending_target_scores if action == "Attack" else "None"
	battle_controller.record_ai_decision(unit, record)

## The facts of one decision as the controller knows them. BattleController adds the
## fields it owns (decision id, state revision, difficulty, commander) when it publishes.
func _build_decision_record(action: String, subject: String, reason: String, alternatives: String) -> AIDecisionRecord:
	var record := AIDecisionRecord.new()
	record.action = action
	record.subject = subject
	record.reason = reason
	record.alternatives = alternatives
	record.mission_goal = current_mission_intent.get_debug_label()
	record.squad_adjustments = "None" if _squad_notes.is_empty() else "; ".join(_squad_notes)
	record.position_scores = _last_position_scores
	record.movement_profile = _last_movement_profile
	record.position_candidates = _last_position_candidates
	record.target_candidates = _last_target_candidates
	record.context = _decision_context()
	return record

func _publish_movement_preview(destination: Vector3i, summary: String) -> void:
	if not _dependencies_alive(): return
	_last_position_scores = summary
	_movement_preview_pending_completion = true
	var record := _build_decision_record("Move", str(destination), "Selected destination; movement is beginning.", "Attack, Wait")
	record.stage = AIDecisionRecord.STAGE_SELECTED
	battle_controller.record_ai_decision(unit, record)

func _wait_for_next_turn(reason: String, alternatives: String) -> bool:
	if not _dependencies_alive(): return false
	_record_ai_decision("Wait", unit.name, reason, alternatives)
	return await battle_controller.try_end_unit_turn(unit, reason)

func _movement_wait_reason(prefix: String) -> String:
	var occupied_by: Array[String] = []
	var outside_route := 0
	var unsafe := 0
	var below_threshold := 0
	var reserved: Array[String] = []
	for candidate in _last_position_candidates:
		if not candidate.is_rejected():
			continue
		var reason := candidate.reason
		if reason.begins_with("Corridor reserved by ") or reason.begins_with("Destination reserved by "):
			var holder := reason.get_slice(" reserved by ", 1)
			if not reserved.has(holder): reserved.append(holder)
		elif reason.begins_with("Occupied by "):
			var blocker := reason.trim_prefix("Occupied by ")
			if not occupied_by.has(blocker): occupied_by.append(blocker)
		elif reason == "Outside useful route":
			outside_route += 1
		elif reason == "Unsafe second advance":
			unsafe += 1
		else:
			below_threshold += 1
	var details: Array[String] = []
	if not _route_block_note.is_empty(): details.append(_route_block_note)
	if not occupied_by.is_empty(): details.append("route blocked by %s" % ", ".join(occupied_by.slice(0, 3)))
	if not reserved.is_empty(): details.append("cells reserved by %s" % ", ".join(reserved.slice(0, 3)))
	if outside_route > 0: details.append("%d cells outside route" % outside_route)
	if unsafe > 0: details.append("%d unsafe cells" % unsafe)
	if below_threshold > 0: details.append("%d moves below threshold" % below_threshold)
	if details.is_empty(): details.append(_no_destination_reason())
	return "%s %s" % [prefix, "; ".join(details)]

## Query rejections that describe the moment, not the situation: never a reason for a decision.
const TRANSIENT_QUERY_CODES: Array[StringName] = [&"action_busy", &"paused", &"battle_unavailable", &"stale_revision", &"service_unavailable"]

## The shared Move query's own answer, so the reason matches what the player's UI would be told:
## either why no move is legal at all, or that legal moves exist but none was worth taking.
func _no_destination_reason() -> String:
	var query := battle_controller.query_move(unit)
	if not query.is_legal():
		# The engine being busy, paused or mid-revision says nothing about the tactical situation.
		if query.validation.code in TRANSIENT_QUERY_CODES:
			return "no destination was worth taking"
		return "no legal destination (%s)" % query.validation.message
	return "%d legal destinations, none worth taking" % query.legal_destination_cells.size()

func _decision_context() -> AIDecisionContext:
	var context := AIDecisionContext.new()
	if _commander_policy != null and _difficulty_policy != null and _policy != null:
		context.commander_composition = _commander_policy.composition_snapshot(_difficulty_policy, _policy)
	context.attack_plan = _last_attack_plan.duplicate()
	context.grid_position = unit.grid_position if is_instance_valid(unit) else Vector3i(-1, -1, -1)
	context.remaining_ap = unit.stats.current_ap if is_instance_valid(unit) and unit.stats else -1
	context.recent_move_origins = _recent_move_origins.duplicate()
	context.consecutive_low_value_actions = _consecutive_low_value_actions
	context.hold_score = _optional_score(_last_hold_score)
	context.move_acceptance_threshold = _optional_score(_last_move_threshold)
	context.urgency_bonus = _last_urgency_bonus
	context.route_corridor = _last_route_corridor
	return context

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
