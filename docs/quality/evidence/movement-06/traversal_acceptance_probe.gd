extends SceneTree
## Companion to the ordinary traversal suites. Runs the real Range at seed 1.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0
var capture_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func(): quit(2))
	if DisplayServer.get_name() == "headless":
		Engine.time_scale = 5.0
	elif not OS.get_cmdline_user_args().is_empty():
		capture_dir = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor := f.turns.player_units[0]
	var enemy := f.turns.enemy_units[0]
	var service := f.battle.action_service
	var receipts: Array = []
	service.action_committed.connect(func(result): receipts.append(result))
	var stairs := [Vector3i(6, 0, 15), Vector3i(6, 3, 12)]
	var ramp := [Vector3i(11, 0, 15), Vector3i(11, 3, 12)]
	var ladder := [Vector3i(12, 0, 4), Vector3i(12, 3, 5)]
	var vault := [Vector3i(21, 0, 9), Vector3i(21, 0, 11)]
	var vault_checkpoint := Vector3i(21, 0, 10)
	f.place(enemy, Vector3i(8, 0, 9))
	for scenario in [["stairs", stairs, 3.0], ["ramp", ramp, 3.0], ["ladder", ladder, 1.0], ["vault", vault, 3.0]]:
		for direction in [0, 1]:
			await _check_move(f, actor, scenario[1][direction], scenario[1][1 - direction],
				"%s-%s" % [scenario[0], "forward" if direction == 0 else "reverse"], scenario[2], receipts)
	await _check_move(f, actor, Vector3i(5, 0, 15), stairs[1], "stairs-turned-entry", 4.0, receipts)

	f.place(actor, ladder[0])
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var clear := f.battle.query_move(actor, ladder[1])
	var request := service.make_move_request(actor, ladder[1], TacticalActionRequest.Source.PLAYER)
	f.place(enemy, ladder[1])
	var revision := service.state_revision
	var rng := service.get_combat_rng_state()
	var count := receipts.size()
	var ap := actor.stats.current_ap
	var occupied := f.battle.query_move(actor, ladder[1])
	_check(clear.is_legal() and not occupied.is_legal() and occupied.validation.code == &"occupied",
		"An occupied ladder landing invalidates the previous legal preview")
	_check(await service.submit_move(request, true) == null and service.last_rejection.code == &"occupied",
		"Fresh validation rejects the unversioned landing change")
	_check(service.state_revision == revision and service.get_combat_rng_state() == rng
		and receipts.size() == count and actor.stats.current_ap == ap and f.grid.get_unit_at(ladder[0]) == actor
		and f.grid.get_unit_at(ladder[1]) == enemy, "Rejected Move is read-only")
	print("[Occupied landing] initial=", clear.path_cells, " rejection=", occupied.validation.code)

	f.place(actor, Vector3i(12, 0, 3))
	await _check_ai_route(f, enemy, ladder[0], ladder[0], receipts)
	f.place(enemy, vault[1])
	f.place(actor, Vector3i(21, 0, 7))
	var closed: Array[MapCellData] = []
	# Constrain the approach so the AI must evaluate the barrier instead of flanking.
	for x in [20, 22]:
		for z in range(8, 13):
			var side := f.grid.get_cell_data(Vector3i(x, 0, z))
			if side != null and side.walkable:
				side.walkable = false
				closed.append(side)
	f.rebuild_graph()
	f.battle.pathfinder.live_grid = f.grid
	await _check_ai_route(f, enemy, vault[0], vault_checkpoint, receipts)
	f.place(actor, Vector3i(21, 0, 8))
	f.place(enemy, Vector3i(21, 0, 13))
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var corridor := f.battle.query_move(actor, vault[1])
	var crossing := service.make_move_request(actor, vault[1], TacticalActionRequest.Source.PLAYER)
	f.place(enemy, vault[0])
	var before_block: Array = [service.state_revision, service.get_combat_rng_state(), receipts.size(), actor.stats.current_ap]
	var blocked := f.battle.query_move(actor, vault[1])
	_check(corridor.is_legal() and vault[0] in corridor.path_cells and vault[0] not in blocked.path_cells,
		"An intermediate live occupant invalidates the previously legal path")
	var updated := await service.submit_move(crossing, true)
	if blocked.is_legal():
		_check(updated != null and updated.path_cells == blocked.path_cells and f.grid.get_unit_at(vault[1]) == actor
			and blocked.path_cost <= blocked.movement_budget and service.state_revision == before_block[0] + 1
			and f.grid.get_unit_at(vault[0]) == enemy, "Confirmation commits the legal detour, preserving the blocker")
	else:
		_check(updated == null and before_block ==
			[service.state_revision, service.get_combat_rng_state(), receipts.size(), actor.stats.current_ap]
			and f.grid.get_unit_at(vault[0]) == enemy and f.grid.get_unit_at(Vector3i(21, 0, 8)) == actor,
			"Changed route occupancy rejects the previously valid request without mutation")
	print("[Occupied approach] initial=", corridor.path_cells, " updated=", blocked.path_cells,
		" reason=", blocked.validation.code, " cost=", blocked.path_cost)
	for side in closed:
		side.walkable = true
	f.rebuild_graph()
	f.battle.pathfinder.live_grid = f.grid

	f.place(enemy, Vector3i(21, 0, 13))
	f.place(actor, vault[0])
	f.ready_actor(enemy, 6, 4)
	f.act_as(enemy)
	var armed := await service.submit_overwatch(service.make_overwatch_request(enemy, TacticalActionRequest.Source.AI), true)
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var air := f.battle.query_move(actor, vault_checkpoint)
	var guard_air := service.query_guard_reaction(enemy, actor, vault_checkpoint)
	var guard_end := service.query_guard_reaction(enemy, actor, vault[1])
	_seed_guard_hit(service, guard_air)
	var reactive := await service.submit_move(service.make_move_request(actor, vault[1], TacticalActionRequest.Source.PLAYER), true)
	_check(armed != null and not air.is_legal() and air.validation.code == &"transit_only",
		"Vault checkpoint permits transit and prohibits stopping")
	_check(reactive != null and reactive.reaction_events.size() == 1 and not reactive.movement_interrupted,
		"Guard consumes one reaction while the surviving mover completes the vault")
	if reactive != null and not reactive.reaction_events.is_empty():
		var event := reactive.reaction_events[0]
		_check(event.did_hit and event.checkpoint_cell == vault_checkpoint and event.checkpoint_index == 1
			and reactive.path_cells[event.checkpoint_index] == event.checkpoint_cell,
			"Guard hits at the airborne logical checkpoint before the legal landing")
		print("[Guard vault] route=", reactive.path_cells, " checkpoint=", event.checkpoint_cell,
			" air=", guard_air.reason, " landing=", guard_end.reason, " hit=", event.did_hit)

	f.place(actor, vault[0])
	f.ready_actor(enemy, 6, 4)
	f.act_as(enemy)
	await service.submit_overwatch(service.make_overwatch_request(enemy, TacticalActionRequest.Source.AI), true)
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	actor.stats.current_hp = 1
	_seed_guard_hit(service, service.query_guard_reaction(enemy, actor, vault_checkpoint))
	var interrupted := await service.submit_move(service.make_move_request(actor, vault[1], TacticalActionRequest.Source.PLAYER), true)
	_check(interrupted != null and interrupted.movement_interrupted and interrupted.path_cells == [vault[0], vault_checkpoint]
		and interrupted.target_cell == vault_checkpoint and actor.stats.is_defeated and interrupted.presentation_completed,
		"Lethal Guard truncates the vault at the airborne logical checkpoint")
	_check(f.grid.get_unit_at(vault[0]) == null and f.grid.get_unit_at(vault_checkpoint) == null
		and f.grid.get_unit_at(vault[1]) == null and not service.is_busy, "Defeat leaves no occupancy or busy action on the route")
	if interrupted:
		print("[Lethal vault] route=", interrupted.path_cells, " AP=", interrupted.actor_ap_before - interrupted.actor_ap_after)
	await f.dispose(self)
	await _check_replay(ladder[0], ladder[1])
	await _check_replay(vault[0], vault[1])
	print("Traversal acceptance: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _seed_guard_hit(service: TacticalActionService, opportunity: Dictionary) -> void:
	if not opportunity.get("can_fire", false):
		return
	var rng := RandomNumberGenerator.new()
	for candidate in range(1, 1000):
		rng.seed = candidate
		if AttackActionResult.roll_hits(rng.randf() * 100.0, opportunity.evaluation.hit_chance):
			service._combat_rng.seed = candidate
			return

func _check_replay(start: Vector3i, end: Vector3i) -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor := f.turns.player_units[0]
	f.place(actor, start)
	var recording: BattleReplayRecording = f.level._replay_recorder.recording
	recording.initial_state_fingerprint = BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager)
	var service := f.battle.action_service
	for destination in [end, start]:
		var request := service.make_move_request(actor, destination, TacticalActionRequest.Source.PLAYER)
		var result := await service.submit_move(request, true)
		_check(result != null, "Round-trip recording commits Move to %s" % destination)
	var restored := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary())))
	_check(restored.is_playable() and restored.actions.size() == 2, "Traversal recording round-trips through JSON")
	await f.dispose(self)
	if not restored.is_playable():
		return
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_replay(restored)
	level.battle_initialization_finished.connect(func(ok: bool, _errors: Array):
		if ok:
			var replay_actor: TacticalUnit = level.turn_manager.player_units[0]
			var grid: GridManager = level.battle_controller.grid_manager
			grid.update_unit_position(replay_actor, grid.get_unit_grid(replay_actor), start)
			replay_actor.global_position = grid.grid_to_world(start) + Vector3.UP * replay_actor.standing_height
	, CONNECT_ONE_SHOT)
	root.add_child(level)
	await process_frame
	var player := level.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
	if player:
		player.set_playback_speed(4.0)
		var deadline := Time.get_ticks_msec() + 15000
		while not player.playback_complete and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(player.playback_succeeded and player.verified_actions == 2
			and level.turn_manager.player_units[0].grid_position == start,
			"Playback matches receipts, fingerprints and arrival: " + player.last_divergence)
		print("[Replay] ", start, " -> ", end, " -> ", start, " verified=", player.verified_actions,
			" divergence=", player.last_divergence)
	else:
		_check(false, "Traversal playback did not initialize")
	level.queue_free()
	await process_frame

func _check_ai_route(f: RefCounted, enemy: TacticalUnit, goal: Vector3i, through: Vector3i, receipts: Array) -> void:
	f.ready_actor(enemy, 6, 4)
	f.act_as(enemy)
	var inventory: Array[Vector3i] = f.legal_moves(enemy)
	var expected: MoveQueryResult = f.battle.query_move(enemy, goal)
	var count := receipts.size()
	var ai: AIController = f.ai_of(enemy)
	ai._ensure_policy()
	ai._squad_context = f.battle.get_squad_context(enemy)
	ai.current_mission_intent = ai._get_ai_mission_intent()
	if await ai._move_toward_cell(goal, false, "authored route check") and receipts.size() == count + 1:
		var result: MoveActionResult = receipts.back()
		_check(result.target_cell == goal and goal in inventory and f.grid.get_unit_at(goal) == enemy
			and result.request.source == TacticalActionRequest.Source.AI, "AI commits the goal from its shared inventory")
		_check(expected.is_legal() and result.path_cells == expected.path_cells and through in result.path_cells
			and result.actor_ap_before - result.actor_ap_after == expected.cost.ap, "AI route and AP match the shared targeted query")
		print("[AI] goal=", goal, " route=", result.path_cells, " AP=", result.actor_ap_before - result.actor_ap_after)
	else:
		_check(false, "AI did not commit a Move toward %s: %s" % [goal, ai._route_block_note])

func _check_move(f: RefCounted, actor: TacticalUnit, start: Vector3i, end: Vector3i, label: String,
		expected_weight: float, receipts: Array) -> void:
	if actor.grid_position != start:
		f.place(actor, start)
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var battle: BattleController = f.battle
	var service := battle.action_service
	var inventory: MoveQueryResult = battle.query_move(actor)
	var query := battle.query_move(actor, end)
	_check(inventory.is_legal() and end in inventory.legal_destination_cells and query.is_legal(),
		label + ": inventory and targeted query agree")
	if not query.is_legal():
		return
	battle.tactical_unit = actor
	battle.is_move_mode_active = true
	var capture := not capture_dir.is_empty() and label == "vault-forward"
	var hit := {"grid_position": end, "position": f.grid.grid_to_world(end)}
	if capture:
		var camera := f.level.get_node("CameraRig") as TacticalCamera
		camera.focus_position((f.grid.grid_to_world(start) + f.grid.grid_to_world(end)) * 0.5)
		camera._manual_pitch = true
		camera.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(-75.0), 0)
		camera._set_zoom(8.0)
		await create_timer(0.5).timeout
		hit = battle.mouse_raycaster.get_floor_raycast_result(camera.camera.unproject_position(f.grid.grid_to_world(end)))
		_check(hit.get("grid_position") == end, "The viewport ray selects the vault landing")
	battle._update_movement_preview(hit)
	var preview := battle._preview_query
	_check(preview != null and preview.path_cells == query.path_cells and preview.path_cost == query.path_cost
		and battle.movement_ghost.visible and battle.movement_ghost.destination.is_equal_approx(f.grid.grid_to_world(end)),
		label + ": active preview shows the authorized route and canonical ghost")
	if capture:
		await _capture("vault-preview", func(): battle._update_movement_preview(hit))
	battle.toggle_move_mode()
	var seen := receipts.size()
	var revision := service.state_revision
	if capture:
		create_timer(0.35).timeout.connect(func(): await _capture("vault-crossing"))
	var moved := await battle.try_move(actor, end)
	_check(moved and receipts.size() == seen + 1, label + ": exactly one Move committed")
	if not moved or receipts.size() != seen + 1:
		return
	var result: MoveActionResult = receipts.back()
	_check(result.path_cells == query.path_cells and result.actor_ap_after == query.actor_ap_after
		and result.actor_ap_before - result.actor_ap_after == query.cost.ap
		and result.committed_revision == revision + 1 and is_equal_approx(query.path_cost, expected_weight)
		and query.path_cost <= query.movement_budget,
		label + ": receipt agrees on route, budget, AP and revision")
	var landing: Vector3 = f.grid.grid_to_world(end) + Vector3.UP * actor.standing_height
	_check(f.grid.get_unit_at(start) == null and f.grid.get_unit_at(end) == actor
		and result.presentation_completed and actor.global_position.is_equal_approx(landing),
		label + ": occupancy and presentation settle at the canonical stop")
	print("[Traversal] ", label, " path=", result.path_cells, " cost=", query.path_cost,
		" budget=", query.movement_budget, " AP=", query.cost.ap, " arrival=", actor.global_position)
	if capture:
		await _capture("vault-arrival")

func _capture(label: String, before_draw := Callable()) -> void:
	if before_draw.is_valid():
		await RenderingServer.frame_pre_draw
		before_draw.call()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "Saved " + label)
