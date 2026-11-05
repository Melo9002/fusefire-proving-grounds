extends SceneTree

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const LoadingYard = preload("res://systems/generation/loading_yard_layout.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var ids := [Catalog.GENERATED_COVER, Catalog.REFINERY, Catalog.INDUSTRIAL_WAREHOUSE, Catalog.REFINERY_2, Catalog.LOADING_YARD, Catalog.REFINERY_FAMILY, Catalog.URBAN_FAMILY]
	check(ids.all(func(id): return Catalog.has(id)), "Every selectable battlefield has one catalog identity")
	check(Catalog.map_size(Catalog.REFINERY_2, Vector2i.ONE) == Vector2i(96, 80), "Fixed authored size comes from the catalog")
	check(Catalog.map_size(Catalog.GENERATED_COVER, Vector2i(24, 20)) == Vector2i(24, 20), "Generated cover retains supported requested size")
	for id in ids:
		var config := BattleConfiguration.new()
		config.generated_map = true
		config.select_battlefield(id)
		var legacy_flags := [config.refinery, config.industrial_warehouse, config.refinery_2, config.loading_yard]
		check(legacy_flags.count(true) <= 1, "Catalog selection cannot activate competing legacy flags: %s" % id)
		var restored := BattleConfiguration.new()
		restored.apply_replay(config.to_replay())
		check(restored.resolved_battlefield_id() == id, "Replay preserves battlefield identity: %s" % id)
	var old := BattleConfiguration.new()
	old.refinery_2 = true
	check(old.resolved_battlefield_id() == Catalog.REFINERY_2, "Historical boolean replay resolves through the catalog")
	var invalid := BattleConfiguration.new()
	invalid.generated_map = true
	invalid.battlefield_id = &"missing_map"
	check(not invalid.validate_generation_selection().is_empty(), "Unknown battlefield IDs reject explicitly")

	var menu = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var seen := {}
	for index in menu.map_size_option.item_count:
		var id := StringName(menu.map_size_option.get_item_metadata(index))
		check(Catalog.has(id), "Match Setup option resolves to a catalog entry: %s" % id)
		if index >= FlatMapGenerator.MAP_SIZES.size(): check(not seen.has(id), "Special battlefield appears only once: %s" % id)
		seen[id] = true
	check(seen.has(Catalog.URBAN_FAMILY), "Match Setup exposes the urban family preview")
	menu.map_size_option.select(menu.map_size_option.item_count - 1)
	menu._refresh_generation_controls()
	var selected: BattleConfiguration = menu._build_battle_configuration()
	check(selected.resolved_battlefield_id() == Catalog.REFINERY_FAMILY and selected.map_size == Vector2i(64, 64), "Match Setup exposes the authored-parcel refinery family")
	check(menu.population_toggle.visible and selected.content_manifest.population_enabled, "Refinery family exposes tactical population as an explicit enabled mode")
	menu.population_toggle.button_pressed = false
	var unpopulated: BattleConfiguration = menu._build_battle_configuration()
	check(not unpopulated.content_manifest.population_enabled, "Match Setup can request the same complete site without movable tactical population")
	menu.population_toggle.button_pressed = true
	menu.free()

	var started := Time.get_ticks_msec()
	selected.generated_map = true
	selected.player_count = 2
	selected.enemy_count = 2
	selected.ally_count = 0
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(selected)
	root.add_child(level)
	await process_frame
	await process_frame
	check(level.battle_initialization_succeeded, "Refinery family initializes through the shared battle path: %s" % [level.battle_initialization_errors])
	check(level.active_generated_map != null and level.active_generated_map.source_kind == "authored_refinery_family", "Tactical and presentation identity agree")
	check(level.get_node_or_null("GeneratedTerrain/RefinerySiteA") != null or level.get_node_or_null("GeneratedTerrain/RefinerySiteB") != null, "Authored plot renders through the catalog")
	check(StringName(level._replay_configuration.get("battlefield_id", "")) == Catalog.REFINERY_FAMILY, "Replay records the stable battlefield ID")
	check(not level._replay_configuration.get("content_manifest", {}).is_empty(), "Replay records exact accepted plot and parcel choices")
	var stale_manifest: Dictionary = level.active_generated_map.content_manifest.duplicate(true)
	stale_manifest.plot_revision = 999
	var stale_config := BattleConfiguration.new()
	stale_config.generated_map = true
	stale_config.select_battlefield(Catalog.REFINERY_FAMILY)
	stale_config.battle_seed = selected.battle_seed
	stale_config.content_manifest = stale_manifest
	var rejected_level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	rejected_level.configure_battle(stale_config)
	root.add_child(rejected_level)
	await process_frame
	await process_frame
	check(not rejected_level.battle_initialization_succeeded, "Stale exact content fails before a partial battle activates")
	check(rejected_level.get_node_or_null("GeneratedTerrain") == null, "Rejected content leaves no partial environment presentation")
	rejected_level.queue_free()
	print("Battlefield catalog: %d failure(s), Refinery family initialization %d ms" % [failures, Time.get_ticks_msec() - started])
	level.queue_free()
	await process_frame
	quit(1 if failures else 0)
