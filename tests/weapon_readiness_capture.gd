extends SceneTree
## Weapon readiness captures (explicit-only; images need a display, the numbers do not).
## Stages one attack presentation inside a real battle fixture (so cover comes from the same tactical queries the
## game uses) and records it on a fixed presentation-time grid: two filmstrip rows (the shooter's right side, and
## three-quarter from behind-left) plus every per-frame number as JSON.
##   godot_console --path . --script res://tests/weapon_readiness_capture.gd -- <directory> <scenario> [scenario...]
## Scenarios: relaxed (standing, lowered carry), guard (a sustained AIMED request holds the weapon up), crouch
## (cover 1.1 m), kneel (cover 0.9 m), kneel_aimed (kneel with the weapon already held up: the control for the kneel shot), interrupt (a hit lands 0.12 s into the raise).
## Output: <directory>/readiness-<scenario>-a.png (t 0.0 to 0.5 s), -b.png (t 0.6 to 1.1 s), readiness-<scenario>.json.
## The game runs at quarter speed while capturing so a rendered frame covers about 4 ms of presentation time.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const TILE := Vector2i(320, 420)
const TIMES := [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <directory> <scenario> [scenario...]")
		quit(2)
		return
	var directory: String = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var images := DisplayServer.get_name() != "headless"
	for index in range(1, args.size()):
		await _scenario(directory, String(args[index]), images)
	quit(0)

func _views(rig: UnitVisualAdapter, focus_y: float) -> Array:
	var basis := rig.rig.character_root.global_basis.orthonormalized()
	var origin := rig.global_position + Vector3.UP * focus_y
	return [
		[origin + basis * Vector3(-2.3, 0.35, 0.3), origin],
		[origin + basis * Vector3(1.6, 0.5, -1.9), origin],
	]

func _scenario(directory: String, scenario: String, images: bool) -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	f.battle.set_debug_enemy_control(true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10))
	f.place(enemy, Vector3i(12, 0, 10))
	for node in f.level.find_children("*", "CanvasLayer", true, false):
		node.visible = false
	var adapter := actor.visual_adapter
	var cover_height := -1.0
	match scenario:
		"crouch": cover_height = 1.1
		"kneel", "kneel_aimed": cover_height = 0.9
	f.set_cover(f.grid.get_unit_grid(actor) + Vector3i.RIGHT, MapCellData.CoverType.NONE if cover_height < 0.0 else MapCellData.CoverType.LOW, maxf(cover_height, 0.0))
	var lights := Node3D.new()
	adapter.add_child(lights)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.2
	lights.add_child(sun)
	var viewports: Array[SubViewport] = []
	var cameras: Array[Camera3D] = []
	for i in 2:
		var viewport := SubViewport.new()
		viewport.size = TILE
		viewport.world_3d = root.world_3d
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var camera := Camera3D.new()
		camera.near = 0.04
		camera.fov = 42.0
		viewport.add_child(camera)
		camera.current = true
		viewports.append(viewport)
		cameras.append(camera)
	var diagnostics := HandContactDiagnostics.attach(adapter.rig)
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)
	if diagnostics.overlay != null:
		diagnostics.overlay.visible = false   # measure, but keep the images clean
	for i in 30: await process_frame
	if scenario in ["guard", "kneel_aimed"]:
		adapter.request_readiness(&"guard", WeaponReadiness.Level.AIMED)
	adapter.present_idle()
	await create_timer(1.8).timeout
	for i in 3: await process_frame
	Engine.time_scale = 0.25
	var focus_y := 0.8 if scenario.begins_with("kneel") else 1.0
	var tiles: Array = [[], []]
	var rows: Array = []
	var phase_log: Array = []
	adapter.presenter.attack.shot_released.connect(func(timeline: Dictionary) -> void: phase_log.append({"event": "shot_fired", "t": timeline.fire_t}))
	adapter.present_attack(enemy.global_position)
	var started: float = adapter.presenter.time
	var next_tile := 0
	var interrupted := false
	while next_tile < TIMES.size() and adapter.presenter.time - started < 2.0:
		var t: float = adapter.presenter.time - started
		if scenario == "interrupt" and not interrupted and t >= 0.12:
			interrupted = true
			adapter.present_hit()
			phase_log.append({"event": "hit", "t": t})
		var sample: Dictionary = diagnostics.latest
		rows.append({"t": snappedf(t, 0.0001), "phase": adapter.presenter.attack.phase, "state": String(adapter.get_presentation_state()), "blend": snappedf(adapter.rig.aim_blend, 0.0001),
			"muzzle_error_deg": snappedf(adapter.weapon_alignment_error_degrees(), 0.001), "flash": adapter.rig.muzzle_flash.visible, "recoil": snappedf(adapter.rig.recoil, 0.0001),
			"readiness": String(WeaponReadiness.level_name(adapter.readiness_level())),
			"dominant_wrist_mm": snappedf(float(sample.hands[0].wrist_to_ik_target) * 1000.0, 0.01) if not sample.is_empty() else -1.0,
			"support_wrist_mm": snappedf(float(sample.hands[1].wrist_to_ik_target) * 1000.0, 0.01) if not sample.is_empty() else -1.0,
			"support_elbow_deg": snappedf(float(sample.hands[1].elbow_angle_deg), 0.1) if not sample.is_empty() else -1.0})
		if images and t >= float(TIMES[next_tile]):
			var views := _views(adapter, focus_y)
			for v in 2:
				cameras[v].position = views[v][0]
				cameras[v].look_at(views[v][1])
			await RenderingServer.frame_post_draw
			for v in 2:
				tiles[v].append(viewports[v].get_texture().get_image())
			next_tile += 1
		elif not images:
			next_tile = TIMES.size() if t > 1.2 else next_tile
		await process_frame
	Engine.time_scale = 1.0
	if images:
		for half in 2:
			var sheet := Image.create(TILE.x * 6, TILE.y * 2, false, Image.FORMAT_RGB8)
			for v in 2:
				for column in 6:
					var index: int = half * 6 + column
					if index < tiles[v].size():
						sheet.blit_rect(tiles[v][index], Rect2i(Vector2i.ZERO, TILE), Vector2i(column * TILE.x, v * TILE.y))
			sheet.save_png(directory.path_join("readiness-%s-%s.png" % [scenario, "ab"[half]]))
	var out := FileAccess.open(directory.path_join("readiness-%s.json" % scenario), FileAccess.WRITE)
	out.store_string(JSON.stringify({"scenario": scenario, "timeline": _plain(adapter.presenter.attack.timeline), "events": phase_log, "frames": rows}, "  "))
	out.close()
	print("READINESS %s: fired %s at %.3f s, muzzle %.2f deg, blend %.3f, forced %s, %d frames" % [scenario, adapter.presenter.attack.timeline.get("fired"), adapter.presenter.attack.timeline.get("fire_t", -1.0), adapter.presenter.attack.timeline.get("fire_muzzle_error_degrees", -1.0), adapter.presenter.attack.timeline.get("fire_blend", -1.0), adapter.presenter.attack.timeline.get("forced"), rows.size()])
	for viewport in viewports: viewport.queue_free()
	await f.dispose(self)

func _plain(timeline: Dictionary) -> Dictionary:
	var copy := timeline.duplicate(true)
	for entry in copy.get("phases", []):
		entry["phase"] = String(AttackSequence.Phase.keys()[entry["phase"]])
	return copy
