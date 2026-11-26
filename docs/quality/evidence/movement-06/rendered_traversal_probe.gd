extends SceneTree
## Normal-speed audit capture from real tactical Move calls in the Test Range.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Pass an output directory to this rendered probe.")
		quit(2)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var fixture := Fixture.new()
	await fixture.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = fixture.turns.player_units[0]
	var success := true
	for sample in [
		{"name": "stairs-up", "start": Vector3i(6, 0, 15), "end": Vector3i(6, 3, 12)},
		{"name": "ramp-down", "start": Vector3i(11, 3, 12), "end": Vector3i(11, 0, 15)},
		{"name": "ladder-up", "start": Vector3i(12, 0, 4), "end": Vector3i(12, 3, 5)},
		{"name": "ladder-down", "start": Vector3i(12, 3, 5), "end": Vector3i(12, 0, 4)},
	]:
		if actor.grid_position != sample.start:
			fixture.place(actor, sample.start)
		fixture.ready_actor(actor, 6, 4)
		fixture.turns.select_player_unit(actor)
		var camera := fixture.level.get_node("CameraRig") as TacticalCamera
		camera.focus_position((fixture.grid.grid_to_world(sample.start) + fixture.grid.grid_to_world(sample.end)) * 0.5)
		camera._manual_pitch = true
		camera.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-140.0 if "ladder" in sample.name else -55.0), 0)
		camera._set_zoom(9.0)
		await create_timer(0.45).timeout
		var battle := fixture.battle
		var query := battle.query_move(actor, sample.end)
		if not query.is_legal():
			push_error("Traversal query rejected: " + sample.name)
			success = false
			continue
		var done := []
		var started := Time.get_ticks_msec()
		var go := func() -> void: done.append(await battle.try_move(actor, sample.end))
		go.call()
		var samples := 0
		for seconds in [0.6, 0.8, 0.8]:
			await create_timer(seconds).timeout
			if not done.is_empty():
				break
			await RenderingServer.frame_post_draw
			var path: String = output.path_join("%s-%d.png" % [sample.name, samples])
			if root.get_texture().get_image().save_png(path) != OK:
				success = false
			samples += 1
		while done.is_empty() and Time.get_ticks_msec() - started < 18000:
			await process_frame
		var arrived: bool = not done.is_empty() and done[0] and actor.grid_position == sample.end
		print("[RenderedMove] ", sample.name, " actor=", actor.tactical_id, " route=", query.path_cells, " arrived=", arrived, " elapsed_ms=", Time.get_ticks_msec() - started, " captures=", samples)
		success = success and arrived and samples > 0
		await create_timer(0.6).timeout
	await fixture.dispose(self)
	quit(0 if success else 2)
