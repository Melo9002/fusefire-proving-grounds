extends SceneTree
## Preserved human replay. All comparison rays inspect verified states without changing them.
const Battle := preload("res://levels/prototype_map/prototype_map.tscn")
const REVISIONS := [22, 23, 28, 29, 36, 37, 41, 42, 55, 56, 64, 66, 67, 73, 74, 75, 80]
var recording: BattleReplayRecording
var level: BattleLevel

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(2)
		return
	recording = BattleReplayRecording.load_json(args[0])
	if not recording.is_playable():
		push_error(recording.validation_message())
		quit(1)
		return
	level = Battle.instantiate()
	level.configure_replay(recording)
	root.add_child(level)
	if not level.battle_initialization_succeeded:
		quit(1)
		return
	var player := level.get_node("BattleReplayPlayer") as BattleReplayPlayer
	player.set_playback_speed(4)
	player.playback_progressed.connect(_capture)
	var success: bool = await player.playback_finished
	quit(0 if success and player.verified_actions == recording.actions.size() else 1)

func _capture(index: int, _total: int) -> void:
	var battle := level.battle_controller
	var service := battle.action_service
	var revision := service.state_revision
	if revision not in REVISIONS: return
	var grid := battle.grid_manager
	var rows := []
	for player in level.turn_manager.player_units:
		if not is_instance_valid(player) or player.stats.is_defeated: continue
		for enemy in level.turn_manager.enemy_units:
			if not is_instance_valid(enemy) or enemy.stats.is_defeated: continue
			rows.append(_lane(player, enemy, grid))
			rows.append(_lane(enemy, player, grid))
	print("[ReplayLanes] ", JSON.stringify({"index": index, "revision": revision,
		"map": grid.map_data.source_kind, "contextual": grid.map_data.contextual_discovery_enabled, "lanes": rows}))
	if revision != 22: return
	var record := recording.actions[index]
	var watcher := service.actor_registry.resolve(&"PlayerUnit2")
	var mover := service.actor_registry.resolve(&"EnemyUnit1")
	var guards := []
	var path: Array = record.resolved.path
	for point in path.slice(1):
		var cell := Vector3i(point[0], point[1], point[2])
		var verdict := service.query_guard_reaction(watcher, mover, cell)
		guards.append({"cell": str(cell), "legal": verdict.can_fire, "reason": verdict.reason,
			"chance": verdict.evaluation.hit_chance if verdict.has("evaluation") else 0})
	print("[ReplayGuard] ", JSON.stringify(guards))

func _lane(actor: TacticalUnit, target: TacticalUnit, grid: GridManager) -> Dictionary:
	var source := grid.get_unit_grid(actor)
	var dest := grid.get_unit_grid(target)
	var support := CombatRules.get_support_position(source, grid)
	var ground := CombatRules.get_support_position(dest, grid)
	var from_center := grid.get_cell_data(source).support_center
	var to_center := grid.get_cell_data(dest).support_center
	var origin := support + Vector3.UP * actor.standing_height
	var h := Vector3.UP * target.standing_height
	var center := ground + h
	var heading := center - origin
	var side := Vector3(-heading.z, 0, heading.x).normalized() * grid.cell_size * 0.28
	var samples := [ground + h * 1.2, ground + h * 1.75, ground + h * 0.9 + side, ground + h * 0.9 - side, ground + h * 0.5]
	var names := ["core", "head", "side_plus", "side_minus", "lower"]
	var eval := CombatRules.evaluate_attack(actor, target, grid, null)
	var open := []
	var blockers := {}
	var centered := []
	var head_sight := []
	var head := support + Vector3.UP * actor.standing_height * 1.75
	for i in samples.size():
		var obstruction := _blocker(origin, samples[i], source, dest, grid)
		if obstruction.is_empty(): open.append(names[i])
		else: blockers[names[i]] = obstruction
		if _blocker(origin + from_center - support, samples[i] + to_center - ground, source, dest, grid).is_empty():
			centered.append(names[i])
		if i < 2 and _blocker(head, samples[i], source, dest, grid).is_empty(): head_sight.append(names[i])
	return {"pair": "%s>%s" % [actor.tactical_id, target.tactical_id], "from": str(source), "to": str(dest),
		"from_offset": str(support - from_center), "to_offset": str(ground - to_center),
		"legal": eval.is_legal, "reason": eval.reason, "base_chance": eval.hit_chance,
		"open": open, "blockers": blockers, "center_translation_control": centered,
		"head_sight": head_sight, "core_head_shot": "core" in open or "head" in open}

func _blocker(origin: Vector3, sample: Vector3, source: Vector3i, dest: Vector3i, grid: GridManager) -> String:
	var ignored: Array[Vector3i] = [source, dest]
	var cell := CombatRules._get_geometry_between(origin, sample, grid, false, ignored, true)
	if not cell: return ""
	return "%s %s" % [cell.shot_obstacle_label, cell.grid_position]
