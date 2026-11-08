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
	var objectives := picker.objective_hud as ObjectiveHUD
	objectives.objective_label.text = "RESCUE VIP — COMPLETE\nEXTRACT VIP — ACTIVE\nELIMINATE — OPTIONAL"
	objectives.end_mission_button.show()
	await process_frame
	await process_frame
	check(picker._level_panel.get_global_rect().position.y >= objectives.get_global_rect().end.y + 7.0, "Multiline objectives and departure button leave space above floor controls")
	objectives.hide()
	await process_frame
	check(picker._level_panel.get_global_rect().position.y < objectives.get_global_rect().end.y, "When objectives are hidden, the floor controls reclaim the space")
	objectives.show()
	move = await service.submit_move(service.make_move_request(actor, layout.ROOF_LADDER_BOTTOM, TacticalActionRequest.Source.PLAYER), true)
	check(move != null and actor.grid_position == layout.ROOF_LADDER_BOTTOM, "Authoritative Move can descend the roof ladder")
	var interior := Vector3i(14, 0, 7)
	grid.update_unit_position(actor, actor.grid_position, interior)
	actor.global_position = grid.grid_to_world(interior) + Vector3.UP * actor.standing_height
	rig.camera.fov = 38.0
	rig.camera.global_position = actor.global_position + Vector3(0, 0.5, -6)
	rig.camera.look_at(actor.global_position)
	var wall := battle.find_child("Wall_14_5", true, false)
	var wall_face := wall.get_child(0) as MeshInstance3D
	rig._update_camera_occlusion(0.0)
	await _capture("warehouse-solid")
	rig._update_camera_occlusion(0.2)
	check(rig._environment_apertures.active.get(wall_face, {}).get("strength") == 1.0 and is_zero_approx(wall_face.transparency), "Warehouse wall uses a local aperture without fading the whole wall")
	var neighbor := battle.find_child("Wall_15_5", true, false).get_child(0) as MeshInstance3D
	check(rig._environment_apertures.active.get(neighbor, {}).get("strength") == 1.0, "An opening that crosses a wall tile edge includes the neighboring tile")
	var blocker := CombatRules.get_blocking_cell(rig.camera.global_position, actor.global_position, grid)
	check(blocker != null and blocker.grid_position == Vector3i(14, 0, 5), "Visible aperture preserves the warehouse wall's tactical LOS blocker")
	await _capture("warehouse-aperture")
	rig._cinematic_active = true
	rig._cinematic_look_target = actor.global_position
	rig._update_camera_occlusion(0.2)
	check(not rig._environment_apertures.active.has(wall_face) and wall_face.transparency > 0.8, "Warehouse action camera retains its existing whole-wall fade")
	battle.queue_free()
	await process_frame
	print("Industrial roof movement: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _capture(view: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join(view + ".png")) == OK, "Captured %s" % view)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
