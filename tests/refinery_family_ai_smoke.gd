extends SceneTree
## Full tactical/replay proof for a representative authored battlefield.

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const Layout = preload("res://systems/generation/refinery_family_layout.gd")
const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
var family_id := Catalog.REFINERY_FAMILY
var family_layout = Layout
var family_plots = PlotCatalog

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("urban"):
		family_id = Catalog.URBAN_FAMILY
		family_layout = load("res://systems/generation/urban_family_layout.gd")
		family_plots = load("res://systems/generation/urban_plot_catalog.gd")
	elif args.has("garage"):
		family_id = Catalog.PARKING_GARAGE
		family_layout = load("res://systems/generation/parking_garage_layout.gd")
		family_plots = family_layout
	elif args.has("authored"):
		family_id = Catalog.REFINERY_2
		family_layout = load("res://systems/generation/refinery_2_layout.gd")
		family_plots = null
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var passed := true
	for seed in ([16, 17] if family_plots else [16]):
		passed = await _run_seed(seed, args.has("disk"), not args.has("empty")) and passed
	Engine.time_scale = previous_time_scale
	print("%s AI matrix: %s" % [family_id, "PASSED" if passed else "FAILED"])
	if not passed: push_error("%s tactical/replay matrix failed" % family_id)
	quit(0 if passed else 1)

func _run_seed(seed: int, disk_round_trip: bool, population_enabled: bool) -> bool:
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": seed,
		"mission_kind": MissionObjectiveDefinition.Kind.REACH,
		"player_count": 3,
		"enemy_count": 3,
		"map_size": Vector2i(64, 64),
		"battlefield_id": family_id,
		"content_manifest": {"population_enabled": population_enabled} if family_plots else {},
		"difficulty": AIDifficultyPolicy.Tier.NORMAL,
		"maximum_rounds": 24,
		"stall_seconds": 6.0,
		"timeout_seconds": 60.0,
	})
	var passed: bool = result.map_source == family_layout.SOURCE_KIND \
		and result.validation_errors.is_empty() \
		and result.decision_count > 0 \
		and result.status == AIMatchSimulationResult.Status.COMPLETED
	var recording = BattleReplaySession.last_recording
	var recorded_manifest: Dictionary = recording.configuration.get("content_manifest", {}) if recording else {}
	passed = passed and recording != null and StringName(recording.configuration.get("battlefield_id", "")) == family_id
	if family_plots:
		var recorded_plot: Dictionary = family_plots.get_definition(StringName(recorded_manifest.get("plot_id", &"")))
		passed = passed and not recorded_plot.is_empty() and recorded_manifest.placements.size() == recorded_plot.slots.size()
		passed = passed and recorded_manifest.get("population_enabled") == population_enabled
	if recording and disk_round_trip:
		var directory := "res://artifacts/generation-acceptance"
		var path := "%s/%s-%d-%s.replay.json" % [directory, family_id, seed, "populated" if population_enabled else "empty"]
		var folder_status := DirAccess.make_dir_recursive_absolute(directory)
		var save_status := BattleReplaySession.save_last(path) if folder_status == OK else folder_status
		if save_status == OK:
			recording = BattleReplaySession.load_recording(path)
			passed = passed and recording.is_playable() and recording.configuration.content_manifest == recorded_manifest
			print("Saved and reopened replay at %s" % path)
		else:
			push_error("Replay save failed for %s: %s" % [path, error_string(save_status)])
			passed = false
	if recording:
		var replay := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
		replay.configure_replay(recording)
		root.add_child(replay)
		while replay.turn_manager.current_round == 0 and not replay.battle_initialization_attempted: await process_frame
		passed = passed and replay.battle_initialization_succeeded and replay.active_generated_map.content_manifest == recorded_manifest
		var player := replay.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
		if player:
			player.set_playback_speed(4.0)
			var deadline := Time.get_ticks_msec() + 30000
			while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
			passed = passed and player.playback_succeeded and player.verified_actions == recording.actions.size()
			print("%s playback: %d/%d actions, succeeded=%s" % [family_id, player.verified_actions, recording.actions.size(), player.playback_succeeded])
		else:
			passed = false
		replay.queue_free()
		await process_frame
	simulator.queue_free()
	await process_frame
	print("%s seed %d: %s — %s" % [family_id, seed, "PASSED" if passed else "FAILED", result.summary()])
	return passed
