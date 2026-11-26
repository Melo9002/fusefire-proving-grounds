extends SceneTree
## Real move, occupancy, combat geometry, IK contact and compiler-versioned replay.
const Parcels = preload("res://systems/generation2/authored_parcel_catalog.gd")
const LocalContent = preload("res://systems/generation2/local_parcel_content.gd")
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const Compiler = preload("res://systems/generation2/authored_scene_map_compiler.gd")
const Pose = preload("res://presentation/tactical/tactical_pose_context.gd")
const Cabinet = preload("res://tests/fixtures/rounded_equipment.tscn")

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	Engine.time_scale = 12.0 if DisplayServer.get_name() == "headless" else 1.0
	_primitive_cases()
	await _tank_battle()
	await _drum_battle()
	await _range_replay()
	print("Curved tactical battle: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _primitive_cases() -> void:
	var curve := RoundedPrism.from_box(Vector3.ZERO, Vector2(1.8, 1.3), 0.65, 1.6, 0.0)
	var corner := Vector3(1.15, 0, 0.65)
	var outward := Vector3(1, 0, 1).normalized()
	var tangent := Vector3(-outward.z, 0, outward.x)
	var near := corner + outward * (0.65 + 0.32)
	check(curve.segment_clear(near - tangent * 0.2, near + tangent * 0.2, 0.28, 1.8, 0.04, 0.0001), "Near-tangent full body sweep is safe")
	var tight := near - outward * 0.025
	check(not curve.segment_clear(tight - tangent * 0.2, tight + tangent * 0.2, 0.28, 1.8, 0.04), "Near-tangent gap smaller than the body is blocked")
	var start := Vector3(-2.0, 0, 0)
	var finish := Vector3(2.0, 0, 0)
	check(curve.segment_clear(start, start, 0.28, 1.8) == false, "Required clearance includes 0.32 m expanded reach")
	start.x = -2.3
	finish.x = 2.3
	check(curve.segment_clear(start, start, 0.28, 1.8) and curve.segment_clear(finish, finish, 0.28, 1.8)
		and not curve.segment_clear(start, finish, 0.28, 1.8), "Both endpoints fit and the route between them is blocked")
	var narrow_center := Vector3(2.25, 0, 0)
	var wall := AABB(Vector3(2.35, 0, -3), Vector3(1, 2, 6))
	var nearby: Array[CylinderPart] = [curve]
	check(not SurfacePlacement.resolve(narrow_center, [wall], 0.28, 1.8, 0.04, 0.5, Vector3.INF, true, nearby).fits,
		"Rounded wall and rectangular neighbor leave no body-sized passage")
	var maker := Cabinet.instantiate() as Node3D
	maker.rotation.y = 0.41
	maker.scale = Vector3(1.5, 2, 1.5)
	var data := TacticalMapBuilder.generate(12, 12, 1.0, 17)
	Compiler.compile(maker, data, 1.0)
	check(data.curved_parts.size() == 1 and data.curved_parts[0] is RoundedPrism, "Yawed and uniformly horizontally scaled fixture compiles a rounded rectangle")
	if not data.curved_parts.is_empty():
		check(is_equal_approx(data.curved_parts[0].radius, 0.975) and is_equal_approx(data.curved_parts[0].height, 3.2), "Horizontal radius and independent vertical scale are preserved")
	maker.scale.x = 1.2
	var fallback := TacticalMapBuilder.generate(12, 12, 1.0, 17)
	Compiler.compile(maker, fallback, 1.0)
	check(fallback.curved_parts.is_empty() and not fallback.movement_parts.is_empty(), "Unsupported elliptical scaling retains a conservative solid box")
	maker.free()

func _make_battle(configuration: BattleConfiguration) -> BattleLevel:
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(configuration)
	root.add_child(level)
	current_scene = level
	return level

func _tank_battle() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	config.player_count = 2
	config.enemy_count = 2
	var battle := _make_battle(config)
	await process_frame
	check(battle.battle_initialization_succeeded, "Service Depot compiles through real battle initialization")
	var grid := battle.battle_controller.grid_manager
	var data := grid.map_data
	check(data.curved_parts.size() == 1, "Depot stores one authoritative round tank")
	if data.curved_parts.is_empty():
		battle.free()
		return
	var tank := data.curved_parts[0]
	var requested := data.content_manifest.duplicate(true)
	requested.compiler_revision = 6
	requested.erase("standing_points_signature")
	var historical := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, 16, 1.0, requested)
	var recovered := _recovered(data, historical, tank)
	check(not recovered.is_empty(), "Tank restores at least one previously blocked stopping cell")
	check(data.get_cell(grid.world_to_grid(tank.center + Vector3.UP * 0.02)) != null and not data.get_cell(grid.world_to_grid(tank.center + Vector3.UP * 0.02)).can_stop, "Tank center still cannot host a body")
	var circle := tank.axis()
	var z := circle.y + tank.radius * 0.78
	var origin := Vector3(circle.x + tank.radius * 0.78, 1.0, z)
	var outside := origin + Vector3.RIGHT * 2.0
	check(CombatRules.get_blocking_cell(origin, outside, grid) == null, "Ray beside the true circular corner passes")
	var blocker := CombatRules.get_blocking_cell(Vector3(circle.x - tank.radius - 1, 1, circle.y), Vector3(circle.x + tank.radius + 1, 1, circle.y), grid)
	check(blocker != null and blocker.curved_part == tank, "Ray through the tank hits the shared curved obstacle")
	var pipe_bounds := AABB()
	for part in data.movement_parts:
		if is_equal_approx(minf(part.size.x, part.size.z), 0.502) and is_equal_approx(maxf(part.size.x, part.size.z), 0.710):
			pipe_bounds = part
			break
	var outward := pipe_bounds.get_center() - tank.center
	outward.y = 0.0
	var across := outward.normalized().cross(Vector3.UP)
	var pipe_point := tank.center + outward.normalized() * (tank.radius + 0.15) + Vector3.UP
	var pipe := CombatRules.get_blocking_cell(pipe_point - across, pipe_point + across, grid)
	check(pipe_bounds.has_volume() and pipe != null and pipe.curved_part == null, "The pipe still blocks a ray outside the round shell")

	if not recovered.is_empty():
		await _move_at_tank(battle, recovered, tank)
	battle.free()
	await process_frame

func _recovered(data: MapData, old: MapData, part: CylinderPart) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: MapCellData in data.cells.values():
		var legacy := old.get_cell(cell.grid_position)
		if not cell.can_stop or not legacy or legacy.can_stop: continue
		var contact := part.contact(cell.world_position)
		if contact.found and contact.distance <= 0.82:
			result.append(cell.grid_position)
	return result

func _move_at_tank(battle: BattleLevel, recovered: Array[Vector3i], tank: CylinderPart) -> void:
	var actor := battle.turn_manager.player_units[0]
	var second := battle.turn_manager.player_units[1]
	var controller := battle.battle_controller
	var grid := controller.grid_manager
	var target := Vector3i(-1, -1, -1)
	var start := Vector3i.ZERO
	for destination in recovered:
		for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var candidate: Vector3i = destination + offset
			if grid.can_unit_occupy_cell(actor, candidate) and SurfaceNavigation.edge_clear(grid.map_data, grid.grid_to_world(candidate), grid.grid_to_world(destination)):
				start = candidate
				target = destination
				break
		if target.x >= 0: break
	check(target.x >= 0, "At least one restored tank cell connects to a legal neighbor")
	if target.x < 0: return
	# Controlled starting positions for this real Depot authority scenario.
	grid.update_unit_position(actor, actor.grid_position, start)
	actor.global_position = grid.grid_to_world(start) + Vector3.UP * actor.standing_height
	battle.turn_manager.select_player_unit(actor)
	var desired := grid.grid_to_world(target)
	var old_second := second.grid_position
	check(grid.can_unit_occupy_cell(second, target), "The recovered tank cell can physically host the second unit")
	grid.update_unit_position(second, old_second, target)
	check(not controller.query_move(actor, target).is_legal(), "Occupied curved stop rejects movement")
	grid.update_unit_position(second, target, old_second)
	var move := controller.query_move(actor, target)
	check(move.is_legal(), "Player move preview sees the restored tile")
	var planner = battle.player_units_parent.get_node("%sAI" % actor.name)
	check(target in planner._legal_move_destinations(), "AI candidate inventory uses the same restored tile")
	if not move.is_legal(): return
	await _capture(battle, grid.grid_to_world(target), "depot-before-move")
	check(await controller.try_move(actor, target), "Authority commits the move beside the real tank")
	var stand := actor.global_position - Vector3.UP * actor.standing_height
	check(stand.is_equal_approx(desired) and SurfaceNavigation.body_clear(grid.map_data, stand), "MIRA reaches the canonical body-clear point")
	var radial := tank.contact(desired)
	var blocked_adjacent := grid.world_to_grid(desired + radial.direction)
	check(CombatRules.can_reach_adjacent(start, target, grid)
		and not CombatRules.can_reach_adjacent(target, blocked_adjacent, grid),
		"Mission adjacency uses supported reach beside the tank and rejects reaching into it")
	var ray_start := desired + Vector3.UP
	var ray_end: Vector3 = ray_start + radial.direction * (radial.distance + 0.03)
	var same_cell_hit := CombatRules.get_blocking_cell(ray_start, ray_end, grid)
	check(grid.world_to_grid(ray_start) == grid.world_to_grid(ray_end)
		and same_cell_hit != null and same_cell_hit.curved_part == tank,
		"A real curved obstacle still blocks a ray entirely inside the recovered cell")
	var contact := Pose.cover_at(grid, target, radial.direction)
	check(contact.get("stand_position", Vector3.INF) == desired and contact.get("surface_normal", Vector3.ZERO).dot(radial.surface_normal) > 0.99,
		"Pose contact uses the same standing point and actual radial normal")
	var defender_side := grid.world_to_grid(desired + radial.direction * (tank.radius * 2.0 + 1.5))
	check(CombatRules.get_directional_cover(defender_side, target, grid) == MapCellData.CoverType.FULL, "Tank provides directional full cover across its real boundary")
	print("[CurveTank] start=%s recovered=%s standing=%s contact=%s" % [start, target, desired, radial.distance])
	await _capture(battle, actor.global_position, "depot-curved-stop")
	await _tank_shot(battle, actor, tank)
	await _move_around_tank(battle, actor, tank, radial.surface_normal)

func _move_around_tank(battle: BattleLevel, actor: TacticalUnit, tank: CylinderPart, initial_normal: Vector3) -> void:
	var controller := battle.battle_controller
	var grid := controller.grid_manager
	var plan: MoveQueryResult
	for x in range(-5, 6):
		for z in range(-5, 6):
			var cell := actor.grid_position + Vector3i(x, 0, z)
			if not grid.can_unit_occupy_cell(actor, cell): continue
			var contact := tank.contact(grid.grid_to_world(cell))
			if not contact.found or contact.distance > 0.82 or contact.surface_normal.dot(initial_normal) > 0.85: continue
			var candidate := controller.query_move(actor, cell)
			if candidate.is_legal() and candidate.path_cells.size() >= 3:
				plan = candidate
				break
		if plan != null: break
	check(plan != null, "A multi-edge Move can turn around the tank while staying beside its shell")
	if plan == null: return
	var destination: Vector3i = plan.path_cells[-1]
	var start := actor.grid_position
	check(await controller.try_move(actor, destination) and actor.grid_position == destination,
		"Authority follows the computed route around the tank")
	print("[CurveArc] start=%s end=%s path=%s" % [start, destination, plan.path_cells])
	await _capture(battle, actor.global_position, "depot-around-tank")

func _tank_shot(battle: BattleLevel, actor: TacticalUnit, tank: CylinderPart) -> void:
	var controller := battle.battle_controller
	var service := controller.action_service
	var grid := controller.grid_manager
	var enemy := battle.turn_manager.enemy_units[0]
	var preview: AttackQueryResult
	var blocked := Vector3i(-1, -1, -1)
	var open := Vector3i(-1, -1, -1)
	for x in range(-7, 8):
		for z in range(-7, 8):
			var cell := actor.grid_position + Vector3i(x, 0, z)
			if not grid.can_unit_occupy_cell(enemy, cell): continue
			_set_fixture_cell(grid, enemy, cell)
			var candidate := controller.query_attack(actor, enemy)
			var obstacle := CombatRules.get_blocking_cell_between_units(actor, enemy, grid)
			if blocked.x < 0 and candidate.reason == "Blocked" and obstacle != null and obstacle.curved_part == tank:
				blocked = cell
			if open.x < 0 and candidate.is_legal() and abs(x) + abs(z) >= 2:
				var standing := grid.grid_to_world(cell)
				var contact := tank.contact(standing)
				if contact.found and contact.distance < 2.0:
					open = cell
			if open.x >= 0 and blocked.x >= 0: break
		if open.x >= 0 and blocked.x >= 0: break
	check(blocked.x >= 0 and open.x >= 0, "Depot fixture has both a blocked tank shot and a legal shot beside its shell")
	if blocked.x < 0 or open.x < 0: return
	actor.tactical_state.is_overwatching = true
	_set_fixture_cell(grid, enemy, blocked)
	check(not service.query_guard_reaction(actor, enemy).can_fire, "Guard cannot shoot through the circular tank")
	check(not controller.query_attack(actor, enemy).is_legal(), "Attack preview rejects the tank obstruction")
	_set_fixture_cell(grid, enemy, open)
	check(service.query_guard_reaction(actor, enemy).can_fire, "Guard can fire beside the tank")
	actor.tactical_state.is_overwatching = false
	preview = controller.query_attack(actor, enemy)
	var inventory := controller.query_attack(actor).get_candidate(enemy.tactical_id)
	check(preview.is_legal() and inventory != null and inventory.is_legal() and inventory.hit_chance == preview.hit_chance,
		"Player preview and AI attack inventory agree")
	var request := service.make_attack_request(actor, enemy, TacticalActionRequest.Source.PLAYER)
	var receipt := await service.submit_attack(request, DisplayServer.get_name() == "headless")
	check(receipt != null and receipt.hit_chance == preview.hit_chance and receipt.environmental_cover == preview.cover_type,
		"Attack beside the tank commits with the preview's chance and cover")
	print("[CurveAttack] actor=%s blocked=%s legal=%s chance=%s" % [actor.grid_position, blocked, open, preview.hit_chance])

func _set_fixture_cell(grid: GridManager, unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _drum_battle() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	config.player_count = 2
	config.enemy_count = 2
	var battle := _make_battle(config)
	await process_frame
	if not battle.battle_initialization_succeeded:
		check(false, "Depot drum battle initializes")
		battle.free()
		return
	var controller := battle.battle_controller
	var grid := controller.grid_manager
	var data := grid.map_data
	var old_manifest := data.content_manifest.duplicate(true)
	old_manifest.compiler_revision = 7
	old_manifest.standing_points_signature = "cdfa61020838350c9d81b07e7d674f5152760c67c7091ce0013852b03f433273"
	var old := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, 16, 1.0, old_manifest)
	check(old.generation_errors.is_empty(), "Revision 7 reconstructs the published Depot standing-point signature")
	var middle := Vector3i(25, 0, 2)
	check(not data.get_cell(middle).can_stop, "The middle of the drum remains physically blocked")
	var solid := CombatRules.get_blocking_cell(Vector3(3.5, 1, -17.5), Vector3(7.0, 1, -17.5), grid)
	check(solid != null and solid.authored_shot_bounds.size.is_equal_approx(Vector3(2.576478, 2.076478, 4.240002)),
		"Shots through the middle still hit the measured drum bounds")
	for index in 2:
		var z := 0 if index == 0 else 5
		var actor := battle.turn_manager.player_units[index]
		var start := Vector3i(24, 0, z)
		var destination := Vector3i(25, 0, z)
		var previous := old.get_cell(destination)
		check(previous != null and not previous.can_stop, "The older drum compiler keeps its original blocked end tile")
		check(grid.can_unit_occupy_cell(actor, start), "Legal approach to the end of the drum")
		_set_fixture_cell(grid, actor, start)
		battle.turn_manager.select_player_unit(actor)
		var preview := controller.query_move(actor, destination)
		check(preview.is_legal(), "Move preview offers the recovered drum end %s" % destination)
		if not preview.is_legal(): continue
		var point := grid.grid_to_world(destination)
		var ray := CombatRules.get_blocking_cell(point + Vector3(-0.9, 1, 0), point + Vector3(0.9, 1, 0), grid)
		check(ray == null, "The visible gap past the drum end also clears a shot")
		check(await controller.try_move(actor, destination) and actor.grid_position == destination
			and (actor.global_position - Vector3.UP * actor.standing_height).is_equal_approx(point),
			"MIRA follows the approved route to the canonical drum end point")
		print("[DrumWalk] %s to %s at %s" % [start, destination, point])
		await _capture(battle, point, "depot-drum-end-%d" % index)
	battle.free()
	await process_frame

func _range_replay() -> void:
	var parcel = Parcels.get_definition(Parcels.SURFACE_FIT_RANGE)
	var root_parcel := parcel.instantiate() as Node3D
	var cabinet := Cabinet.instantiate() as Node3D
	cabinet.position = Vector3(5, 0, 9.5)
	cabinet.rotation.y = 0.41
	root_parcel.add_child(cabinet)
	cabinet.owner = root_parcel
	var packed := PackedScene.new()
	check(packed.pack(root_parcel) == OK, "Mount reusable rounded fixture in Surface Fit Range")
	root_parcel.free()
	var saved := LocalContent.archive(packed)
	check(not saved.has("error"), "Archive exact rounded range fixture")
	if saved.has("error"): return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.PARCEL_TEST)
	config.map_size = parcel.size
	config.player_count = 3
	config.enemy_count = 2
	config.battle_seed = 17
	config.content_manifest = {"local_content": saved.content}
	var battle := _make_battle(config)
	await process_frame
	check(battle.battle_initialization_succeeded, "Rounded fixture initializes through the actual parcel test battle")
	if not battle.battle_initialization_succeeded: battle.free(); return
	var controller := battle.battle_controller
	var grid := controller.grid_manager
	var data := grid.map_data
	check(data.curved_parts.size() == 1 and data.curved_parts[0] is RoundedPrism, "Round rectangle remains round after archive and compilation")
	if data.curved_parts.is_empty(): battle.free(); return
	var part := data.curved_parts[0]
	var old_manifest := data.content_manifest.duplicate(true)
	old_manifest.compiler_revision = 6
	old_manifest.erase("standing_points_signature")
	var old := BattlefieldCatalog.generate(BattlefieldCatalog.PARCEL_TEST, parcel.size, 17, 1.0, old_manifest)
	var recovered := _recovered(data, old, part)
	var target := Vector3i(-1, -1, -1)
	print("[CurveRange] recovered=%s old_errors=%s" % [recovered, old.generation_errors])
	for actor: TacticalUnit in battle.turn_manager.player_units:
		battle.turn_manager.select_player_unit(actor)
		for cell in recovered:
			var planned := controller.query_move(actor, cell)
			if not planned.is_legal():
				print("[CurveRange] %s to %s: %s" % [actor.grid_position, cell, planned.validation.message])
				continue
			var action := await controller.action_service.submit_move(controller.action_service.make_move_request(actor, cell, TacticalActionRequest.Source.PLAYER), DisplayServer.get_name() == "headless")
			check(action != null and actor.grid_position == cell, "MIRA moves into the recovered rounded-corner tile")
			if action == null: continue
			var point := grid.grid_to_world(cell)
			check((actor.global_position - Vector3.UP * actor.standing_height).is_equal_approx(point) and planned.path[-1] == point, "Rounded corner uses identical preview and commit coordinates")
			print("[CurveCabinet] cell=%s standing=%s path=%s" % [cell, point, planned.path_cells])
			target = cell
			await _capture(battle, actor.global_position, "range-rounded-corner")
			break
		if target.x >= 0: break
	check(target.x >= 0, "At least one recovered rounded tile is actually reachable from deployment")
	var recording: BattleReplayRecording = battle._replay_recorder.recording
	var output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://.godot")
	var path := output.path_join("curve-range.replay.json")
	check(recording.save_json(path) == OK, "Save compiled rounded range replay")
	var restored := BattleReplayRecording.load_json(path)
	check(restored != null and restored.is_playable(), "Reload the exact rounded range replay: %s" % (restored.validation_message() if restored else "null"))
	battle.free()
	await process_frame
	if restored == null or not restored.is_playable(): return
	var replay := BattleScene.instantiate() as BattleLevel
	replay.configure_replay(restored)
	root.add_child(replay)
	current_scene = replay
	await process_frame
	var player := replay.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
	var deadline := Time.get_ticks_msec() + 20000
	while player != null and not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
	check(player != null and player.playback_succeeded and player.verified_actions == 1, "Fresh battle replays the exact rounded move and fingerprint")
	replay.free()
	await process_frame

func _capture(battle: BattleLevel, point: Vector3, label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	var camera := battle.get_node("CameraRig") as TacticalCamera
	camera.focus_position(point)
	camera._manual_pitch = true
	camera.rotation = Vector3(deg_to_rad(-44), deg_to_rad(-33), 0)
	camera._set_zoom(14.0)
	for frame in 18: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[1])
	check(root.get_texture().get_image().save_png(args[1].path_join(label + ".png")) == OK, "Saved render " + label)
