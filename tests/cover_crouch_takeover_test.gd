extends SceneTree
## Regression for issue 62: when a character stops and takes cover while a stride is still swinging, the crouch used to replace the legs in ONE frame, so the stepping foot slammed to the floor
## (the tactical scenario, 4.22 s: a 33 cm step of the right foot in one frame). CoverCrouchModifier now hands the legs over from the clip to the solved crouch over `takeover_seconds`.
## The test plays that scenario in the Workbench and measures the largest one-frame step of either ankle around the moment cover is entered. Negative control: `takeover_seconds = 0` is the old
## instant takeover and must show the snap (otherwise this test could not see the defect). The finished crouch is covered by the other cover and portability tests.
var failures := 0
var checks := 0
var ankles: Array[Vector3] = []
var times: Array[float] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _grab(bench) -> void:
	var sk: Skeleton3D = bench.rig.skeleton
	var t: float = float(bench.scenario_runner.time)
	times.append(t)
	times.append(t)
	ankles.append(sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftFoot")).origin)
	ankles.append(sk.get_bone_global_pose(sk.find_bone("mixamorig_RightFoot")).origin)

## The largest one-frame step of either ankle in the scenario seconds `from` to `to`, with the legs handed over in `takeover_seconds`.
func _worst_step(bench, takeover_seconds: float, from: float, to: float) -> float:
	bench.rig.crouch_modifier.takeover_seconds = takeover_seconds
	ankles.clear()
	times.clear()
	bench.start_scenario(&"tactical", false)
	var guard := 0
	while bench.scenario_runner.running and float(bench.scenario_runner.time) < to + 0.1 and guard < 2400:
		await process_frame
		guard += 1
	var worst := 0.0
	for index in range(2, ankles.size()):
		if times[index] >= from and times[index] <= to and times[index] >= 0.0:
			worst = maxf(worst, ankles[index].distance_to(ankles[index - 2]))
	return worst

func _run() -> void:
	Engine.max_fps = 60
	var bench = load("res://tools/animation_workbench/pose_workbench.tscn").instantiate()
	root.add_child(bench)
	for i in 30: await process_frame
	bench.rig.skeleton.skeleton_updated.connect(func() -> void: _grab(bench))
	check(bench.rig.crouch_modifier != null, "the rig has a crouch modifier")
	var treated: float = await _worst_step(bench, 0.2, 3.9, 4.6)
	var instant: float = await _worst_step(bench, 0.0, 3.9, 4.6)
	print("  largest one-frame ankle step while cover is entered (tactical scenario, 3.9 to 4.6 s): handover %.3f m, instant takeover (old behaviour) %.3f m" % [treated, instant])
	check(instant > 0.15, "Negative control: the instant takeover does slam the stepping foot (%.3f m in one frame), so this test can see the defect" % instant)
	check(treated < 0.12, "With the handover no ankle moves more than 12 cm in one frame when cover is entered (%.3f m; it was 0.33 m)" % treated)
	check(treated < instant * 0.5, "The handover at least halves the worst step (%.3f against %.3f m)" % [treated, instant])

	print("Cover crouch takeover: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
