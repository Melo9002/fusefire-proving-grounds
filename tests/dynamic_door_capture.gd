extends SceneTree
## The dynamic door through the game's own interface (explicit-only, needs a display; automated, not a human playtest):
##   godot_console --path . --script res://tests/dynamic_door_capture.gd -- <directory>
## Match Setup (the Interaction Range selected in its real option list, the battle started through its Start button's signal; synthetic mouse clicks do not reach the menu in this harness), then the battle's own HUD:
## the unit is walked to the door through the controller's move confirmation, the HUD's door button is read (text, enabled, tooltip) and pressed, the committed state is checked on the map, and frames are saved of
## the closed door, the HUD, the open door, the refusal with a unit in the doorway, and the door closed again. Everything printed is read from the running game.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
var _directory := ""
var _steps := 0
var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_steps += 1
	if not ok:
		_fails += 1
	print("STEP %02d %s %s %s" % [_steps, "ok  " if ok else "FAIL", label, detail])


func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_directory, name])


func _run() -> void:
	_directory = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_directory)
	var menu: Node = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.8).timeout
	var index := -1
	for i in menu.map_size_option.item_count:
		if StringName(menu.map_size_option.get_item_metadata(i)) == Catalog.INTERACTION_RANGE:
			index = i
	_check("Match Setup lists the Interaction Range", index >= 0, menu.map_size_option.get_item_text(index) if index >= 0 else "")
	menu.map_size_option.select(index)
	menu._on_battlefield_selected(index)
	menu.seed_input.value = 2   # even seeds: the door starts closed
	menu.start_button.pressed.emit()
	var level: BattleLevel = null
	var waited := 0.0
	while waited < 30.0:
		await create_timer(0.5).timeout
		waited += 0.5
		if current_scene != null and current_scene is BattleLevel and (current_scene as BattleLevel).battle_initialization_succeeded:
			level = current_scene as BattleLevel
			break
	_check("The battle started from Match Setup", level != null)
	if level == null:
		quit(1)
		return
	await create_timer(1.0).timeout
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var battle := level.battle_controller
	var service := battle.action_service
	var map := battle.grid_manager.map_data
	var unit := level.turn_manager.player_units[0]
	var hud := level.find_child("ActionHUDController", true, false) as ActionHUDController
	var door: DoorData = map.doors[&"door_a"]
	var rig := level.get_node("CameraRig") as TacticalCamera
	_check("The door is closed at the start and the HUD shows no door button yet", door.state == DoorData.CLOSED and hud.door_button != null and not hud.door_button.visible, "state %s" % door.state)
	rig.global_position = battle.grid_manager.grid_to_world(Vector3i(7, 0, 12))
	rig._set_zoom(14.0)
	await create_timer(0.8).timeout
	await _snap("01_closed_overview")
	# Walk to the door: the controller's move confirmation (what the Move button's confirmation calls).
	battle.is_move_mode_active = true
	await battle.confirm_player_action(&"move", unit, null, Vector3i(7, 0, 11))
	var waited_move := 0.0
	while battle.is_action_in_progress and waited_move < 15.0:
		await create_timer(0.1).timeout
		waited_move += 0.1
	await create_timer(0.6).timeout
	_check("The unit stands in front of the door", battle.grid_manager.get_unit_grid(unit) == Vector3i(7, 0, 11), str(battle.grid_manager.get_unit_grid(unit)))
	hud._update_button_states()
	await create_timer(0.5).timeout
	var ap_before := unit.stats.current_ap
	_check("The HUD offers the door: a visible, enabled button that says what it does", hud.door_button.visible and not hud.door_button.disabled and hud.door_button.text == "Open door", "'%s' tooltip '%s'" % [hud.door_button.text, hud.door_button.tooltip_text])
	rig.global_position = battle.grid_manager.grid_to_world(Vector3i(7, 0, 12))
	await create_timer(0.5).timeout
	await _snap("02_hud_open_door_offered")
	var revision_before := service.state_revision
	hud.door_button.pressed.emit()
	await create_timer(1.8).timeout
	_check("Pressing it opens the door through the action service: one committed action, no AP spent", door.state == DoorData.OPEN and service.state_revision == revision_before + 1 and unit.stats.current_ap == ap_before, "state %s revision %d->%d AP %d->%d" % [door.state, revision_before, service.state_revision, ap_before, unit.stats.current_ap])
	var presenter := level.get_node_or_null("DoorPresenter") as DoorPresenter
	var label := level.find_child("DoorLabel_door_a", true, false) as Label3D
	_check("The door's own label and leaf follow the committed state", presenter != null and label != null and label.text.contains("OPEN"), label.text if label else "no label")
	await create_timer(0.4).timeout
	await _snap("03_open")
	_check("The HUD now offers to close it", hud.door_button.visible and hud.door_button.text == "Close door", "'%s'" % hud.door_button.text)
	# A refusal the player can read: a unit stands in the doorway.
	var enemy := level.turn_manager.enemy_units[0]
	battle.grid_manager.update_unit_position(enemy, battle.grid_manager.get_unit_grid(enemy), Vector3i(7, 0, 12))
	enemy.global_position = battle.grid_manager.grid_to_world(Vector3i(7, 0, 12)) + Vector3.UP * enemy.standing_height
	await create_timer(0.5).timeout
	hud._update_button_states()
	await create_timer(0.5).timeout
	_check("With a unit in the doorway the close button is disabled and says why", hud.door_button.disabled and hud.door_button.tooltip_text.contains("doorway"), "tooltip '%s'" % hud.door_button.tooltip_text)
	await _snap("04_refused_unit_in_doorway")
	battle.grid_manager.update_unit_position(enemy, Vector3i(7, 0, 12), Vector3i(7, 0, 17))
	enemy.global_position = battle.grid_manager.grid_to_world(Vector3i(7, 0, 17)) + Vector3.UP * enemy.standing_height
	await create_timer(0.5).timeout
	hud._update_button_states()
	await create_timer(0.3).timeout
	hud.door_button.pressed.emit()
	await create_timer(1.8).timeout
	_check("The door closes again from the same button", door.state == DoorData.CLOSED, "state %s" % door.state)
	await _snap("05_closed_again")
	print("DOOR CAPTURE %d steps, %d failed" % [_steps, _fails])
	quit(1 if _fails > 0 else 0)
