extends SceneTree
## Current supported workflow, replacing the retired multi-map menu contract.
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const Layout = preload("res://systems/generation2/generator.gd")
const Resolver = preload("res://systems/generation2/authored_plot_resolver.gd")
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_generation_boundary()
	var unknown := Layout.generate("missing_source", 17, 1.0, {})
	check(not unknown.generation_errors.is_empty() and unknown.cells.is_empty(), "Standalone entry rejects unsupported source instead of using Depot")
	check(Catalog.PLAYABLE == [Catalog.SERVICE_DEPOT, Catalog.FREIGHT_YARD, Catalog.FLEET_STATION], "Three curated sites share one current generation path")
	check(Catalog.map_size(Catalog.SERVICE_DEPOT, Vector2i.ONE) == Vector2i(40, 40), "Authored plot owns map dimensions")
	for retired in [Catalog.REFINERY_2, Catalog.LOADING_YARD, Catalog.REFINERY_FAMILY, Catalog.URBAN_FAMILY, &"missing_map"]:
		var config := BattleConfiguration.new()
		config.generated_map = true
		config.select_battlefield(retired)
		check(not Catalog.has(retired) and not config.validate_generation_selection().is_empty(), "Retired/unknown selection rejects: %s" % retired)
		var rejected := Catalog.generate(retired, Vector2i.ZERO, 17, 1.0)
		check(not rejected.generation_errors.is_empty() and rejected.cells.is_empty(), "Rejected identity never silently builds a replacement: %s" % retired)
	var menu = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.map_size_option.item_count == 5 and menu._selected_battlefield_id() == Catalog.SERVICE_DEPOT, "Setup offers the three curated sites, test range and Crossfire deployment, with Service Depot selected")
	var selected: BattleConfiguration = menu._build_battle_configuration()
	check(selected.content_manifest.population_enabled and menu.population_toggle.visible, "Population is explicit and enabled by default")
	menu.population_toggle.button_pressed = false
	check(not menu._build_battle_configuration().content_manifest.population_enabled, "Same pipeline supports population-off")
	var range_index := -1
	var range_count := 0
	for index in menu.map_size_option.item_count:
		if menu.map_size_option.get_item_metadata(index) == Catalog.TACTICAL_TEST_RANGE:
			range_index = index
			range_count += 1
	check(range_count == 1 and range_index >= 0, "The existing range appears exactly once in Match Setup")
	if range_index >= 0:
		menu.map_size_option.select(range_index)
		menu.map_size_option.item_selected.emit(range_index)
		var range_config: BattleConfiguration = menu._build_battle_configuration()
		check(range_config.battlefield_id == Catalog.TACTICAL_TEST_RANGE and range_config.map_size == Vector2i(32, 32), "Selecting the range builds its existing identity and dimensions")
		check(menu.map_size_option.get_item_text(range_index).contains("Test map") and not range_config.content_manifest.population_enabled, "The range is labeled as a test map and starts with its authored examples unobscured")
		check(range_config.battlefield_id in Catalog.SELECTABLE, "The same selection list also permits range replay opening")
		var range_level := BattleScene.instantiate() as BattleLevel
		range_level.configure_battle(range_config)
		root.add_child(range_level)
		check(range_level.battle_initialization_succeeded and range_level.active_generated_map.source_kind == Layout.RANGE_SOURCE, "The menu configuration starts the original range through current Generation 2")
		check(range_level._replay_configuration.battlefield_id == Catalog.TACTICAL_TEST_RANGE, "Range recordings retain the same identity, not a duplicated map")
		range_level.queue_free()
		await process_frame
	menu.free()
	var plots := {}
	var variants := {}
	for map_seed in range(8):
		var resolved := Resolver.resolve(Layout.DepotPlots, map_seed)
		check(Resolver.is_valid(resolved), "Seed %d resolves: %s" % [map_seed, resolved.errors])
		check(resolved == Resolver.resolve(Layout.DepotPlots, map_seed), "Seed %d is deterministic" % map_seed)
		check(resolved.placements.size() == 3, "Every required slot has a parcel")
		plots[resolved.plot_id] = true
		variants[resolved.placements[0].parcel_id] = true
		check(Resolver.resolve(Layout.DepotPlots, 999, true, resolved) == resolved, "Recorded choices own provenance and placements")
		var plot := Layout.DepotPlots.get_definition(resolved.plot_id)
		check(ParcelSlotContract.validate_plot_footprints(plot).is_empty(), "Slots respect plot bounds, ownership and roads")
	check(plots.size() == 2 and variants.size() == 2, "Matrix exercises both authored plots and loading variants")
	var empty := Resolver.resolve(Layout.DepotPlots, 17, false)
	check(Resolver.is_valid(empty) and empty.placements.size() == 3 and empty.placements.all(func(p): return p.population.is_empty()), "Population-off preserves all required structures")
	var exact := Resolver.resolve(Layout.DepotPlots, 16)
	for mutation in ["plot", "parcel", "socket"]:
		var broken := exact.duplicate(true)
		match mutation:
			"plot": broken.plot_revision = 999
			"parcel": broken.placements[0].parcel_id = &"missing_parcel"
			"socket": broken.placements[0].population[0].socket_id = &"unknown_socket"
		check(not Resolver.is_valid(Resolver.resolve(Layout.DepotPlots, 16, true, broken)), "Invalid %s dependency rejects without substitution" % mutation)
	selected.generated_map = true
	selected.battle_seed = 17
	selected.player_count = 2
	selected.enemy_count = 2
	selected.ally_count = 0
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(selected)
	root.add_child(level)
	await process_frame
	await process_frame
	check(not ResourceLoader.has_cached("res://tests/fixtures/legacy_generation/flat_map_generator.gd") and not ResourceLoader.has_cached("res://tests/fixtures/legacy_generation/generated_terrain_presenter.gd"), "Current real battle loads neither legacy generator nor procedural renderer")
	check(level.battle_initialization_succeeded, "Actual Service Depot battle initializes: %s" % [level.battle_initialization_errors])
	check(level.active_generated_map != null and level.active_generated_map.source_kind == Layout.DEPOT_SOURCE, "Tactical and visual identity agree")
	check(level.get_node_or_null("GeneratedTerrain/DepotServiceSpine") != null, "Accepted authored plot renders through the real presentation path")
	check(StringName(level._replay_configuration.get("battlefield_id", "")) == Catalog.CONTEXTUAL_DEPOT
		and level.active_generated_map.contextual_discovery_enabled,
		"Replay records the exact contextual Depot variant selected by the setup defaults")
	check(not level._replay_configuration.get("content_manifest", {}).is_empty(), "Replay records exact accepted placements")
	var stale_config := BattleConfiguration.new()
	stale_config.generated_map = true
	stale_config.select_battlefield(Catalog.SERVICE_DEPOT)
	stale_config.content_manifest = level.active_generated_map.content_manifest.duplicate(true)
	stale_config.content_manifest.plot_revision = 999
	var rejected_level := BattleScene.instantiate() as BattleLevel
	rejected_level.configure_battle(stale_config)
	root.add_child(rejected_level)
	await process_frame
	await process_frame
	check(not rejected_level.battle_initialization_succeeded and rejected_level.get_node_or_null("GeneratedTerrain") == null, "Stale dependency cannot activate a partial battle or presentation")
	rejected_level.queue_free()
	level.queue_free()
	await process_frame
	print("Current generation: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_generation_boundary() -> void:
	for filename in DirAccess.get_files_at("res://systems/generation2"):
		if not filename.ends_with(".gd"): continue
		var path := "res://systems/generation2/" + filename
		var source := FileAccess.get_file_as_string(path)
		check(not source.contains("FlatMapGenerator") and not source.contains("GeneratedTerrainPresenter") and not source.contains("res://systems/generation/") and not source.contains("res://tests/"), "Generation2 has no legacy implementation dependency: %s" % filename)
