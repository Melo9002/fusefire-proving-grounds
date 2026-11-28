extends SceneTree
## Runs a manifest through the production AI simulator and writes one receipt per case.

const Modes := CombatRules.EngagementPolicy
var _case: Dictionary
var _evidence: Dictionary
var _started := 0
var _activation_started := 0
var _batch: Dictionary
var _out: FileAccess

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(2)
		return
	_batch = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_out = FileAccess.open(args[1], FileAccess.WRITE)
	if _out == null: quit(2); return
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	for entry in _batch.cases:
		_case = entry
		var config: Dictionary = entry.duplicate()
		config["maximum_rounds"] = int(config.get("maximum_rounds", 8))
		config["timeout_seconds"] = 180.0
		config["stall_seconds"] = 30.0
		config["difficulty"] = AIDifficultyPolicy.Tier.HARD
		config["battlefield_id"] = StringName(config.battlefield_id)
		config["capture_combat_policy_evidence"] = true
		config["laboratory_observer"] = _observe
		config["laboratory_completion"] = _save_replay
		_evidence = {"hits_checked": 0, "hits_unchecked": 0, "one_way_damage": 0, "damage": 0, "activation_ms": [],
			"return_queries": 0, "return_query_usec": 0, "no_return": [], "guard_counterfactual_holds": 0}
		var result := await simulator.run_match(config)
		var data := result.reproduction_data()
		data.erase("action_outcomes")
		data.erase("decisions")
		data["elapsed_seconds"] = result.elapsed_seconds
		data["case"] = entry
		data["evidence"] = _evidence
		data["provenance"] = _batch.provenance
		_out.store_line(JSON.stringify(data))
		_out.flush()
	quit()

func _observe(level: BattleLevel) -> void:
	var battle := level.battle_controller
	var isolated: Array[int] = []
	if _case.coordination in ["ii", "ic"]: isolated.append(TacticalUnit.Faction.PLAYER)
	if _case.coordination in ["ii", "ci"]: isolated.append(TacticalUnit.Faction.ENEMY)
	battle.simulation_isolated_squad_factions = isolated
	_evidence["initial_fingerprint"] = level._replay_recorder.recording.initial_state_fingerprint
	_started = Time.get_ticks_usec()
	_activation_started = _started
	level.turn_manager.active_unit_changed.connect(func(actor):
		if not is_instance_valid(actor): return
		var now := Time.get_ticks_usec()
		_evidence.activation_ms.append((now - _activation_started) / 1000.0)
		_activation_started = now)
	battle.action_service.action_committed.connect(func(action): _action(battle, action))

func _action(battle: BattleController, action) -> void:
	if action is MoveActionResult or action is AttackActionResult:
		for row in action.guard_checks.values():
			_evidence.guard_counterfactual_holds += int(row.get("held_fire", false))
	if not action is AttackActionResult or action.damage <= 0: return
	_evidence.damage += action.damage
	var attacker := battle.action_service.actor_registry.resolve(action.request.actor_id)
	var target := battle.action_service.actor_registry.resolve(action.request.target_id)
	if not is_instance_valid(attacker) or not is_instance_valid(target) or target.stats.is_defeated or attacker.stats.is_defeated:
		_evidence.hits_unchecked += 1
		return
	var grid := battle.grid_manager
	var a := grid.get_unit_grid(attacker)
	var b := grid.get_unit_grid(target)
	var central := CombatRules.requires_central(grid.map_data.engagement_policy)
	var before := Time.get_ticks_usec()
	var can_return := CombatRules._has_physical_lane(target, b, attacker, a, grid, central)
	_evidence.return_query_usec += Time.get_ticks_usec() - before
	_evidence.return_queries += 1
	_evidence.hits_checked += 1
	if can_return: return
	_evidence.one_way_damage += action.damage
	_evidence.no_return.append({"attacker": action.request.actor_id, "target": action.request.target_id,
		"revision": action.committed_revision, "round": battle.turn_manager.current_round,
		"from": str(a), "to": str(b), "damage": action.damage, "target_ap": target.stats.current_ap,
		"target_sp": target.stats.current_supply_points, "target_range": target.attack_range,
		"distance": CombatRules.attack_distance(a, b, grid), "solution": action.firing_solution.to_replay_record()})

func _save_replay(level: BattleLevel, _result: AIMatchSimulationResult) -> void:
	var recording: BattleReplayRecording = level._replay_recorder.recording
	var path: String = _case.get("replay", "")
	if not path.is_empty() and not recording.actions.is_empty():
		_evidence["replay_saved"] = recording.save_json(path) == OK

