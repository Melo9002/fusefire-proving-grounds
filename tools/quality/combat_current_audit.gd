extends SceneTree
## Explicit step-1 evidence, not future combat rules or a balance regression gate.
## Replaces only an isolated diagnostic battle's map; never saves runtime content.
var level: BattleLevel
var grid: GridManager
var actor: TacticalUnit
var target: TacticalUnit
var evidence: Array = []
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 1604
	config.player_count = 1
	config.enemy_count = 1
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	if not level.battle_initialization_succeeded:
		push_error("Audit fixture could not initialize")
		quit(1)
		return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	(level.get_node("CameraRig") as TacticalCamera).set_process(false)
	grid = level.battle_controller.grid_manager
	actor = level.turn_manager.player_units[0]
	target = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service

	# A full-height wall blocks the center ray to a raised target, while a
	# higher body sample remains visible. No synthetic LOS flag override.
	_reset(Vector3i(1, 0, 5), Vector3i(6, 0, 5))
	for cell in [Vector3i(8, 2, 5), Vector3i(9, 2, 5)]:
		grid.map_data.add_cell(MapCellData.new(cell, grid.grid_to_world(cell)))
	_place(target, Vector3i(9, 2, 5))
	_solid(Vector3i(5, 0, 5), 2.0, MapCellData.CoverType.FULL)
	MapGraphBuilder.build(grid.map_data, level.battle_controller.pathfinder)
	var shot := level.battle_controller.query_attack(actor, target)
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var hostiles: Array[TacticalUnit] = [target]
	var position_score := AIPositionScorer.evaluate(actor, actor.grid_position, actor.grid_position, Vector3i(-1, -1, -1), 0, false, hostiles, grid, policy, null)
	var inventory := level.battle_controller.query_attack(actor).get_candidate(target.tactical_id)
	actor.tactical_state.establish_overwatch()
	var movement := MoveActionResult.new()
	movement.path_cells.assign([Vector3i(8, 2, 5), target.grid_position])
	service._resolve_overwatch_reactions(target, movement)
	evidence.append({"case": "center_ray_vs_body_samples", "source": [1, 0, 5], "target": [9, 2, 5], "barrier": [5, 0, 5], "barrier_height": 2.0,
		"shot_legal": shot.is_legal(), "chance": shot.hit_chance, "visibility": shot.visibility_fraction,
		"inventory_agrees": inventory.is_legal() == shot.is_legal() and inventory.hit_chance == shot.hit_chance,
		"range_overlay_includes_target": level.battle_controller._legal_shot_cells(actor).has(target.grid_position),
		"ai_position_firing_score": position_score.firing, "guard_checkpoint_reactions": movement.reaction_events.size(),
		"guard_chance": movement.reaction_events[0].hit_chance if not movement.reaction_events.is_empty() else -1})

	# The inverse mismatch: low geometry is tested by shots, but skipped by
	# the center-line helper's LOS-blockers-only candidate set.
	_reset(Vector3i(1, 0, 5), Vector3i(9, 0, 5))
	_solid(Vector3i(2, 0, 5), 1.15, MapCellData.CoverType.LOW)
	shot = level.battle_controller.query_attack(actor, target)
	position_score = AIPositionScorer.evaluate(actor, actor.grid_position, actor.grid_position, Vector3i(-1, -1, -1), 0, false, hostiles, grid, policy, null)
	evidence.append({"case": "low_barrier_false_lane", "source": [1, 0, 5], "target": [9, 0, 5], "barrier": [2, 0, 5], "barrier_height": 1.15,
		"shot_legal": shot.is_legal(), "reason": shot.reason, "visibility": shot.visibility_fraction,
		"range_overlay_includes_target": level.battle_controller._legal_shot_cells(actor).has(target.grid_position), "ai_position_firing_score": position_score.firing})

	# The exact same short obstacle gets the same chance for either cover label.
	for kind in [MapCellData.CoverType.LOW, MapCellData.CoverType.FULL]:
		_reset(Vector3i(1, 0, 5), Vector3i(6, 0, 5))
		_solid(Vector3i(5, 0, 5), 0.2, kind)
		shot = level.battle_controller.query_attack(actor, target)
		evidence.append({"case": "cover_label", "kind": MapCellData.CoverType.keys()[kind], "chance": shot.hit_chance, "visibility": shot.visibility_fraction, "legal": shot.is_legal()})

	# Dominant-axis cover changes abruptly either side of a diagonal tie.
	_reset(Vector3i(1, 0, 2), Vector3i(6, 0, 6))
	_solid(Vector3i(6, 0, 5), 0.2, MapCellData.CoverType.LOW)
	var headings := []
	for source in [Vector3i(1, 0, 2), Vector3i(1, 0, 1), Vector3i(2, 0, 1)]:
		_place(actor, source)
		shot = level.battle_controller.query_attack(actor, target)
		headings.append({"source": [source.x, source.y, source.z], "cover": int(shot.cover_type), "chance": shot.hit_chance})
	evidence.append({"case": "dominant_axis_cover", "target": [6, 0, 6], "cover_cell": [6, 0, 5], "headings": headings})

	# Traversal order is not distance order for blocker diagnostics.
	_reset(Vector3i(9, 0, 5), Vector3i(1, 0, 5))
	_solid(Vector3i(3, 0, 5), 3, MapCellData.CoverType.FULL)
	_solid(Vector3i(7, 0, 5), 3, MapCellData.CoverType.FULL)
	shot = level.battle_controller.query_attack(actor, target)
	evidence.append({"case": "blocker_order", "source": [9, 0, 5], "target": [1, 0, 5], "nearest_blocker": [7, 0, 5],
		"reported_blocker": var_to_str(shot.evaluation.blocking_cell.grid_position) if shot.evaluation.blocking_cell else "none", "reason": shot.reason})

	# Height affects geometry/range, with no explicit clear-shot accuracy bonus.
	_reset(Vector3i(1, 0, 5), Vector3i(6, 0, 5))
	var level_chance := level.battle_controller.query_attack(actor, target).hit_chance
	var raised := Vector3i(1, 2, 5)
	grid.map_data.add_cell(MapCellData.new(raised, grid.grid_to_world(raised)))
	_place(actor, raised)
	evidence.append({"case": "clear_height", "level_chance": level_chance, "elevated_chance": level.battle_controller.query_attack(actor, target).hit_chance,
		"three_dimensional_range": CombatRules.attack_distance(raised, target.grid_position, grid)})

	# Destination feedback evaluates the old Shield state, while Move cancels it.
	_reset(Vector3i(2, 0, 5), Vector3i(7, 0, 5))
	actor.shield_capability = ShieldCapability.new()
	var shield_result = await service.submit_shield(service.make_shield_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	if shield_result == null: failures += 1
	var destination := Vector3i(2, 0, 6)
	var move_query := service.query_move(actor.tactical_id, destination)
	var preview := CombatRules.evaluate_attack_after_move(target, actor, destination, grid, actor.get_world_3d())
	var text_before := TacticalFeedbackText.movement(move_query, actor, hostiles, grid)
	var move_result = await service.submit_move(service.make_move_request(actor, destination, TacticalActionRequest.Source.PLAYER), true)
	if move_result == null: failures += 1
	var after := CombatRules.evaluate_attack(target, actor, grid, actor.get_world_3d())
	evidence.append({"case": "shield_destination", "move_legal": move_query.is_legal(), "preview_shield": preview.shield_applied, "preview_enemy_chance": preview.hit_chance,
		"preview_damage_multiplier": preview.shield_damage_multiplier, "shield_after_move": actor.tactical_state.is_shielding,
		"actual_destination_shield": after.shield_applied, "actual_enemy_chance": after.hit_chance, "actual_damage_multiplier": after.shield_damage_multiplier, "feedback": text_before})

	# Repeated queries/inventory are pure; a normal commit matches its prediction.
	_reset(Vector3i(1, 0, 5), Vector3i(6, 0, 5))
	var rng_before := service.get_combat_rng_state()
	var revision_before := service.state_revision
	var ap_before := actor.stats.current_ap
	shot = service.query_attack(actor.tactical_id, target.tactical_id)
	for index in 100: service.query_attack(actor.tactical_id)
	var pure := rng_before == service.get_combat_rng_state() and service.state_revision == revision_before and actor.stats.current_ap == ap_before
	var result = await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	if result == null: failures += 1
	evidence.append({"case": "query_commit_control", "queries_preserve_rng_revision_ap": pure, "predicted_chance": shot.hit_chance,
		"committed_chance": result.hit_chance if result else -1, "damage": result.damage if result else -1, "roll": result.roll if result else -1})
	# Header acceptance is separate from later per-action divergence checks.
	# This synthetic map is not an archived playable scenario: do not play it back.
	var document: Dictionary = level._replay_recorder.recording.to_dictionary()
	document.simulation_version = "audit-unknown-combat-rules"
	var future_header := BattleReplayRecording.from_dictionary(document)
	evidence.append({"case": "unknown_rules_header", "header_accepted": future_header.is_playable(), "validation": future_header.validation_message(), "full_playback_attempted": false})

	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Supply one JSON output path")
		failures += 1
	else:
		DirAccess.make_dir_recursive_absolute(args[0].get_base_dir())
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"seed": 1604, "records": evidence, "fixture_failures": failures}, "\t"))
		else: failures += 1
	for record in evidence: print("[CombatAudit] ", JSON.stringify(record))
	level.queue_free()
	await process_frame
	await process_frame
	print("Combat audit: %d observations, %d fixture failure(s)" % [evidence.size(), failures])
	quit(1 if failures else 0)

func _reset(source: Vector3i, destination: Vector3i) -> void:
	grid.cell_size = 1.0
	grid.elevation_step = 1.0
	grid.map_floor.size = Vector3(12, 0.2, 12)
	grid.map_floor.position.y = -0.1
	grid.map_data = TacticalMapBuilder.generate(12, 12, 1.0, 1604, 1)
	grid.occupancy_map.clear()
	for unit in [actor, target]:
		unit.tactical_state.reset()
		unit.shield_capability = null
		unit.attack_range = 20
		unit.stats.set_available_ap_for_setup(3)
		unit.stats.current_supply_points = 4
		unit.stats.current_hp = 100
	_place(actor, source)
	_place(target, destination)
	if not grid.grid_to_world(source).is_equal_approx(grid.map_data.get_cell(source).world_position): failures += 1
	MapGraphBuilder.build(grid.map_data, level.battle_controller.pathfinder)

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _solid(cell: Vector3i, height: float, kind: MapCellData.CoverType) -> void:
	var data := grid.get_cell_data(cell)
	data.cover_type = kind
	data.cover_height = height
	data.blocks_line_of_sight = height >= 2
	data.walkable = false
	data.can_stop = false
	grid.map_data.rebuild_los_index()
