extends SceneTree

const StateFingerprint := preload("res://systems/replay/battle_state_fingerprint.gd")

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	var menu := level.get_node("Visualizers/BattleUI/BattlePauseMenu") as BattlePauseMenu
	var debug := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var camera := level.get_node("CameraRig") as TacticalCamera
	var world_bar := level.find_child("UnitWorldBar", true, false) as UnitWorldBar
	check(is_instance_valid(world_bar), "Battle creates a unit world stats bar")
	check(debug.z_index > world_bar.z_index and menu.z_index > world_bar.z_index, "Debug and pause UI render above world stats bars")
	check(menu.z_index > debug.z_index, "Pause menu remains the highest modal layer")

	menu.set_open(true)
	check(menu.visible and menu.is_open and paused, "Opening the battle menu pauses gameplay")
	check(camera.process_mode != Node.PROCESS_MODE_ALWAYS, "Normal pause also freezes the tactical camera")
	check(menu.has_node("Dimmer/Center/Panel/Margin/Options/ResumeButton"), "Pause menu exposes Resume")
	check(menu.has_node("Dimmer/Center/Panel/Margin/Options/SetupButton"), "Pause menu exposes Return to Match Setup")
	check(menu.has_node("Dimmer/Center/Panel/Margin/Options/ActionCameraOption"), "Pause menu exposes action-camera frequency")
	menu.set_open(false)
	check(not menu.visible and not menu.is_open and not paused, "Resume closes the menu and restores gameplay")

	debug.set_panel_open(true)
	check(debug.panel_open and paused, "F3's debug panel retains its independent pause behavior")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	menu._unhandled_key_input(escape)
	check(not debug.panel_open and menu.is_open and paused, "Esc transfers a debug pause to the options menu")
	menu.set_open(false)

	await _check_enemy_simulation_pause(level, menu)

	level.queue_free()
	await process_frame
	print("Battle pause menu: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_enemy_simulation_pause(level: BattleLevel, menu: BattlePauseMenu) -> void:
	level.turn_manager.end_current_turn()
	check(level.turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN, "Test enters the enemy phase")
	var enemy := level.turn_manager.enemy_units[0]
	var fingerprint_before := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager)
	var world_before := enemy.global_position
	var moving_before := enemy.is_moving
	var action_before := level.battle_controller.is_action_in_progress

	menu.set_open(true)
	await create_timer(1.0).timeout

	var fingerprint_during := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager)
	check(fingerprint_during == fingerprint_before, "Paused enemy turn does not change authoritative battle state")
	check(enemy.global_position.is_equal_approx(world_before), "Paused enemy turn does not move presentation position")
	check(enemy.is_moving == moving_before, "Paused enemy turn does not start movement")
	check(level.battle_controller.is_action_in_progress == action_before, "Paused enemy turn does not start an action")

	menu.set_open(false)
	await create_timer(1.5).timeout
	var fingerprint_after := StateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager)
	check(fingerprint_after != fingerprint_before or enemy.is_moving or level.battle_controller.is_action_in_progress, "Enemy AI resumes after unpausing")
