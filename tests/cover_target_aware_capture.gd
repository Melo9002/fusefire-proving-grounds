extends SceneTree
## Rendered evidence for target-aware cover firing (explicit-only: needs a GPU, not part of the standard tiers). A real authorized attack from behind a wall at a target
## to the left, then to the right: passive, aimed, shot and recovered frames of each, written to one contact sheet.
## godot --path . --script res://tests/cover_target_aware_capture.gd -- <output.png>
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_path := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://cover_target_aware.png"
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	f.battle.set_debug_enemy_control(true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	for x in [5, 6, 7]:
		f.set_cover(Vector3i(x, 0, 12), MapCellData.CoverType.FULL, 2.2)
		# A visible slab so the wall reads in the capture.
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 2.2, 1.0)
		slab.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.45, 0.38)
		slab.material_override = material
		f.level.add_child(slab)
		slab.global_position = f.grid.grid_to_world(Vector3i(x, 0, 12)) + Vector3(0, 1.1, 0)
	f.place(actor, Vector3i(6, 0, 11))
	f.ready_actor(actor, 6, 8)
	f.act_as(actor)
	var adapter := actor.visual_adapter
	var camera := Camera3D.new()
	f.level.add_child(camera)
	camera.fov = 55.0
	camera.global_position = adapter.global_position + Vector3(-1.8, 2.4, -3.2)
	camera.look_at(adapter.global_position + Vector3(0.5, 1.0, 1.6), Vector3.UP)
	camera.current = true
	for i in 20: await process_frame
	adapter.present_idle()
	await create_timer(1.0).timeout
	var tiles: Array[Image] = []
	for scenario in [Vector3i(11, 0, 12), Vector3i(1, 0, 12)]:
		f.place(enemy, scenario)
		tiles.append(await _snap("passive"))
		var done: Array = []
		var attack := func() -> void:
			await f.battle.try_attack(actor, enemy)
			done.append(true)
		attack.call()
		var taken := {"aim": false, "shot": false}
		var guard := 0
		while (done.is_empty() or adapter.attack_phase != UnitVisualAdapter.AttackPhase.NONE) and guard < 1500:
			guard += 1
			await process_frame
			if not taken.aim and adapter.aim_blend > 0.9 and adapter.attack_phase != UnitVisualAdapter.AttackPhase.NONE:
				taken.aim = true
				tiles.append(await _snap("aim"))
			if not taken.shot and adapter.get_presentation_state() in [&"shoot", &"shoot_left", &"shoot_right"]:
				taken.shot = true
				await create_timer(0.07).timeout
				tiles.append(await _snap("shot " + str(adapter.get_presentation_state())))
		await create_timer(1.0).timeout
		tiles.append(await _snap("recovered"))
	var width := 480
	var height := 270
	var sheet := Image.create(width * 4, height * 2, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		var tile := tiles[i]
		if tile == null:
			continue
		tile.resize(width, height)
		sheet.blit_rect(tile, Rect2i(0, 0, width, height), Vector2i((i % 4) * width, (i / 4) * height))
	sheet.save_png(out_path)
	print("tiles %d -> %s" % [tiles.size(), out_path])
	await f.dispose(self)
	quit(0)

func _snap(_label: String) -> Image:
	await process_frame
	await process_frame
	return root.get_texture().get_image()
