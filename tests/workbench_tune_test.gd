extends SceneTree
## The Workbench made usable without a guide: the Start tab is first and offers every scenario (disabled with a reason when it cannot run); the Tune tab turns the motion profiles' own @export ranges into
## controls that change the LIVE character, undo to the saved values, and save a file the character loads when it is built (so the game uses it too); stair edits go through the authored profile and are
## measured again per body; the Why? tab never leaves an older run's findings under a "no recording" line; and a replay on its way to a moment is never reported as PAUSED.
## Tuning is written to a scratch folder (CharacterRig.tuning_folder_override), never into art/.
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const SCRATCH := "user://workbench_tune_test"
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

func _close(bench: Node3D) -> void:
	bench.queue_free()
	await _frames(3)

func _clean() -> void:
	var folder := ProjectSettings.globalize_path(SCRATCH)
	if DirAccess.dir_exists_absolute(folder):
		for file in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file))

func _entry(tab: TuneTab, name: StringName) -> Dictionary:
	for entry in TuneTab.entries_of(tab.profile()):
		if entry.name == name:
			return entry
	return {}

## "Edit in Godot": the request the editor plugin reads, the heartbeat that says an editor is open, a clip copied into a file with a scene that edits it on the body, and edits saved outside (as the
## editor would) reaching the live character and a newly built one. The editor plugin itself needs a running editor and is not exercised here.
func _godot_round_trip() -> void:
	EditorBridge.folder = SCRATCH.path_join("bridge")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EditorBridge.folder))
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(EditorBridge.folder)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(EditorBridge.folder).path_join(file))
	var now := Time.get_unix_time_from_system()
	check(not EditorBridge.editor_alive(now), "with no heartbeat no editor counts as open")
	EditorBridge.beat()
	check(EditorBridge.editor_alive(now + 1.0) and not EditorBridge.editor_alive(now + 30.0), "a heartbeat counts for a few seconds only")
	var req := EditorBridge.request("res://x.tres", "Clips", "rifle_idle")
	EditorBridge.send(req, false)
	check(EditorBridge.pending("").get("id", "") == req.id and EditorBridge.pending(String(req.id)).is_empty(), "the editor sees a new request once")
	check(EditorBridge.pending("", now + EditorBridge.STALE_SECONDS + 5.0).is_empty(), "an old request is ignored")
	EditorBridge.done()
	check(EditorBridge.pending("").is_empty(), "a handled request is gone")

	# A clip: copied into clips.tres, with a scene whose AnimationPlayer drives the model's skeleton.
	var bench := await _bench(&"mira_0", false)
	var tune: TuneTab = bench.panel.tab_named(&"Tune")
	tune.pick_clip(&"rifle_idle")
	tune.edit_clip(false)
	var library_file := ClipFiles.library_path(bench.rig)
	var scene_file := ClipFiles.scene_path(bench.rig)
	check(FileAccess.file_exists(library_file) and ClipFiles.load_library(bench.rig).has_animation(&"rifle_idle"), "the clip is saved as a file (%s)" % library_file)
	var sent := EditorBridge.pending("")
	check(String(sent.get("path", "")) == scene_file and String(sent.get("animation", "")) == "rifle_idle" and String(sent.get("node", "")) == ClipFiles.PLAYER, "the editor is asked to open the clip's scene on that clip")
	var scene: Node = (ResourceLoader.load(scene_file, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var player := scene.get_node(ClipFiles.PLAYER) as AnimationPlayer
	check(player != null and player.has_animation(&"rifle_idle") and player.get_node_or_null(player.root_node) is Skeleton3D, "the editing scene's player has the clip and its root is the model's skeleton")
	scene.free()
	# A save from outside (what Ctrl+S in the editor does): a changed key reaches the live player.
	OS.delay_msec(1100)   # file times are in whole seconds
	var library := ClipFiles.load_library(bench.rig)
	var clip := library.get_animation(&"rifle_idle")
	var track := 0
	var moved := Quaternion(Vector3.UP, 0.7) * clip.rotation_track_interpolate(track, 0.0)
	clip.track_set_key_value(track, 0, moved)
	ResourceSaver.save(library, library_file)
	tune.pick_up_outside_edits()
	var live: Animation = bench.rig.animation_controller.animation_player.get_animation(&"rifle_idle")
	check(live.track_get_key_value(track, 0).is_equal_approx(moved), "an edit saved outside plays at once in the Workbench")
	await _close(bench)
	bench = await _bench(&"mira_0", false)
	check(bench.rig.clip_library != null and bench.rig.animation_controller.animation_player.get_animation(&"rifle_idle").track_get_key_value(track, 0).is_equal_approx(moved), "a newly built character plays the edited clip (the game does the same)")
	# A clip that is not a bone clip of this body is skipped, not applied.
	var bad := Animation.new()
	var value_track := bad.add_track(Animation.TYPE_VALUE)
	bad.track_set_path(value_track, NodePath(".:visible"))
	bad.track_insert_key(value_track, 0.0, true)
	library = ClipFiles.load_library(bench.rig)
	if library.has_animation(&"aim"):
		library.remove_animation(&"aim")
	library.add_animation(&"aim", bad)
	ResourceSaver.save(library, library_file)
	var applied := ClipFiles.apply_saved(bench.rig)
	check(applied.skipped.has(&"aim") and applied.applied.has(&"rifle_idle"), "a clip that is not a bone clip is skipped (%s)" % [applied])
	# Settings saved outside reach the live profile.
	tune = bench.panel.tab_named(&"Tune")
	tune.pick(&"cover_profile")
	var path := tune.save()
	tune.refresh()
	OS.delay_msec(1100)
	var outside := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CoverPostureProfile
	outside.high_cover_crouch_depth = 0.33
	ResourceSaver.save(outside, path)
	tune.pick_up_outside_edits()
	check(is_equal_approx(bench.rig.cover_profile.high_cover_crouch_depth, 0.33) and tune.changed_count() == 0, "a settings file saved outside is picked up (%.3f)" % bench.rig.cover_profile.high_cover_crouch_depth)
	await _close(bench)
	_clean()
	EditorBridge.folder = "user://adda_bridge"

func _run() -> void:
	CharacterRig.tuning_folder_override = SCRATCH
	_clean()

	# --- Start tab: first, and every scenario is one button (an unavailable one is disabled and says why).
	var bench := await _bench(&"mira_0", false)
	var panel: WorkbenchPanel = bench.panel
	check(panel.tabs.current_tab == 0 and panel.tabs.get_tab_title(0) == "Start", "the Workbench opens on the Start tab")
	var start: StartTab = panel.tab_named(&"Start")
	var buttons: Array[Button] = []
	for node in start.get_children():
		if node is Button and String(node.text).length() > 2 and String(node.text)[1] == " ":
			buttons.append(node)
	check(buttons.size() == WorkbenchScenarios.all().size(), "the Start tab has one button per scenario (%d)" % buttons.size())
	var tactical_disabled := false
	for button in buttons:
		if String(button.text).begins_with("A"):
			tactical_disabled = button.disabled and button.tooltip_text.contains("Not available")
	check(tactical_disabled, "unarmed, the cover-and-fire scenario is disabled and says why")

	# --- Tune: entries come from the profile's own exports, with range and unit.
	var tune: TuneTab = panel.tab_named(&"Tune")
	for index in TuneTab.PROFILES.size():
		tune.pick(TuneTab.PROFILES[index].property)
		check(TuneTab.entries_of(tune.profile()).size() >= 5, "%s offers its settings (%d)" % [TuneTab.PROFILES[index].title, TuneTab.entries_of(tune.profile()).size()])
	tune.pick(&"cover_profile")
	var depth := _entry(tune, &"high_cover_crouch_depth")
	var limits := TuneTab.range_of(depth)
	check(limits.ok and is_equal_approx(float(limits.min), 0.0) and is_equal_approx(float(limits.max), 0.4) and limits.suffix == "m", "a setting carries its declared range and unit (%s)" % [limits])
	check(TuneTab.humanize("high_cover_crouch_depth") == "High cover crouch depth", "names read as words")

	# A change reaches the live character at once; Undo puts it back.
	var rig: CharacterRig = bench.rig
	var original := rig.cover_profile.high_cover_crouch_depth
	tune._apply(depth, 0.31)
	check(is_equal_approx(rig.cover_profile.high_cover_crouch_depth, 0.31) and tune.changed_count() == 1, "a change applies to the live character and is counted as unsaved")
	tune.undo()
	check(is_equal_approx(rig.cover_profile.high_cover_crouch_depth, original) and tune.changed_count() == 0, "Undo returns to the saved value")

	# Save writes a file in the character's tuning folder; a character built afterwards loads it (that is what the game does).
	tune._apply(_entry(tune, &"high_cover_crouch_depth"), 0.27)
	var path := tune.save()
	check(path == SCRATCH.path_join("cover_profile.tres") and FileAccess.file_exists(path) and tune.changed_count() == 0, "Save writes the profile to the tuning folder (%s)" % path)
	await _close(bench)
	bench = await _bench(&"mira_0", false)
	check(is_equal_approx(bench.rig.cover_profile.high_cover_crouch_depth, 0.27), "a newly built character uses the saved value (%.3f)" % bench.rig.cover_profile.high_cover_crouch_depth)
	await _close(bench)
	# Negative control: without the file the character is built with the authored default.
	_clean()
	bench = await _bench(&"mira_0", false)
	check(is_equal_approx(bench.rig.cover_profile.high_cover_crouch_depth, original), "with no tuning file the authored default is used (%.3f)" % bench.rig.cover_profile.high_cover_crouch_depth)
	# A file of the wrong kind is ignored, not half-applied.
	ResourceSaver.save(StairProfile.new(), SCRATCH.path_join("cover_profile.tres"))
	await _close(bench)
	bench = await _bench(&"mira_0", false)
	check(bench.rig.cover_profile is CoverPostureProfile and is_equal_approx(bench.rig.cover_profile.high_cover_crouch_depth, original), "a tuning file of the wrong kind is ignored")
	_clean()
	await _close(bench)

	# --- Stairs: the tab edits the authored profile; the live one is measured and scaled again for the body; measured values are not offered.
	for character in [&"mira_0", &"small_mira_0"]:
		bench = await _bench(character, false)
		tune = bench.panel.tab_named(&"Tune")
		tune.pick(&"stair_profile")
		check(_entry(tune, &"leg_length").is_empty() and _entry(tune, &"ankle_height").is_empty(), "%s: stair values measured from the body are not offered" % character)
		var ratio: float = bench.rig.body_ratio()
		var leg_before: float = bench.rig.stair_profile.leg_length
		tune._apply(_entry(tune, &"swing_lift"), 0.2)
		check(is_equal_approx(bench.rig.stair_profile_source.swing_lift, 0.2) and absf(bench.rig.stair_profile.swing_lift - 0.2 * ratio) < 0.0005 and is_equal_approx(bench.rig.stair_profile.leg_length, leg_before),
			"%s: a stair change reaches the live profile scaled for the body (%.4f for ratio %.3f) and the measured leg stays" % [character, bench.rig.stair_profile.swing_lift, ratio])
		await _close(bench)

	# --- Why?: a "no recording" answer never leaves an older run's findings on screen.
	bench = await _bench(&"mira_0", false)
	var why: WhyTab = bench.panel.tab_named(&"Why?")
	check(bench.start_scenario(&"contacts"), "contacts starts")
	bench.set_sim_paused(true)
	for i in 120:
		bench.step_sim()
		await process_frame
	why._analyze()
	check(why._list.get_child_count() > 0 and why._headline.text.contains("Stairs"), "findings are listed and the headline names the run (%s)" % why._headline.text)
	check(why.list_label(why._report.findings[0]).contains(" s  "), "a finding's line starts with when it happened (%s)" % why.list_label(why._report.findings[0]))
	why._recorder().rows.clear()
	why._analyze()
	await _frames(2)
	check(why._list.get_child_count() == 0 and why._report.is_empty() and why._headline.text.contains("no recording"), "'no recording' clears the previous findings")

	# --- A replay on its way is "Going to", not PAUSED; once there it is paused.
	check(bench.replay_to(&"contacts", 1.0), "replay to 1.0 s starts")
	await _frames(2)
	check(bench.pending_steps() > 0 and bench.playback_text().begins_with("Going to") and not bench.playback_text().contains("PAUSED"), "on its way the status says where it is going (%s)" % bench.playback_text())
	while bench.pending_steps() > 0:
		await process_frame
	check(bench.playback_text().begins_with("PAUSED") and absf(bench.scenario_runner.time - 1.0) < 0.06, "once there it says PAUSED at the moment (%s)" % bench.playback_text())
	check(Engine.max_fps == bench._saved_max_fps and not bench._seeking, "the frame cap is put back after the replay")
	await _close(bench)

	await _godot_round_trip()

	CharacterRig.tuning_folder_override = ""
	print("workbench_tune_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
