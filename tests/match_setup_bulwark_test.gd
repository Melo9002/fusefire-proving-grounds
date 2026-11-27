extends SceneTree
## The Bulwark and the Skirmisher can be chosen in the match setup menu, reach the battle as the chosen
## units, and wear their stripes there (yellow and red).

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _find_selectors(node: Node, found: Array[OptionButton]) -> void:
	for child in node.get_children():
		if child is OptionButton and child.name == &"ArchetypeOption":
			found.append(child)
		_find_selectors(child, found)

func _run() -> void:
	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	await process_frame
	var selectors: Array[OptionButton] = []
	_find_selectors(setup, selectors)
	check(not selectors.is_empty(), "The setup menu shows a unit selector for every roster slot")
	var bulwark_index := -1
	if not selectors.is_empty():
		for index in selectors[0].item_count:
			if selectors[0].get_item_metadata(index) == &"bulwark":
				bulwark_index = index
		check(bulwark_index >= 0 and selectors[0].get_item_text(bulwark_index) == "Bulwark", "The Bulwark is in the unit selection list")
	if bulwark_index >= 0:
		selectors[0].select(bulwark_index)
		selectors[0].item_selected.emit(bulwark_index)
		check(setup.player_archetypes[0] == &"bulwark", "Choosing it sets the first player slot")
		var description := selectors[0].get_parent().find_child("Description", true, false) as Label
		check(description != null and description.text.contains("every direction"), "The menu describes it")
	var skirmisher_index := -1
	if selectors.size() > 1:
		for index in selectors[1].item_count:
			if selectors[1].get_item_metadata(index) == &"skirmisher":
				skirmisher_index = index
		check(skirmisher_index >= 0 and selectors[1].get_item_text(skirmisher_index) == "Skirmisher", "The Skirmisher is in the unit selection list")
	if skirmisher_index >= 0:
		selectors[1].select(skirmisher_index)
		selectors[1].item_selected.emit(skirmisher_index)
		check(setup.player_archetypes[1] == &"skirmisher", "Choosing it sets the second player slot")
	var engagement := setup.engagement_option
	check(engagement.get_selected_id() == CombatRules.EngagementPolicy.LEGACY, "Fresh setup defaults to Legacy")
	for policy in CombatRules.EngagementPolicy.values():
		var index := engagement.get_item_index(policy)
		check(index >= 0, "Setup offers %s" % CombatRules.engagement_policy_label(policy))
		if index < 0: continue
		engagement.select(index)
		check(setup._build_battle_configuration().engagement_policy == policy, "Selected option reaches the battle configuration")
	engagement.select(engagement.get_item_index(CombatRules.EngagementPolicy.SYMMETRIC))
	engagement.item_selected.emit(engagement.selected)
	check(setup.deployment_summary.text.contains("Engagement: Symmetrical"), "The briefing shows the active selection")
	var contextual := setup.contextual_firing_toggle
	check(not contextual.disabled and not contextual.button_pressed, "Contextual firing is opt-in on the default Depot")
	for index in setup.map_size_option.item_count:
		var id: StringName = setup.map_size_option.get_item_metadata(index)
		setup.map_size_option.select(index)
		setup.map_size_option.item_selected.emit(index)
		var variant := BattlefieldCatalog.contextual_variant(id)
		check(setup._build_battle_configuration().battlefield_id == id, "Toggle off preserves the ordinary battlefield")
		check(contextual.disabled == variant.is_empty(), "Only certified battlefields enable the contextual toggle")
		if not contextual.disabled:
			contextual.button_pressed = true
			check(setup._build_battle_configuration().battlefield_id == variant, "Toggle on selects the corresponding certified variant")
		contextual.button_pressed = false
	setup.map_size_option.select(0)
	setup.map_size_option.item_selected.emit(0)
	contextual.button_pressed = true
	check(setup.deployment_summary.text.contains("Contextual firing: On"), "The briefing confirms the contextual firing selection")
	setup.start_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while not current_scene is BattleLevel and Time.get_ticks_msec() < deadline:
		await process_frame
	var battle := current_scene as BattleLevel
	check(battle != null, "The battle starts")
	if battle:
		for i in 10: await process_frame
		check(battle.battle_controller.grid_manager.map_data.engagement_policy == CombatRules.EngagementPolicy.SYMMETRIC,
			"Start Battle applies Symmetrical to the live firing rules")
		check(battle._replay_recorder.recording.configuration.engagement_policy == CombatRules.EngagementPolicy.SYMMETRIC,
			"The match recording preserves the selected engagement rule")
		check(battle.battle_controller.grid_manager.map_data.contextual_discovery_enabled, "Start Battle enables contextual firing")
		check(battle._replay_recorder.recording.configuration.battlefield_id == BattlefieldCatalog.CONTEXTUAL_DEPOT,
			"The match recording identifies the certified contextual variant")
		var unit: TacticalUnit = battle.turn_manager.player_units[0]
		check(unit.archetype_id == &"bulwark" and unit.shield_capability != null and unit.stats.speed == 4, "The chosen slot spawns as a Bulwark")
		var stripe: Node = null
		for node in unit.find_children("ClassMarkerStripe", "", true, false):
			stripe = node
		check(stripe != null and stripe.get_child_count() == 1, "The Bulwark wears its stripe in battle")
		if stripe and stripe.get_child_count() == 1:
			var color := ((stripe.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
			check(color.r > 0.7 and color.g > 0.6 and color.b < 0.3, "The Bulwark's stripe is yellow (%s)" % str(color))
		var runner: TacticalUnit = battle.turn_manager.player_units[1] if battle.turn_manager.player_units.size() > 1 else null
		if runner:
			check(runner.archetype_id == &"skirmisher" and runner.stats.speed == 7 and is_equal_approx(runner.weapon_damage_multiplier, 0.8), "The second slot spawns as a Skirmisher")
			var red_stripe: Node = null
			for node in runner.find_children("ClassMarkerStripe", "", true, false):
				red_stripe = node
			check(red_stripe != null and red_stripe.get_child_count() == 1, "The Skirmisher wears a stripe")
			if red_stripe and red_stripe.get_child_count() == 1:
				var red := ((red_stripe.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
				check(red.r > 0.7 and red.g < 0.3 and red.b < 0.3, "The Skirmisher's stripe is red (%s)" % str(red))
		var other: TacticalUnit = battle.turn_manager.player_units[2] if battle.turn_manager.player_units.size() > 2 else null
		if other:
			check(other.archetype_id == &"generic" and other.find_children("ClassMarkerStripe", "", true, false).is_empty(), "A Generic unit has no stripe")
		battle.queue_free()
	await process_frame
	await _check_combat_lab()
	print("Match setup Bulwark: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _check_combat_lab() -> void:
	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	var lab := setup.combat_lab
	setup._setup_tabs.current_tab = setup._setup_tabs.get_tab_idx_from_control(lab)
	var initial := lab.build_configuration()
	check(initial.engagement_policy == CombatRules.EngagementPolicy.SYMMETRIC and not initial.contextual_firing_disabled
		and initial.guard_minimum_chance == 15 and initial.enemy_commander == AICommanderPolicy.Profile.CAUTIOUS
		and initial.battlefield_id == BattlefieldCatalog.CONTEXTUAL_SHOWCASE, "Combat Lab opens with the comparison defaults")
	check(setup.start_button.text == "START COMPARISON" and setup.deployment_summary.text.contains("Guard: 15% minimum"),
		"The comparison briefing and start button follow the active tab")
	check(lab.launch_command().ends_with("-- symmetric guard=15"), "Copy uses the matching default launcher switches")

	for button in lab._battlefield.get_buttons():
		if button.get_meta("value") == 1: button.button_pressed = true
	for button in lab._commander.get_buttons():
		if button.get_meta("value") == AICommanderPolicy.Profile.DEFAULT: button.button_pressed = true
	for button in lab._guard.get_buttons():
		if button.get_meta("value") == 25: button.button_pressed = true
	lab._contextual.button_pressed = false
	check(lab.launch_command().ends_with("-- symmetric no-context guard=25 ordinary pressure"),
		"Copy combines independent comparison choices")
	setup.start_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while not current_scene is BattleLevel and Time.get_ticks_msec() < deadline:
		await process_frame
	var battle := current_scene as BattleLevel
	check(battle != null, "Start Comparison launches a live battle")
	if battle:
		var record: Dictionary = battle._replay_recorder.recording.configuration
		check(record.battlefield_id == BattlefieldCatalog.CONTEXTUAL_FREIGHT and record.seed == 16 and record.guard_minimum_chance == 25
			and record.engagement_policy == CombatRules.EngagementPolicy.SYMMETRIC and record.contextual_firing_disabled
			and record.enemy_commander == AICommanderPolicy.Profile.DEFAULT, "The actual comparison saves the selected settings")
		check(not battle.battle_controller.grid_manager.map_data.contextual_discovery_enabled
			and battle.battle_controller.action_service.guard_minimum_chance == 25, "Combat Lab selections reach live authority")
		battle.queue_free()
	await process_frame
