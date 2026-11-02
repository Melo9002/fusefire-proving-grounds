extends SceneTree

const LoadingScreen = preload("res://ui/battle_loading_screen.gd")
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var screen := LoadingScreen.new()
	root.add_child(screen)
	await process_frame
	screen.set_stage("Constructing tactical battlefield…", 0.28)
	check(screen._stage.text == "Constructing tactical battlefield…", "Loading screen reports the real preparation stage")
	check(is_equal_approx(screen._progress.value, 0.28), "Loading screen reports bounded progress")
	screen.show_failure([{"code": "INVALID_MAP", "message": "No legal deployment region"}])
	check(screen._back_button.visible, "Initialization failure offers a return to setup")
	check("INVALID_MAP" in screen._detail.text and "No legal deployment region" in screen._detail.text, "Initialization failure remains actionable")
	screen.queue_free()
	await process_frame
	await _check_real_transition()
	print("Battle loading screen: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_real_transition() -> void:
	var menu := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(menu)
	current_scene = menu
	menu.generated_map_toggle.button_pressed = true
	for index in menu.map_size_option.item_count:
		if StringName(menu.map_size_option.get_item_metadata(index)) == Catalog.LOADING_YARD:
			menu.map_size_option.select(index)
			break
	menu._start_battle()
	check(menu.get_node_or_null("BattleLoadingScreen") != null, "Starting a battle displays the loading screen before construction")
	var deadline := Time.get_ticks_msec() + 5000
	while current_scene == menu and Time.get_ticks_msec() < deadline:
		await process_frame
	check(current_scene is BattleLevel, "Successful initialization transitions from loading screen to battle")
	if current_scene is BattleLevel:
		var battle := current_scene as BattleLevel
		check(battle.battle_initialization_succeeded, "Loading transition only activates a validated battle")
		check(battle.active_generated_map != null and battle.active_generated_map.source_kind == "authored_loading_yard", "Loading transition preserves the selected battlefield")
		battle.queue_free()
		await process_frame
