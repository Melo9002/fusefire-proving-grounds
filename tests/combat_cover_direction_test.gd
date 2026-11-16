extends SceneTree
## Intended step-5 contract: physical protection, 20/40 cover and max stacking.
var failures := 0
var checks := 0
var level: BattleLevel
var grid: GridManager
var actor: TacticalUnit
var target: TacticalUnit
const CENTER := Vector3i(16, 0, 16)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _rot(offset: Vector3i, turn: int) -> Vector3i:
	var point := Basis(Vector3.UP, turn * PI * 0.5) * Vector3(offset)
	return Vector3i(roundi(point.x), offset.y, roundi(point.z))

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.get_cell_data(cell).world_position

func _reset(turn := 0) -> void:
	grid.map_data = TacticalMapBuilder.generate(32, 32, 1, 17)
	grid.occupancy_map.clear()
	actor.standing_height = 1
	target.standing_height = 1
	actor.tactical_state.clear_aim()
	target.tactical_state.clear_shield()
	_place(actor, CENTER + _rot(Vector3i(-5, 0, 0), turn))
	_place(target, CENTER)

func _solid(at: Vector3i, height: float, cover: MapCellData.CoverType) -> MapCellData:
	var cell := grid.get_cell_data(at)
	cell.cover_height = height
	cell.cover_type = cover
	cell.walkable = cover == MapCellData.CoverType.LOW
	cell.can_stop = false
	cell.blocks_line_of_sight = cover == MapCellData.CoverType.FULL
	cell.authored_shot_parts.assign([AABB(cell.world_position + Vector3(-0.45, 0, -0.45), Vector3(0.9, height, 0.9))])
	cell.authored_shot_bounds = cell.authored_shot_parts[0]
	grid.map_data.rebuild_los_index()
	return cell

func _shot() -> CombatRules.AttackEvaluation:
	return CombatRules.evaluate_attack(actor, target, grid, level.get_world_3d())

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Cover checks start a real validated battle")
	if not level.battle_initialization_succeeded:
		level.queue_free()
		await process_frame
		quit(1)
		return
	grid = level.battle_controller.grid_manager
	actor = level.turn_manager.player_units[0]
	target = level.turn_manager.enemy_units[0]
	for turn in 4:
		_reset(turn)
		_solid(CENTER + _rot(Vector3i.LEFT, turn), 0.8, MapCellData.CoverType.LOW)
		var front := _shot()
		check(front.is_legal and front.cover_type == MapCellData.CoverType.LOW and is_equal_approx(front.visibility_fraction, 0.8) and front.hit_chance == 80, "Low cover protects the front for 20 points, without adding the 10-point exposure penalty; turn %d" % turn)
		check(front.cover_cell == grid.get_cell_data(CENTER + _rot(Vector3i.LEFT, turn)) and front.cover_penalty == 20 and front.obstruction_penalty == 10 and front.protection_penalty == 20, "Evaluation identifies the actual protecting cell and separate, non-stacked contributions")
		_place(actor, CENTER + _rot(Vector3i(3, 0, 0), turn))
		check(_shot().cover_type == MapCellData.CoverType.NONE and _shot().hit_chance == 100, "Rear attack flanks the cover; turn %d" % turn)
		_place(actor, CENTER + _rot(Vector3i(0, 0, -3), turn))
		check(_shot().cover_type == MapCellData.CoverType.NONE and _shot().hit_chance == 100, "Side attack flanks the cover; turn %d" % turn)
		_place(actor, CENTER + _rot(Vector3i(-5, 0, 0), turn))
		grid.get_cell_data(actor.grid_position).world_position.y = 4
		check(_shot().cover_type == MapCellData.CoverType.NONE and _shot().hit_chance == 100, "Shooting physically above low cover removes its protection; turn %d" % turn)
		_reset(turn)
		_solid(CENTER + _rot(Vector3i.LEFT, turn), 1.3, MapCellData.CoverType.FULL)
		grid.get_cell_data(actor.grid_position).world_position.y = 1.2
		var full := _shot()
		check(full.is_legal and full.cover_type == MapCellData.CoverType.FULL and is_equal_approx(full.visibility_fraction, 0.4) and full.hit_chance == 60, "Full cover and two visible samples produce max(40,40), not 80; turn %d" % turn)
	_reset()
	_place(actor, CENTER + Vector3i(-4, 0, -4))
	var west := _solid(CENTER + Vector3i.LEFT, 1.3, MapCellData.CoverType.FULL)
	var north := _solid(CENTER + Vector3i.FORWARD, 1.3, MapCellData.CoverType.FULL)
	west.authored_shot_parts.clear()
	west.authored_shot_bounds = AABB()
	north.authored_shot_parts.clear()
	north.authored_shot_bounds = AABB()
	var diagonal := _shot()
	check(diagonal.is_legal and diagonal.cover_type == MapCellData.CoverType.FULL and diagonal.protection_penalty == 50, "Paired full-cover corners protect the same lower-body seam as LOS, without stacking two faces")
	# A candidate with a taller body must use that body, not a default-height ghost.
	_reset()
	_solid(CENTER + Vector3i.LEFT, 0.8, MapCellData.CoverType.LOW)
	target.standing_height = 2
	check(_shot().cover_type == MapCellData.CoverType.NONE, "Tall body's lower reference clears a small crate")
	check(CombatRules.get_directional_cover(actor.grid_position, target.grid_position, grid) == MapCellData.CoverType.NONE, "Occupied generic cover query uses the actual target height")
	var tall_candidate := CENTER + Vector3i.BACK
	_place(target, tall_candidate)
	check(CombatRules.evaluate_attack_at_cell(actor, target, CENTER, grid, level.get_world_3d()).cover_type == MapCellData.CoverType.NONE, "Hypothetical destination retains the actual tall body's height")
	_reset()
	var missed := _solid(CENTER + Vector3i.LEFT, 0.8, MapCellData.CoverType.LOW)
	missed.authored_shot_parts.assign([AABB(missed.world_position + Vector3(-0.45, 0, 0.35), Vector3(0.9, 0.8, 0.1))])
	check(_shot().cover_type == MapCellData.CoverType.NONE and _shot().hit_chance == 100, "A neighboring label cannot protect when its actual part misses the body ray")
	_reset()
	_solid(CENTER + Vector3i.LEFT, 0.2, MapCellData.CoverType.LOW)
	check(_shot().cover_type == MapCellData.CoverType.NONE and _shot().hit_chance == 100, "A tiny crate below the lower-body reference does not invent cover")
	_reset()
	var compound := _solid(CENTER + Vector3i.LEFT, 1.3, MapCellData.CoverType.FULL)
	compound.authored_shot_parts.assign([
		AABB(compound.world_position + Vector3(-0.45, 0, -0.45), Vector3(0.9, 1.3, 0.25)),
		AABB(compound.world_position + Vector3(-0.45, 0, 0.2), Vector3(0.9, 1.3, 0.25)),
	])
	var gap := _shot()
	check(gap.is_legal and gap.cover_type == MapCellData.CoverType.NONE and is_equal_approx(gap.visibility_fraction, 0.6) and gap.hit_chance == 75, "An empty compound gap gives no cover but retains genuine shoulder obstruction")
	_reset()
	var mixed := _solid(CENTER + Vector3i.LEFT, 2, MapCellData.CoverType.FULL)
	mixed.authored_shot_parts.assign([
		AABB(mixed.world_position + Vector3(-0.45, 0, -0.45), Vector3(0.9, 0.8, 0.9)),
		AABB(mixed.world_position + Vector3(-0.45, 0, 0.35), Vector3(0.9, 2, 0.1)),
	])
	var low_part := _shot()
	check(low_part.cover_cell == mixed and low_part.cover_type == MapCellData.CoverType.LOW and low_part.hit_chance == 80, "A low protecting part does not inherit full cover from a different tall part sharing its cell")
	_reset()
	_solid(CENTER + Vector3i.LEFT * 3, 1, MapCellData.CoverType.LOW)
	var distant := _shot()
	check(distant.is_legal and distant.cover_type == MapCellData.CoverType.NONE and distant.hit_chance == 60, "Distant obstruction is not adjacent cover and still affects exposure")
	_reset()
	_solid(CENTER + Vector3i.LEFT, 0.8, MapCellData.CoverType.LOW)
	target.shield_capability = ShieldCapability.new()
	target.tactical_state.establish_shield(Vector2.LEFT)
	check(_shot().hit_chance == 60, "Shield's separate -20 stacks with max(cover, exposure), not their sum")
	target.tactical_state.clear_shield()
	var before := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var query := level.battle_controller.query_attack(actor, target)
	var predicted := CombatRules.evaluate_attack_from_cell(actor, actor.grid_position, target, grid, level.get_world_3d())
	check(query.is_legal() and query.hit_chance == 80 and predicted.hit_chance == query.hit_chance, "Service and predicted-cell evaluation use the same cover result")
	check(before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Cover queries do not mutate occupancy, stance or resources")
	var service := level.battle_controller.action_service
	var result := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(result != null and result.hit_chance == query.hit_chance, "Committed attack uses the advertised cover-adjusted chance")
	var tuning = CombatRules.cover_tuning
	var original_low: int = tuning.low_cover_penalty
	tuning.low_cover_penalty = 25
	var tuned := _shot()
	check(tuned.hit_chance == 75, "Editing the shared low-cover value updates evaluation without changing its geometry; chance=%d cover=%d exposure=%d tuning=%d shared=%d" % [tuned.hit_chance, tuned.cover_penalty, tuned.obstruction_penalty, tuning.low_cover_penalty, CombatRules.cover_tuning.low_cover_penalty])
	tuning.low_cover_penalty = 100
	check(_shot().reason == "Invalid cover tuning" and CombatRules.evaluate_attack_from_cell(actor, actor.grid_position, target, grid, level.get_world_3d()).reason == "Invalid cover tuning", "Invalid tuning rejects normal and predicted shots consistently")
	tuning.low_cover_penalty = original_low
	level.queue_free()
	await process_frame
	await process_frame
	if OS.get_cmdline_user_args().has("capture") and DisplayServer.get_name() != "headless":
		await _capture_range()
	print("Directional cover: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _capture_range() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.content_manifest = {"population_enabled": false}
	config.battle_seed = 17
	config.player_count = 1
	config.enemy_count = 1
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	level.battle_controller.set_process(false)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	level.get_node("Visualizers/BattleUI").hide()
	grid = level.battle_controller.grid_manager
	actor = level.turn_manager.player_units[0]
	target = level.turn_manager.enemy_units[0]
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	root.add_child(camera)
	camera.make_current()
	var caption_layer := CanvasLayer.new()
	caption_layer.layer = 100
	root.add_child(caption_layer)
	var caption := Label.new()
	caption.position = Vector2(32, 32)
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_constant_override("outline_size", 6)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption_layer.add_child(caption)
	DirAccess.make_dir_recursive_absolute("res://artifacts/cover-direction")
	for setup in [
		["low-cover", Vector3i(23, 0, 13), Vector3i(23, 0, 17), 80, MapCellData.CoverType.LOW],
		["flank", Vector3i(25, 0, 17), Vector3i(23, 0, 17), 100, MapCellData.CoverType.NONE],
		["full-cover", Vector3i(27, 0, 13), Vector3i(27, 0, 17), 50, MapCellData.CoverType.FULL],
	]:
		_place(actor, setup[1])
		_place(target, setup[2])
		actor.global_position += Vector3.UP * actor.standing_height
		target.global_position += Vector3.UP * target.standing_height
		var query := level.battle_controller.query_attack(actor, target)
		check(query.is_legal() and query.hit_chance == setup[3] and query.cover_type == setup[4], "Real editable range matches %s expectation" % setup[0])
		var evaluation := query.evaluation
		caption.text = "%s: %d%% hit\nCover %d / exposure %d -> combined %d (stronger only)" % [setup[0], query.hit_chance, evaluation.cover_penalty, evaluation.obstruction_penalty, evaluation.protection_penalty]
		var view_offset := Vector3(7, 8, 10) if setup[0] == "full-cover" else Vector3(-7, 8, 6)
		camera.position = grid.grid_to_world(setup[2]) + view_offset
		camera.look_at(grid.grid_to_world(setup[2]) + Vector3(0, 0.6, -1.7))
		level.battle_controller.shot_trajectory_visualizer.draw_trajectory(CombatRules.get_shot_origin(actor, grid), query.aim_point, evaluation, true)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://artifacts/cover-direction/%s.png" % setup[0]) == OK, "Cover capture saved: %s" % setup[0])
	caption_layer.queue_free()
	camera.queue_free()
	level.queue_free()
	await process_frame
	await process_frame
