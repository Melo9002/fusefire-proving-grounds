extends SceneTree

const SCENE := preload("res://tools/animation_workbench/pose_workbench.tscn")
const WALL := {"full": true, "height": 1.4, "left": 1.0, "right": 2.0,
	"left_ok": true, "right_ok": true, "aim": false}
const YAW_TOLERANCE := 0.005

var failures := 0
var checks := 0
var capture_folder := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _steps(bench: Node3D, count: int) -> void:
	for index in count:
		var before: float = bench.presenter.time
		bench.step_sim()
		# A screenshot resumes after drawing. The next process_frame signal
		# may arrive before the workbench has consumed its queued step.
		for frame in 3:
			await process_frame
			if bench.presenter.time > before:
				break
		if bench.presenter.time <= before:
			_check(false, "The workbench consumes its requested step")
			return

func _capture(label: String) -> void:
	if capture_folder.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_folder.path_join(label + ".png")) == OK,
		"Capture saved for %s" % label)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture=") and DisplayServer.get_name() != "headless":
			capture_folder = ProjectSettings.globalize_path(argument.trim_prefix("capture="))
			DirAccess.make_dir_recursive_absolute(capture_folder)
	for model in [&"mira_0", &"small_mira_0"]:
		WorkbenchSession.character = model
		WorkbenchSession.armed = true
		var bench := SCENE.instantiate()
		root.add_child(bench)
		await process_frame
		bench.set_sim_paused(true)
		bench.step_seconds = 1.0 / 60.0
		var rig: CharacterRig = bench.rig
		for next_state: StringName in [&"idle", &"walk", &"stairs", &"ladder"]:
			bench.reset_scene()
			await _steps(bench, 32)
			var heading := deg_to_rad(31.0 if next_state == &"idle" else (19.0 if next_state == &"walk" else 0.0))
			rig.presenter.face_yaw(heading, false, false)
			bench.set_cover_demo(WALL.duplicate())
			await _steps(bench, 32)
			var cover_yaw := rig.cover_yaw()
			var label := "%s to %s" % [model, next_state]
			_check(absf(cover_yaw) > deg_to_rad(30.0), "%s starts with a real cover yaw" % label)
			if next_state == &"idle":
				# An attack also turns the rig toward its target. Its temporary heading
				# must not replace the facing that existed before entering cover.
				bench.set_cover_target(Vector3(3.0, 0.0, 4.0))
				await _steps(bench, 23)
				_check(absf(angle_difference(rig.rotation.y, heading)) > 0.05,
					"%s temporarily tracks the cover target" % label)
				await _capture("%s-cover-aim" % model)
			elif next_state == &"stairs":
				await _capture("%s-cover-protected" % model)
			var before := rig.character_root.global_rotation.y
			bench.set_cover_demo({})
			match next_state:
				&"walk":
					bench.command_move(2.4)
					bench.turn_by(70.0)
				&"stairs":
					bench.start_stair_demo(0.18, 0.28, 8, true, 1.4)
				&"ladder":
					bench.start_ladder_demo(3.0, 1, 0.85)
			_check(absf(angle_difference(before, rig.character_root.global_rotation.y)) < YAW_TOLERANCE,
				"%s preserves the visible heading at handoff" % label)
			var release_yaw := absf(rig.cover_yaw())
			await _steps(bench, 1)
			var first_frame_yaw := absf(rig.cover_yaw())
			_check(first_frame_yaw < release_yaw and first_frame_yaw > YAW_TOLERANCE,
				"%s eases toward neutral on the first frame (%.1f to %.1f degrees)" % [
					label, rad_to_deg(release_yaw), rad_to_deg(first_frame_yaw)])
			await _steps(bench, 31)
			var expected := heading + (deg_to_rad(70.0) if next_state == &"walk" else 0.0)
			_check(absf(rig.cover_yaw()) < YAW_TOLERANCE and
				absf(angle_difference(rig.character_root.global_rotation.y, expected)) < YAW_TOLERANCE,
				"%s settles on the intended heading and releases cover (body %.1f, cover %.1f degrees)" % [
					label, rad_to_deg(rig.character_root.global_rotation.y), rad_to_deg(rig.cover_yaw())])
			print("%s | cover yaw magnitude %.1f -> %.1f -> %.1f deg | final facing %.1f deg" % [
				label, rad_to_deg(release_yaw), rad_to_deg(first_frame_yaw),
				rad_to_deg(absf(rig.cover_yaw())), rad_to_deg(rig.character_root.global_rotation.y)])
			match next_state:
				&"idle":
					_check(rig.animation_controller.current_state == &"rifle_idle", "%s returns to idle" % label)
					await _capture("%s-after-idle" % model)
					rig.animation_controller.play(&"aim")
					await _steps(bench, 20)
					_check(absf(angle_difference(rig.character_root.global_rotation.y, heading)) < YAW_TOLERANCE,
						"%s aiming afterwards preserves heading" % label)
				&"walk":
					_check(rig.animation_controller.current_state == &"move" and is_nan(bench.turn_goal),
						"%s completes the turn while walking" % label)
				&"stairs":
					_check(rig.stairs != null and float(bench.stair_demo.s) > float(bench.stair_demo.enter),
						"%s advances on the stairs" % label)
				&"ladder":
					_check(rig.ladder != null and float(bench.ladder_demo.climbed) > 0.2,
						"%s advances up the ladder" % label)
			await _capture("%s-after-%s" % [model, &"aim" if next_state == &"idle" else next_state])
		bench.end_ladder_demo()
		var opposite_wall := WALL.duplicate()
		opposite_wall.left = WALL.right
		opposite_wall.right = WALL.left
		var previous_yaw := 0.0
		for wall: Dictionary in [WALL, opposite_wall]:
			bench.set_cover_demo(wall.duplicate())
			await _steps(bench, 20)
			var yaw := rig.cover_yaw()
			_check(absf(yaw) > deg_to_rad(30.0) and yaw * previous_yaw <= 0.0,
				"%s reacquires cover on each side without a scene reset" % model)
			previous_yaw = yaw
			bench.set_cover_demo({})
			await _steps(bench, 20)
			_check(absf(rig.cover_yaw()) < YAW_TOLERANCE,
				"%s returns to zero cover offset on repeated release" % model)
		bench.queue_free()
		await process_frame
	WorkbenchSession.character = &""
	print("Workbench cover release: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
