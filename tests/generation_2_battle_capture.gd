extends SceneTree
## Explicit rendered evidence for Task 6.1. This exercises the real Match Setup
## selector and normal BattleLevel scene rather than a presentation-only fixture.

const CAPTURE_SIZE := Vector2i(1600, 900)
const OUTPUT_NAMES := ["generation-2-match-setup.png", "generation-2-industrial-17-playable.png"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = CAPTURE_SIZE
	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	setup.generated_map_toggle.button_pressed = true
	setup.generation_preset_option.select(1)
	setup._on_generation_preset_selected(1)
	setup.auto_seed_toggle.button_pressed = false
	setup.seed_input.value = 17
	setup._update_summary(0.0)
	setup.get_node("CenterContainer/Panel/Margin/VBox/Body/SetupTabs").current_tab = 2
	await RenderingServer.frame_post_draw
	if not _save(output.path_join(OUTPUT_NAMES[0])): return
	setup.queue_free()
	await process_frame

	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	config.player_count = 2
	config.enemy_count = 2
	config.mission = MissionCatalog.create_mission(0, 2, false)
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(config)
	var completed: Array = []
	battle.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors}), CONNECT_ONE_SHOT)
	root.add_child(battle)
	var deadline := Time.get_ticks_msec() + 30000
	while completed.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	if completed.is_empty() or not completed[0].success:
		push_error("Generation 2.0 battle capture initialization failed: %s" % str(completed))
		quit(1)
		return
	var rig := battle.get_node("CameraRig") as TacticalCamera
	rig.focus_position(Vector3.ZERO)
	rig._set_zoom(72.0)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save(output.path_join(OUTPUT_NAMES[1])): return
	print("Generation 2.0 battle captures saved to " + output)
	quit()

func _save(path: String) -> bool:
	var error := root.get_texture().get_image().save_png(path)
	if error == OK: return true
	push_error("Generation 2.0 capture failed: %s" % error)
	quit(1)
	return false
