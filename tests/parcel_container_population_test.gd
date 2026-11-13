extends SceneTree

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Draft = preload("res://tools/parcel_editor/population_field_draft.gd")
const Export = preload("res://tools/parcel_editor/population_scene_export.gd")
const Layout = preload("res://systems/generation/refinery_family_layout.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const FIELD := Rect2i(7, 20, 3, 10)
const SOCKET := &"painted_container_7_20"
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_authoring()
	var on_seed := -1
	var off_seed := -1
	for map_seed in range(0, 32, 4):
		var manifest := RefineryPlotResolver.resolve(map_seed)
		check(manifest.errors.is_empty(), "Refinery seed %d resolves the painted apron" % map_seed)
		var loading := _loading(manifest)
		if loading.is_empty(): continue
		check(loading.parcel_id == Catalog.LOADING_YARD_PAINTED, "Refinery %d selects the registered painted apron" % map_seed)
		if _occupied(loading) and on_seed < 0: on_seed = map_seed
		if not _occupied(loading) and off_seed < 0: off_seed = map_seed
		if on_seed >= 0 and off_seed >= 0: break
	check(on_seed >= 0 and off_seed >= 0, "Two seeds on the same plot vary occupancy at the same container position")
	if on_seed >= 0 and off_seed >= 0:
		print("Painted container occupied seed %d, empty seed %d" % [on_seed, off_seed])
		await _check_battle(on_seed, true)
		await _check_battle(off_seed, false)
	print("Painted container population: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_authoring() -> void:
	var source = Catalog.get_definition(Catalog.LOADING_YARD_A)
	var parcel: Node3D = source.instantiate()
	var draft := Draft.new()
	draft.begin(source, parcel)
	parcel.free()
	check(draft.add("ground", "containers", FIELD), "Paint a strip in the source loading apron")
	var result := Export.build(source, draft, null)
	check(not result.has("error") and result.get("container_count") == 2, "Export resolves two calibrated candidates from paint: %s" % result.get("error", ""))
	if result.has("error"): return
	var path := "res://.godot/container_population_export_test.tscn"
	check(ResourceSaver.save(result.definition.scene, path) == OK, "Save container paint and guides as an ordinary parcel scene")
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(scene != null, "Reopen the exported scene")
	if scene == null: return
	var exported := AuthoredParcelDefinition.new(result.definition.parcel_id, "Container draft", Catalog.LOADING_SERVICE, 1, Vector2i(16, 32), scene)
	var root_node := exported.instantiate()
	check(exported.validate().is_empty() and not (root_node.get_node("Container_painted_container_7_20") as Node3D).visible, "Reopened rules preserve an empty authoring view")
	root_node.free()
	DirAccess.remove_absolute(path)
	var registered = Catalog.get_definition(Catalog.LOADING_YARD_PAINTED)
	check(_new_sockets(exported) == _new_sockets(registered), "Registered candidates match independently exported paint")
	draft.undo()
	draft.add("ground", "containers", Rect2i(4, 4, 3, 5))
	check(Export.build(source, draft, null).get("error", "").contains("No new positions fit"), "Paint inside the building cannot export a tactical container")

func _new_sockets(definition) -> Array:
	return definition.population_sockets().filter(func(socket): return String(socket.socket_id).begins_with("painted_container_"))

func _loading(manifest: Dictionary) -> Dictionary:
	for placement: Dictionary in manifest.placements:
		if placement.slot_id == &"loading": return placement
	return {}

func _occupied(placement: Dictionary) -> bool:
	return placement.population.any(func(choice): return choice.socket_id == SOCKET)

func _check_battle(map_seed: int, occupied: bool) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = map_seed
	config.select_battlefield(BattlefieldCatalog.REFINERY_FAMILY)
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Seed %d starts a playable refinery battle" % map_seed)
	if level.battle_initialization_succeeded:
		var data := level.active_generated_map
		var grid := level.battle_controller.grid_manager
		var loading := _loading(data.content_manifest)
		var center := ParcelTransform.cell(Vector3i(8, 0, 22), Vector2i(16, 32), loading.origin, loading.rotation)
		var cell := data.get_cell(center)
		var from := center + Vector3i.LEFT * 2
		var to := center + Vector3i.RIGHT * 2
		var origin := grid.grid_to_world(from) + Vector3.UP
		var destination := grid.grid_to_world(to) + Vector3.UP
		var cover := CombatRules.get_directional_cover(from, center + Vector3i.RIGHT * 2, grid)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		check(_occupied(loading) == occupied and cell.can_stop != occupied, "Seed %d changes actual stopping legality at the painted position" % map_seed)
		check((CombatRules.get_blocking_cell(origin, destination, grid) != null) == occupied, "Seed %d changes a real sightline through the painted position" % map_seed)
		check((cell.cover_type == MapCellData.CoverType.FULL) == occupied, "Seed %d stamps authored full cover only for a placed container" % map_seed)
		check((cover == MapCellData.CoverType.FULL) == occupied, "Seed %d changes the directional cover query beside the position" % map_seed)
		var path := graph.calculate_3d_path(from, to)
		check(not path.is_empty() and path.has(cell.world_position) != occupied, "Seed %d preserves a route with a detour around the container when present" % map_seed)
		check(graph.calculate_3d_path(from, center).is_empty() == occupied, "Seed %d permits moving to the painted cell only while empty" % map_seed)
		var recording := Recording.new()
		recording.configuration = {"battlefield_id": &"refinery_family", "content_manifest": data.content_manifest}
		var restored := Recording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary())))
		var replay := Layout.generate(999, 1.0, restored.configuration.content_manifest)
		check(replay.generation_errors.is_empty() and replay.content_manifest.placements == data.content_manifest.placements, "Seed %d stores exact container choices through replay reconstruction" % map_seed)
	level.queue_free()
	await process_frame
