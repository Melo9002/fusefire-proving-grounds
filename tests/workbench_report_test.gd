extends SceneTree
## "Report this moment": a person's note becomes a folder a coding agent can work from. It holds the note, the exact moment (scenario, time, frame, step), character and equipment, the source revision,
## what was on screen, ADDA's observations near the moment (labelled observations, causes unconfirmed), how to reproduce it in the window and headless, and the Tune drafts in use (copied, since drafts
## are local). A headless agent run does not read a person's drafts unless asked, so it reproduces the game. Reports are written to a scratch folder, never into the repository.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const SCRATCH := "user://workbench_report_test"
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

func _bench() -> Node3D:
	WorkbenchSession.character = &"mira_0"
	WorkbenchSession.armed = false
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(12)
	bench.step_seconds = 0.05
	return bench

func _clean(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for dir in DirAccess.get_directories_at(absolute):
		_clean(path.path_join(dir))
		DirAccess.remove_absolute(absolute.path_join(dir))
	for file in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))

func _read_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _run() -> void:
	_clean(SCRATCH)
	CharacterRig.tuning_folder_override = SCRATCH.path_join("tuning")
	MomentReport.folder = SCRATCH.path_join("reports")

	# A report during a scenario: paused at the moment, with the note.
	var bench := await _bench()
	var start: StartTab = bench.panel.tab_named(&"Start")
	check(bench.start_scenario(&"contacts"), "contacts starts")
	bench.set_sim_paused(true)
	for i in 20:
		bench.step_sim()
		await process_frame
	start._note.text = "her feet slide on the first stair"
	var result: Dictionary = await start.report()
	var dir := String(result.get("path", ""))
	check(bool(result.ok) and dir.begins_with(MomentReport.folder) and dir.contains("contacts") and dir.contains("her-feet-slide"), "the report is saved in its own named folder (%s)" % dir)
	var data := _read_json(dir.path_join("moment.json"))
	check(data.get("format") == MomentReport.FORMAT and data.get("note") == "her feet slide on the first stair" and data.get("character") == "mira_0" and data.get("armed") == false, "it keeps the note, the character and the equipment")
	var moment: Dictionary = data.get("moment", {})
	check(moment.get("scenario") == "contacts" and absf(float(moment.get("scenario_time_s", -1.0)) - 1.0) < 0.06 and int(moment.get("frame", -1)) == 20 and bool(moment.get("paused", false)),
		"it keeps the exact moment: scenario, time and frame (%s)" % [moment])
	check(String(data.get("revision", {}).get("commit", "")) != "", "it names the source revision")
	var reproduce: Dictionary = data.get("reproduce", {})
	check(String(reproduce.get("headless", "")).contains("-Scenario contacts") and String(reproduce.get("headless", "")).contains("-Unarmed") and String(reproduce.get("window", "")).contains("--scenario=contacts")
		and String(reproduce.get("at", "")) == "1.00" and not String(reproduce.get("headless", "")).contains("-Drafts"), "it says how to reproduce it in the window and headless (%s)" % [reproduce])
	var evidence: Dictionary = data.get("evidence", {})
	check(bool(evidence.get("recorded", false)) and int(evidence.get("rows", 0)) >= 20 and FileAccess.file_exists(dir.path_join("adda_report.json")), "ADDA's recording of the run comes with it")
	for finding: Dictionary in evidence.get("near", []):
		check(absf(float(finding.at_s) - 1.0) <= MomentReport.NEAR_SECONDS + 0.01 and finding.has("observed") and finding.has("possible_causes_not_confirmed"), "a nearby finding is an observation with unconfirmed causes (%s)" % finding.title)
	var readme := FileAccess.get_file_as_string(dir.path_join("README.md"))
	check(readme.contains("her feet slide on the first stair") and readme.contains("## Reproduce") and readme.contains("## Not established") and readme.contains("judgement of how the animation looks")
		and readme.contains("Do not claim it looks better because the numbers improved"), "the README gives the note, how to reproduce it and what is not established")
	check(data.get("on_screen", {}).get("animation_state", "") != "" and (data.get("on_screen", {}).get("pose_stages_active", []) as Array).size() > 0, "it records what was on screen")
	if DisplayServer.get_name() != "headless":
		check(FileAccess.file_exists(dir.path_join("screenshot.png")), "a screenshot is saved")

	# Tune drafts in use travel with the report, and the README says how to use them.
	var tune: TuneTab = bench.panel.tab_named(&"Tune")
	tune.pick(&"cover_profile")
	for entry in TuneTab.entries_of(tune.profile()):
		if entry.name == &"high_cover_crouch_depth":
			tune._apply(entry, 0.3)
	tune.save_draft()
	start._note.text = "crouch looks too deep"
	result = await start.report()
	dir = String(result.path)
	data = _read_json(dir.path_join("moment.json"))
	var tuning: Dictionary = data.get("tuning", {})
	check((tuning.get("drafts_in_use", []) as Array).size() == 1 and FileAccess.file_exists(dir.path_join("tuning/cover_profile.tres")) and (tuning.get("changes_from_game", {}) as Dictionary).has("cover_profile")
		and String(data.reproduce.headless).contains("-Drafts"), "the drafts in use are copied, listed against the game, and the reproduction asks for them")
	await _frames(2)
	bench.queue_free()
	await _frames(3)

	# An agent's headless run reproduces the GAME: it reads a person's drafts only when asked.
	WorkbenchSession.read_drafts = false
	bench = await _bench()
	check(not CharacterRig.use_drafts and not is_equal_approx(bench.rig.cover_profile.high_cover_crouch_depth, 0.3), "without --drafts the drafts are not read")
	bench.queue_free()
	await _frames(3)
	WorkbenchSession.read_drafts = true
	bench = await _bench()
	check(is_equal_approx(bench.rig.cover_profile.high_cover_crouch_depth, 0.3), "the window reads them")

	# Free play: no scenario clock, and the report says the moment cannot be replayed exactly.
	start = bench.panel.tab_named(&"Start")
	start._note.text = "idle looks stiff"
	data = _read_json(String((await start.report()).path).path_join("moment.json"))
	check(data.get("moment", {}).get("scenario") == "" and String(data.get("reproduce", {}).get("note", "")).contains("Free play"), "a free-play report says it cannot be replayed exactly")
	bench.queue_free()
	await _frames(3)

	CharacterRig.tuning_folder_override = ""
	MomentReport.folder = MomentReport.FOLDER
	_clean(SCRATCH)
	print("workbench_report_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
