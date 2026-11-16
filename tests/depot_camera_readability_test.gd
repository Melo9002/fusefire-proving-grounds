extends SceneTree
## Real saved Depot scenes: controls, inspection, live framing and replay ownership.
const Fingerprint = preload("res://systems/replay/battle_state_fingerprint.gd")
var failures := 0
var output := ""
var poses := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		output = args[1]
		DirAccess.make_dir_recursive_absolute(output)
	for map_seed in [16, 17]: await _case(map_seed)
	print("Depot camera readability: %d orbit/zoom poses, %d failure(s)" % [poses, failures])
	quit(1 if failures else 0)

func _case(map_seed: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = map_seed
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Depot camera case initializes")
	if not level.battle_initialization_succeeded:
		level.free()
		return
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var actor := level.turn_manager.active_unit
	var before := Fingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager, true, true, true, true, true, true)
	var workshop := level.find_child("EastWorkshop", true, false) as TacticalVisualOccluder
	check(workshop != null and workshop.occlusion_bounds.size.length_squared() > 0, "Saved workshop derives usable visual-occlusion bounds on load")
	var inside := false
	var original_transparency := {}
	for mesh: MeshInstance3D in workshop.find_children("*", "MeshInstance3D", true, false):
		original_transparency[mesh] = mesh.transparency
		inside = inside or mesh.get_aabb().has_point(mesh.to_local(Vector3(32, 4, 0)))
	check(not inside, "Scenery placement clears the reported westward camera pose")
	rig.camera.global_position = Vector3(32, 4, 0)
	rig.camera.look_at(Vector3(-8, 2, 0))
	rig._update_camera_occlusion(1.0)
	await _image("%d-westward-clear" % map_seed)
	# Use the actual floor-inspection/fallback path, where friendly apertures close.
	rig.inspect_floor(Vector3(0, 0, -8))
	rig.camera.global_position = Vector3(65, 3, -8)
	rig.camera.look_at(Vector3(0, 0.5, -8))
	rig._update_camera_occlusion(1.0)
	for mesh: MeshInstance3D in workshop.find_children("*", "MeshInstance3D", true, false):
		check(mesh.transparency >= 0.82 or is_equal_approx(mesh.transparency, 0.82), "Saved scenery fades during floor browsing: %s" % mesh.transparency)
	await _image("%d-floor-inspection" % map_seed)
	workshop.restore_view()
	for mesh in original_transparency:
		check(is_equal_approx(mesh.transparency, original_transparency[mesh]), "Leaving inspection restores the saved scene's original transparency")
	rig._inspected_floor = Vector3.INF
	# The diagnostic floor shot directly oriented the lens; normal orbit owns
	# the rig rotation and expects its child lens to have zero local rotation.
	rig.camera.rotation = Vector3.ZERO
	rig.focus_position(actor.global_position)
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		for pitch in [2.0, 12.0, 45.0, 88.0]:
			_orbit(rig, yaw, pitch)
			for zoom in [4.0, 20.0, 56.0]:
				rig._set_zoom(zoom)
				rig._update_camera_occlusion(1.0)
				poses += 1
				check(rig.camera.global_transform.is_finite() and is_equal_approx(rig._zoom, zoom), "Orbit/zoom remains controllable at %s/%s/%s" % [yaw, pitch, zoom])
				var blocked := []
				for geometry in rig._environment_apertures.cinematic_blockers(rig.camera.global_position, actor.global_position, {}):
					var aperture: Dictionary = rig._environment_apertures.active.get(geometry, {})
					if geometry.visible and geometry.transparency < 0.8 and float(aperture.get("strength", 0)) < 0.99:
						blocked.append(String(geometry.get_path()))
				check(blocked.is_empty(), "Selected subject remains revealed at %s/%s/%s: %s" % [yaw, pitch, zoom, blocked])
				if pitch == 45 and zoom == 20: await _image("%d-orbit-%d" % [map_seed, int(yaw)])
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var old_zoom := rig._zoom
	rig._unhandled_input(wheel)
	check(rig._zoom < old_zoom, "Wheel input still zooms after the orbit sweep")
	rig._pan(Vector2.ONE, 100)
	check(absf(rig.global_position.x) <= 22 and absf(rig.global_position.z) <= 22, "Pan remains bounded and does not trap focus in scenery")
	rig.focus_selected_unit()
	check(rig.global_position.is_equal_approx(actor.global_position), "Recenter returns to the selected unit")
	var director := level.action_camera_director
	var framed: bool = await director.present(actor, &"attack", level.turn_manager.enemy_units[0].global_position, 0, false, true)
	rig._update_camera_occlusion(1.0)
	check(framed and rig._cinematic_active and rig.camera.global_transform.is_finite(), "Live action-camera framing settles")
	check(rig._environment_apertures.cinematic_blockers(rig.camera.global_position, actor.visual_adapter.get_camera_focus(), rig._cinematic_hidden).is_empty(), "Live framing avoids or hides registered visual blockers")
	await _image("%d-live-action" % map_seed)
	await director.finish_live_presentation(framed)
	check(not rig._cinematic_active and not rig.is_camera_transitioning(), "Action camera returns control without a stuck transition")
	check(Fingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager, true, true, true, true, true, true) == before, "Camera and scenery visibility never change tactical state")
	check(await level.battle_controller.try_aim(actor), "Record an authoritative action for camera-mode replay")
	var path := "res://.godot/depot-camera-%d-%d.replay.json" % [map_seed, OS.get_process_id()]
	check(level._replay_recorder.recording.save_json(path) == OK, "Save camera-review replay")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable(), "Reload the saved replay")
	level.queue_free()
	await process_frame
	await process_frame
	for mode in [BattleReplayPlayer.CameraMode.FREE, BattleReplayPlayer.CameraMode.SELECTION_FOCUS, BattleReplayPlayer.CameraMode.CINEMATIC]:
		var replay := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		replay.configure_replay(loaded)
		root.add_child(replay)
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		player.set_camera_mode(mode)
		var deadline := Time.get_ticks_msec() + 10000
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		check(player.playback_complete and player.playback_succeeded and player.verified_actions == loaded.actions.size(), "Replay camera mode %d verifies every action: %s" % [mode, player.last_divergence])
		var replay_rig := replay.get_node("CameraRig") as TacticalCamera
		check(not replay_rig._cinematic_active, "Finished playback releases cinematic ownership")
		await _image("%d-replay-mode-%d" % [map_seed, mode])
		replay.queue_free()
		await process_frame
		await process_frame
	DirAccess.remove_absolute(path)

func _orbit(rig: TacticalCamera, yaw: float, pitch: float) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_MIDDLE
	button.pressed = true
	rig._unhandled_input(button)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2((rig.rotation_degrees.y - yaw) / rig.drag_sensitivity, (rig.rotation_degrees.x + pitch) / rig.drag_sensitivity)
	rig._unhandled_input(motion)
	button.pressed = false
	rig._unhandled_input(button)

func _image(title: String) -> void:
	if output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(title + ".png")) == OK, "Capture " + title)
