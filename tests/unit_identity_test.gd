extends SceneTree
## Issue #16: two soldiers are immediately distinguishable on cards, above the selected unit and in
## messages, while the stable IDs that actions and replays use do not change.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _world_bar_for(level: BattleLevel, unit: TacticalUnit) -> UnitWorldBar:
	for child in level.get_node("Visualizers/BattleUI").get_children():
		if child is UnitWorldBar and child._target_unit == unit:
			return child as UnitWorldBar
	return null

func _run() -> void:
	_callsign_table()
	await _battle_identities()
	await _roles_on_cards()
	print("Unit identity: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _callsign_table() -> void:
	var seen := {}
	for slot in UnitCallsign.PLAYER.size():
		var name := UnitCallsign.for_slot(TacticalUnit.Faction.PLAYER, slot)
		check(not seen.has(name), "Player callsigns are distinct (%s)" % name)
		seen[name] = true
		check(name.length() <= 7, "A player callsign fits a narrow card (%s)" % name)
	for slot in UnitCallsign.ALLY.size():
		var name := UnitCallsign.for_slot(TacticalUnit.Faction.ALLY, slot)
		check(not seen.has(name), "Ally callsigns do not repeat a player callsign (%s)" % name)
		seen[name] = true
	check(UnitCallsign.for_slot(TacticalUnit.Faction.PLAYER, 5) == "Soldier 6", "Slots beyond the table still get a distinct name")
	check(UnitCallsign.for_slot(TacticalUnit.Faction.ENEMY, 1) == "Hostile 2", "Hostiles are numbered")
	check(UnitCallsign.for_slot(TacticalUnit.Faction.NEUTRAL, 0).is_empty(), "A neutral unit has no callsign")

func _battle_identities() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(3, 2, false, 1, 1)
	root.add_child(level)
	await create_timer(0.3).timeout
	var turns := level.turn_manager
	check(turns.player_units.size() == 3 and turns.allied_units.size() == 1 and turns.enemy_units.size() == 2, "Setup: three players, one ally, two hostiles")

	# Stable identities are exactly what they were.
	for index in turns.player_units.size():
		var unit: TacticalUnit = turns.player_units[index]
		check(String(unit.name) == "PlayerUnit%d" % (index + 1) and String(unit.tactical_id) == "PlayerUnit%d" % (index + 1), "Stable ID is unchanged (%s / %s)" % [unit.name, unit.tactical_id])
	check(String(turns.enemy_units[0].tactical_id) == "EnemyUnit1" and String(turns.allied_units[0].tactical_id) == "AllyUnit1", "Hostile and ally IDs are unchanged")

	# Distinct readable names.
	var names: Array[String] = []
	for unit in turns.player_units:
		names.append(unit.get_display_name())
	check(names == ["Alpha", "Bravo", "Charlie"], "Soldiers are Alpha, Bravo and Charlie (%s)" % str(names))
	check(turns.allied_units[0].get_display_name() == "Foxtrot", "The ally has its own callsign")
	check(turns.enemy_units[0].get_display_name() == "Hostile 1" and turns.enemy_units[1].get_display_name() == "Hostile 2", "Hostiles are numbered")
	check(turns.player_units[0].get_log_name() == "Alpha (PlayerUnit1)", "Logs carry the callsign and the stable ID (%s)" % turns.player_units[0].get_log_name())
	var anonymous := load("res://units/tactical_unit.tscn").instantiate() as TacticalUnit
	anonymous.name = "SomeUnit"
	check(anonymous.get_display_name() == "SomeUnit" and anonymous.get_log_name() == "SomeUnit", "A unit without a display name falls back to its node name")
	anonymous.free()

	# Cards.
	var bar := level.get_node("Visualizers/BattleUI/UnitPortraitBar") as UnitPortraitBar
	check(bar.portraits.size() == 3, "One card per soldier")
	var headings: Array[String] = []
	for portrait in bar.portraits:
		headings.append(portrait.title_label.text)
	check(headings == ["ALPHA", "BRAVO", "CHARLIE"], "Cards are headed by distinct callsigns (%s)" % str(headings))
	check(not "BEAN" in "".join(headings), "The shared heading is gone")
	for portrait in bar.portraits:
		check(portrait.name_label.text == "Generic", "The role sits under the callsign (%s)" % portrait.name_label.text)
		var font := portrait.title_label.get_theme_font("font")
		var size := portrait.title_label.get_theme_font_size("font_size")
		var width := font.get_string_size(portrait.title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		check(width <= portrait.custom_minimum_size.x - 16.0, "The heading fits the card (%s: %.0f of %.0f px)" % [portrait.title_label.text, width, portrait.custom_minimum_size.x - 16.0])
	var widest := "CHARLIE"
	var probe := bar.portraits[0]
	var probe_width := probe.title_label.get_theme_font("font").get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1, probe.title_label.get_theme_font_size("font_size")).x
	check(probe_width <= probe.custom_minimum_size.x - 16.0, "The longest callsign fits a card (%.0f of %.0f px)" % [probe_width, probe.custom_minimum_size.x - 16.0])

	# Exhausted and dead cards keep their identity readable.
	turns.player_units[1].stats.consume_ap(turns.player_units[1].stats.current_ap)
	await process_frame
	check(bar.portraits[1].display_state == UnitPortrait.DisplayState.EXHAUSTED and bar.portraits[1].title_label.text == "BRAVO", "An exhausted card still names its soldier")
	turns.player_units[2].stats.take_damage(1000)
	await create_timer(0.3).timeout
	check(bar.portraits[2].display_state == UnitPortrait.DisplayState.DEAD and bar.portraits[2].title_label.text == "CHARLIE", "A dead card still names its soldier")

	# Above the selected unit.
	var world_bar := _world_bar_for(level, turns.player_units[0])
	check(world_bar != null and world_bar.name_label != null, "A unit has a world-space bar with a name")
	if world_bar != null and world_bar.name_label != null:
		check(world_bar.name_label.visible and world_bar.name_label.text == "Alpha", "The bar above a unit names it (%s)" % world_bar.name_label.text)
	var enemy_bar := _world_bar_for(level, turns.enemy_units[0])
	check(enemy_bar != null and enemy_bar.name_label != null and enemy_bar.name_label.text == "Hostile 1", "A hostile's bar names it too")
	level.queue_free()
	await process_frame
	await process_frame

## Roles come from the archetype's own display name.
func _roles_on_cards() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	config.player_count = 2
	config.enemy_count = 1
	config.player_archetypes = [&"shieldbearer", &"marksman"]
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	await process_frame
	var bar := level.get_node("Visualizers/BattleUI/UnitPortraitBar") as UnitPortraitBar
	check(bar.portraits.size() == 2 and bar.portraits[0].name_label.text == "Shieldbearer" and bar.portraits[1].name_label.text == "Marksman", "Cards show each soldier's role (%s)" % str(bar.portraits.map(func(p): return p.name_label.text)))
	check(bar.portraits[0].title_label.text == "ALPHA" and bar.portraits[1].title_label.text == "BRAVO", "Roles do not replace the callsign")
	level.queue_free()
	await process_frame
	await process_frame
