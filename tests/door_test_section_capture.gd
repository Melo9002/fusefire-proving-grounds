extends SceneTree
## The Tactical Test Range's environmental interaction section through the game's own interface (explicit-only, needs a display; automated, not a human playtest):
##   godot_console --path . --script res://tests/door_test_section_capture.gd -- <directory>
## Match Setup (the range selected in its real option list, the battle started through its Start button's signal), then the battle's own HUD: the door button is read (text, enabled, tooltip) and pressed for each of
## the two doors, the committed state is checked on the map, and frames are saved. The unit is placed at each doorway's approach cell (deployment to the section is a separate on-foot reachability check in
## door_test_section_test; the range's move range is shorter than the walk).
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


func _place(level: BattleLevel, unit: TacticalUnit, cell: Vector3i) -> void:
	var grid := level.battle_controller.grid_manager
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height


func _overhead(rig: TacticalCamera, level: BattleLevel, cell: Vector3i, zoom: float) -> void:
	rig._manual_pitch = true
	rig.rotation.x = -deg_to_rad(72.0)
	rig.global_position = level.battle_controller.grid_manager.grid_to_world(cell)
	rig._set_zoom(zoom)
	await create_timer(0.8).timeout


func _run() -> void:
	_directory = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_directory)
	var menu: Node = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.8).timeout
	var index := -1
	for i in menu.map_size_option.item_count:
		if StringName(menu.map_size_option.get_item_metadata(i)) == Catalog.TACTICAL_TEST_RANGE:
			index = i
	_check("Match Setup lists the Tactical Test Range", index >= 0, menu.map_size_option.get_item_text(index) if index >= 0 else "")
	menu.map_size_option.select(index)
	menu._on_battlefield_selected(index)
	menu.seed_input.value = 5
	menu.start_button.pressed.emit()
	var level: BattleLevel = null
	var waited := 0.0
	while waited < 40.0:
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
	var enemy := level.turn_manager.enemy_units[0]
	var hud := level.find_child("ActionHUDController", true, false) as ActionHUDController
	var rig := level.get_node("CameraRig") as TacticalCamera
	var north: DoorData = map.doors[&"door_north"]
	var south: DoorData = map.doors[&"door_south"]
	_check("Two doors, both closed at the start, HUD shows no door button yet", map.doors.size() == 2 and north.state == DoorData.CLOSED and south.state == DoorData.CLOSED and not hud.door_button.visible)
	await _overhead(rig, level, Vector3i(11, 0, 19), 26.0)
	await _snap("01_section_closed")
	# North door through the HUD.
	_place(level, unit, Vector3i(11, 0, 16))
	hud._update_button_states()
	await create_timer(0.5).timeout
	var ap_before := unit.stats.current_ap
	_check("At the north approach the HUD offers 'Open door' (enabled, with a tooltip)", hud.door_button.visible and not hud.door_button.disabled and hud.door_button.text == "Open door", "'%s' tooltip '%s'" % [hud.door_button.text, hud.door_button.tooltip_text])
	await _snap("02_hud_offers_north_door")
	var revision := service.state_revision
	hud.door_button.pressed.emit()
	await create_timer(1.8).timeout
	_check("Pressing it opens only the north door, costs no AP, advances the revision once", north.state == DoorData.OPEN and south.state == DoorData.CLOSED and unit.stats.current_ap == ap_before and service.state_revision == revision + 1, "north %s south %s AP %d->%d" % [north.state, south.state, ap_before, unit.stats.current_ap])
	await _snap("03_north_open")
	await _overhead(rig, level, Vector3i(11, 0, 19), 26.0)
	await _snap("03b_north_open_overhead")
	# South door through the HUD.
	_place(level, unit, Vector3i(11, 0, 22))
	hud._update_button_states()
	await create_timer(0.5).timeout
	_check("At the south approach the HUD offers the south door", hud.door_button.visible and hud.door_button.text == "Open door" and not hud.door_button.disabled)
	hud.door_button.pressed.emit()
	await create_timer(1.8).timeout
	_check("Both doors are now open, each by its own press", north.state == DoorData.OPEN and south.state == DoorData.OPEN)
	await _snap("04_both_open")
	await _overhead(rig, level, Vector3i(11, 0, 19), 26.0)
	await _snap("04b_both_open_overhead")
	# A refusal the player can read: a unit stands where the south leaf would swing... close first, then obstruct.
	hud.door_button.pressed.emit()
	await create_timer(1.8).timeout
	_check("The same button now closes the south door", south.state == DoorData.CLOSED and north.state == DoorData.OPEN)
	_place(level, enemy, Vector3i(12, 0, 20))
	await create_timer(0.4).timeout
	hud._update_button_states()
	await create_timer(0.5).timeout
	_check("A unit inside where the leaf swings disables the button and says why", hud.door_button.disabled and hud.door_button.tooltip_text.length() > 0, "tooltip '%s'" % hud.door_button.tooltip_text)
	await _snap("05_refused_leaf_obstructed")
	_place(level, enemy, Vector3i(1, 0, 2))
	# Window and routes: an oblique view from the east, north door open.
	await _overhead(rig, level, Vector3i(12, 0, 19), 16.0)
	await _snap("06_window_and_ring")
	print("SECTION CAPTURE %d steps, %d failed" % [_steps, _fails])
	quit(1 if _fails > 0 else 0)
