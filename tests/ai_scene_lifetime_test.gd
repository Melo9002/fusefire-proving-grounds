extends SceneTree
## A yielded activation must stop when its owning battle leaves the scene tree.
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0

class SuspendedAI extends AIController:
	signal resume_decision
	var suspended := false
	func _try_mission_step(_has_moved: bool) -> MissionStepResult:
		suspended = true
		await resume_decision
		return MissionStepResult.NONE

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_overlay_ownership()
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 17
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Real current battlefield initializes")
	var controller := level.battle_controller
	var turns := level.turn_manager
	var actor := turns.active_unit
	for original in level.find_children("*", "AIController", true, false):
		original.free()
	var ai := SuspendedAI.new()
	ai.unit = actor
	ai.battle_controller = controller
	ai.turn_manager = turns
	ai.objective_manager = level.objective_manager
	level.add_child(ai)
	controller.debug_player_ai = true
	ai._execute_turn()
	var deadline := Time.get_ticks_msec() + 3000
	while not ai.suspended and Time.get_ticks_msec() < deadline:
		await process_frame
	check(ai.suspended, "Activation reaches a deterministic asynchronous decision boundary")
	var phase := turns.current_phase
	var ap := actor.stats.current_ap
	var position := actor.grid_position
	root.remove_child(level)
	check(not ai._should_control_unit(), "Detached battle cannot retain AI control of a live unit")
	ai.resume_decision.emit()
	await process_frame
	check(not ai._is_executing, "Detached activation unwinds without getting stuck")
	check(turns.current_phase == phase and turns.active_unit == actor and actor.stats.current_ap == ap and actor.grid_position == position, "Detached continuation cannot act or advance the turn")
	turns.end_current_turn()
	turns._advance_exhausted_unit_if_needed(actor.get_instance_id())
	turns._continue_after_active_unit_removed(true, false, false)
	check(turns.current_phase == phase, "An external stale turn request cannot advance a detached manager")
	level.free()
	await process_frame
	await _check_initial_delay(config)
	print("AI scene lifetime: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_initial_delay(config: BattleConfiguration) -> void:
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	for original in level.find_children("*", "AIController", true, false):
		original.free()
	var ai := SuspendedAI.new()
	ai.unit = level.turn_manager.active_unit
	ai.turn_manager = level.turn_manager
	ai.battle_controller = level.battle_controller
	ai.objective_manager = level.objective_manager
	level.add_child(ai)
	level.battle_controller.debug_player_ai = true
	ai._execute_turn()
	check(ai._is_executing, "Activation really waits in its initial presentation delay")
	root.remove_child(level)
	await create_timer(AIController.ACTIVATION_PRESENTATION_DELAY_SECONDS + 0.1).timeout
	check(not ai._is_executing and not ai.suspended, "An initial timer cannot start a decision after battle removal")
	level.free()
	await process_frame

func _check_overlay_ownership() -> void:
	for overlay in [DebugMapInspector.new(), AIScoringOverlay.new()]:
		var resources: Array = [overlay._zone_mesh, overlay._link_mesh] if overlay is DebugMapInspector else [overlay._position_mesh, overlay._target_mesh, overlay._score_labels]
		var kind: String = overlay.get_script().resource_path.get_file()
		overlay.free()
		check(resources.all(func(node): return not is_instance_valid(node)), "%s frees owned meshes even without entering the tree" % kind)
		for node in resources:
			if is_instance_valid(node): node.free()
