extends SceneTree

const ParcelContract = preload("res://systems/generation/environment_parcel_spatial_contract.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

var failures := 0

func _init() -> void:
	_test_frontage_intervals()
	_test_generated_ownership_and_relationships()
	_test_invalid_contracts()
	print("Parcel spatial contracts: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func _test_frontage_intervals() -> void:
	var bounds := Rect2i(10, 20, 6, 4)
	var roads: Dictionary = {}
	for x in range(10, 16): roads[Vector2i(x, 19)] = "road_north"
	var spans := ParcelContract.frontage_spans(bounds, roads, "full")
	check(spans.size() == 1 and spans[0].start == [10, 20] and spans[0].end == [16, 20] and spans[0].width_cells == 6, "a full adjacent boundary produces one exact half-open frontage")

	roads.clear()
	for x in range(12, 14): roads[Vector2i(x, 19)] = "road_partial"
	spans = ParcelContract.frontage_spans(bounds, roads, "partial")
	check(spans.size() == 1 and spans[0].start == [12, 20] and spans[0].end == [14, 20] and spans[0].width_cells == 2, "one touching road interval does not promote the whole boundary to frontage")

	roads.clear()
	for x in [10, 11, 14, 15]: roads[Vector2i(x, 19)] = "road_%d" % x
	spans = ParcelContract.frontage_spans(bounds, roads, "split")
	check(spans.size() == 2 and spans[0].start == [10, 20] and spans[0].end == [12, 20] and spans[1].start == [14, 20] and spans[1].end == [16, 20], "disconnected road contact remains two frontage intervals")

	for z in range(20, 24): roads[Vector2i(16, z)] = "road_east"
	spans = ParcelContract.frontage_spans(bounds, roads, "multi")
	check(spans.size() == 3 and spans.any(func(value): return value.outward_direction == [1, 0] and value.start == [16, 20] and value.end == [16, 24]), "independent road-facing boundaries retain their own positioned spans")

	check(ParcelContract.frontage_spans(bounds, {}, "none").is_empty(), "a parcel with no adjacent road has no usable frontage")

	var asymmetric := Rect2i(3, 7, 3, 8)
	var west_roads: Dictionary = {}
	for z in range(9, 14): west_roads[Vector2i(2, z)] = "road_west"
	spans = ParcelContract.frontage_spans(asymmetric, west_roads, "asymmetric")
	check(spans.size() == 1 and spans[0].outward_direction == [-1, 0] and spans[0].start == [3, 9] and spans[0].end == [3, 14] and spans[0].width_cells == 5, "asymmetric parcels preserve exact intervals on a quarter-turned boundary")

func _test_generated_ownership_and_relationships() -> void:
	var first_data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 2208, &"industrial_district")
	var repeated_data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 2208, &"industrial_district")
	var first := BattlefieldLayoutDocument.from_generated(first_data, "parcel_contract_2208")
	var repeated := BattlefieldLayoutDocument.from_generated(repeated_data, "parcel_contract_2208")
	check(first.validate().is_empty(), "generated ownership/frontage document validates")
	check(first.to_json() == repeated.to_json(), "parcel ownership and frontage serialization are deterministic")

	var parcels: Array = first.spatial_layout.get("parcels", [])
	check(parcels.size() == first_data.environment_layout_plan.parcels.size() and not parcels.is_empty(), "every generated plan parcel has one document parcel record")
	var owned: Dictionary = {}
	var placement_ids: Dictionary = {}
	for placement in first.spatial_layout.placements: placement_ids[str(placement.placement_id)] = placement
	for parcel in parcels:
		for occupant in parcel.occupants:
			var ref := str(occupant.placement_ref)
			check(placement_ids.has(ref), "%s resolves owned placement %s" % [parcel.parcel_id, ref])
			check(not owned.has(ref), "%s has one unambiguous parcel owner" % ref)
			owned[ref] = parcel.parcel_id
		for frontage in parcel.frontage_spans:
			check(frontage.width_cells > 0 and not frontage.road_refs.is_empty(), "%s records a positioned positive-width road frontage" % frontage.frontage_id)
			for road_ref in frontage.road_refs: check(placement_ids.has(str(road_ref)), "%s resolves adjacent road %s" % [frontage.frontage_id, road_ref])
	check(first.relationships.any(func(value): return value.kind == ParcelContract.FRONTAGE_TO_STREET), "documents expose frontage-to-street relationships")
	check(first.relationships.any(func(value): return value.kind == ParcelContract.REQUIRED_OCCUPANT and value.required), "documents expose required occupants")
	check(first.relationships.any(func(value): return value.kind == ParcelContract.REQUIRED_OCCUPANT and not value.required), "documents distinguish optional occupants")
	check(first.relationships.any(func(value): return value.kind in [ParcelContract.PEDESTRIAN_ACCESS, ParcelContract.LOADING_ACCESS, ParcelContract.SERVICE_CLEARANCE]), "documents use the bounded functional-access vocabulary")

	var decoded := LayoutStore.decode(LayoutStore.encode(first), IndustrialModuleCatalog.create())
	check(decoded.ok, "schema-2 persistence accepts parcel ownership and frontage records")
	if decoded.ok:
		check(JSON.parse_string(JSON.stringify(decoded.document.spatial_layout.parcels)) == JSON.parse_string(JSON.stringify(first.spatial_layout.parcels)), "save/load preserves parcel ownership and exact frontage geometry")
		var reconstructed: EnvironmentLayoutPlan = decoded.document.to_environment_layout_plan()
		check(reconstructed.parcels.size() == parcels.size(), "document reconstruction restores parcel identities and records")
		check(reconstructed.parcels.any(func(value): return not value.road_edges.is_empty()), "reconstructed plans recover road-facing directions from exact frontage spans")

	var edited := first.editable_copy()
	var owned_ref := str(parcels.filter(func(value): return not value.occupants.is_empty())[0].occupants[0].placement_ref)
	var changed_layout := EnvironmentModuleLayout.new(&"ownership_edit", 2208)
	var catalog := IndustrialModuleCatalog.create()
	for record in edited.spatial_layout.placements:
		var origin: Array = record.origin
		var variation := int(record.variation) + (1 if record.placement_id == owned_ref else 0)
		changed_layout.try_add(catalog[StringName(record.component_id)], EnvironmentModulePlacement.new(StringName(record.component_id), Vector2i(int(origin[0]), int(origin[1])), int(record.rotation), variation, int(record.elevation)), edited.map_size())
	edited.apply_edited_layout(changed_layout)
	check(edited.spatial_layout.parcels.all(func(value): return value.validation_state == "requires_revalidation"), "editing an owned placement explicitly invalidates preserved parcel contracts")
	check(edited.relationships.any(func(value): return value.kind == ParcelContract.REQUIRED_OCCUPANT and value.get("validation_state", "") == "requires_revalidation"), "dependent ownership relationships require revalidation after an edit")

func _test_invalid_contracts() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 2208, &"industrial_district")
	var source := BattlefieldLayoutDocument.from_generated(data, "parcel_contract_invalid")
	var occupied_parcels: Array = source.spatial_layout.parcels.filter(func(value): return not value.occupants.is_empty())
	check(occupied_parcels.size() >= 2, "negative ownership fixture has two occupied parcels")
	if occupied_parcels.size() < 2: return

	var broken := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	broken.spatial_layout.parcels[1].occupants.append(broken.spatial_layout.parcels[0].occupants[0].duplicate(true))
	check(_has_code(broken.validate(), "AMBIGUOUS_PARCEL_OWNERSHIP"), "one placement cannot be silently owned by two parcels")

	broken = BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	broken.spatial_layout.parcels[0].occupants[0].placement_ref = "placement_missing"
	check(_has_code(broken.validate(), "MISSING_PARCEL_OCCUPANT"), "missing owned placement references fail explicitly")

	var frontage_parcel: Dictionary = source.spatial_layout.parcels.filter(func(value): return not value.frontage_spans.is_empty())[0]
	var parcel_index: int = source.spatial_layout.parcels.find(frontage_parcel)
	broken = BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	broken.spatial_layout.parcels[parcel_index].frontage_spans[0].width_cells += 1
	check(_has_code(broken.validate(), "INVALID_FRONTAGE_WIDTH"), "frontage width must agree with independently positioned endpoints")

	broken = BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	broken.spatial_layout.parcels[parcel_index].frontage_spans[0].road_refs = [broken.spatial_layout.parcels[0].occupants[0].placement_ref]
	check(_has_code(broken.validate(), "INVALID_FRONTAGE_ROAD"), "frontage references must resolve to actual road placements")

func _has_code(values: Array[Dictionary], code: String) -> bool:
	return values.any(func(value): return value.get("code", "") == code)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
