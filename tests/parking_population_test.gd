extends SceneTree

const Layout = preload("res://systems/generation/urban_family_layout.gd")
const Parcels = preload("res://systems/generation/authored_parcel_catalog.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var headings := {}
	var arrangements := {}
	var example := {}
	for map_seed in range(0, 32, 2):
		var resolved := Layout.resolve(map_seed)
		var office: Dictionary = resolved.placements[-1]
		check(office.parcel_id == Parcels.INDUSTRIAL_OFFICE_PAINTED_PARKING, "Fresh service streets choose the validated painted parking variant")
		var added: Array = office.population.filter(func(choice): return String(choice.socket_id).begins_with("row_bay_"))
		var signature := str(added.map(func(choice): return choice.socket_id))
		if not added.is_empty() and not arrangements.has(signature):
			arrangements[signature] = map_seed
		for choice: Dictionary in office.population:
			headings[choice.yaw_turns] = true
			check(choice.yaw_turns in [0, 2], "Parking remains aligned forward or reverse")
			if example.is_empty(): example = resolved
		check(resolved == Layout.resolve(map_seed), "Heading choices repeat for identical inputs")
	check(headings.has(0) and headings.has(2), "Fixed seed matrix exercises forward and reverse parking")
	check(arrangements.size() > 1, "Different map seeds choose different occupied bays within the same painted parking area")
	for map_seed: int in arrangements.values().slice(0, 2):
		await _check_playable_parking(map_seed)
	var recording := Recording.new()
	recording.configuration = {"battlefield_id": &"urban_family", "content_manifest": example}
	var json: Variant = JSON.parse_string(JSON.stringify(recording.to_dictionary()))
	var restored := Recording.from_dictionary(json)
	var replay := Layout.generate(999, 1.0, restored.configuration.content_manifest)
	check(replay.generation_errors.is_empty() and replay.content_manifest.placements == example.placements, "Actual replay JSON preserves accepted parking headings with a different supplied seed")
	var parcel = Parcels.get_definition(Parcels.INDUSTRIAL_OFFICE_PARKING_A)
	var original: Dictionary = example.duplicate(true)
	original.placements[-1].parcel_id = parcel.parcel_id
	original.placements[-1].population = original.placements[-1].population.filter(func(choice): return not String(choice.socket_id).begins_with("row_bay_"))
	check(Layout.generate(999, 1.0, original).generation_errors.is_empty(), "An exact manifest can still reconstruct the original office parcel")
	for turn in 4:
		var forward: Node3D = parcel.instantiate()
		var reverse: Node3D = parcel.instantiate()
		var choice := {"socket_id": &"parking_west", "yaw_turns": 0}
		parcel.apply_population(forward, [choice])
		choice.yaw_turns = 2
		parcel.apply_population(reverse, [choice])
		forward.transform = ParcelTransform.scene_transform(parcel.size, Vector3i.ZERO, turn, Vector2i(32, 32))
		reverse.transform = forward.transform
		root.add_child(forward)
		root.add_child(reverse)
		var a: Node3D = forward.get_node("SedanWest")
		var b: Node3D = reverse.get_node("SedanWest")
		check(a.global_position.is_equal_approx(b.global_position), "rotation %d keeps reversing cars in the same bay" % turn)
		check(a.global_basis.z.dot(b.global_basis.z) < -0.999, "rotation %d physically reverses the real imported car" % turn)
		var basis := b.basis
		parcel.apply_population(reverse, [choice])
		check(b.basis.is_equal_approx(basis), "Applying recorded choices twice does not rotate twice")
		forward.free()
		reverse.free()
	for invalid in [1, 3, -2, 0.5, "reverse"]:
		var broken: Dictionary = example.duplicate(true)
		broken.placements[-1].population[0].yaw_turns = invalid
		check(not Layout.generate(0, 1.0, broken).generation_errors.is_empty(), "Unsupported parking heading %s rejects" % str(invalid))
	var legacy: Dictionary = example.duplicate(true)
	for choice: Dictionary in legacy.placements[-1].population:
		choice.erase("yaw_turns")
	check(Layout.generate(0, 1.0, legacy).generation_errors.is_empty(), "Historical choices without heading retain authored forward placement")
	print("Parking population: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_playable_parking(map_seed: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = map_seed
	config.select_battlefield(BattlefieldCatalog.URBAN_FAMILY)
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Urban seed %d starts a playable battle" % map_seed)
	if level.battle_initialization_succeeded:
		var data := level.active_generated_map
		var office: Dictionary = data.content_manifest.placements[-1]
		var definition = Parcels.get_definition(office.parcel_id)
		var car_cells := {}
		for socket: Dictionary in definition.population_sockets():
			var position: Vector3 = socket.local_position
			car_cells[socket.socket_id] = office.origin + Vector3i(position)
		for choice: Dictionary in office.population:
			if String(choice.socket_id).begins_with("row_bay_"):
				var cell := data.get_cell(car_cells[choice.socket_id])
				check(not cell.can_stop and cell.blocks_line_of_sight and cell.cover_type == MapCellData.CoverType.FULL, "Resolved car stamps authoritative occupancy, LOS and cover")
		check(data.get_cell(Vector3i(30, 0, 43)).can_stop, "The painted row's aisle remains walkable in battle")
	level.queue_free()
	await process_frame
