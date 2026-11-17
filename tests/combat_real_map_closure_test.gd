extends SceneTree
## Current-site query/AI/commit parity and repeatable diagnostic timings.
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0
var checks := 0
var measurements: Array[Dictionary] = []
var capture_dir := ""

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _timing(callable: Callable) -> Dictionary:
	for warmup in 8: callable.call()
	var elapsed: Array[float] = []
	for sample in 128:
		var start := Time.get_ticks_usec()
		callable.call()
		elapsed.append(float(Time.get_ticks_usec() - start) / 1000)
	elapsed.sort()
	var total := 0.0
	for value in elapsed: total += value
	return {"samples": elapsed.size(), "mean_ms": total / elapsed.size(), "p95_ms": elapsed[121], "max_ms": elapsed[-1]}

func _place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _capture(name: String, level: BattleLevel, focus: Vector3) -> void:
	if capture_dir.is_empty(): return
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var offset := Vector3(9, 13, 11)
	# Inspect feedback from an ordinary clear orbit, using the existing camera
	# obstruction query. An obstructed fixed audit angle is recorded separately.
	var actor := level.turn_manager.player_units[0]
	for candidate in [Vector3(9, 13, 11), Vector3(-9, 13, 11), Vector3(9, 13, -11), Vector3(-9, 13, -11)]:
		if rig._cinematic_view_clear(actor.global_position, focus + candidate):
			offset = candidate
			break
	print("[ClosureCamera] %s offset %s" % [name, offset])
	rig.camera.global_position = focus + offset
	rig.camera.look_at(focus)
	await create_timer(0.25).timeout
	rig._update_camera_occlusion(0.3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "Capture real-site feedback " + name)

func _case(id: StringName, seed_value: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(id)
	config.battle_seed = seed_value
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "%s/%d initializes" % [id, seed_value])
	if not level.battle_initialization_succeeded:
		level.queue_free()
		await process_frame
		return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var battle := level.battle_controller
	battle.set_process(false)
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	var service := battle.action_service
	level.turn_manager.select_player_unit(actor)
	# Find a genuine supported cell with a shot near this site's actual enemy.
	# This is fixture setup, not movement teleportation available to players.
	var cells: Array = grid.map_data.cells.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i): return a.x < b.x if a.x != b.x else a.y < b.y if a.y != b.y else a.z < b.z)
	var found := false
	for cell: Vector3i in cells:
		if not grid.can_unit_occupy_cell(actor, cell): continue
		var distance := CombatRules.attack_distance(cell, enemy.grid_position, grid)
		if distance < 1.5 or distance > actor.attack_range: continue
		if CombatRules.evaluate_attack_from_cell(actor, cell, enemy, grid, null).is_legal:
			_place(actor, cell, grid)
			found = true
			break
	check(found, "%s/%d has an occupied-body-safe controlled firing position" % [id, seed_value])
	if not found:
		level.queue_free()
		await process_frame
		return
	var query := battle.query_attack(actor, enemy)
	var inventory := battle.query_attack(actor).get_candidate(enemy.tactical_id)
	var outgoing := CombatRules.evaluate_attack_from_cell(actor, actor.grid_position, enemy, grid, null)
	check(query.is_legal() and inventory.is_legal() and outgoing.is_legal and query.hit_chance == inventory.hit_chance and query.hit_chance == outgoing.hit_chance and query.damage_on_hit == inventory.damage_on_hit, "HUD/direct/inventory/destination use the same real geometry")
	var ai: AIController
	for controller: AIController in level.find_children("*", "AIController", true, false):
		if controller.unit == actor: ai = controller
	check(ai != null, "Battle owns the acting unit's AI controller")
	if ai == null:
		level.queue_free()
		await process_frame
		return
	var chosen := ai._find_attack_target()
	check(chosen != null and battle.query_attack(actor, chosen).is_legal(), "Actual AI scorer selects a legal inventory target")
	for record in ai._last_target_candidates:
		if record.status == "rejected": continue
		for candidate: TacticalUnit in level.turn_manager.enemy_units:
			if String(candidate.name) == record.target:
				var candidate_query := battle.query_attack(actor, candidate)
				check(record.hit_chance == candidate_query.hit_chance, "Actual AI scoring records the UI chance")
	var rng_before := service.get_combat_rng_state()
	var state_before := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var timing := _timing(func(): return battle.query_attack(actor, enemy))
	var inventory_timing := _timing(func(): return battle.query_attack(actor))
	check(rng_before == service.get_combat_rng_state() and state_before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Repeated real-site queries change no state or RNG")
	var move_query: MoveQueryResult
	for offset in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]:
		var candidate := battle.query_move(actor, actor.grid_position + offset)
		if candidate.is_legal():
			move_query = candidate
			break
	check(move_query != null, "Real firing position has a legal neighboring move")
	var hover_timing := {}
	if move_query:
		var enemies: Array[TacticalUnit] = level.turn_manager.enemy_units
		hover_timing = _timing(func(): return TacticalFeedbackText.movement_options(move_query, actor, enemies, grid))
		var options := TacticalFeedbackText.movement_options(move_query, actor, enemies, grid)
		check(options.size() == enemies.size(), "Destination explains both current enemies")
		for option in options:
			var predicted: CombatRules.AttackEvaluation = option.outgoing
			var expected := CombatRules.evaluate_attack_from_cell(actor, move_query.target_cell, option.enemy, grid, null)
			check(predicted.is_legal == expected.is_legal and predicted.hit_chance == expected.hit_chance, "Destination option matches authoritative proposed-origin evaluation")
	check(rng_before == service.get_combat_rng_state() and state_before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Move options and repeated protection/outgoing queries remain pure")
	battle._set_tactical_preview(TacticalFeedbackText.shot(query), TacticalFeedbackText.chance_color(query.hit_chance, query.is_legal()))
	battle.shot_trajectory_visualizer.draw_trajectory(CombatRules.get_shot_origin(actor, grid), query.evaluation.aim_point, query.evaluation, true)
	await _capture("%s-%d-shot" % [id, seed_value], level, (actor.global_position + enemy.global_position) * 0.5)
	if move_query:
		battle.shot_trajectory_visualizer.clear()
		var options := TacticalFeedbackText.movement_options(move_query, actor, level.turn_manager.enemy_units, grid)
		battle.shot_trajectory_visualizer.draw_destination_options(actor, move_query.target_cell, options)
		battle.path_visualizer.draw_path(move_query.path, Color(0, 0.5, 1, 0.4))
		battle._set_tactical_preview(TacticalFeedbackText.movement_description(move_query, actor, options, grid))
		if not is_instance_valid(battle.movement_ghost):
			battle.movement_ghost = MovementGhost.new()
			battle.add_child(battle.movement_ghost)
		battle.movement_ghost.show_destination(actor, move_query.target_cell, grid)
		await _capture("%s-%d-move" % [id, seed_value], level, (actor.global_position + enemy.global_position) * 0.5)
	var result := await service.submit_attack(service.make_attack_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true)
	check(result != null and result.hit_chance == query.hit_chance and result.damage == (query.damage_on_hit if result.did_hit else 0), "Real-site commit honors predicted chance and on-hit damage")
	var row := {"site": String(id), "seed": seed_value, "chance": query.hit_chance, "shot": timing, "inventory": inventory_timing, "destination_options": hover_timing}
	measurements.append(row)
	print("[ClosureQuery] ", JSON.stringify(row))
	level.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		capture_dir = args[0]
		if DisplayServer.get_name() == "headless":
			push_error("Capture requires a renderer")
			quit(1)
			return
		root.size = Vector2i(1440, 900)
		DirAccess.make_dir_recursive_absolute(capture_dir)
	for id in BattlefieldCatalog.PLAYABLE:
		for seed_value in [16, 17]: await _case(id, seed_value)
	check(measurements.size() == 6, "Every site/seed case completed the full contract")
	var timing_path := "res://artifacts/combat-closure-query-cost.json" if capture_dir.is_empty() else capture_dir.path_join("query-cost.json")
	var file := FileAccess.open(timing_path, FileAccess.WRITE)
	check(file != null, "Save query timings")
	if file:
		file.store_string(JSON.stringify({"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(), "renderer": DisplayServer.get_name(), "conditions": measurements}, "\t"))
		file.close()
	print("Real-map combat closure: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
