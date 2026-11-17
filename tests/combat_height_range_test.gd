extends SceneTree
## Step-6 contract: real support heights, one rounded chance, editable tuning.
var failures := 0
var checks := 0
var level: BattleLevel
var grid: GridManager
var actor: TacticalUnit
var target: TacticalUnit
var capture_path := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture": capture_path = args[1]
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _place(unit: TacticalUnit, key: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, key)
	unit.global_position = grid.grid_to_world(key) + Vector3.UP * unit.standing_height

## Keep actual 3D distance constant when isolating height; points remain in their
## X/Z cells. Y deliberately differs from the named floor to catch index shortcuts.
func _setup(distance: float, source_y := 0.0, target_y := 0.0, unit := 1.0) -> void:
	grid.cell_size = unit
	grid.map_data = TacticalMapBuilder.generate(32, 32, unit, 17)
	grid.occupancy_map.clear()
	var horizontal := sqrt(maxf(0, distance * distance - pow(source_y - target_y, 2)))
	var source := Vector3i(5, 0, 5)
	var destination := source + Vector3i(roundi(horizontal), 0, 0)
	grid.get_cell_data(source).world_position.y = source_y * unit
	grid.get_cell_data(destination).world_position = Vector3((-10.5 + horizontal) * unit, target_y * unit, -10.5 * unit)
	for soldier in [actor, target]:
		soldier.standing_height = unit
		soldier.attack_range = 10
		soldier.tactical_state.reset()
		soldier.stats.set_available_ap_for_setup(3)
		soldier.stats.current_supply_points = 4
	_place(actor, source)
	_place(target, destination)

func _shot(bonus := 0) -> CombatRules.AttackEvaluation:
	return CombatRules.evaluate_attack(actor, target, grid, null, bonus)

func _capture_authored(name: String, shot: CombatRules.AttackEvaluation) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13
	root.add_child(camera)
	camera.make_current()
	var focus := (actor.global_position + target.global_position) * 0.5
	camera.position = focus + Vector3(10, 8, 12)
	camera.look_at(focus)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var label := Label.new()
	label.position = Vector2(32, 32)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_constant_override("outline_size", 6)
	label.text = "%s: %d%% hit\nActual height modifier %+.1f / range penalty %.1f" % [name, shot.hit_chance, shot.height_modifier, shot.range_penalty]
	layer.add_child(label)
	level.get_node("Visualizers/BattleUI").hide()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_path)
	check(root.get_texture().get_image().save_png(capture_path.path_join(name + ".png")) == OK, "Saved actual authored-height review: " + name)
	camera.queue_free()
	layer.queue_free()
	await process_frame

func _run() -> void:
	if not capture_path.is_empty() and DisplayServer.get_name() == "headless":
		push_error("Capture requires a renderer")
		quit(1)
		return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.content_manifest = {"population_enabled": false}
	config.player_count = 1
	config.enemy_count = 1
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Real editable range initializes")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	grid = level.battle_controller.grid_manager
	actor = level.turn_manager.player_units[0]
	target = level.turn_manager.enemy_units[0]
	# Actual authored ramp/stair/deck support, not fabricated floor labels.
	actor.attack_range = 30
	var case_index := 0
	for pair in [[Vector3i(11, 1, 14), Vector3i(15, 0, 15)], [Vector3i(6, 2, 13), Vector3i(2, 0, 15)], [Vector3i(12, 3, 5), Vector3i(12, 0, 3)]]:
		_place(actor, pair[0])
		_place(target, pair[1])
		var shot := _shot()
		var expected := (grid.grid_to_world(pair[0]).y - grid.grid_to_world(pair[1]).y) * 5
		check(shot.is_legal and is_equal_approx(shot.height_modifier, expected), "Authored ramp/stair/deck uses actual height: %s -> %s (%s, height %s)" % [pair[0], pair[1], shot.reason, shot.height_modifier])
		if not capture_path.is_empty(): await _capture_authored(["ramp", "stairs", "deck"][case_index], shot)
		case_index += 1
	for sample in [[2.0, 100], [5.0, 100], [6.0, 100], [7.0, 96], [8.0, 83], [9.0, 61], [10.0, 30]]:
		_setup(sample[0])
		var shot := _shot()
		check(shot.is_legal and shot.hit_chance == sample[1], "Range %s/10 produces %s%%, got %s (%s)" % [sample[0], sample[1], shot.hit_chance, shot.reason])
	_setup(10.001)
	check(not _shot(1000).is_legal and _shot(1000).reason == "Out of range", "Bonuses never extend maximum range")
	for unit: float in [0.5, 1.0, 2.0]:
		for heights in [[2.0, 0.0, 93], [0.0, 2.0, 73], [0.25, 0.0, 84], [0.0, 0.25, 81], [5.0, 0.0, 100], [0.0, 5.0, 63]]:
			_setup(8, heights[0], heights[1], unit)
			var shot := _shot()
			check(shot.is_legal and shot.hit_chance == heights[2] and absf(shot.distance_tiles - 8) < 0.00001, "Height %s/%s at fixed 80%% 3D range, unit %s: expected %s, got %s" % [heights[0], heights[1], unit, heights[2], shot.hit_chance])
	_setup(10)
	check(_shot(CombatRules.cover_tuning.aim_accuracy_bonus).hit_chance == 65, "Step 7 Aim +35: max-range 30 becomes 65")
	_setup(5)
	check(_shot(CombatRules.cover_tuning.guard_accuracy_modifier).hit_chance == 85, "Guard retains its separate -15 modifier")
	_setup(5)
	var wall := grid.get_cell_data(actor.grid_position + Vector3i.RIGHT * 2)
	wall.cover_height = 4
	wall.cover_type = MapCellData.CoverType.FULL
	wall.blocks_line_of_sight = true
	grid.map_data.rebuild_los_index()
	check(not _shot(1000).is_legal and _shot(1000).reason == "Blocked", "Accuracy bonuses never turn solid geometry into a legal shot")
	var tuning = CombatRules.cover_tuning
	var previous := -1.0
	var monotonic := true
	for index in 1001:
		var penalty: float = tuning.range_penalty_for(float(index) / 1000)
		monotonic = monotonic and penalty >= previous and (index > 600 or penalty == 0)
		previous = penalty
	check(monotonic and is_equal_approx(previous, 70), "Dense range sweep preserves plateau, monotonic tail and endpoint")
	for invalid in [["safe_range_fraction", 1.0], ["safe_range_fraction", -0.1], ["range_exponent", 1.0], ["range_penalty_at_limit", -1.0], ["height_accuracy_per_tile", INF], ["height_accuracy_cap", -1.0]]:
		var original: Variant = tuning.get(invalid[0])
		tuning.set(invalid[0], invalid[1])
		check(not tuning.is_valid() and _shot().reason == "Invalid combat tuning", "Invalid tuning rejects: %s" % invalid[0])
		check(BattleReplayRecording.new().validation_message().contains("Invalid combat tuning"), "Replay also rejects invalid tuning: %s" % invalid[0])
		tuning.set(invalid[0], original)
	_setup(8)
	var original_safe: float = tuning.safe_range_fraction
	tuning.safe_range_fraction = 0.8
	check(_shot().hit_chance == 100, "Editing the shared plateau updates the actual evaluation")
	tuning.safe_range_fraction = original_safe
	_setup(8, 2.25, 0.25)
	check(_shot().hit_chance == 93 and _shot().height_modifier == 10, "Common fractional floor translation preserves the relative-height result")
	var signature: String = tuning.signature()
	var original_height: float = tuning.height_accuracy_per_tile
	tuning.height_accuracy_per_tile += 0.00000001
	check(tuning.signature() != signature, "Even small scalar edits change replay compatibility")
	tuning.height_accuracy_per_tile = original_height
	actor.attack_range = 0
	check(not _shot().is_legal and _shot().reason.contains("Invalid attack range"), "Nonpositive weapon range rejects safely")
	actor.attack_range = 10
	grid.cell_size = 0
	check(not _shot().is_legal and is_inf(CombatRules.attack_distance(actor.grid_position, target.grid_position, grid)), "Invalid tile scale never divides by zero")
	_setup(8, 2)
	var before := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var rng_before := level.battle_controller.action_service.get_combat_rng_state()
	var query := level.battle_controller.query_attack(actor, target)
	var prediction := CombatRules.evaluate_attack_from_cell(actor, actor.grid_position, target, grid, null)
	var guard := CombatRules.evaluate_attack_at_cell(actor, target, target.grid_position, grid, null)
	check(query.is_legal() and query.hit_chance == 93 and prediction.hit_chance == 93 and guard.hit_chance == 93, "Service, prediction and checkpoint share height/range calculation")
	check(TacticalFeedbackText.shot(query).contains("Range penalty 17.5") and TacticalFeedbackText.shot(query).contains("Height +10.0"), "Preview explains the same continuous range/height contributions")
	check(before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager) and rng_before == level.battle_controller.action_service.get_combat_rng_state(), "Height/range queries leave authoritative state and combat RNG untouched")
	var service := level.battle_controller.action_service
	var result := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(result != null and result.hit_chance == query.hit_chance and result.did_hit == (result.roll < query.hit_chance), "Committed roll uses exactly the advertised rounded chance")
	level.queue_free()
	await process_frame
	await process_frame
	print("Height and range: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
