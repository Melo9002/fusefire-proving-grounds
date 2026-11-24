extends SceneTree
## ADDA's investigation workflow on the REAL systems: the Workbench scenarios (stairs, ladder, ladder landing, rescue and carry, cover, exploration) played on MIRA and Small MIRA, armed and unarmed, recorded, analysed,
## reported, compared and read back. Scenarios are stepped paused with a fixed step so every run is the same run.
##   1 recording       rows are one per frame, time-ordered, with the final-pose bones, targets, claims and stage ownership
##   2 report          the structured report has every field an agent relies on and survives JSON
##   3 determinism     the same run twice compares as UNCHANGED, metric for metric
##   4 experiments     armed against unarmed, MIRA against Small MIRA and 60 against 30 fps compare as the comparison rules say they must
##   5 contexts        stairs, ladder, rescue and carry each leave the events that belong to them
##   6 mesh            leg-vertex sampling puts a FRESH mesh record on every ladder row, and a run without it says it did not look
##   7 tidy            recording leaves no listener behind (that it changes no pose is proved bit for bit in adda_cli_test)
##   8 negative        a body teleported by 40 cm in one frame is found; an idle body is not
##   9 honesty         every finding on a real run says the cause is unknown and its hypotheses are unconfirmed
##  10 the tab         the Why? tab lists, selects, shows, replays, compares and exports
##  11 unsupported     a scenario the configuration cannot play is refused with its reason
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
	await _frames(10)
	return bench

## Plays `id` to its end in paused fixed steps and returns the report. `mesh` samples the leg vertices; `recording` false stops the recorder at once (the control for the passivity check).
func _play(bench: Node3D, id: StringName, step: float, mesh := false, recording := true) -> void:
	bench.step_seconds = step
	check(bench.start_scenario(id), "scenario %s starts" % id)
	if mesh:
		bench.diagnostics.begin_recording(func() -> float: return float(bench.scenario_runner.time) if bench.scenario_runner.running else -1.0, true)
		bench.scenario_runner.step_run.connect(bench._mark_step) if not bench.scenario_runner.step_run.is_connected(bench._mark_step) else null
	if not recording:
		bench.diagnostics.end_recording()
	bench.set_sim_paused(true)
	var frames := 0
	while bench.scenario_runner.running and frames < 6000:
		bench.step_sim()
		await process_frame
		frames += 1

func _report(bench: Node3D, id: String, character: String, armed: bool) -> Dictionary:
	return AddaReport.build(bench.diagnostics.recorder, {"scenario": id, "character": character, "command": WorkbenchSession.repro_command(StringName(id)), "cli": "test"})

func _record(character: StringName, armed: bool, id: StringName, step: float, mesh := false) -> Dictionary:
	var bench := await _bench(character, armed)
	await _play(bench, id, step, mesh)
	var report := _report(bench, String(id), String(character), armed)
	var recorder: SessionRecorder = bench.diagnostics.recorder
	var result := {"report": report, "rows": recorder.rows.duplicate(), "bench": bench}
	return result

func _kinds(report: Dictionary) -> Array:
	return (report.events as Array).map(func(e: Dictionary) -> String: return String(e.kind))

func _run() -> void:
	var dt := 1.0 / 60.0
	# Runs: the same MIRA contacts run twice, unarmed, Small MIRA with the leg mesh sampled, and 30 fps.
	var a := await _record(&"mira_0", true, &"contacts", dt)
	var a2 := await _record(&"mira_0", true, &"contacts", dt)
	var unarmed := await _record(&"mira_0", false, &"contacts", dt)
	var small := await _record(&"small_mira_0", true, &"contacts", dt, true)
	var slow := await _record(&"mira_0", true, &"contacts", 1.0 / 30.0)
	_recording(a)
	_report_fields(a)
	_determinism(a, a2)
	_experiments(a, unarmed, small, slow)
	_contexts(a)
	_mesh(a, small)
	await _rescue()
	_honesty([a, unarmed, small, slow])
	await _passive()
	await _negative()
	await _tab(a)
	await _unsupported()
	for run in [a, a2, unarmed, small, slow]:
		(run.bench as Node).queue_free()
	await _frames(2)
	print("adda_workflow_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

# ---- 1

func _recording(run: Dictionary) -> void:
	var rows: Array = run.rows
	var expected := 13.0 / (1.0 / 60.0)
	check(rows.size() > expected - 10 and rows.size() < expected + 10, "one row per stepped frame: %d rows for a 13 s scenario at 60 fps (about %d)" % [rows.size(), int(expected)])
	var ordered := true
	var dt_ok := true
	for i in range(1, rows.size()):
		ordered = ordered and float(rows[i].t) > float(rows[i - 1].t) and int(rows[i].n) == int(rows[i - 1].n) + 1
		dt_ok = dt_ok and absf(float(rows[i].dt) - 1.0 / 60.0) < 0.0005
	check(ordered, "rows are strictly time-ordered and consecutively numbered")
	check(dt_ok, "every row's step is the fixed 1/60 s")
	var row: Dictionary = rows[rows.size() / 2]
	check((row.bones as Dictionary).size() >= 20 and (row.hands as Array).size() == 2 and (row.feet as Array).size() >= 0 and (row.stages as Array).size() > 0 and String(row.state) != "", "a row holds the mapped bones (%d), both hands, the stages engaged (%s) and the animation state" % [(row.bones as Dictionary).size(), ",".join(row.stages)])
	check(float(row.st) >= 0.0 and float(rows.back().st) > 12.0, "rows carry the scenario clock (ends at %.2f s)" % float(rows.back().st))
	check((run.report.markers as Array).size() >= 5, "the scenario's own steps are markers on the same axis (%d)" % (run.report.markers as Array).size())

# ---- 2

func _report_fields(run: Dictionary) -> void:
	var report: Dictionary = run.report
	for key in ["format", "version", "config", "summary", "findings", "worst_frames", "events", "markers", "samples", "instruments", "limitations", "meta"]:
		check(report.has(key), "report has '%s'" % key)
	var config: Dictionary = report.config
	for key in ["scenario", "character", "identity", "armed", "body_ratio", "frame_dt_s", "fps", "rows", "duration_s", "mesh_sampling", "engine", "revision", "command", "cli"]:
		check(config.has(key), "config has '%s'" % key)
	check(config.scenario == "contacts" and config.character == "mira_0" and config.armed == true and absf(float(config.fps) - 60.0) < 0.5, "the config says what was run: %s, %s, armed %s, %.1f fps" % [config.scenario, config.character, config.armed, float(config.fps)])
	check(String(config.revision.commit) != "" and config.revision.has("dirty") and String(config.engine).begins_with("4."), "it names the source revision (%s) and the engine (%s)" % [config.revision.commit, config.engine])
	check(String(config.command).contains("--scenario=contacts"), "and the command that relaunches it")
	var again: Variant = JSON.parse_string(JSON.stringify(report))
	check(again is Dictionary and (again as Dictionary).findings.size() == (report.findings as Array).size() and (again as Dictionary).summary.metrics.size() == (report.summary.metrics as Dictionary).size(), "the report survives JSON")
	var kinds: Array = (report.instruments as Array).map(func(i: Dictionary) -> String: return "%s=%s" % [i.kind, i.status])
	check(kinds.has("MESH_INTERSECTION=UNSUPPORTED") and kinds.has("PHYSICAL_COLLISION=UNSUPPORTED") and kinds.has("JOINT_POSITION=TAKEN") and kinds.has("VERTEX_OVERLAP=NOT TAKEN"), "instruments: what was taken, what was not, what is unsupported (%s)" % [kinds])
	var samples: Dictionary = report.samples
	check(int(samples.count) < (run.rows as Array).size() and int(samples.count) > 0 and String(samples.selection).contains("worst"), "the summary carries the worst frames only (%d of %d rows), not a wall of data" % [int(samples.count), (run.rows as Array).size()])
	var worst_ok := true
	for frame: Dictionary in report.worst_frames:
		var present := false
		for row: Dictionary in samples.rows:
			present = present or int(row.n) == int(frame.n)
		worst_ok = worst_ok and present
	check(worst_ok, "every worst frame named has its recorded row in the report")

# ---- 3

func _determinism(a: Dictionary, a2: Dictionary) -> void:
	var result := ReportCompare.compare(a.report, a2.report)
	# In-process, the rig's own frame time is the engine's real delta (not fixed), so two runs agree only to within that noise; the EXACT reproducibility contract is tested with --fixed-fps in adda_cli_test.
	check(result.comparable and int(result.counts.incomparable) == 0 and int(result.counts.missing) == 0, "the same run twice is comparable with nothing incomparable or missing")
	var worst := 0.0
	var worst_key := ""
	for row: Dictionary in result.metrics:
		if row.delta != null and absf(float(row.delta)) > worst:
			worst = absf(float(row.delta))
			worst_key = String(row.key)
	check(worst < 3.0, "and no metric differs between the two runs by more than 3 units (worst %.3f in %s: the rig's own frame time is not fixed in-process)" % [worst, worst_key])

# ---- 4

func _experiments(a: Dictionary, unarmed: Dictionary, small: Dictionary, slow: Dictionary) -> void:
	var armed := ReportCompare.compare(a.report, unarmed.report)
	check(armed.comparable and (armed.notes as Array).any(func(n: String) -> bool: return n.contains("Armed state differs")), "armed against unarmed compares, and says it is an experiment")
	var bodies := ReportCompare.compare(a.report, small.report)
	check(bodies.comparable and (bodies.notes as Array).any(func(n: String) -> bool: return n.contains("body size")), "MIRA against Small MIRA compares with lengths normalised by body size")
	check(float(small.report.config.body_ratio) < float(a.report.config.body_ratio) - 0.05, "the ratio it used is real: Small MIRA %.3f against MIRA %.3f" % [float(small.report.config.body_ratio), float(a.report.config.body_ratio)])
	var meshes := _row(bodies, "mesh.worst_vertices")
	check(not meshes.is_empty() and meshes.verdict == "MISSING" and String(meshes.reason).contains("not measured in A"), "the leg-vertex metric exists only where it was sampled, and the other run is MISSING, not zero")
	var rates := ReportCompare.compare(a.report, slow.report)
	check(_row(rates, "discontinuity.worst_speed_mps").verdict == "INCOMPARABLE" and (rates.notes as Array).any(func(n: String) -> bool: return n.contains("frame rate")), "60 against 30 fps: the snap speed is refused, not compared")
	check(absf(float(slow.report.config.fps) - 30.0) < 0.5, "and the report knows it ran at %.1f fps" % float(slow.report.config.fps))
	check(_row(rates, "foot.right.worst_slide_mm").verdict != "INCOMPARABLE" and _row(rates, "foot.right.worst_error_mm").verdict == "INCOMPARABLE", "while a slide in millimetres still compares across frame rates, and the foot error at the first held frame (which the frame step decides) does not")

func _row(result: Dictionary, key: String) -> Dictionary:
	for row: Dictionary in result.metrics:
		if row.key == key:
			return row
	return {}

# ---- 5

func _contexts(a: Dictionary) -> void:
	var report: Dictionary = a.report
	var kinds := _kinds(report)
	var changes := (report.events as Array).filter(func(e: Dictionary) -> bool: return e.kind == "context_changed").map(func(e: Dictionary) -> String: return "%s>%s" % [e.detail.from, e.detail.to])
	var seen := {}
	for row: Dictionary in a.rows:
		seen[String(row.context)] = true
	check(seen.has("stairs") and seen.has("ladder") and changes.has("stairs>free") and changes.has("free>ladder") and changes.has("ladder>free"), "the stairs and the ladder are contexts, and each ends or begins as a context change (%s; seen %s)" % [changes, seen.keys()])
	check(kinds.has("foot_planted") and kinds.has("foot_released") and kinds.has("contact_acquired") and kinds.has("contact_released"), "feet plant and release, hands acquire and release contacts")
	var sources := {}
	for row: Dictionary in a.rows:
		for foot: Dictionary in row.feet:
			sources[String(foot.source)] = true
	check(sources.has("stair planner") and sources.has("ladder solver"), "the foot plans come from the stair planner and the ladder solver (%s)" % [sources.keys()])
	var ladder_rows := (a.rows as Array).filter(func(r: Dictionary) -> bool: return r.has("ladder"))
	check(ladder_rows.size() > 100 and not (ladder_rows[0].ladder.foot_rung as Array).is_empty(), "ladder rows carry the climbed height and the rungs the feet are on (%d rows)" % ladder_rows.size())
	var metrics: Dictionary = report.summary.metrics
	check(metrics.has("foot.left.worst_error_mm") and metrics.has("hand.left.worst_deficit_cm") and metrics.has("hand.right.worst_error_mm"), "the hand and foot metrics are there")
	var owners := {}
	for row: Dictionary in a.rows:
		for hand: Dictionary in row.hands:
			owners[String(hand.owner)] = true
	check(owners.has("contact claim"), "hand contacts are labelled with their owner (%s)" % [owners.keys()])

# ---- 6

func _mesh(a: Dictionary, small: Dictionary) -> void:
	var fresh := 0
	var other := 0
	for row: Dictionary in small.rows:
		if row.has("mesh"):
			if String(row.mesh.status) == "FRESH":
				fresh += 1
			else:
				other += 1
	var ladder_rows := (small.rows as Array).filter(func(r: Dictionary) -> bool: return r.has("ladder")).size()
	check(fresh > ladder_rows * 0.8, "with mesh sampling on, nearly every ladder row has a FRESH leg-vertex record (%d of %d ladder rows, %d not fresh)" % [fresh, ladder_rows, other])
	check(small.report.config.mesh_sampling == true and small.report.summary.metrics.has("mesh.worst_vertices"), "the report says mesh sampling was on and carries its metric")
	check(not a.report.config.mesh_sampling and not (a.report.summary.metrics as Dictionary).has("mesh.worst_vertices"), "a run without it carries no mesh metric")
	var not_measured := (a.report.findings as Array).filter(func(f: Dictionary) -> bool: return f.kind == "not_measured")
	check(not_measured.size() == 1 and String(not_measured[0].observation.text).contains("not evidence of a clean climb"), "and says plainly that it did not look, instead of staying silent")
	var rung := (small.report.findings as Array).filter(func(f: Dictionary) -> bool: return f.kind == "mesh_overlap")
	for finding: Dictionary in rung:
		check(finding.subject.has("surface") and finding.observation.facts.has("bar") and (finding.observation.facts.bar.radius_m as float) > 0.0 and (finding.subject.bones as Array).size() == 1, "a mesh finding names the part, the bar (%s) and carries the environment's own bar and normal" % [finding.subject.get("surface", {}).get("name", "?")])
		break

# ---- rescue and carry

func _rescue() -> void:
	for pair in [[&"mira_0", true], [&"small_mira_0", false]]:
		var run := await _record(pair[0], pair[1], &"rescue", 1.0 / 60.0)
		var label := "%s %s rescue" % [pair[0], "armed" if pair[1] else "unarmed"]
		var kinds := _kinds(run.report)
		var contexts := {}
		for row: Dictionary in run.rows:
			contexts[String(row.context)] = true
		check(contexts.has("carry") and contexts.has("free"), "%s: the body is in a carry context during the lift and carry (%s)" % [label, contexts.keys()])
		check(kinds.has("contact_acquired") or kinds.has("reach_exceeded"), "%s: the passenger contacts show up as hand events (%s)" % [label, kinds.slice(0, 6)])
		check((run.report.config.armed as bool) == pair[1], "%s: the report records the weapon state" % label)
		(run.bench as Node).queue_free()
		await _frames(2)

# ---- 9

func _honesty(runs: Array) -> void:
	var honest := true
	var total := 0
	for run in runs:
		for f: Dictionary in run.report.findings:
			total += 1
			honest = honest and f.cause == "unknown" and (f.evidence.kinds as Array).size() > 0 and (f.evidence.does_not_establish as Array).size() > 0
			for h: Dictionary in f.hypotheses:
				honest = honest and h.status == "unconfirmed" and String(h.experiment) != ""
	check(total > 5 and honest, "all %d findings across the real runs say the cause is unknown, every hypothesis is unconfirmed with an experiment, and each names what its measurement does not establish" % total)

# ---- 7

func _passive() -> void:
	# That recording changes no pose bit is proved with a fixed frame rate in adda_cli_test (the probe hash); here: it leaves nothing behind.
	var tidy := await _bench(&"mira_0", true)
	var before: int = tidy.rig.skeleton.skeleton_updated.get_connections().size()
	var recorder2: SessionRecorder = tidy.diagnostics.begin_recording(Callable(), true)
	await _frames(3)
	check(tidy.rig.skeleton.skeleton_updated.get_connections().size() > before, "while recording, the witness is listening")
	tidy.diagnostics.end_recording()
	check(recorder2.is_clean() and tidy.rig.skeleton.skeleton_updated.get_connections().size() == before, "stopping leaves the skeleton with the listeners it started with (%d, was %d)" % [tidy.rig.skeleton.skeleton_updated.get_connections().size(), before])
	tidy.diagnostics.shutdown()
	tidy.queue_free()
	await _frames(2)

# ---- 8

func _negative() -> void:
	var bench := await _bench(&"mira_0", true)
	bench.diagnostics.begin_recording(Callable())
	await _frames(40)
	var clean := TimelineAnalysis.analyze(bench.diagnostics.recorder.rows)
	check((clean.events as Array).filter(func(e: Dictionary) -> bool: return e.kind == "pose_snap").is_empty(), "normal case: an idle body for %d frames has no pose snap" % bench.diagnostics.recorder.rows.size())
	var root_node: Node3D = bench.rig.character_root
	root_node.global_position += Vector3(0.0, 0.0, 0.4)   # the fault: the body is carried 40 cm in one frame
	await _frames(40)
	var faulty := TimelineAnalysis.analyze(bench.diagnostics.recorder.rows)
	var snaps := (faulty.events as Array).filter(func(e: Dictionary) -> bool: return e.kind == "pose_snap")
	check(snaps.size() == 1 and absf(float(snaps[0].value) - 40.0) < 2.0 and int(snaps[0].detail.count) >= 10, "a 40 cm teleport in one frame is ONE pose snap of about 40 cm moving %d bones and the root together" % (int(snaps[0].detail.count) if not snaps.is_empty() else 0))
	var report := AddaReport.build(bench.diagnostics.recorder, {"scenario": "free", "character": "mira_0"})
	check(String(report.summary.headline).contains("1 finding") and report.findings[0].kind == "pose_snap" and String(report.findings[0].observation.text).contains("40."), "the finding says it in words: %s" % String(report.findings[0].observation.text).substr(0, 120))
	root_node.global_position -= Vector3(0.0, 0.0, 0.4)
	bench.diagnostics.shutdown()
	bench.queue_free()
	await _frames(2)

# ---- 10

func _tab(run: Dictionary) -> void:
	var bench: Node3D = run.bench
	var tab: WhyTab = bench.panel.tab_named(&"Why?")
	check(tab != null and bench.panel.tabs.get_tab_title(WorkbenchPanel.index_of(&"Why?")) == "Why?", "the Why? tab is there and found by name")
	tab._analyze()
	check(String(tab._headline.text).contains("finding") and tab._list.get_child_count() > 0 and tab._list.get_child_count() <= 8, "'What happened?' gives a plain headline and at most 8 findings to start with (%d)" % tab._list.get_child_count())
	var findings: Array = tab._report.findings
	tab._select(findings[0])
	check(String(tab._observed.text).contains(findings[0].title) and String(tab._causes.text).contains("unknown") and String(tab._detail.text).contains("Does not establish"), "selecting a finding shows what was measured, 'cause: unknown', and the technical detail on request")
	var mesh_free := findings.filter(func(f: Dictionary) -> bool: return f.kind != "not_measured")
	tab._select(mesh_free[0])
	tab._show_it()
	check(tab._marker.focus != Vector3.INF, "'Show it' puts a marker on the body and has a place to look")
	tab._part_choice.select(1)
	tab._on_part(1)
	check(bench.diagnostics.highlight != null and not bench.diagnostics.highlight.bone_names.is_empty(), "choosing a body part highlights its bones")
	tab._save_baseline()
	tab._compare()
	check(String(tab._compare_text.text).contains("VERDICT: UNCHANGED"), "saving a baseline and comparing with it says UNCHANGED (%s)" % String(tab._compare_text.text).substr(0, 80))
	tab._export()
	check(String(tab._export_text.text).begins_with("Saved"), "the report exports: %s" % String(tab._export_text.text).substr(0, 60))
	var none: Array[String] = []
	bench.diagnostics.highlight_bones(none)
	tab._selected = mesh_free[0]
	tab._replay()
	check(bench.sim_paused and bench.scenario_runner.running, "'Replay to this moment' restarts the scenario and pauses on it")
	var waited := 0
	while bench.pending_steps() > 0 and waited < 900:
		await process_frame
		waited += 1
	await _frames(2)
	check(bench.scenario_runner.time > 0.0 and absf(bench.scenario_runner.time - float(mesh_free[0].reproduce.st)) < 0.2, "and it stops at the finding's time (%.2f s, wanted %.2f s)" % [bench.scenario_runner.time, float(mesh_free[0].reproduce.st)])

# ---- 11

func _unsupported() -> void:
	var bench := await _bench(&"small_mira_0", false)
	check(not bench.start_scenario(&"tactical"), "an unarmed body is refused the tactical scenario")
	check(not WorkbenchScenarios.supported(WorkbenchScenarios.find(&"tactical"), bench.rig).ok and String(WorkbenchScenarios.supported(WorkbenchScenarios.find(&"tactical"), bench.rig).reason).contains("weapon"), "and the reason is named: a weapon is needed")
	bench.queue_free()
	await _frames(2)
