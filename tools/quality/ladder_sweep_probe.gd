extends SceneTree
## A reversible sweep over one ladder parameter, measured on the REAL rig and mesh. For each value: the share of ascent/descent frames in which a skinned leg vertex is inside a bar by more than 8 mm and
## by more than 15 mm, the mean depth of the worst vertex per frame, and what the change costs: hands in reach (of the held ones), the worst planted-ankle error and the knees' mean spread. Nothing persists:
## the value is set on a throwaway profile or geometry instance.
##   godot_console --headless --path . --script res://tools/quality/ladder_sweep_probe.gd -- <name> <v1,v2,...> [small|mira] [up|down] [armed]
## <name>: a TraversalProfile property (ankle_behind_share, knee_turn_degrees, hips_height, climb_lean_degrees, foot_window_bias, hand_window_bias, foot_half_spread, swing_lift, weight_shift...) or
## `pitch`, `first_rung`, `rail_span` for the ladder itself (what-ifs; the authored ladder is not changed).
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var name: String = args[0]
	var values: Array[float] = []
	for text in String(args[1]).split(","):
		values.append(float(text))
	var key := "small" if args.has("small") else "mira"
	var direction := -1 if args.has("down") else 1
	var armed := args.has("armed")
	var stage := Node3D.new()
	root.add_child(stage)
	var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	stage.add_child(host)
	for i in 20:
		await process_frame
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	var original := rig.traversal_profile.duplicate()
	for value in values:
		rig.traversal_profile = original.duplicate()
		rig.begin_traversal(&"ladder", 4.0, direction)
		match name:
			"pitch":
				rig.ladder.geometry.pitch = value
			"first_rung":
				rig.ladder.geometry.first = value
			"rail_span":
				rig.ladder.geometry.rail_half_span_m = value
			_:
				rig.traversal_profile.set(name, value)
		var frames := 0
		var over8 := 0
		var over15 := 0
		var depth_sum := 0.0
		var count_sum := 0
		var count_max := 0
		var crossing := 0
		var held := 0
		var reachable := 0
		var ankle_worst := 0.0
		var spread := 0.0
		var h := 0.8 if direction > 0 else 3.2
		while h > 0.7 and h < 3.3:
			host.position.y = h
			rig.set_traversal_progress(h)
			await process_frame
			await process_frame
			frames += 1
			var pose: LadderPose = rig.ladder.pose
			var found := clearance.offenders(rig.ladder.geometry, h, 0.003, 100000)
			count_sum += found.size()
			count_max = maxi(count_max, found.size())
			crossing += 1 if found.size() >= 5 else 0
			var depth: float = float(found[0].depth) if not found.is_empty() else 0.0
			depth_sum += depth
			over8 += 1 if depth > 0.008 else 0
			over15 += 1 if depth > 0.015 else 0
			spread += clearance.knee_spread()
			for side in 2:
				if pose.hand_weight[side] > 0.99:
					held += 1
					var target: Vector3 = rig.character_root.to_global(pose.hands[side])
					var shoulder: Vector3 = rig.character_root.to_global(clearance.joints.shoulder[side])
					reachable += 1 if target.distance_to(shoulder) <= rig.ladder_body().arm_length() else 0
				if pose.foot_swing[side] == 0.0 and pose.weight > 0.99:
					var ankle: Vector3 = rig.character_root.to_global(clearance.joints.ankle[side])
					ankle_worst = maxf(ankle_worst, ankle.distance_to(rig.foot_targets[side].global_position))
			h += 0.01 * direction
		print("%s %s %s %s=%.3f: surface vertices inside bars (over 3 mm): mean %d per frame, max %d, 5 or more in %d%% of frames; worst vertex mean %.1f mm | hands in reach %d%% (%d held) | planted ankle worst %.1f mm | knee spread %.0f cm" % [key, "armed" if armed else "unarmed", "up" if direction > 0 else "down", name, value, count_sum / maxi(frames, 1), count_max, 100 * crossing / maxi(frames, 1), 1000.0 * depth_sum / maxi(frames, 1), 100 * reachable / maxi(held, 1), held, ankle_worst * 1000.0, 100.0 * spread / maxi(frames, 1)])
		rig.end_traversal()
		await process_frame
	quit(0)
