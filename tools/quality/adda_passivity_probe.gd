extends SceneTree
## ADDA passivity probe. Plays the `contacts` Workbench scenario at a FIXED frame rate and prints one hash of every final-pose sample of the hips, wrists and ankles. Run it with and without ADDA's recorder (and with
## its leg-vertex sampler): if the hashes are equal, observing changed no pose by a single bit.
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/adda_passivity_probe.gd -- [--record] [--mesh] [--perturb] [--scenario=<id>]
## It prints `POSEHASH <hash> SAMPLES <count> ROWS <recorded rows>`. Only meaningful with --fixed-fps (without it the engine's own frame time varies and no two runs match).
const BENCH := "res://tools/animation_workbench/pose_workbench.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var flags := OS.get_cmdline_user_args()
	var id := &"contacts"
	for flag in flags:
		if flag.begins_with("--scenario="):
			id = StringName(flag.trim_prefix("--scenario="))
	var bench: Node3D = (load(BENCH) as PackedScene).instantiate()
	root.add_child(bench)
	WorkbenchSession.autostart_scenario = &""
	for i in 4:
		await process_frame
	var rig: CharacterRig = bench.rig
	var skeleton := rig.skeleton
	var recorder: SessionRecorder = null
	if "--record" in flags:
		recorder = SessionRecorder.attach(rig)
		recorder.clock = func() -> float: return float(bench.scenario_runner.time) if bench.scenario_runner.running else -1.0
		if "--mesh" in flags:
			recorder.enable_mesh(1)
		recorder.start()
	var witness := PoseWitness.acquire(skeleton)
	var names: Array[StringName] = [rig.bones.hips, rig.bones.left_arm[2], rig.bones.right_arm[2], rig.bones.left_leg[2], rig.bones.right_leg[2]]
	var samples := PackedFloat32Array()
	var handler := func() -> void:
		for name in names:
			var at := skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
			samples.append(at.x)
			samples.append(at.y)
			samples.append(at.z)
	witness.final_pose.connect(handler)
	var frames := 0
	if "--perturb" in flags:
		rig.character_root.position.x += 0.001   # the negative control: a 1 mm nudge of the body must change the hash, or the hash proves nothing
	bench.scenario_runner.start(bench, WorkbenchScenarios.find(id))
	while bench.scenario_runner.running and frames < 4000:
		await process_frame
		frames += 1
	witness.final_pose.disconnect(handler)
	witness.release()
	var rows := recorder.rows.size() if recorder != null else 0
	if recorder != null:
		recorder.stop()
	print("POSEHASH %d SAMPLES %d ROWS %d" % [hash(samples), samples.size() / 3 / names.size(), rows])
	quit(0)
