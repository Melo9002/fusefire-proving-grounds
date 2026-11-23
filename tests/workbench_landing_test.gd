extends SceneTree
## The supported ladder transfer in the ANIMATION WORKBENCH: the same production solver, rig and hand contacts the sandbox uses, reproducible from a name, pausable, steppable and measurable. Both humanoids,
## armed and unarmed: the `landing` scenario plays a deck with posts and a deck whose ladder rails run on (each climbed and then entered from the deck in reverse), then two landings that must stay on the fallback.
## Stepped deterministically (paused, fixed step). What is checked: the rig reports the landing as supported or as a fallback with its reason; held grips are within the arm in the plan; pausing holds the pose and a single
## step advances the transfer by exactly its length; interrupting at the lip leaves no contact and returns the rifle; the panel's ladder readout names the status and the clearances.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _bench(character: StringName, armed: bool) -> Node3D:
	WorkbenchSession.character = character
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(12)
	bench.step_seconds = 0.05
	return bench

func _run() -> void:
	for character in [&"mira_0", &"small_mira_0"]:
		for armed in [true, false]:
			var bench := await _bench(character, armed)
			var label := "%s %s" % [character, "armed" if armed else "unarmed"]
			await _scenario(bench, label)
			await _pause_and_step(bench, label)
			await _interrupt(bench, label, armed)
			bench.queue_free()
			await _frames(3)
	print("workbench_landing_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## The scenario, frame by frame: which landing statuses the rig reported, and the grips held within reach.
func _scenario(bench: Node3D, label: String) -> void:
	check(bench.start_scenario(WorkbenchScenarios.LANDING), "%s: the landing scenario starts" % label)
	bench.set_sim_paused(true)
	var statuses := {}
	var held := 0
	var unreachable_held := 0
	var readouts := 0
	var frames := 0
	while bench.scenario_runner.running and frames < 3000:
		bench.step_sim()
		await process_frame
		frames += 1
		var report: Dictionary = bench.ladder_landing_report()
		if bool(report.active):
			statuses[String(report.status)] = true
			var pose: LadderPose = bench.rig.ladder.pose
			for side in 2:
				if pose != null and pose.landing_phase >= 0.0 and pose.hand_weight[side] > 0.99 and pose.hand_deck[side] > 0.99:
					held += 1
					if not pose.hand_reachable[side]:
						unreachable_held += 1
			if frames % 20 == 0:
				var text: String = bench.diagnostics.ladder_text()
				if text.contains("landing:") and text.contains("knee spread"):
					readouts += 1
	var seen := ", ".join(statuses.keys())
	check(statuses.has("supported (workbench posts)") and statuses.has("supported (workbench extended rails)"), "%s: the posts and the extended rails were reported supported (%s)" % [label, seen])
	var fallbacks := 0
	for status in statuses:
		if String(status).begins_with("fallback: "):
			fallbacks += 1
	check(fallbacks >= 2, "%s: the deck with nothing to hold and the lip out of reach were reported as fallbacks with a reason (%s)" % [label, seen])
	check(held > 20 and unreachable_held == 0, "%s: held grips were within the arm's reach in the plan (%d samples, %d beyond)" % [label, held, unreachable_held])
	check(readouts > 5, "%s: the panel's ladder readout names the landing and the measured clearances (%d readouts)" % [label, readouts])
	check(bench.rig.ladder == null and bench.ladder_demo.is_empty() and bench.rig.grip_modifier.contact_weight == ([0.0, 0.0] if bench.rig.has_weapon() else [CharacterRig.HANGING_HAND_WEIGHT, CharacterRig.HANGING_HAND_WEIGHT]), "%s: the scenario ended with no traversal and no contact left" % label)

## Pausing holds the pose; one step advances the transfer by exactly the step length at the demo's rate.
func _pause_and_step(bench: Node3D, label: String) -> void:
	bench.start_ladder_demo(3.0, 1, 0.85, 2.3, "posts")
	bench.set_sim_paused(true)
	await _frames(2)
	var climbed: float = float(bench.ladder_demo.climbed)
	var hips_before: Vector3 = bench.rig.ladder.pose.hips
	await _frames(8)
	check(is_equal_approx(float(bench.ladder_demo.climbed), climbed) and bench.rig.ladder.pose.hips.is_equal_approx(hips_before), "%s: paused, the landing climb does not move over 8 rendered frames" % label)
	bench.step_sim()
	await _frames(2)
	check(absf(float(bench.ladder_demo.climbed) - climbed - 0.85 * bench.step_seconds) < 0.0001, "%s: one step advances the climb by exactly the step length (%.4f m)" % [label, float(bench.ladder_demo.climbed) - climbed])
	bench.end_ladder_demo()

## Interrupt twice: while the hands hold the posts (acquisition) and while the feet cross the lip (release).
func _interrupt(bench: Node3D, label: String, armed: bool) -> void:
	for stage in [[2.8, 0.0, true, "acquiring the posts"], [3.0, 0.5, false, "crossing the lip"]]:
		bench.start_ladder_demo(3.0, 1, 0.0, float(stage[0]), "posts")
		bench.set_ladder_across(float(stage[1]))
		bench.set_sim_paused(true)
		await _frames(3)
		var in_transfer: bool = bench.rig.ladder != null and bench.rig.ladder.pose.landing_phase > 0.4
		check(in_transfer, "%s: interrupting while %s (phase %.2f)" % [label, stage[3], bench.rig.ladder.pose.landing_phase if bench.rig.ladder != null else -1.0])
		if bool(stage[2]):
			check(bench.rig.traversal_contacts_active(), "%s: the hands hold their grips while %s" % [label, stage[3]])
		bench.end_ladder_demo()
		await _frames(3)
		var grip: HandGripModifier = bench.rig.grip_modifier
		check(bench.rig.ladder == null and not bench.rig.traversal_contacts_active(), "%s: interrupted while %s leaves no traversal and no ladder contact" % [label, stage[3]])
		if armed:
			check(grip.contact_weight == [0.0, 0.0] and not bench.rig.is_weapon_stowed(), "%s: interrupted while %s, the rifle is back in the hands" % [label, stage[3]])
		else:
			check(grip.contact_weight == [CharacterRig.HANGING_HAND_WEIGHT, CharacterRig.HANGING_HAND_WEIGHT], "%s: interrupted while %s, the unarmed hands are back to the hang" % [label, stage[3]])
