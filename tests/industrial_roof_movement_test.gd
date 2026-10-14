extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.industrial_warehouse = true
	config.map_size = Vector2i(40, 30)
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(config)
	root.add_child(battle)
	while battle.turn_manager.current_round == 0:
		await process_frame
	var actor := battle.turn_manager.active_unit
	var grid := battle.battle_controller.grid_manager
	var layout = IndustrialWarehouseLayoutBuilder
	grid.update_unit_position(actor, actor.grid_position, layout.ROOF_LADDER_BOTTOM)
	actor.global_position = grid.get_cell_data(layout.ROOF_LADDER_BOTTOM).world_position + Vector3.UP * actor.standing_height
	actor.movement_speed = 12
	var service := battle.battle_controller.action_service
	var before := actor.stats.current_ap
	var move = await service.submit_move(service.make_move_request(actor, layout.ROOF_LADDER_TOP, TacticalActionRequest.Source.PLAYER), true)
	check(move != null, "Authoritative Move can climb the roof ladder")
	check(actor.grid_position == layout.ROOF_LADDER_TOP and actor.stats.current_ap == before - 1, "Climb changes elevation and spends exactly one AP")
	var rig := battle.get_node("CameraRig") as TacticalCamera
	rig._cancel_selection_focus()
	rig.set_process(false)
	var roof: WarehouseRoofCutaway = get_nodes_in_group("tactical_roof_cutaways")[0]
	rig._update_camera_occlusion()
	check(roof.visible, "Selected rooftop actor keeps roof visible")
	rig.inspect_floor(roof.global_position + Vector3(0, 0, 0))
	rig._update_camera_occlusion()
	check(not roof.visible, "Explicit interior inspection cuts away roof")
	rig.inspect_floor(roof.global_position + Vector3.UP * layout.ROOF_LEVEL)
	rig._update_camera_occlusion()
	check(roof.visible, "Explicit rooftop inspection restores roof")
	# Exercise actual stacked collider picking, not just cutaway arithmetic.
	rig.camera.global_position = Vector3(-1, 15, -3)
	rig.camera.look_at(Vector3(-1, 0, -3), Vector3.FORWARD)
	await physics_frame
	await physics_frame
	var picker := battle.get_node("Systems/MouseRaycaster") as MouseRaycaster
	var screen := rig.camera.unproject_position(Vector3(-1, 0, -3))
	var candidates := picker.get_floor_candidates(screen)
	check(candidates.size() >= 2, "Roof and interior both have selectable physics surfaces")
	var hit := picker.get_floor_raycast_result(screen)
	check(not hit.is_empty() and hit.grid_position.y == layout.ROOF_LEVEL, "Rooftop inspection selects rooftop destinations")
	picker.cycle_surface(1, screen)
	hit = picker.get_floor_raycast_result(screen)
	check(not hit.is_empty() and hit.grid_position.y == 0, "Alt-wheel surface cycling selects interior ground")
	rig._update_camera_occlusion()
	check(not roof.visible, "Surface picker updates camera cutaway")
	picker.cycle_surface(-1, screen)
	rig._update_camera_occlusion()
	check(roof.visible, "Surface picker restores roof inspection")
	picker._inspect_level(0.0)
	check(picker._level_panel.visible and picker._level_label.text.contains("Ground"), "Persistent UI identifies the inspected ground level")
	var wall_point := grid.get_cell_data(Vector3i(12, 0, 5)).world_position
	rig.camera.global_position = wall_point + Vector3.UP * 15
	rig.camera.look_at(wall_point, Vector3.FORWARD)
	screen = rig.camera.unproject_position(wall_point)
	hit = picker.get_floor_raycast_result(screen)
	check(hit.is_empty(), "No roof fallback when the lower cell beneath the cursor is blocked")
	picker.cycle_surface(1, screen)
	hit = picker.get_floor_raycast_result(screen)
	check(not hit.is_empty() and hit.grid_position.y == layout.ROOF_LEVEL, "Explicit upper-floor cycling still exposes roof destinations")
	picker._update_level_panel()
	check(picker._level_label.text.contains("Roof"), "UI updates after explicit floor cycling")
	move = await service.submit_move(service.make_move_request(actor, layout.ROOF_LADDER_BOTTOM, TacticalActionRequest.Source.PLAYER), true)
	check(move != null and actor.grid_position == layout.ROOF_LADDER_BOTTOM, "Authoritative Move can descend the roof ladder")
	battle.queue_free()
	await process_frame
	print("Industrial roof movement: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
