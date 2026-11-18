extends SceneTree
## Explicit-only AI baseline (milestone 05, step 2). Not part of any Ironclad tier.
## Runs the real AI over the current sites and mission kinds and writes one JSON file
## per match plus a [Baseline] line. Pair with tools/quality/ai_baseline_summary.py.
##
## godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- \
##   tag=baseline site=service_depot,freight_yard,fleet_station mission=ALL seeds=16,17 \
##   difficulty=NORMAL players=3 enemies=3 profile-ai
##
## "profile-ai" additionally prints [AIPlan] planning-time lines, which the summarizer
## joins to the [BaselineBegin] markers. Diagnostics read state; they do not change decisions.

const MISSIONS := {
	"ELIMINATE": MissionObjectiveDefinition.Kind.ELIMINATE,
	"PROTECT": MissionObjectiveDefinition.Kind.PROTECT,
	"RESCUE": MissionObjectiveDefinition.Kind.RESCUE,
	"REACH": MissionObjectiveDefinition.Kind.REACH,
	"SURVIVE": MissionObjectiveDefinition.Kind.SURVIVE,
	"EXTRACT": MissionObjectiveDefinition.Kind.EXTRACT,
	"ENEMY_EVACUATION": MissionObjectiveDefinition.Kind.ENEMY_EVACUATION,
	"INTERACT_TERMINAL": MissionObjectiveDefinition.Kind.INTERACT_TERMINAL,
}

func _initialize() -> void:
	_run.call_deferred()

func _arguments() -> Dictionary:
	var result := {"tag": "baseline", "site": "service_depot,freight_yard,fleet_station", "mission": "ALL",
		"seeds": "16,17", "difficulty": "NORMAL", "players": "3", "enemies": "3", "timeout": "60", "rounds": "30"}
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2:
			result[parts[0]] = parts[1]
	return result

func _run() -> void:
	var args := _arguments()
	var tag: String = args.tag
	var directory := "res://artifacts/ai-baseline/%s" % tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var missions: Array = MISSIONS.keys() if args.mission == "ALL" else Array(String(args.mission).split(","))
	var difficulty_index: int = AIDifficultyPolicy.Tier.keys().find(String(args.difficulty).to_upper())
	if difficulty_index < 0:
		push_error("Unknown difficulty %s" % args.difficulty)
		quit(2)
		return
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 12.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var unfinished := 0
	for site in String(args.site).split(","):
		for mission_name in missions:
			if not MISSIONS.has(mission_name):
				push_error("Unknown mission %s" % mission_name)
				continue
			var kind: MissionObjectiveDefinition.Kind = MISSIONS[mission_name]
			for seed_text in String(args.seeds).split(","):
				var seed_value := int(seed_text)
				var label := "%s-%s-%d" % [site, mission_name, seed_value]
				print("[BaselineBegin] %s" % label)
				var result := await simulator.run_match({
					"seed": seed_value,
					"mission_kind": kind,
					"player_count": int(args.players),
					"enemy_count": int(args.enemies),
					"ally_count": 1 if kind in [MissionObjectiveDefinition.Kind.PROTECT, MissionObjectiveDefinition.Kind.RESCUE] else 0,
					"include_vip": kind == MissionObjectiveDefinition.Kind.PROTECT,
					"battlefield_id": StringName(site),
					"map_size": BattlefieldCatalog.map_size(StringName(site), Vector2i(40, 40)),
					"difficulty": difficulty_index,
					"maximum_rounds": int(args.rounds),
					"stall_seconds": 8.0,
					"timeout_seconds": float(args.timeout),
				})
				var data := result.reproduction_data()
				data["label"] = label
				data["site"] = site
				var file := FileAccess.open("%s/%s.json" % [directory, label], FileAccess.WRITE)
				file.store_string(JSON.stringify(data, "\t"))
				file.close()
				print("[Baseline] %s | %s" % [label, result.summary()])
				if not result.completed(): unfinished += 1
	Engine.time_scale = previous_time_scale
	print("[BaselineDone] %s unfinished=%d" % [tag, unfinished])
	quit(0)
