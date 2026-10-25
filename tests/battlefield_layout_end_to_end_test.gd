extends SceneTree
## Phase 4 lifecycle contract. This drives the real Map Editor construction,
## composer, persistence, compiler, and presenter paths with temporary files.

const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

var failures := 0
var assembly_placements_seen := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var configurations: Array[Dictionary] = [
		{"environment": &"industrial_district", "seed": 2208, "edit": "visual_variation"},
		{"environment": &"mixed_service", "seed": 11027, "edit": "visual_variation"},
		{"environment": &"commercial_street", "seed": 7319, "edit": "visual_variation"},
	]
	for configuration in configurations:
		await _exercise_editor_lifecycle(configuration)
	check(assembly_placements_seen > 0, "lifecycle matrix resolves authored assembly placements and dependencies")
	_test_unresolvable_deployment_failure()
	print("Battlefield layout end-to-end: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _exercise_editor_lifecycle(configuration: Dictionary) -> void:
	var environment: StringName = configuration.environment
	var seed: int = configuration.seed
	var path := _temporary_path(environment, seed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var editor = load("res://tools/map_editor.tscn").instantiate()
	editor.custom_layout_path = path
	root.add_child(editor)
	await process_frame

	editor.layout_preset = environment
	editor.generation_seed = seed
	editor._rebuild()
	await process_frame
	var generated: MapData = editor.displayed_data
	var source: BattlefieldLayoutDocument = generated.battlefield_layout_document
	var source_signature := source.signature()
	var source_placement_count: int = source.spatial_layout.placements.size()
	check(source.environment_id == String(environment), "%s/%d generation records the requested identity" % [environment, seed])
	check(source.provenance.origin == "generated" and source.provenance.generation_seed == seed, "%s/%d records generated provenance and the original seed" % [environment, seed])
	check(not source.provenance.generation_config.is_empty() and source.provenance.algorithm_revisions.parcel_grammar == BattlefieldLayoutDocument.PARCEL_GRAMMAR_REVISION and source.provenance.algorithm_revisions.road_topology == BattlefieldLayoutDocument.ROAD_TOPOLOGY_REVISION, "%s/%d pins generator configuration and content revisions" % [environment, seed])
	check(source_placement_count > 5 and source.relationships.any(func(value): return value.get("kind", "") == "parcel_template"), "%s/%d is a nontrivial layout with required parcel relationships" % [environment, seed])
	check(_presented_identity(editor) == environment and _presentation_matches_document(editor, source), "%s/%d tactical and visual construction consume the same identity, placements, and rotations" % [environment, seed])
	_count_and_validate_assemblies(source)

	editor._compose_current_layout()
	await process_frame
	var copied: BattlefieldLayoutDocument = editor.custom_document
	var pre_edit_ids := _placement_ids(copied)
	check(copied.provenance.origin == "edited" and copied.provenance.source_origin == "generated", "%s/%d editable copy preserves source provenance" % [environment, seed])
	check(copied.provenance.generation_seed == seed and copied.environment_id == String(environment), "%s/%d editable copy preserves seed and identity" % [environment, seed])
	var edit_result := _apply_representative_edit(editor, str(configuration.edit))
	check(edit_result.ok, "%s/%d accepts its representative placement edit: %s" % [environment, seed, edit_result.get("error", "")])
	if not edit_result.ok:
		editor.queue_free()
		await process_frame
		return
	check(editor.custom_document.provenance.edit_state == "modified" and editor.custom_document.mission_context.validation_state == "requires_revalidation", "%s/%d edit invalidates prior deployment validation without regenerating the seed" % [environment, seed])
	check(_unchanged_id_count(pre_edit_ids, _placement_ids(editor.custom_document)) >= pre_edit_ids.size() - 1, "%s/%d preserves stable IDs for unchanged placements" % [environment, seed])
	check(editor.custom_document.relationships.any(func(value): return value.get("kind", "") == "parcel_template" and value.get("validation_state", "") == "requires_revalidation"), "%s/%d keeps affected parcel relationships with explicit revalidation state" % [environment, seed])

	editor._rebuild()
	await process_frame
	check(editor.custom_build_errors.is_empty(), "%s/%d edited document recompiles tactically" % [environment, seed])
	check(editor.custom_document.mission_context.validation_state == "validated", "%s/%d edited deployment context is explicitly revalidated" % [environment, seed])
	if edit_result.has("blocked_spawn"):
		check(edit_result.blocked_spawn not in _all_deployments(editor.displayed_data), "%s/%d invalidated deployment cell is deterministically repaired" % [environment, seed])
	var edited_transform := str(edit_result.changed_signature)
	var edited_document: BattlefieldLayoutDocument = editor.custom_document
	var compiled_before_save := _tactical_signature(editor.displayed_data)
	var presentation_before_save := _presentation_signature(editor)

	editor._save_custom_layout()
	check(not editor.custom_dirty and FileAccess.file_exists(path), "%s/%d saves through the real Map Editor path" % [environment, seed])
	var persisted := LayoutStore.load(editor.editor_catalog, path)
	check(persisted.ok, "%s/%d persisted document passes strict reload: %s" % [environment, seed, persisted.error])
	if persisted.ok:
		check(persisted.document.environment_id == String(environment) and persisted.document.provenance.generation_seed == seed, "%s/%d save retains identity, seed, and configuration" % [environment, seed])
		check(_has_placement_signature(persisted.document, edited_transform), "%s/%d saved placement edit is not overwritten by original-seed regeneration" % [environment, seed])
		check(_relationship_signature(persisted.document) == _relationship_signature(edited_document), "%s/%d required relationship references survive persistence" % [environment, seed])
		check(_dependency_signature(persisted.document) == _dependency_signature(edited_document), "%s/%d resolved asset, calibration, and assembly dependencies survive persistence" % [environment, seed])

	editor._clear_custom_layout()
	await process_frame
	editor._load_custom_layout(true)
	await process_frame
	check(editor.custom_build_errors.is_empty() and editor.custom_document.environment_id == String(environment), "%s/%d reload reconstructs the saved document instead of the cleared working state" % [environment, seed])
	check(_has_placement_signature(editor.custom_document, edited_transform), "%s/%d reload retains the representative edit" % [environment, seed])
	check(_tactical_signature(editor.displayed_data) == compiled_before_save, "%s/%d reload reproduces equivalent authoritative tactical data and deployments" % [environment, seed])
	check(_presentation_signature(editor) == presentation_before_save and _presented_identity(editor) == environment, "%s/%d reload reproduces presentation identity, placements, and rotations" % [environment, seed])
	check(source.signature() == source_signature and source.spatial_layout.placements.size() == source_placement_count, "%s/%d generated source remains independent and unchanged" % [environment, seed])

	var first_rebuild := BattlefieldLayoutDocumentCompiler.compile(editor.custom_document)
	var second_rebuild := BattlefieldLayoutDocumentCompiler.compile(editor.custom_document)
	check(first_rebuild.ok and second_rebuild.ok and _tactical_signature(first_rebuild.data) == _tactical_signature(second_rebuild.data), "%s/%d repeated reconstruction is deterministic" % [environment, seed])
	check(_document_semantics(first_rebuild.document) == _document_semantics(second_rebuild.document), "%s/%d repeated reconstruction preserves meaningful document state" % [environment, seed])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor.queue_free()
	await process_frame

func _apply_representative_edit(editor, kind: String) -> Dictionary:
	if kind == "deployment_obstruction":
		var catalog: Dictionary = editor.editor_catalog
		for spawn in _all_deployments(editor.displayed_data):
			var candidate := _clone_layout(editor.custom_layout, editor.preview_map_size, catalog)
			var barrier := EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(spawn.x, spawn.z))
			if candidate.try_add(catalog.construction_barrier_vault, barrier, editor.preview_map_size):
				editor._accept_custom_layout(candidate)
				return {"ok": true, "blocked_spawn": spawn, "changed_signature": barrier.signature()}
		return {"ok": false, "error": "no deployment cell accepted the authored barrier"}
	var owned_refs: Dictionary = {}
	for parcel in editor.custom_document.spatial_layout.get("parcels", []):
		for occupant in parcel.get("occupants", []): owned_refs[str(occupant.get("placement_ref", ""))] = true
	var target_index := -1
	for preferred in [&"street_light", &"service_dumpster", &"cargo_container", &"construction_barrier_vault"]:
		for index in editor.custom_layout.placements.size():
			var placement_id := str(editor.custom_document.spatial_layout.placements[index].get("placement_id", ""))
			if editor.custom_layout.placements[index].component_id == preferred and not owned_refs.has(placement_id):
				target_index = index
				break
		if target_index >= 0:
			break
	if target_index < 0:
		for index in editor.custom_layout.placements.size():
			var placement_id := str(editor.custom_document.spatial_layout.placements[index].get("placement_id", ""))
			if not owned_refs.has(placement_id):
				target_index = index
				break
	if target_index < 0:
		return {"ok": false, "error": "layout contains no placement to edit"}
	var candidate := EnvironmentModuleLayout.new(editor.custom_layout.layout_id, editor.custom_layout.generation_seed)
	var changed: EnvironmentModulePlacement
	for index in editor.custom_layout.placements.size():
		var source: EnvironmentModulePlacement = editor.custom_layout.placements[index]
		var copy := EnvironmentModulePlacement.new(source.component_id, source.origin, source.rotation, source.variation + (1 if index == target_index else 0), source.elevation)
		if not candidate.try_add(editor.editor_catalog[copy.component_id], copy, editor.preview_map_size):
			return {"ok": false, "error": candidate.errors.back()}
		if index == target_index:
			changed = copy
	editor._accept_custom_layout(candidate)
	return {"ok": true, "changed_signature": changed.signature()}

func _clone_layout(source: EnvironmentModuleLayout, map_size: Vector2i, catalog: Dictionary) -> EnvironmentModuleLayout:
	var result := EnvironmentModuleLayout.new(source.layout_id, source.generation_seed)
	for placement: EnvironmentModulePlacement in source.placements:
		var copy := EnvironmentModulePlacement.new(placement.component_id, placement.origin, placement.rotation, placement.variation, placement.elevation)
		if not result.try_add(catalog[copy.component_id], copy, map_size):
			return result
	return result

func _test_unresolvable_deployment_failure() -> void:
	var data := FlatMapGenerator.generate(6, 6, 1.0, 4404, 2)
	for cell: MapCellData in data.cells.values():
		cell.walkable = false
		cell.can_stop = false
	var result := EnvironmentDeploymentResolver.repair(data)
	check(not result.ok and result.failures.any(func(value): return value.code == "DEPLOYMENT_REPAIR_FAILED"), "unresolvable deployment requirements remain explicit construction failures")

func _count_and_validate_assemblies(document: BattlefieldLayoutDocument) -> void:
	var dependency_ids: Dictionary = {}
	for dependency in document.dependencies:
		if dependency.get("kind", "") == "assembly":
			dependency_ids[str(dependency.get("id", ""))] = true
	for placement in document.spatial_layout.placements:
		var assembly_id := str(placement.get("assembly_ref", ""))
		if assembly_id.is_empty():
			continue
		assembly_placements_seen += 1
		check(dependency_ids.has(assembly_id), "%s resolves authored assembly dependency %s" % [document.document_id, assembly_id])

func _presentation_matches_document(editor, document: BattlefieldLayoutDocument) -> bool:
	var modular: Node = editor.content.get_node_or_null("ModularEnvironment")
	if modular == null or modular.get_child_count() != document.spatial_layout.placements.size():
		return false
	var expected: Dictionary = {}
	for record in document.spatial_layout.placements:
		var origin: Array = record.origin
		expected["%s@%d,%d" % [record.component_id, origin[0], origin[1]]] = int(record.rotation)
	for child in modular.get_children():
		var origin: Vector2i = child.get_meta("origin", Vector2i(-999, -999))
		var key := "%s@%d,%d" % [child.get_meta("component_id", ""), origin.x, origin.y]
		if not expected.has(key) or int(child.get_meta("rotation", -1)) != expected[key]:
			return false
	return true

func _presented_identity(editor) -> StringName:
	var modular: Node = editor.content.get_node_or_null("ModularEnvironment")
	return modular.get_meta("environment_identity", &"") if modular != null else &""

func _presentation_signature(editor) -> String:
	var modular: Node = editor.content.get_node_or_null("ModularEnvironment")
	if modular == null:
		return "missing"
	var parts: Array[String] = ["identity=%s" % modular.get_meta("environment_identity", &"")]
	for child in modular.get_children():
		var origin: Vector2i = child.get_meta("origin", Vector2i.ZERO)
		parts.append("%s@%d,%d:r%d:v%d" % [child.get_meta("component_id", ""), origin.x, origin.y, child.get_meta("rotation", 0), child.get_meta("variation", 0)])
	parts.sort()
	return "|".join(parts).sha256_text()

func _tactical_signature(data: MapData) -> String:
	var parts: Array[String] = ["size=%d,%d" % [data.map_size.x, data.map_size.y]]
	var positions := data.cells.keys()
	positions.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	for position in positions:
		var cell: MapCellData = data.cells[position]
		parts.append("c=%d,%d,%d:%d:%d:%d:%.3f:%d:%d" % [position.x, position.y, position.z, int(cell.walkable), int(cell.can_stop), cell.cover_type, cell.cover_height, int(cell.blocks_line_of_sight), cell.movement_cost])
	for placement: EnvironmentModulePlacement in data.environment_modules:
		parts.append("p=" + placement.signature())
	var zones := data.zones.keys()
	zones.sort_custom(func(a, b): return String(a) < String(b))
	for zone_id in zones:
		var zone: MapZoneData = data.zones[zone_id]
		var cells: Array[String] = []
		for cell in zone.cells:
			cells.append("%d,%d,%d" % [cell.x, cell.y, cell.z])
		cells.sort()
		parts.append("z=%s:%d:%d:%s" % [zone.zone_id, zone.kind, zone.faction, ",".join(cells)])
	parts.sort()
	return "|".join(parts).sha256_text()

func _document_semantics(document: BattlefieldLayoutDocument) -> Dictionary:
	return JSON.parse_string(document.to_json())

func _placement_ids(document: BattlefieldLayoutDocument) -> Array[String]:
	var result: Array[String] = []
	for placement in document.spatial_layout.placements:
		result.append(str(placement.placement_id))
	return result

func _unchanged_id_count(before: Array[String], after: Array[String]) -> int:
	var result := 0
	for id in before:
		if id in after:
			result += 1
	return result

func _has_placement_signature(document: BattlefieldLayoutDocument, expected: String) -> bool:
	return document.to_module_layout().placements.any(func(value): return value.signature() == expected)

func _relationship_signature(document: BattlefieldLayoutDocument) -> Array:
	return JSON.parse_string(JSON.stringify(document.relationships))

func _dependency_signature(document: BattlefieldLayoutDocument) -> Array:
	return JSON.parse_string(JSON.stringify(document.dependencies))

func _all_deployments(data: MapData) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for zone in data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
		result.append_array(zone.cells)
	return result

func _temporary_path(environment: StringName, seed: int) -> String:
	var output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	if not output.is_empty():
		return output.path_join("phase4_%s_%d.json" % [environment, seed])
	return "user://phase4_%s_%d.json" % [environment, seed]

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
