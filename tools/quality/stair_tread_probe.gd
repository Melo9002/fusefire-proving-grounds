extends SceneTree
## Probe (explicit, headless): during the stair entry of scenario C, how far does a foot the plan calls PLANTED move against the tread under it?
## The bench is a treadmill: the stair group moves by -travel(s); a point on a tread moves exactly that much. A foot that holds its tread moves the same; the difference is slide against the tread.
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/stair_tread_probe.gd -- [mira_0|small_mira_0] [seconds] [noroll]
## Written for the stair-entry report (adda_reports/20261124-092555-...): ADDA compares the ankle with the PLAN; this compares it with the TREAD, which is what a person sees.
## Prints per planted run: frames, start/end s, ankle slide against the tread (mm), the PLAN's slide against the tread (mm), and ankle-to-plan error.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	WorkbenchSession.character = StringName(args[0]) if args.size() > 0 else &"mira_0"
	WorkbenchSession.armed = false
	WorkbenchSession.read_drafts = false
	WorkbenchSession.autostart_scenario = &""
	var seconds := float(args[1]) if args.size() > 1 else 5.0
	var bench: Node3D = (load("res://tools/animation_workbench/pose_workbench.tscn") as PackedScene).instantiate()
	root.add_child(bench)
	for i in 12:
		await process_frame
	bench.step_seconds = 1.0 / 60.0
	if args.size() > 2 and args[2] == "noroll":
		bench.rig.stair_profile_source.stance_motion_enabled = false   # experiment: the planned stance roll off
		bench.rig.reapply_stair_profile()
	bench.start_scenario(&"contacts")
	bench.set_sim_paused(true)
	var prev := {}
	var runs := [{}, {}]
	var report: Array[String] = []
	var frame := 0
	while bench.scenario_runner.time < seconds and frame < 2000:
		bench.step_sim()
		await process_frame
		frame += 1
		if bench.stair_demo.is_empty() or bench.rig.stairs == null or bench.rig.stairs.pose == null:
			continue
		var s := float(bench.stair_demo.s)
		var travel: Vector3 = bench._stair_travel(bench.stair_demo.model, s)
		var now := {"s": s, "travel": travel, "t": bench.scenario_runner.time}
		for foot in 2:
			now["ankle%d" % foot] = bench._stair_actual[foot]
			now["plan%d" % foot] = bench.rig.stairs.pose.feet[foot].position
			now["planted%d" % foot] = bench.rig.stairs.pose.feet[foot].planted
		if not prev.is_empty():
			var tread_move: Vector3 = -(now.travel - prev.travel)
			for foot in 2:
				var run: Dictionary = runs[foot]
				if bool(now["planted%d" % foot]) and bool(prev["planted%d" % foot]):
					if run.is_empty():
						run = {"from_t": prev.t, "from_s": prev.s, "frames": 0, "ankle": Vector3.ZERO, "plan": Vector3.ZERO, "worst_err": 0.0}
					run.frames += 1
					run.ankle += (now["ankle%d" % foot] - prev["ankle%d" % foot]) - tread_move
					run.plan += (now["plan%d" % foot] - prev["plan%d" % foot]) - tread_move
					run.worst_err = maxf(run.worst_err, (now["ankle%d" % foot] - now["plan%d" % foot]).length())
					run["to_t"] = now.t
					runs[foot] = run
				elif not run.is_empty():
					report.append(_line(foot, run))
					runs[foot] = {}
		prev = now
	for foot in 2:
		if not (runs[foot] as Dictionary).is_empty():
			report.append(_line(foot, runs[foot]))
	report.sort()
	for line in report:
		print(line)
	quit(0)

func _line(foot: int, run: Dictionary) -> String:
	return "t %5.2f-%5.2f s  %s foot planted %3d frames | ankle vs tread %6.1f mm (along %5.1f, up %5.1f) | plan vs tread %6.1f mm | worst ankle-plan %5.1f mm" % [
		run.from_t, run.get("to_t", run.from_t), "L" if foot == 0 else "R", run.frames, run.ankle.length() * 1000.0, run.ankle.z * 1000.0, run.ankle.y * 1000.0,
		run.plan.length() * 1000.0, run.worst_err * 1000.0]
