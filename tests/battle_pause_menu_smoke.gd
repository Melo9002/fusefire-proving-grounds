extends SceneTree

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

	menu.set_open(true)
	check(menu.visible and menu.is_open and paused, "Opening the battle menu pauses gameplay")
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

	level.queue_free()
	await process_frame
	print("Battle pause menu: %d failure(s)" % failures)
	quit(1 if failures else 0)
