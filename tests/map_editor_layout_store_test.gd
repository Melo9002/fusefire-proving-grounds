extends SceneTree

const LayoutStore = preload("res://tools/map_editor_layout_store.gd")
var failures := 0

func _init() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var generated_data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 2208, &"industrial_district")
	var generated := BattlefieldLayoutDocument.from_generated(generated_data, "persisted_generated_2208")
	var authored := _authored_document()
	var edited := generated.editable_copy()
	_test_round_trips(catalog, generated, authored, edited)
	_test_file_persistence(catalog, edited)
	_test_representative_file(catalog)
	_test_dependency_failures(catalog, edited)
	_test_format_failures(catalog, edited)
	_test_legacy_policy(catalog)
	print("Map Editor layout store: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func _authored_document() -> BattlefieldLayoutDocument:
	var data := FlatMapGenerator.generate(32, 32, 1.0, 3303)
	var layout := ModularIndustrialLayoutBuilder.apply(data, 1.0, 3303, &"certified_equipment_parcel")
	return BattlefieldLayoutDocument.from_authored(layout, data.map_size, &"industrial_service_pad", "persisted_authored_service_pad", data)

func _test_round_trips(catalog: Dictionary, generated: BattlefieldLayoutDocument, authored: BattlefieldLayoutDocument, edited: BattlefieldLayoutDocument) -> void:
	for label in ["generated", "authored", "edited"]:
		var source: BattlefieldLayoutDocument = {"generated": generated, "authored": authored, "edited": edited}[label]
		var decoded := LayoutStore.decode(LayoutStore.encode(source), catalog)
		check(decoded.ok, "%s unified document round-trips: %s" % [label, decoded.error])
		if not decoded.ok:
			continue
		check(_json_semantic(decoded.document) == _json_semantic(source), "%s identity, provenance, placements, relationships, dependencies, and mission context survive" % label)
		check(decoded.layout.signature() == source.to_module_layout(catalog).signature(), "%s reconstructs deterministic module placements" % label)
		var normalized_once := LayoutStore.encode(decoded.document)
		var normalized_twice := LayoutStore.encode(LayoutStore.decode(normalized_once, catalog).document)
		check(normalized_once == normalized_twice, "%s serialization is deterministic after JSON type normalization" % label)
	check(edited.provenance.origin == "edited" and edited.provenance.source_origin == "generated", "generated-to-edited provenance remains distinct from its generated source")
	var edited_result := LayoutStore.decode(LayoutStore.encode(edited), catalog)
	check(edited_result.document.environment_id == "industrial_district" and edited_result.document.provenance.generation_seed == 2208, "edited persistence retains environment, seed, and generation configuration")
	check(_relationship_signature(edited_result.document) == _relationship_signature(edited), "required assembly and parcel relationships retain stable references")

func _test_file_persistence(catalog: Dictionary, edited: BattlefieldLayoutDocument) -> void:
	var test_output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	var path := test_output.path_join("map_editor_layout_store_test.json") if not test_output.is_empty() else "user://map_editor_layout_store_test.json"
	var save_error := LayoutStore.save(edited, path)
	check(save_error.is_empty(), "validated unified document saves to disk%s" % ("" if save_error.is_empty() else ": " + save_error))
	var persisted := LayoutStore.load(catalog, path)
	check(persisted.ok and _json_semantic(persisted.document) == _json_semantic(edited), "saved generated-to-edited document reloads without semantic loss")
	if persisted.ok:
		var compiled := BattlefieldLayoutDocumentCompiler.compile(persisted.document)
		check(compiled.ok and compiled.data.battlefield_layout_document.environment_id == &"industrial_district", "reloaded document recompiles with the correct presentation identity")
		check(_zone_signature(compiled.data) == _mission_signature(persisted.document), "persisted deployment behavior survives deterministic reconstruction")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_representative_file(catalog: Dictionary) -> void:
	# This historical document predates shipping_container_family and records
	# cargo with an empty assembly_ref. T04 must not silently bless that change.
	var path := "res://docs/architecture/examples/persisted-edited-industrial-layout.json"
	var before := FileAccess.get_file_as_string(path)
	var result := LayoutStore.load(catalog, path)
	check(not result.ok and result.code == "ASSEMBLY_REFERENCE_MISMATCH", "historical cargo without its current assembly binding requires explicit migration")
	check(FileAccess.get_file_as_string(path) == before, "rejected historical fixture remains unchanged on disk")

func _test_dependency_failures(catalog: Dictionary, source: BattlefieldLayoutDocument) -> void:
	var missing_required := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	missing_required.spatial_layout.placements[0].asset_refs = ["missing_pack/missing_required_asset"]
	missing_required.dependencies.append({"kind": "asset", "id": "missing_pack/missing_required_asset", "required": true, "geometry_sha256": "missing", "calibration_signature": "missing", "required_by": [missing_required.spatial_layout.placements[0].placement_id]})
	var missing_result := LayoutStore.decode(LayoutStore.encode(missing_required), catalog)
	check(not missing_result.ok and missing_result.code == "MISSING_ASSET_DEPENDENCY" and "missing_required_asset" in missing_result.error, "missing required assets reject loading with the affected identity")

	var optional := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	optional.dependencies.append({"kind": "asset", "id": "missing_pack/optional_banner", "required": false, "required_by": []})
	var optional_result := LayoutStore.decode(LayoutStore.encode(optional), catalog)
	check(optional_result.ok and not optional_result.warnings.is_empty() and "optional_banner" in optional_result.warnings[0], "missing optional decoration is reported without invalidating required construction")

	var stale := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	var asset_index := _dependency_index(stale.dependencies, "asset")
	stale.dependencies[asset_index].calibration_signature = "stale_calibration"
	var stale_result := LayoutStore.decode(LayoutStore.encode(stale), catalog)
	check(not stale_result.ok and stale_result.code == "STALE_CALIBRATION_DEPENDENCY" and not stale_result.failures.is_empty(), "stale calibration explicitly invalidates loading pending revalidation")

	var missing_assembly := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	for dependency in missing_assembly.dependencies:
		if dependency.get("kind", "") == "assembly":
			dependency.certification_signature = "unavailable"
			break
	var assembly_result := LayoutStore.decode(LayoutStore.encode(missing_assembly), catalog)
	if _dependency_index(missing_assembly.dependencies, "assembly") >= 0:
		check(not assembly_result.ok and assembly_result.code == "STALE_ASSEMBLY_DEPENDENCY", "unavailable or stale assembly certification is rejected explicitly")

func _test_format_failures(catalog: Dictionary, source: BattlefieldLayoutDocument) -> void:
	var unsupported: Dictionary = JSON.parse_string(LayoutStore.encode(source))
	unsupported.schema_version = 99
	var unsupported_result := LayoutStore.decode(JSON.stringify(unsupported), catalog)
	check(not unsupported_result.ok and unsupported_result.code == "UNSUPPORTED_PERSISTENCE_VERSION", "unsupported persistence schema is rejected")
	var incomplete := {"schema_version": LayoutStore.SCHEMA_VERSION, "format": LayoutStore.FORMAT_ID}
	var incomplete_result := LayoutStore.decode(JSON.stringify(incomplete), catalog)
	check(not incomplete_result.ok and incomplete_result.code == "MISSING_LAYOUT_DOCUMENT", "incomplete persistence envelope is rejected")
	var malformed_result := LayoutStore.decode("{ definitely not JSON", catalog)
	check(not malformed_result.ok and malformed_result.code == "MALFORMED_JSON" and "line" in malformed_result.error, "corrupted JSON returns an actionable parse error")

func _test_legacy_policy(catalog: Dictionary) -> void:
	var legacy_text := FileAccess.get_file_as_string(LayoutStore.STARTER_PATH)
	var ambiguous := LayoutStore.decode(legacy_text, catalog)
	check(not ambiguous.ok and ambiguous.code == "LEGACY_ENVIRONMENT_REQUIRED" and ambiguous.legacy_available, "schema-1 files never acquire an invented environment identity")
	var compatible := LayoutStore.decode(legacy_text, catalog, &"legacy_compatibility")
	check(compatible.ok and compatible.legacy and compatible.document.environment_id == "legacy_compatibility", "schema-1 files remain accessible in explicitly labeled compatibility mode")
	check(compatible.document.provenance.identity_status == "explicit_legacy_compatibility" and compatible.document.presentation.road_presentation_mode == "legacy", "legacy reconstruction records its missing historical context instead of fabricating it")
	check(compatible.layout.placements.size() == 6 and not compatible.warnings.is_empty(), "tracked starter placements migrate safely with a visible information-loss warning")

func _dependency_index(values: Array[Dictionary], kind: String) -> int:
	for index in values.size():
		if values[index].get("kind", "") == kind:
			return index
	return -1

func _json_semantic(document: BattlefieldLayoutDocument) -> Dictionary:
	return JSON.parse_string(document.to_json())

func _relationship_signature(document: BattlefieldLayoutDocument) -> String:
	var values: Array[String] = []
	for relationship in document.relationships:
		values.append("%s:%s:%s" % [relationship.get("relationship_id", ""), relationship.get("subject_ref", ""), relationship.get("object_ref", "")])
	return "|".join(values)

func _zone_signature(data: MapData) -> String:
	var values: Array[String] = []
	for zone_id in data.zones:
		var zone: MapZoneData = data.zones[zone_id]
		for cell in zone.cells:
			values.append("%s:%d:%d,%d,%d" % [zone.zone_id, zone.faction, cell.x, cell.y, cell.z])
	values.sort()
	return "|".join(values)

func _mission_signature(document: BattlefieldLayoutDocument) -> String:
	var values: Array[String] = []
	for zone in document.mission_context.get("zones", []):
		for cell in zone.get("cells", []):
			values.append("%s:%d:%d,%d,%d" % [zone.get("zone_id", ""), zone.get("faction", -1), cell[0], cell[1], cell[2]])
	values.sort()
	return "|".join(values)

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
