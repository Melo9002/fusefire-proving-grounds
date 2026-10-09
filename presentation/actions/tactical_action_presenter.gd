class_name TacticalActionPresenter
extends Node

## Presents already-committed tactical action results. This script may move
## visual transforms and drive cameras/animation, but never changes gameplay.

var actor_registry: TacticalActorRegistry
var grid_manager: GridManager
var action_camera_director: ActionCameraDirector
var replay_mode_provider: Callable
var attack_feedback: Callable
var extracted_actor_cleanup: Callable

func setup(
	registry: TacticalActorRegistry,
	grid: GridManager,
	camera_director: ActionCameraDirector,
	is_replay_mode: Callable,
	attack_feedback_callback: Callable,
	extraction_cleanup_callback: Callable
) -> void:
	actor_registry = registry
	grid_manager = grid
	action_camera_director = camera_director
	replay_mode_provider = is_replay_mode
	attack_feedback = attack_feedback_callback
	extracted_actor_cleanup = extraction_cleanup_callback

func present_attack(result: AttackActionResult) -> void:
	var attacker := _actor(result.request.actor_id)
	var target := _actor(result.request.target_id)
	if not is_instance_valid(attacker):
		result.presentation_error = "Attack presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed:
		if result.target_defeated and is_instance_valid(target): target.queue_free()
		return
	var camera_presented := false
	if _camera_available():
		camera_presented = await action_camera_director.present(attacker, &"attack", result.target_position, result.actor_ap_after, result.target_defeated)
	if not is_instance_valid(attacker):
		result.presentation_error = "Attack actor left the scene during presentation"
		await _finish_camera(camera_presented)
		return
	attacker.present_attack(result.target_position)
	if result.did_hit and is_instance_valid(target):
		target.present_attack_impact(result.target_defeated)
		if result.target_defeated: target.finish_defeat_presentation()
	if attack_feedback.is_valid(): attack_feedback.call(attacker, target, result.did_hit, result.hit_chance)
	if camera_presented:
		await _safe_delay(0.42)
		await _finish_camera(true)

func present_move(result: MoveActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Move presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed:
		_snap_to_committed_destination(unit, result)
		return
	var camera_presented := false
	if _camera_available():
		camera_presented = await action_camera_director.present(unit, &"move", grid_manager.grid_to_world(result.target_cell), result.actor_ap_after)
	if not is_instance_valid(unit):
		result.presentation_error = "Move actor left the scene before traversal"
		await _finish_camera(camera_presented)
		return
	unit.move_along_path(result.presentation_path, result.visual_segments)
	await _wait_for_movement(unit, result)
	if is_instance_valid(unit): _snap_to_committed_destination(unit, result)
	else: result.presentation_error = "Move actor left the scene during traversal"
	await _finish_camera(camera_presented)

func present_simple(result: SimpleActionResult) -> void:
	var unit := _actor(result.request.actor_id)
	if not is_instance_valid(unit):
		result.presentation_error = "Presenter could not find actor '%s'" % result.request.actor_id
		return
	if result.presentation_suppressed: return
	if result.request.kind == &"wait":
		print_rich("[color=slate_gray][WaitAction][/color] %s ends activation — %s" % [unit.name, result.request.details.get("reason", "No useful action available.")])
		return
	var camera_presented := false
	if _camera_available():
		var facing := unit.visual_adapter.global_basis.z if is_instance_valid(unit.visual_adapter) else Vector3.FORWARD
		camera_presented = await action_camera_director.present(unit, &"defend", unit.global_position + facing * 3.0, result.actor_ap_after)
	if camera_presented:
		await _safe_delay(0.25)
		await _finish_camera(true)

func present_mission(result: MissionActionResult, actor: TacticalUnit, _target: TacticalUnit) -> void:
	if result.request.kind == &"extract":
		await _present_extract(result, actor)
		if extracted_actor_cleanup.is_valid(): extracted_actor_cleanup.call(actor)
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

func _present_extract(result: MissionActionResult, actor: TacticalUnit) -> void:
	if result.presentation_suppressed: return
	if not is_instance_valid(actor):
		result.presentation_error = "Extract presenter could not find actor '%s'" % result.request.actor_id
		return
	var camera_presented := false
	if _camera_available():
		var facing := actor.visual_adapter.global_basis.z if is_instance_valid(actor.visual_adapter) else Vector3.FORWARD
		camera_presented = await action_camera_director.present(actor, &"extract", actor.global_position + facing * 3.0, actor.stats.current_ap, true)
	if is_instance_valid(actor) and is_instance_valid(actor.visual_adapter):
		actor.visual_adapter.present_boarding()
		await _safe_delay(0.6)
	await _finish_camera(camera_presented)

func _snap_to_committed_destination(unit: TacticalUnit, result: MoveActionResult) -> void:
	if not result.presentation_path.is_empty(): unit.global_position = result.presentation_path[-1]
	elif is_instance_valid(grid_manager): unit.global_position = grid_manager.grid_to_world(result.target_cell)

func _actor(actor_id: StringName) -> TacticalUnit:
	return actor_registry.resolve(actor_id) if is_instance_valid(actor_registry) else null

func _camera_available() -> bool:
	return is_instance_valid(action_camera_director) and not (replay_mode_provider.is_valid() and replay_mode_provider.call())

func _safe_delay(seconds: float) -> void:
	if is_inside_tree() and get_tree(): await get_tree().create_timer(seconds, false).timeout

func _wait_for_movement(unit: TacticalUnit, result: MoveActionResult) -> void:
	# Polling also observes scene teardown; awaiting movement_finished alone could
	# strand the action barrier if the visual actor disappears mid-traversal.
	var deadline := Time.get_ticks_msec() + 30000
	while is_instance_valid(unit) and unit.is_moving and is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(unit) and unit.is_moving:
		result.presentation_error = "Movement presentation timed out; snapped to committed destination"
		unit.is_moving = false

func _finish_camera(was_presented: bool) -> void:
	if was_presented and is_instance_valid(action_camera_director): await action_camera_director.finish_live_presentation(true)
