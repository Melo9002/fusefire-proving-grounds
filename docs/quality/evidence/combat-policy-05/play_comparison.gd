extends SceneTree
## Same deployment and seed across policies. "pressure" selects Freight Yard.

const MODES := {"legacy": 0, "head-core": 1, "symmetric": 2, "combined": 3}
const Scene := preload("res://levels/prototype_map/prototype_map.tscn")

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var config := BattleConfiguration.new()
	var pressure := false
	var ordinary := false
	var size := 2
	var smoke := false
	var autoplay := false
	var capture_path := ""
	for arg in OS.get_cmdline_user_args():
		if MODES.has(arg):
			config.engagement_policy = MODES[arg]
		elif arg == "no-context": config.contextual_firing_disabled = true
		elif arg == "pressure": pressure = true
		elif arg == "ordinary": ordinary = true
		elif arg == "duel": size = 1
		elif arg == "3v3": size = 3
		elif arg.begins_with("capture="): capture_path = arg.substr(8)
		elif arg == "autoplay": autoplay = true
		elif arg == "smoke": smoke = true
		elif arg.begins_with("guard=") and arg.substr(6).is_valid_int():
			config.guard_minimum_chance = arg.substr(6).to_int()
		else:
			push_error("Unknown comparison option: " + arg)
			quit(2)
			return
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_FREIGHT if pressure else BattlefieldCatalog.CONTEXTUAL_SHOWCASE)
	config.player_count = size
	config.enemy_count = size
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, size)
	config.battle_seed = 16
	config.difficulty = AIDifficultyPolicy.Tier.HARD
	config.enemy_commander = AICommanderPolicy.Profile.DEFAULT if ordinary else AICommanderPolicy.Profile.CAUTIOUS
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	current_scene = level
	if not level.battle_initialization_succeeded:
		quit(1)
		return
	var layer := CanvasLayer.new()
	layer.layer = 3
	level.add_child(layer)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	panel.position = Vector2(20, 126)
	var title := Label.new()
	panel.add_child(title)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.text = "%s  ·  %s  ·  Guard %s" % [CombatRules.engagement_policy_label(config.engagement_policy),
		"Side steps off" if config.contextual_firing_disabled else "Side steps on",
		"%d%% minimum" % config.guard_minimum_chance if config.guard_minimum_chance > 0 else "first legal shot"]
	print("[CombatPolicy] ", title.text)
	if autoplay:
		level.battle_controller.action_service.action_committed.connect(func(result):
			if result is AttackActionResult or (result is MoveActionResult and not result.reaction_events.is_empty()):
				print("[RenderedCombat] ", JSON.stringify(result.to_replay_record())))
		await process_frame
		level.battle_controller.set_debug_player_ai(true)
	if smoke:
		await create_timer(19.0 if autoplay else 2.0).timeout
		if not capture_path.is_empty():
			var status: Error = level._replay_recorder.recording.save_json(capture_path)
			if status != OK:
				push_error("Unable to save comparison recording: " + error_string(status))
				quit(1)
				return
		quit()
