extends SceneTree

var failures := 0
var progress_events := 0
var completion_events := 0
var failure_events := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var eliminate := _objective(&"eliminate", MissionObjectiveDefinition.Kind.ELIMINATE, true, 2)
	var rescue := _objective(&"rescue", MissionObjectiveDefinition.Kind.RESCUE, false, 1)
	rescue.target_ids = [&"civilian_1"]
	var definition := MissionDefinition.new()
	definition.mission_id = &"foundation_test"
	definition.title = "Foundation Test"
	definition.objectives = [eliminate, rescue]

	var manager := ObjectiveManager.new()
	root.add_child(manager)
	manager.objective_progress_changed.connect(func(_state): progress_events += 1)
	manager.objective_completed.connect(func(_state): completion_events += 1)
	manager.objective_failed.connect(func(_state): failure_events += 1)

	check(manager.load_mission(definition), "Valid mission data loads")
	check(manager.get_objectives().size() == 2, "Every definition receives runtime state")
	check(manager.get_objective(&"rescue").definition.target_ids == [&"civilian_1"], "Objective target IDs remain data driven")
	check(manager.add_progress(&"eliminate"), "Active objective accepts progress")
	check(manager.get_objective(&"eliminate").progress == 1, "Progress is stored independently from its definition")
	check(not manager.are_required_objectives_complete(), "Partial required progress does not complete the mission set")
	check(manager.add_progress(&"eliminate", 10), "Progress clamps at its target")
	check(manager.get_objective(&"eliminate").is_completed(), "Reaching the target completes an objective")
	check(manager.get_objective(&"eliminate").progress == 2, "Completed progress does not exceed its target")
	check(manager.are_required_objectives_complete(), "Optional objectives do not block required completion")
	check(not manager.add_progress(&"eliminate"), "Completed objectives cannot change")
	check(manager.fail_objective(&"rescue"), "Active objectives can fail")
	check(manager.get_objective(&"rescue").is_failed(), "Failure is retained in runtime state")
	check(not manager.has_required_objective_failed(), "Optional failure does not fail the required set")
	check(progress_events == 2 and completion_events == 1 and failure_events == 1, "Objective changes publish one clear event each")

	var invalid := MissionDefinition.new()
	invalid.mission_id = &"duplicate_test"
	invalid.objectives = [eliminate, eliminate]
	check(not manager.load_mission(invalid), "Duplicate objective IDs are rejected")
	check(manager.mission == definition, "Rejected mission data preserves the active mission")

	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	var objective_option := setup.objective_option
	var setup_panel := setup.get_node("CenterContainer/Panel") as PanelContainer
	var setup_tabs := setup.get_node("CenterContainer/Panel/Margin/VBox/Body/SetupTabs") as TabContainer
	check(setup_panel.global_position.y >= 0.0 and setup_panel.global_position.y + setup_panel.size.y <= setup.size.y, "Match setup fits inside the 720p reference viewport")
	check(setup_tabs.get_tab_count() == 4, "Match setup groups choices into four focused tabs")
	check(setup_tabs.get_tab_title(0) == "Mission" and setup_tabs.get_tab_title(1) == "Forces" and setup_tabs.get_tab_title(2) == "Battlefield" and setup_tabs.get_tab_title(3) == "Settings", "Match setup tabs use clear responsibility names")
	check(setup.start_button.text == "START BATTLE", "The primary action remains concise while the briefing carries configuration details")
	check(setup.randomize_seed_button != null and setup.copy_seed_button != null, "Battlefield seed actions are easy to discover")
	check(setup.auto_seed_toggle.button_pressed and setup.seed_input.value >= 1, "A fresh setup prepares a valid automatic seed")
	setup.generated_map_toggle.button_pressed = true
	setup.auto_seed_toggle.button_pressed = false
	setup.seed_input.value = 4242
	check(setup.seed_input.editable and int(setup.seed_input.value) == 4242, "Manual seed mode accepts a reproducible seed")
	setup.auto_seed_toggle.button_pressed = true
	check(not setup.seed_input.editable and setup.seed_input.value >= 1, "Automatic seed mode locks the generated value")
	check(objective_option.item_count == MissionCatalog.PRESETS.size(), "Match setup offers every objective preset")
	check(objective_option.get_item_text(MissionObjectiveDefinition.Kind.EXTRACT) == "Extract", "Objective choices retain their readable names")
	setup._on_objective_selected(MissionObjectiveDefinition.Kind.PROTECT)
	check(setup.vip_toggle.button_pressed and setup.vip_toggle.disabled, "Protect requires and locks its friendly VIP")
	setup._on_objective_selected(MissionObjectiveDefinition.Kind.ELIMINATE)
	check(not setup.vip_toggle.button_pressed and not setup.vip_toggle.disabled, "Leaving Protect restores the optional VIP to its off default")
	setup.vip_toggle.button_pressed = true
	setup.vip_behavior.select(MissionActor.VIPBehavior.PLAYER_CONTROLLED)
	setup._update_summary(0.0)
	check(setup.deployment_summary.text.contains("Player-controlled: 3\nAI allies: 0\nEnemies: 2"), "Setup summary counts a player-controlled VIP separately from combatants")
	setup.vip_behavior.select(MissionActor.VIPBehavior.FOLLOW_ESCORT)
	setup._update_summary(0.0)
	check(setup.deployment_summary.text.contains("Player-controlled: 2\nAI allies: 1\nEnemies: 2"), "Setup summary follows the selected VIP controller")
	setup.difficulty_option.select(AIDifficultyPolicy.Tier.HARD)
	setup.difficulty_option.item_selected.emit(AIDifficultyPolicy.Tier.HARD)
	check(setup.deployment_summary.text.contains("AI DIFFICULTY\nHard"), "Setup briefing follows the selected AI difficulty")
	setup.queue_free()
	await process_frame

	var scene := load("res://levels/prototype_map/prototype_map.tscn") as PackedScene
	var selected_mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.SURVIVE, 4)
	var level := scene.instantiate() as BattleLevel
	level.configure(2, 4, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, selected_mission)
	root.add_child(level)
	var scene_manager := level.get_node("Systems/ObjectiveManager") as ObjectiveManager
	check(scene_manager != null, "The battle scene exposes an ObjectiveManager")
	check(scene_manager.mission == selected_mission, "Battle setup loads its selected mission")
	check(scene_manager.get_objective(&"survive").definition.target_amount == 3, "Preset data reaches runtime objective state")
	level.queue_free()
	await process_frame
	await process_frame
	manager.free()
	print("Objective foundation: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _objective(id: StringName, kind: MissionObjectiveDefinition.Kind, required: bool, target: int) -> MissionObjectiveDefinition:
	var result := MissionObjectiveDefinition.new()
	result.objective_id = id
	result.kind = kind
	result.title = String(id).capitalize()
	result.required = required
	result.target_amount = target
	return result
