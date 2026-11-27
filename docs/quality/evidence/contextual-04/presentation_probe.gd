extends "res://tests/contextual_battlefield_test.gd"
## Normal-speed playback through the ordinary battle cameras. Use --write-movie.
const REPLAY_PATH := "user://contextual-p04-reference.json"
var saved := false


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	if OS.get_cmdline_user_args().has("repeat"):
		await _repeat_then_direct()
		quit(int(failures > 0))
		return
	if OS.get_cmdline_user_args().has("playback"):
		await _playback()
		quit(int(failures > 0))
		return
	if OS.get_cmdline_user_args().has("showcase"):
		await _showcase()
		quit(int(failures > 0))
		return
	await super._run()

func _depot(site: StringName, seed_value: int) -> BattleLevel:
	var level := await super._depot(site, seed_value)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.COMBAT_ONLY
	level.battle_controller.action_service.action_committed.connect(func(result):
		if result is AttackActionResult:
			print("[PresentationAudit] committed ", Engine.get_frames_drawn(), " ", result.request.actor_id, " ", result.firing_solution.to_replay_record()))
	level.battle_controller.attack_resolved.connect(func(actor, _target, _did_hit, _chance):
		if is_instance_valid(actor): print("[PresentationAudit] impact ", Engine.get_frames_drawn(), " ", actor.tactical_id))
	level.battle_controller.action_service.action_presented.connect(func(result):
		if result is AttackActionResult:
			print("[PresentationAudit] settled ", Engine.get_frames_drawn(), " ", result.request.actor_id)
			if not saved and result.request.actor_id == &"EnemyUnit1" and result.firing_solution.body_offset != Vector3.ZERO:
				saved = level._replay_recorder.recording.save_json(REPLAY_PATH) == OK)
	return level

func _observe(actor: TacticalUnit, solution: CombatRules.FiringSolution, label: String) -> Callable:
	var base := super._observe(actor, solution, label)
	return func(timeline):
		print("[PresentationAudit] fired ", Engine.get_frames_drawn(), " ", label, " ", timeline)
		base.call(timeline)

func _repeat_then_direct() -> void:
	var level := await _depot(BattlefieldCatalog.CONTEXTUAL_SHOWCASE, 16)
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	_place(actor, DISCOVERED, grid)
	_place(enemy, OPPONENT, grid)
	for index in 2:
		var query := battle.query_attack(actor, enemy)
		check(query.is_legal() and query.evaluation.firing_solution.body_offset != Vector3.ZERO, "Consecutive Attack retains the contextual solution")
		if not query.is_legal(): return
		actor.visual_adapter.presenter.attack.shot_released.connect(_observe(actor, query.evaluation.firing_solution, "repeat-%d" % index), CONNECT_ONE_SHOT)
		check(await battle.try_attack(actor, enemy), "Attack commits")
	var direct_tile := Vector3i(-1, -1, -1)
	for neighbor in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var cell: Vector3i = DISCOVERED + neighbor
		if not grid.can_unit_occupy_cell(enemy, cell): continue
		var eval := CombatRules.evaluate_attack_at_cell(actor, enemy, cell, grid, null)
		if eval.is_legal and eval.firing_solution.body_offset == Vector3.ZERO:
			direct_tile = cell
			break
	check(direct_tile.x >= 0, "Controlled follow-on has a clear direct lane")
	if direct_tile.x < 0: return
	_place(enemy, direct_tile, grid)
	var direct := battle.query_attack(actor, enemy)
	check(direct.is_legal() and direct.evaluation.firing_solution.body_offset == Vector3.ZERO, "Direct shot follows the contextual posture")
	actor.visual_adapter.presenter.attack.shot_released.connect(func(timing):
		print("[PresentationAudit] fired ", Engine.get_frames_drawn(), " direct-after ", timing), CONNECT_ONE_SHOT)
	check(await battle.try_attack(actor, enemy), "Direct Attack commits")
	check(actor.grid_position == DISCOVERED and not actor.visual_adapter._contextual_attack_active, "Direct shot starts and ends at the same canonical tile")
	for frame in 15: await process_frame

func _showcase() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_SHOWCASE)
	config.battle_seed = 16
	config.player_count = 2
	config.enemy_count = 2
	config.difficulty = AIDifficultyPolicy.Tier.HARD
	config.enemy_commander = AICommanderPolicy.Profile.CAUTIOUS
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Stock 2v2 showcase loads")
	if not level.battle_initialization_succeeded: return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.COMBAT_ONLY
	for frame in 15: await process_frame
	level.turn_manager.end_current_turn()
	var shown := []
	level.battle_controller.action_service.action_presented.connect(func(result):
		if result is AttackActionResult and result.request.source == TacticalActionRequest.Source.AI:
			shown.append(result)
			print("[Showcase] ", result.request.actor_id, " ", result.firing_solution.to_replay_record()))
	var deadline := Time.get_ticks_msec() + 30000
	while level.turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not shown.is_empty() and level.turn_manager.current_phase != TurnManager.TurnPhase.ENEMY_TURN, "An ordinary autonomous enemy turn gets to fire and settles")
	for frame in 15: await process_frame

func _playback() -> void:
	var recording := BattleReplayRecording.load_json(REPLAY_PATH)
	check(recording.is_playable(), "Recorded contextual showcase action is playable")
	if not recording.is_playable(): return
	var level := Scene.instantiate() as BattleLevel
	level.configure_replay(recording)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Contextual replay scene reconstructs")
	if not level.battle_initialization_succeeded: return
	var actor: TacticalUnit = level.turn_manager.enemy_units[0]
	var target: TacticalUnit = level.turn_manager.player_units[0]
	var grid := level.battle_controller.grid_manager
	var solution := CombatRules.evaluate_attack_from_cell(actor, DISCOVERED, target, grid, null).firing_solution
	actor.visual_adapter.presenter.attack.shot_released.connect(_observe(actor, solution, "replayed"), CONNECT_ONE_SHOT)
	var replay := level.get_node("BattleReplayPlayer") as BattleReplayPlayer
	replay.set_camera_mode(BattleReplayPlayer.CameraMode.CINEMATIC)
	var success: bool = await replay.playback_finished
	check(success and replay.verified_actions == recording.actions.size(), "Normal-speed replay verifies all contextual records")
