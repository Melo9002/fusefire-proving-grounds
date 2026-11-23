extends SceneTree
## Where does the leg meet the ladder? Climbs (or descends) a ladder with a real rig and prints, for every frame in which a skinned leg vertex is inside a rung or rail by more than the threshold, what the body
## and the plan were doing: the support phase (the rungs under the feet and whether a foot is swinging), the pelvis, both knees and ankles and the foot targets, the knee stance the planner chose, and the
## worst vertex (bone, bar, depth, place). A summary groups the frames by bone and by the bar's height relative to the higher foot's rung, so a pattern is visible. Read-only.
##   godot_console --headless --path . --script res://tools/quality/ladder_offender_probe.gd -- [mira|small] [armed|unarmed] [up|down] [threshold_mm=8] [verbose]
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}

func _initialize() -> void:
	_run.call_deferred()

func _f(v: Vector3) -> String:
	return "(%+.3f %+.3f %+.3f)" % [v.x, v.y, v.z]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var key := "small" if args.has("small") else "mira"
	var armed := not args.has("unarmed")
	var direction := -1 if args.has("down") else 1
	var threshold := 0.008
	for arg in args:
		if arg.begins_with("threshold_mm="):
			threshold = float(arg.trim_prefix("threshold_mm=")) / 1000.0
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
	rig.skeleton.skeleton_updated.connect(func() -> void: clearance.sample())
	rig.begin_traversal(&"ladder", 4.0, direction)
	var by_bone := {}
	var by_height := {}
	var frames := 0
	var offending := 0
	var h := 0.8 if direction > 0 else 3.2
	while h > 0.7 and h < 3.3:
		host.position.y = h
		rig.set_traversal_progress(h)
		await process_frame
		await process_frame
		frames += 1
		var pose: LadderPose = rig.ladder.pose
		var found := clearance.offenders(rig.ladder.geometry, h, threshold)
		if not found.is_empty():
			offending += 1
			var worst: Dictionary = found[0]
			var higher_rung := maxi(pose.foot_rung[0], pose.foot_rung[1])
			var relative := int(worst.rung) - higher_rung if int(worst.rung) >= 0 else 99
			by_bone[worst.bone] = int(by_bone.get(worst.bone, 0)) + 1
			by_height[relative] = int(by_height.get(relative, 0)) + 1
			if args.has("verbose"):
				var j := clearance.joints
				print("c %.2f feet rungs %s swing [%.2f %.2f] hips %s | knee L %s R %s | ankle L %s R %s | foot tgt L %s R %s | turn %s | worst %s %s %.1f mm at %s (%d vertices)" % [h, pose.foot_rung, pose.foot_swing[0], pose.foot_swing[1], _f(j.hips), _f(j.knee[0]), _f(j.knee[1]), _f(j.ankle[0]), _f(j.ankle[1]), _f(pose.feet[0]), _f(pose.feet[1]), rig.traversal_modifier.knee_turn, worst.bone, worst.bar, float(worst.depth) * 1000.0, _f(worst.point), found.size()])
		h += 0.01 * direction
	print("%s %s %s: %d of %d frames have a leg vertex over %.0f mm inside a bar. By bone: %s. By bar relative to the HIGHER foot's rung (0 = the same rung, +1 = the next one up): %s" % [key, "armed" if armed else "unarmed", "up" if direction > 0 else "down", offending, frames, threshold * 1000.0, by_bone, by_height])
	quit(0)
