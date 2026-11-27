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
	var mission_tab := setup._setup_tabs.get_tab_control(0)
	check(mission_tab.find_child("EngagementSetup", true, false) == null,
		"The Mission tab has no duplicate combat controls")
	check(setup.deployment_summary.text.contains("Engagement: Head/core + symmetrical")
		and setup.deployment_summary.text.contains("Contextual firing: On") and setup.deployment_summary.text.contains("Guard: First legal"),
		"The shared briefing shows Combined, side steps on, and first-legal Guard")
	setup.start_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while not current_scene is BattleLevel and Time.get_ticks_msec() < deadline:
		await process_frame
	var battle := current_scene as BattleLevel
	check(battle != null, "The battle starts")
	if battle:
		for i in 10: await process_frame
		check(battle.battle_controller.grid_manager.map_data.engagement_policy == CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC
			and battle.battle_controller.action_service.guard_minimum_chance == 0,
			"Start Battle applies Combined and first-legal Guard by default")
		check(battle.battle_controller.grid_manager.map_data.contextual_discovery_enabled
			and battle._replay_recorder.recording.configuration.battlefield_id == BattlefieldCatalog.CONTEXTUAL_DEPOT
			and battle._replay_recorder.recording.configuration.engagement_policy == CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC,
			"Regular Depot records the certified contextual variant and Combined rule")
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
	await _check_combat_setup()
	print("Match setup Bulwark: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _check_combat_setup() -> void:
	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	var combat := setup.combat_setup
	setup._setup_tabs.current_tab = setup._setup_tabs.get_tab_idx_from_control(combat)
	check(setup.start_button.text == "START BATTLE", "The Combat tab uses the shared Start Battle button")
	(combat.find_child("CrossfirePreset", true, false) as Button).pressed.emit()
	var crossfire := setup._build_battle_configuration()
	check(crossfire.battlefield_id == BattlefieldCatalog.CONTEXTUAL_SHOWCASE and crossfire.battle_seed == 16
		and crossfire.player_count == 2 and crossfire.enemy_count == 2
		and crossfire.enemy_commander == AICommanderPolicy.Profile.CAUTIOUS
		and crossfire.engagement_policy == CombatRules.EngagementPolicy.SYMMETRIC
		and crossfire.guard_minimum_chance == 15 and not crossfire.contextual_firing_disabled,
		"Crossfire fills in the existing setup controls")
	combat._contextual.button_pressed = false
	var crossfire_off := setup._build_battle_configuration()
	check(crossfire_off.battlefield_id == BattlefieldCatalog.CONTEXTUAL_SHOWCASE and crossfire_off.contextual_firing_disabled,
		"Turning off contextual fire keeps the Crossfire deployment")

	(combat.find_child("PressurePreset", true, false) as Button).pressed.emit()
	check(setup._selected_battlefield_id() == BattlefieldCatalog.FREIGHT_YARD
		and setup._build_battle_configuration().battlefield_id == BattlefieldCatalog.CONTEXTUAL_FREIGHT,
		"Pressure fills in Freight Yard and enables its contextual variant")
	for button in combat._engagement.get_buttons():
		button.button_pressed = true
		check(setup._build_battle_configuration().engagement_policy == button.get_meta("value"),
			"Each engagement choice goes through the shared configuration")
	for button in combat._engagement.get_buttons():
		if button.get_meta("value") == CombatRules.EngagementPolicy.HEAD_CORE: button.button_pressed = true
	for button in combat._guard.get_buttons():
		if button.get_meta("value") == 25: button.button_pressed = true
	setup.player_count.value = 1
	setup.enemy_commander_option.select(AICommanderPolicy.Profile.DEFAULT)
	combat.changed.emit()
	setup._setup_tabs.current_tab = 0
	check(setup.deployment_summary.text.contains("Engagement: Head/core") and setup.deployment_summary.text.contains("Guard: 25% minimum"),
		"The shared briefing follows edits across tabs")
	setup.start_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while not current_scene is BattleLevel and Time.get_ticks_msec() < deadline:
		await process_frame
	var battle := current_scene as BattleLevel
	check(battle != null, "Start Battle launches the edited preset from the Mission tab")
	if battle:
		var record: Dictionary = battle._replay_recorder.recording.configuration
		check(record.battlefield_id == BattlefieldCatalog.CONTEXTUAL_FREIGHT and record.seed == 16 and record.guard_minimum_chance == 25
			and record.engagement_policy == CombatRules.EngagementPolicy.HEAD_CORE and record.player_count == 1
			and record.enemy_commander == AICommanderPolicy.Profile.DEFAULT, "The battle recording preserves edits from every tab")
		check(battle.battle_controller.grid_manager.map_data.contextual_discovery_enabled
			and battle.battle_controller.action_service.guard_minimum_chance == 25, "The edited setup reaches live combat authority")
		battle.queue_free()
	await process_frame
