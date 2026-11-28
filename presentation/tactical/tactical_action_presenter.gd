class_name TacticalActionPresenter
extends Node

## Presents already-committed tactical action results. This script may move
## visual transforms and drive cameras/animation, but never changes gameplay.

var actor_registry: TacticalActorRegistry
var grid_manager: GridManager
var action_camera_director: ActionCameraDirector
var replay_mode_provider: Callable
var attack_feedback: Callable

func setup(
	registry: TacticalActorRegistry,
	grid: GridManager,
	camera_director: ActionCameraDirector,
	is_replay_mode: Callable,
	attack_feedback_callback: Callable
) -> void:
	actor_registry = registry
	grid_manager = grid
	action_camera_director = camera_director
	replay_mode_provider = is_replay_mode
	attack_feedback = attack_feedback_callback

func present_attack(result: AttackActionResult) -> void:
	var attacker := _actor(result.request.actor_id)
	var target := _actor(result.request.target_id)
	if not is_instance_valid(attacker):
		result.presentation_error = "Attack presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed:
		if result.target_defeated and is_instance_valid(target): target.queue_free()
		for event in result.reaction_events:
			if event.target_defeated and is_instance_valid(attacker):
				attacker.queue_free()
				break
		return
	var camera_presented := false
	if _camera_available():
		camera_presented = await _present_attack_camera(attacker, target, result.target_position, result.actor_ap_after, result.target_defeated, result.firing_solution)
	if not is_instance_valid(attacker):
		result.presentation_error = "Attack actor left the scene during presentation"
		await _finish_camera(camera_presented)
		return
	await _present_firing_solution(attacker, result.target_position, result.firing_solution,
		_show_attack_impact.bind(attacker, target, result.did_hit, result.hit_chance, result.target_defeated))
	for condition_event in result.condition_events:
		print_rich("[color=sky_blue][Condition][/color] %s applied to %s" % [condition_event.get("condition_id", ""), condition_event.get("target_id", "")])
	for event in result.reaction_events:
		if not is_instance_valid(target): break
		var focus := attacker.global_position if is_instance_valid(attacker) else result.target_position
		if _camera_available():
			camera_presented = await _present_attack_camera(target, attacker, focus, 0, true, event.firing_solution) or camera_presented
		if not is_instance_valid(target): break
		await _present_firing_solution(target, focus, event.firing_solution,
			_show_attack_impact.bind(target, attacker, event.did_hit, event.hit_chance, event.target_defeated))
		print_rich("[color=orange][Guard Return][/color] %s -> %s: %s (%d%%)" % [event.watcher_id, result.request.actor_id, "HIT %d" % event.damage if event.did_hit else "MISS", event.hit_chance])
		await _safe_delay(0.18)
	if camera_presented:
		await _safe_delay(0.42)
		await _finish_camera(true)

func _present_firing_solution(actor: TacticalUnit, target_world: Vector3, solution: CombatRules.FiringSolution, show_impact: Callable) -> void:
	if solution and solution.body_offset != Vector3.ZERO and is_instance_valid(actor.visual_adapter):
		await actor.visual_adapter.present_contextual_attack(solution.body_offset, solution.facing_point, show_impact)
	else:
		await _wait_for_shot(actor.present_attack(target_world))
		show_impact.call()

func _show_attack_impact(actor: TacticalUnit, target: TacticalUnit, hit: bool, chance: int, defeated: bool) -> void:
	if hit and is_instance_valid(target):
		target.present_attack_impact(defeated)
		if defeated: target.finish_defeat_presentation()
	if attack_feedback.is_valid(): attack_feedback.call(actor, target, hit, chance)

func _present_attack_camera(actor: TacticalUnit, target: TacticalUnit, target_world: Vector3, ap_after: int, important: bool, solution: CombatRules.FiringSolution) -> bool:
	var subject := _attack_camera_subject(actor, target)
	var focus := actor.global_position if subject == target else target_world
	if solution and solution.body_offset != Vector3.ZERO and actor.is_visible_in_tree() and is_instance_valid(target) and target.is_visible_in_tree():
		if action_camera_director.should_present_for_faction(subject.faction, &"attack", ap_after, important):
			return await action_camera_director.present(actor, &"attack", target_world, ap_after, important, true, solution.body_offset)
	return await action_camera_director.present(subject, &"attack", focus, ap_after, important)

func present_reload(result: ReloadActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Reload presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed:
		return
	var camera_presented := false
	if _camera_available():
		var facing := unit.visual_adapter.rig.global_basis.z if is_instance_valid(unit.visual_adapter) else Vector3.FORWARD
		camera_presented = await action_camera_director.present(unit, &"reload", unit.global_position + facing * 3.0, result.actor_ap_after)
	print_rich("[color=light_blue][Reload][/color] %s restores %d SP (%d/%d)" % [unit.get_log_name(), result.supply_points_restored, result.supply_points_after, result.max_supply_points])
	if camera_presented:
		await _safe_delay(0.25)
		await _finish_camera(true)

func present_aim(result: AimActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Aim presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed:
		return
	print_rich("[color=gold][Aim][/color] %s prepares the next shot (+%d)" % [unit.get_log_name(), result.accuracy_bonus])
	# Sights up now; they stay up for as long as the committed Aim lasts.
	unit.present_aim()
	await _safe_delay(0.3)

func present_shield(result: ShieldActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Shield presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed:
		return
	var threat := _actor(result.request.target_id)
	if unit.tactical_state != null and unit.tactical_state.is_shielding and not unit.tactical_state.shield_facing.is_zero_approx():
		unit.face_committed_direction(unit.tactical_state.shield_facing)   # the stance's committed facing, shown exactly as gameplay supplied it
	elif is_instance_valid(threat):
		unit.face_world_position(threat.global_position)
	# Shield-specific animation is deferred. Authoritative state remains visible
	# in the HUD and combat diagnostics while the normal idle pose is safe.
	print_rich("[color=cyan][Shield][/color] %s protects a %.0f degree arc" % [unit.get_log_name(), result.protected_arc_degrees])
	await _safe_delay(0.2)

func present_overwatch(result: OverwatchActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Guard presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed: return
	print_rich("[color=orange][Guard][/color] %s reserves a reaction shot (%d SP ready)" % [unit.get_log_name(), result.supply_points_before])
	await _safe_delay(0.2)

func present_move(result: MoveActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not _move_actor_available(unit):
		result.presentation_error = "Move presenter could not find actor '%s'" % result.request.actor_id
		_present_passenger_release(unit, result)
		return
	if result.presentation_suppressed:
		_snap_to_committed_destination(unit, result)
		_present_passenger_release(unit, result)
		return
	var camera_presented := false
	if _camera_available():
		camera_presented = await action_camera_director.present(unit, &"move", grid_manager.grid_to_world(result.target_cell), result.actor_ap_after)
	if not _move_actor_available(unit):
		result.presentation_error = "Move actor left the scene before traversal"
		_present_passenger_release(unit, result)
		await _finish_camera(camera_presented)
		return
	if result.reaction_events.is_empty():
		unit.move_along_path(result.presentation_path, result.visual_segments)
		await _wait_for_movement(unit, result)
		await _wait_for_rescue_interaction(unit)   # a rescue decided by this move is lifted on arrival; the next command waits for it
	else:
		camera_presented = await _present_reactive_move(unit, result) or camera_presented
	_present_passenger_release(unit, result)
	if is_instance_valid(unit): _snap_to_committed_destination(unit, result)
	else: result.presentation_error = "Move actor left the scene during traversal"
	await _finish_camera(camera_presented)

func _present_reactive_move(unit: TacticalUnit, result: MoveActionResult) -> bool:
	var reactions_by_checkpoint := {}
	for event in result.reaction_events:
		if not reactions_by_checkpoint.has(event.checkpoint_index): reactions_by_checkpoint[event.checkpoint_index] = []
		reactions_by_checkpoint[event.checkpoint_index].append(event)
	var reaction_camera_used := false
	var index := 1
	while index < result.presentation_path.size():
		if not _move_actor_available(unit): return reaction_camera_used
		# Walk on to the next checkpoint a watcher reacts at (or the end) in ONE order: a stair or ladder run between reactions stays whole, so its feet and contacts are continuous.
		var last := index
		while last < result.presentation_path.size() - 1 and not reactions_by_checkpoint.has(last):
			last += 1
		var segment := PackedVector3Array([unit.global_position])
		var poses: Array[StringName] = [&"move"]
		for point_index in range(index, last + 1):
			segment.append(result.presentation_path[point_index])
			poses.append(result.visual_segments[point_index] if point_index < result.visual_segments.size() else &"move")
		unit.move_along_path(segment, poses)
		await _wait_for_movement(unit, result)
		await _wait_for_rescue_interaction(unit)   # a rescue decided by this move is lifted on arrival; the next command waits for it
		if not _move_actor_available(unit): return reaction_camera_used
		for event in reactions_by_checkpoint.get(last, []):
			var watcher := _actor(event.watcher_id)
			if not reaction_camera_used and is_instance_valid(watcher) and _camera_available():
				reaction_camera_used = await _present_attack_camera(watcher, unit, unit.global_position, 0, true, event.firing_solution)
			if not _move_actor_available(unit): return reaction_camera_used
			if is_instance_valid(watcher):
				await _present_firing_solution(watcher, unit.global_position, event.firing_solution,
					_present_move_impact.bind(watcher, unit, event, result))
			print_rich("[color=orange][Guard][/color] %s -> %s: %s (%d%%)" % [event.watcher_id, result.request.actor_id, "HIT %d" % event.damage if event.did_hit else "MISS", event.hit_chance])
			if event.target_defeated:
				return reaction_camera_used
			await _safe_delay(0.18)
		index = last + 1
	return reaction_camera_used

func _present_move_impact(watcher: TacticalUnit, mover: TacticalUnit, event: OverwatchReactionEvent, result: MoveActionResult) -> void:
	if event.target_defeated:
		_present_passenger_release(mover, result)
	_show_attack_impact(watcher, mover, event.did_hit, event.hit_chance, event.target_defeated)

func _present_passenger_release(carrier: TacticalUnit, result: MoveActionResult) -> void:
	if not result.passenger_release_pending:
		return
	result.passenger_release_pending = false
	if is_instance_valid(carrier):
		carrier.present_carry_release()
	if is_instance_valid(result.released_passenger):
		result.released_passenger.present_released_passenger()

func present_simple(result: SimpleActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed: return
	if result.request.kind == &"emergency_seal":
		print_rich("[color=sky_blue][Emergency Seal][/color] %s seals the leak (%d charge(s) remain)" % [unit.get_log_name(), result.charges_after])
		await _safe_delay(0.2)
		return
	if result.request.kind == &"wait":
		print_rich("[color=slate_gray][WaitAction][/color] %s ends activation — %s" % [unit.get_log_name(), result.request.details.get("reason", "No useful action available.")])
		return
	var camera_presented := false
	if _camera_available():
		var facing := unit.visual_adapter.rig.global_basis.z if is_instance_valid(unit.visual_adapter) else Vector3.FORWARD
		camera_presented = await action_camera_director.present(unit, &"defend", unit.global_position + facing * 3.0, result.actor_ap_after)
	if camera_presented:
		await _safe_delay(0.25)
		await _finish_camera(true)

func present_mission(result: MissionActionResult, actor: TacticalUnit, _target: TacticalUnit) -> void:
	if result.request.kind == &"interact_terminal":
		if result.presentation_suppressed: return
		if not is_instance_valid(actor):
			result.presentation_error = "Terminal presenter could not find actor '%s'" % result.request.actor_id
			return
		var terminal_camera_presented := false
		if _camera_available(): terminal_camera_presented = await action_camera_director.present(actor, &"interact_terminal", result.target_position, actor.stats.current_ap, true)
		await _safe_delay(0.25)
		await _finish_camera(terminal_camera_presented)
		return
	if result.request.kind == &"extract":
		await _present_extract(result, actor)
		_cleanup_extracted_actor(actor)
		return
	if result.presentation_suppressed: return
	if not is_instance_valid(actor):
		result.presentation_error = "Rescue presenter could not find actor '%s'" % result.request.actor_id
		return
	var camera_presented := false
	if _camera_available(): camera_presented = await action_camera_director.present(actor, &"rescue", result.target_position, actor.stats.current_ap, true)
	if camera_presented:
		await _safe_delay(0.3)
		await _finish_camera(true)
	await _wait_for_rescue_interaction(actor)

## The rescue is already decided; this only keeps the next command from cutting the carrier's lift short. It observes the lift's presentation handle (which settles when the lift ends, is run to its end,
## or is interrupted because the carrier fell or was freed) and never changes the result. Bounded by the lift's length, as before.
func _wait_for_rescue_interaction(actor: TacticalUnit) -> void:
	if not is_inside_tree() or not is_instance_valid(actor) or not is_instance_valid(actor.visual_adapter):
		return
	var adapter: TacticalCharacterAdapter = actor.visual_adapter
	var handle: ActionHandle = adapter.rig.rescue_presentation()
	if handle == null:
		return
	var deadline := Time.get_ticks_msec() + int((adapter.rig.rescue_interaction.duration() + 0.5) * 1000.0)
	while is_inside_tree() and not handle.is_done() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _present_extract(result: MissionActionResult, actor: TacticalUnit) -> void:
	if result.presentation_suppressed: return
	if not is_instance_valid(actor):
		result.presentation_error = "Extract presenter could not find actor '%s'" % result.request.actor_id
		return
	var camera_presented := false
	if _camera_available():
		var facing := actor.visual_adapter.rig.global_basis.z if is_instance_valid(actor.visual_adapter) else Vector3.FORWARD
		camera_presented = await action_camera_director.present(actor, &"extract", actor.global_position + facing * 3.0, actor.stats.current_ap, true)
	if is_instance_valid(actor) and is_instance_valid(actor.visual_adapter):
		actor.visual_adapter.present_boarding()
		await _safe_delay(0.6)
	await _finish_camera(camera_presented)

func _cleanup_extracted_actor(actor: TacticalUnit) -> void:
	if not is_instance_valid(actor):
		return
	if is_instance_valid(actor_registry):
		actor_registry.unregister_actor(actor)
	actor.queue_free()

func _move_actor_available(unit: TacticalUnit) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion()

func _snap_to_committed_destination(unit: TacticalUnit, result: MoveActionResult) -> void:
	if not _move_actor_available(unit):
		result.presentation_error = "Move actor left the scene during traversal"
		return
	if not result.presentation_path.is_empty(): unit.global_position = result.presentation_path[-1]
	elif is_instance_valid(grid_manager): unit.global_position = grid_manager.grid_to_world(result.target_cell)

func _actor(actor_id: StringName) -> TacticalUnit:
	return actor_registry.resolve(actor_id) if is_instance_valid(actor_registry) else null

func _attack_camera_subject(attacker: TacticalUnit, target: TacticalUnit) -> TacticalUnit:
	if is_instance_valid(attacker) and attacker.faction == TacticalUnit.Faction.ENEMY and is_instance_valid(target) and target.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY]:
		return target
	return attacker

func _camera_available() -> bool:
	return is_instance_valid(action_camera_director) and not (replay_mode_provider.is_valid() and replay_mode_provider.call())

## The attack was resolved before it was shown. Its target reacts when the shot is visible, not when the
## attacker starts raising the weapon. The presenter bounds the raise itself; the deadline only guards
## against a character that stops processing. The shot handle settles when the shot is shown, when the attack
## is ended by something newer (a hit, a defeat) or when the character is removed; it never changes the result.
func _wait_for_shot(attack: AttackHandle) -> void:
	if attack == null or not is_inside_tree():
		return
	var deadline := Time.get_ticks_msec() + 3000
	while not attack.shot.is_done() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _safe_delay(seconds: float) -> void:
	if is_inside_tree() and get_tree(): await get_tree().create_timer(seconds, false).timeout

func _wait_for_movement(unit: TacticalUnit, result: MoveActionResult) -> void:
	# Polling also observes scene teardown; awaiting movement_finished alone could
	# strand the action barrier if the visual actor disappears mid-traversal.
	# 30 s, or three times the walk's own estimated presentation time when that is longer (a slow ladder or stair, a slow replay speed).
	var deadline := Time.get_ticks_msec() + int(maxf(30.0, 3.0 * unit.estimated_move_seconds()) * 1000.0) if is_instance_valid(unit) else Time.get_ticks_msec()
	while _move_actor_available(unit) and unit.is_moving and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _move_actor_available(unit):
		result.presentation_error = "Move actor left the scene during traversal"
		return
	if is_instance_valid(unit) and unit.is_moving:
		result.presentation_error = "Movement presentation timed out; snapped to committed destination"
		unit.is_moving = false
		if is_instance_valid(unit.visual_adapter):
			unit.visual_adapter.finish_movement_traversal()

func _finish_camera(was_presented: bool) -> void:
	if was_presented and is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(action_camera_director) and action_camera_director.is_inside_tree() and not action_camera_director.is_queued_for_deletion():
		await action_camera_director.finish_live_presentation(true)
