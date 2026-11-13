extends SceneTree

# Intentional retirement contract: never reinterpret retired replay presets.
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var menu = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.seed_input.value = 24680
	var selected: BattleConfiguration = menu._build_battle_configuration()
	check(selected.resolved_battlefield_id() == Catalog.SERVICE_DEPOT and selected.map_size == Vector2i(40, 40) and selected.battle_seed == 24680, "Match setup defaults to the compact depot and preserves the explicit seed")
	check(selected.battlefield_preset == BattleConfiguration.BattlefieldPreset.LEGACY, "Match setup preserves the supported replay envelope")
	menu.free()
	var config := BattleConfiguration.new()
	config.generated_map = true
	check(config.validate_generation_selection().is_empty(), "The internal Generator 1 fixture remains available to regression scripts")
	for preset in [1, 2, 99]:
		config.battlefield_preset = preset as BattleConfiguration.BattlefieldPreset
		check(not config.validate_generation_selection().is_empty(), "Retired/unknown preset rejects explicitly")
		var recording := BattleReplayRecording.new()
		recording.configuration = config.to_replay()
		check(recording.validation_message().contains("quarantined"), "Retired replay reports quarantine instead of falling back")
	var document_recording := BattleReplayRecording.new()
	document_recording.configuration = {"battlefield_preset": 0}
	document_recording.battlefield_document = {"schema_version": 1}
	check(document_recording.validation_message().contains("quarantined"), "Document-bearing replay cannot disguise itself as Generator 1")
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	check(level.battle_initialization_attempted and not level.battle_initialization_succeeded, "Unsupported configuration fails initialization")
	check(level.active_generated_map == null, "Failure does not construct a replacement map")
	check(level.turn_manager.player_units.is_empty() and level.turn_manager.enemy_units.is_empty(), "Failure leaves no partial team activation")
	level.free()
	for refinery in [false, true]:
		var first := FlatMapGenerator.generate_with_cover(40, 30, 1.0, 24680, 5, refinery)
		var second := FlatMapGenerator.generate_with_cover(40, 30, 1.0, 24680, 5, refinery)
		check(signature(first) == signature(second), "Repeated Generator 1/Refinery seed preserves cells, spawns and traversal")
	print("Generation retirement: %d failure(s)" % failures)
	quit(1 if failures else 0)

func signature(data: MapData) -> String:
	var parts: Array[String] = []
	for at in data.cells:
		var cell: MapCellData = data.cells[at]
		parts.append(str([at, cell.world_position, cell.walkable, cell.can_stop, cell.cover_type, cell.cover_height, cell.blocks_line_of_sight]))
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY, TacticalUnit.Faction.ENEMY]:
		parts.append(str(data.get_spawn_cells(faction)))
	for link in data.traversal_links:
		parts.append(str([link.from_cell, link.to_cell, link.bidirectional]))
	return "|".join(parts).sha256_text()
