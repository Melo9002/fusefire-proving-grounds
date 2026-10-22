extends SceneTree

var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var generated := _test_generated_document()
	var authored := _test_authored_document()
	_test_validation(generated, authored)
	_test_determinism()
	print("Battlefield layout document: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_generated_document() -> BattlefieldLayoutDocument:
	var data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 2208, &"industrial_district")
	var document := BattlefieldLayoutDocument.from_generated(data, "industrial_2208")
	var errors := document.validate()
	check(errors.is_empty(), "representative generated document validates: %s" % _describe(errors))
	check(document.environment_id == "industrial_district", "generated environment identity is preserved")
	check(document.provenance.origin == "generated" and document.provenance.generator_id == "coherent_environment_assembler", "generated origin and generator identity are explicit")
	check(document.provenance.generation_seed == 2208 and document.provenance.generation_config.plan_signature == data.environment_layout_plan.signature(), "seed and actual plan signature are retained")
	var records: Array = document.spatial_layout.placements
	check(records.size() == data.environment_modules.size(), "every generated placement is represented")
	if not records.is_empty():
		var source: EnvironmentModulePlacement = data.environment_modules[0]
		var record: Dictionary = records[0]
		check(record.component_id == String(source.component_id) and record.origin == [source.origin.x, source.origin.y] and record.rotation == source.rotation and record.variation == source.variation and record.elevation == source.elevation, "placement identity and full authored transform survive conversion")
	check(document.relationships.any(func(value): return value.kind == "parcel_template"), "generated parcel-template relationships are retained")
	check(document.dependencies.any(func(value): return value.kind == "template"), "generated parcel grammar dependencies are explicit")
	check(document.dependencies.any(func(value): return value.kind == "asset"), "resolved imported presentation assets are pinned")
	check(document.dependencies.any(func(value): return value.kind == "assembly" and value.get("resolution", "") in ["certified_contract", "building_definition"] and value.get("certification_signature", "") != ""), "every referenced authored assembly resolves to a concrete revision source")
	check(document.mission_context.status == "preserved" and document.mission_context.zones.size() == data.zones.size(), "generated and repaired deployment zones are preserved")
	var rebuilt := document.to_module_layout()
	check(rebuilt.errors.is_empty() and _placement_signature(rebuilt.placements) == _placement_signature(data.environment_modules), "document deterministically reconstructs the intended module placement list")
	return document

func _test_authored_document() -> BattlefieldLayoutDocument:
	var data := FlatMapGenerator.generate(32, 32, 1.0, 3303)
	var layout := ModularIndustrialLayoutBuilder.apply(data, 1.0, 3303, &"certified_equipment_parcel")
	check(layout.errors.is_empty(), "representative Phase 3 authored parcel is valid before conversion")
	var document := BattlefieldLayoutDocument.from_authored(layout, Vector2i(32, 32), &"industrial_service_pad", "authored_service_pad")
	var errors := document.validate()
	check(errors.is_empty(), "representative authored document validates: %s" % _describe(errors))
	check(document.provenance.origin == "authored" and not document.provenance.has_generation_seed and document.provenance.generator_id.is_empty(), "authored provenance does not invent a generator or seed")
	check(document.relationships.any(func(value): return value.object_ref == "assembly:certified_pipe_service_pad"), "authored parcel preserves its certified Phase 3 template reference")
	check(document.relationships.any(func(value): return value.object_ref == "assembly:pipe_receiver_unit"), "nested measured equipment assembly reference is preserved")
	check(document.dependencies.any(func(value): return value.kind == "assembly" and value.id == "certified_pipe_service_pad"), "assembly certification dependency is pinned")
	check(document.mission_context.status == "not_represented" and document.mission_context.zones.is_empty(), "missing authored mission definitions are identified instead of invented")
	var with_zones := BattlefieldLayoutDocument.from_authored(layout, Vector2i(32, 32), &"industrial_service_pad", "authored_service_pad_with_zones", data)
	check(with_zones.mission_context.status == "preserved" and with_zones.mission_context.zones.size() == data.zones.size(), "existing authored MapData zones can be retained when supplied")
	return document

func _test_validation(generated: BattlefieldLayoutDocument, authored: BattlefieldLayoutDocument) -> void:
	var raw := generated.to_dictionary()
	raw.schema_version = 99
	check(_has_code(BattlefieldLayoutDocument.from_dictionary(raw).validate(), "UNSUPPORTED_SCHEMA_VERSION"), "unsupported schema versions fail explicitly")

	var broken := BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.environment_id = ""
	check(_has_code(broken.validate(), "MISSING_ENVIRONMENT_ID"), "missing environment identity is not silently substituted")

	broken = BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.provenance.erase("generator_id")
	check(_has_code(broken.validate(), "MISSING_GENERATOR"), "generated provenance requires a generator identity")

	broken = BattlefieldLayoutDocument.from_dictionary(authored.to_dictionary())
	broken.provenance.has_generation_seed = true
	check(_has_code(broken.validate(), "INCONSISTENT_PROVENANCE"), "authored provenance cannot claim a generated seed")

	broken = BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.spatial_layout.map_size = [2, 30]
	check(_has_code(broken.validate(), "INVALID_MAP_DIMENSIONS"), "malformed map dimensions are rejected")

	broken = BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.spatial_layout.grid_convention = "unknown"
	check(_has_code(broken.validate(), "UNSUPPORTED_GRID_CONVENTION"), "unknown coordinate conventions are rejected")

	broken = BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.spatial_layout.placements[0].component_id = "missing_component"
	check(_has_code(broken.validate(), "MISSING_PLACEMENT_REFERENCE"), "missing component references identify the affected placement")

	broken = BattlefieldLayoutDocument.from_dictionary(authored.to_dictionary())
	broken.relationships[0].object_ref = "assembly:missing"
	check(_has_code(broken.validate(), "MISSING_RELATIONSHIP_REFERENCE"), "broken required relationship references are rejected")

	broken = BattlefieldLayoutDocument.from_dictionary(authored.to_dictionary())
	var asset_index := _dependency_index(broken.dependencies, "asset")
	broken.dependencies[asset_index].geometry_sha256 = "stale"
	check(_has_code(broken.validate(), "STALE_GEOMETRY_DEPENDENCY"), "stale imported geometry dependencies invalidate the document")

	broken = BattlefieldLayoutDocument.from_dictionary(authored.to_dictionary())
	var assembly_index := _dependency_index(broken.dependencies, "assembly")
	broken.dependencies[assembly_index].certification_signature = "stale"
	check(_has_code(broken.validate(), "STALE_ASSEMBLY_DEPENDENCY"), "stale assembly certifications invalidate the document")

	broken = BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.dependencies.append({"kind": "assembly", "id": "missing_assembly", "certification_signature": "", "required_by": []})
	check(_has_code(broken.validate(), "MISSING_ASSEMBLY_DEPENDENCY"), "unresolved assembly dependencies cannot validate by comparing missing sentinels")

	broken = BattlefieldLayoutDocument.from_dictionary(generated.to_dictionary())
	broken.mission_context.zones[0].cells.append([999, 0, 999])
	check(_has_code(broken.validate(), "ZONE_CELL_OUT_OF_BOUNDS"), "malformed mission cells are rejected without recompiling deployments")

func _test_determinism() -> void:
	var first_data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 7319, &"commercial_street")
	var second_data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 7319, &"commercial_street")
	var first := BattlefieldLayoutDocument.from_generated(first_data, "commercial_7319")
	var second := BattlefieldLayoutDocument.from_generated(second_data, "commercial_7319")
	check(first.signature() == second.signature() and first.to_json() == second.to_json(), "identical inputs produce byte-stable deterministic documents")

func _placement_signature(values: Array) -> String:
	var parts: Array[String] = []
	for placement: EnvironmentModulePlacement in values: parts.append(placement.signature())
	return "|".join(parts)

func _dependency_index(values: Array[Dictionary], kind: String) -> int:
	for index in values.size():
		if values[index].get("kind", "") == kind: return index
	return -1

func _has_code(errors: Array[Dictionary], code: String) -> bool:
	return errors.any(func(value): return value.get("code", "") == code)

func _describe(errors: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for error in errors: parts.append("%s(%s): %s" % [error.code, error.field, error.message])
	return "; ".join(parts)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
