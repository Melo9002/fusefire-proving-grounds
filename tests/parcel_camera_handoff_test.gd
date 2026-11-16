extends SceneTree
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/camera-handoff-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[1])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Capture " + name)

func _run() -> void:
	var editor := load("res://tools/parcel_editor/parcel_editor.tscn").instantiate() as ParcelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame
	editor.select_parcel(AuthoredParcelCatalog.LOADING_YARD_A)
	var box := editor.PlacementLibrary.create("factory_kit/box-small")
	box.position = Vector3(7, 0, 17)
	editor.draft.add_fixed(box)
	box.free()
	editor._apply_draft()
	check(editor.draft.dirty, "Start with a real unsaved object edit, not an empty source session")
	for view in ["top", "orbited"]:
		if view == "top": editor._top_view()
		else:
			editor._oblique_view()
			editor._yaw = -0.8
			editor._pitch = 0.3
			editor._distance = 26
			editor._camera_target += Vector3(2, 0, 3)
			editor._update_camera()
		var saved_view := editor.camera.transform
		var saved_offset := editor.camera.h_offset
		var fingerprint := editor._session_fingerprint()
		check(root.get_camera_3d() == editor.camera, "The editor owns the viewport before testing")
		await _capture(view + "-editor")
		await editor.test_in_battle()
		var live := editor.test_battle
		check(is_instance_valid(live) and live.battle_initialization_succeeded, "Changed editor view starts a valid test battle")
		if not is_instance_valid(live) or not live.battle_initialization_succeeded:
			editor.free()
			quit(1)
			return
		var rig := live.get_node("CameraRig") as TacticalCamera
		rig.set_process(false) # Isolate real input handlers from OS edge scrolling.
		check(root.get_camera_3d() == rig.camera and not editor.camera.current, "The battle camera owns the viewport after " + view + " editing")
		check(live.battle_controller.mouse_raycaster.camera == root.get_camera_3d(), "Mouse picking and rendering use the same battle camera")
		var before := root.get_camera_3d().global_transform
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_MIDDLE
		press.pressed = true
		rig._unhandled_input(press)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(28, 12)
		rig._unhandled_input(motion)
		press.pressed = false
		rig._unhandled_input(press)
		check(not root.get_camera_3d().global_transform.is_equal_approx(before), "Orbit input changes the camera actually rendering the battle")
		before = root.get_camera_3d().global_transform
		press.button_index = MOUSE_BUTTON_WHEEL_UP
		press.pressed = true
		rig._unhandled_input(press)
		check(not root.get_camera_3d().global_transform.is_equal_approx(before), "Zoom input changes the visible battle camera")
		await _capture(view + "-battle")
		check(await live.battle_controller.try_aim(live.turn_manager.active_unit), "Record an action for camera ownership during rewatch")
		BattleReplaySession.store(live._replay_recorder.recording)
		await live.replay_last_battle()
		await process_frame
		var replay := current_scene as BattleLevel
		var replay_rig := replay.get_node("CameraRig") as TacticalCamera
		check(root.get_camera_3d() == replay_rig.camera, "Rewatch switches to the replacement battle's camera")
		replay.return_to_match_setup()
		await process_frame
		check(root.get_camera_3d() == editor.camera and editor.camera.transform.is_equal_approx(saved_view) and is_equal_approx(editor.camera.h_offset, saved_offset), "Returning restores the exact editor camera view")
		check(editor._session_fingerprint() == fingerprint and editor.draft.dirty, "Camera transitions preserve the unsaved object edit and parcel session")
		await _capture(view + "-returned")
	editor.free()
	print("Parcel camera handoff: %d failure(s)" % failures)
	quit(1 if failures else 0)
