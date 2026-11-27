extends SceneTree
## Matched real AI games. Output includes committed authoritative transactions.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var pressure := args.has("pressure")
	var size := 3 if args.has("3v3") else 2
	var mode := 0
	var guard := 0
	for arg in args:
		if arg.begins_with("mode="): mode = arg.substr(5).to_int()
		if arg.begins_with("guard="): guard = arg.substr(6).to_int()
	var result := await simulator.run_match({
		"seed": 16, "difficulty": AIDifficultyPolicy.Tier.HARD,
		"battlefield_id": BattlefieldCatalog.CONTEXTUAL_FREIGHT if pressure else BattlefieldCatalog.CONTEXTUAL_SHOWCASE,
		"player_count": size, "enemy_count": size, "engagement_policy": mode,
		"contextual_firing_disabled": args.has("no-context"), "guard_minimum_chance": guard,
		"player_commander": AICommanderPolicy.Profile.CAUTIOUS if args.has("swapped") else AICommanderPolicy.Profile.DEFAULT,
		"enemy_commander": AICommanderPolicy.Profile.DEFAULT if args.has("ordinary") or args.has("swapped") else AICommanderPolicy.Profile.CAUTIOUS,
		"maximum_rounds": 12, "timeout_seconds": 180.0, "stall_seconds": 15.0,
		"capture_combat_policy_evidence": true,
	})
	print("[PolicyStress] ", JSON.stringify({"status": result.status, "battle_result": result.battle_result,
		"rounds": result.rounds, "decisions": result.decision_count, "reason": result.reason,
		"configuration": result.configuration, "round_samples": result.round_samples}))
	quit(0)
