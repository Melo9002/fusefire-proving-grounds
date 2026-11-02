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
	var ids := [Catalog.GENERATED_COVER, Catalog.REFINERY, Catalog.INDUSTRIAL_WAREHOUSE, Catalog.REFINERY_2, Catalog.LOADING_YARD]
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
	menu.map_size_option.select(menu.map_size_option.item_count - 1)
	var selected: BattleConfiguration = menu._build_battle_configuration()
	check(selected.resolved_battlefield_id() == Catalog.LOADING_YARD and selected.map_size == Vector2i(40, 48), "Match Setup selects Loading Yard without numeric branching")
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
	check(level.battle_initialization_succeeded, "Loading Yard initializes through the shared battle path: %s" % [level.battle_initialization_errors])
	check(level.active_generated_map != null and level.active_generated_map.source_kind == LoadingYard.SOURCE_KIND, "Tactical and presentation identity agree")
	check(level.get_node_or_null("GeneratedTerrain/LoadingYard/Warehouse") != null, "Imported authored parcel renders through the catalog")
	check(StringName(level._replay_configuration.get("battlefield_id", "")) == Catalog.LOADING_YARD, "Replay records the stable battlefield ID")
	print("Battlefield catalog: %d failure(s), Loading Yard initialization %d ms" % [failures, Time.get_ticks_msec() - started])
	level.queue_free()
	await process_frame
	quit(1 if failures else 0)
