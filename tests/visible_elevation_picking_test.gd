extends SceneTree
## Floor viewing must not impose a movement-height ceiling on visible surfaces.
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.content_manifest = {"population_enabled": false}
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "The selectable range initializes")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	var battle := level.battle_controller
	battle.set_process(false)
	var grid := battle.grid_manager
	var rig := level.get_node("CameraRig") as TacticalCamera
	var picker := battle.mouse_raycaster
	rig.set_process(false)
	rig._cancel_selection_focus()
	picker.set_process(false)
	var actor := level.turn_manager.active_unit
	grid.update_unit_position(actor, actor.grid_position, Vector3i(11, 0, 15))
	actor.global_position = grid.grid_to_world(actor.grid_position) + Vector3.UP * actor.standing_height
	check(is_zero_approx(rig.inspected_floor_height()), "Actor is viewing Ground before moving up")
	for key in [Vector3i(11, 1, 14), Vector3i(6, 1, 14), Vector3i(11, 3, 12)]:
		var point := grid.grid_to_world(key)
		rig.camera.global_position = point + Vector3.UP * 30
		rig.camera.look_at(point, Vector3.FORWARD)
		await physics_frame
		await physics_frame
		var screen := rig.camera.unproject_position(point)
		check(picker.get_floor_candidates(screen).any(func(hit): return hit.grid_position == key), "Real visible surface has a physics candidate: %s" % key)
		var hit := picker.get_floor_raycast_result(screen)
		check(not hit.is_empty() and hit.grid_position == key, "Ground view can pick visible ramp/stair/landing %s" % key)
		picker._inspect_level(0)
		hit = picker.get_floor_raycast_result(screen)
		check(not hit.is_empty() and hit.grid_position == key, "Explicit Ground viewing also leaves visible ascent selectable: %s" % key)
	var destination := Vector3i(11, 3, 12)
	var point := grid.grid_to_world(destination)
	rig.camera.global_position = point + Vector3.UP * 30
	rig.camera.look_at(point, Vector3.FORWARD)
	await physics_frame
	var hit := picker.get_floor_raycast_result(rig.camera.unproject_position(point))
	var query := battle.query_move(actor, destination)
	check(query.is_legal(), "The upper landing is reachable through the existing ramp graph")
	if not hit.is_empty():
		battle.tactical_unit = actor
		battle.is_move_mode_active = true
		battle.current_movement_zone.assign([destination])
		battle._update_movement_preview(hit)
		check(not battle._movement_feedback_key.is_empty(), "Hover previews the reachable upper landing while viewing Ground")
		var args := OS.get_cmdline_user_args()
		if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
			root.size = Vector2i(1280, 900)
			rig.camera.global_position = point + Vector3(12, 19, 22)
			rig.camera.look_at(point + Vector3(0, -1, 2))
			await physics_frame
			var angled_hit := picker.get_floor_raycast_result(rig.camera.unproject_position(point))
			check(not angled_hit.is_empty() and angled_hit.grid_position == destination, "Angled camera also picks the visible landing from Ground")
			DirAccess.make_dir_recursive_absolute(args[1])
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(args[1].path_join("visible-ascent-ground-view.png")) == OK, "Rendered review saved")
		check(await battle.try_move(actor, hit.grid_position), "Picked upper surface commits a normal Move without selecting another view level")
		check(actor.grid_position == destination, "Move reaches the same upper landing the picker advertised")
	else:
		check(false, "Visible landing must be clickable before the real Move")
	level.queue_free()
	await process_frame
	await process_frame
	print("Visible elevation picking: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
