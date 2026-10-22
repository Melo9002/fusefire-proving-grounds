extends SceneTree

const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var generated := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 2208, &"industrial_district")
	generated.battlefield_layout_document = BattlefieldLayoutDocument.from_generated(generated, "lifecycle_2208")
	var source := generated.battlefield_layout_document
	_test_copy_and_compile(generated, source)
	_test_edit_revalidation(generated, source)
	_test_failed_repair()
	await _test_presentation(generated, source)
	await _test_map_editor_transition()
	await _test_failed_load_transaction()
	_test_rejections(source)
	print("Battlefield layout lifecycle: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_copy_and_compile(generated: MapData, source: BattlefieldLayoutDocument) -> void:
	var copied := source.editable_copy()
	check(copied != source and copied.signature() != "", "editable document is an independent value copy")
	check(copied.provenance.origin == "edited" and copied.provenance.source_origin == "generated", "copy records edited state while preserving generated origin")
	check(copied.provenance.generator_id == source.provenance.generator_id and copied.provenance.generation_seed == 2208, "copy retains original generator and seed")
	check(_placement_signature(copied) == _placement_signature(source), "copy preserves placement IDs and transforms")
	check(_relationship_signature(copied) == _relationship_signature(source), "copy preserves required relationship references")
	var result := BattlefieldLayoutDocumentCompiler.compile(copied)
	check(result.ok, "unchanged generated copy compiles through document boundary: %s" % _describe(result.errors))
	check(result.data.environment_modules.size() == generated.environment_modules.size(), "shared compiler reconstructs every road, building, and furniture placement")
	check(_zone_signature(result.data) == _zone_signature(generated), "valid repaired deployments survive unchanged copy and compilation")
	check(result.document.mission_context.validation_state == "validated", "compiled mission context records successful deployment validation")
	check(result.data.battlefield_layout_document.environment_id == "industrial_district", "compiled MapData retains its document and environment identity")
	copied.document_id = "mutated_copy"
	check(source.document_id == "lifecycle_2208", "editing copy identity cannot mutate original generated state")

func _test_edit_revalidation(generated: MapData, source: BattlefieldLayoutDocument) -> void:
	var copied := source.editable_copy()
	var layout := copied.to_module_layout()
	var catalog := IndustrialModuleCatalog.create()
	var blocked_spawn := Vector3i(-1, -1, -1)
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ENEMY, TacticalUnit.Faction.ALLY]:
		for spawn in generated.get_spawn_cells(faction):
			var candidate := _clone_layout(layout, generated.map_size, catalog)
			if candidate.try_add(catalog.construction_barrier_vault, EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(spawn.x, spawn.z)), generated.map_size):
				layout = candidate
				blocked_spawn = spawn
				break
		if blocked_spawn != Vector3i(-1, -1, -1): break
	check(blocked_spawn != Vector3i(-1, -1, -1), "nontrivial generated layout has a legal edit location on a deployment cell")
	var unchanged_ids := _placement_ids(copied)
	copied.apply_edited_layout(layout)
	check(copied.provenance.edit_state == "modified" and copied.mission_context.validation_state == "requires_revalidation", "placement edit explicitly invalidates deployment validation")
	check(copied.relationships.any(func(value): return value.get("kind", "") == "parcel_template" and value.get("validation_state", "") == "requires_revalidation"), "parcel relationships affected by an unowned edit remain present but visibly require revalidation")
	var preserved_ids := _placement_ids(copied)
	check(unchanged_ids.all(func(value): return value in preserved_ids), "unchanged placements retain stable identities across edit")
	var result := BattlefieldLayoutDocumentCompiler.compile(copied)
	check(result.ok, "edited document deterministically recompiles after deployment obstruction: %s" % _describe(result.errors))
	check(not result.repairs.is_empty() and result.repairs.any(func(value): return value.from == blocked_spawn), "blocked deployment is relocated rather than silently reset to flat defaults")
	var remaining_deployments: Array[Vector3i] = []
	for zone in result.data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT): remaining_deployments.append_array(zone.cells)
	check(blocked_spawn not in remaining_deployments, "compiled deployments do not retain an illegal obstructed cell")
	var repeated := BattlefieldLayoutDocumentCompiler.compile(copied)
	check(repeated.ok and _zone_signature(repeated.data) == _zone_signature(result.data), "equivalent edited inputs deterministically reproduce repaired deployments")

func _test_failed_repair() -> void:
	var data := FlatMapGenerator.generate(6, 6, 1.0, 9, 2)
	for cell: MapCellData in data.cells.values():
		cell.walkable = false
		cell.can_stop = false
	var result := EnvironmentDeploymentResolver.repair(data)
	check(not result.ok and result.failures.any(func(value): return value.code == "DEPLOYMENT_REPAIR_FAILED"), "unplaceable required deployments are explicit construction failures")

func _test_presentation(generated: MapData, source: BattlefieldLayoutDocument) -> void:
	var result := BattlefieldLayoutDocumentCompiler.compile(source.editable_copy())
	var holder := Node3D.new()
	root.add_child(holder)
	GeneratedTerrainPresenter.build(result.data, holder, 1.0)
	await process_frame
	var modular: Node = holder.get_node_or_null("ModularEnvironment")
	check(modular != null and modular.get_meta("environment_identity") == &"industrial_district", "actual presentation path receives document environment identity")
	check(modular != null and modular.get_meta("environment_identity_source") == "layout_document", "presenter reports document identity source instead of silent fallback")
	check(modular != null and modular.get_child_count() == result.data.environment_modules.size(), "presentation consumes the same document placement set as tactical compilation")
	holder.queue_free()
	await process_frame

func _test_map_editor_transition() -> void:
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.layout_preset = &"industrial_district"
	editor.generation_seed = 2208
	editor._rebuild()
	await process_frame
	var original_document: BattlefieldLayoutDocument = editor.displayed_data.battlefield_layout_document
	editor._compose_current_layout()
	await process_frame
	check(editor.layout_preset == &"custom_layout" and editor.custom_document.provenance.origin == "edited", "Map Editor copy operation enters document-derived edited state")
	check(editor.custom_document.provenance.generation_seed == 2208 and editor.custom_document.environment_id == "industrial_district", "Map Editor preserves source seed and environment through generated-to-edited transition")
	check(editor.displayed_data.battlefield_layout_document != original_document and editor.custom_build_errors.is_empty(), "Map Editor builds an independent validated document copy")
	var modular: Node = editor.content.get_node_or_null("ModularEnvironment")
	check(modular != null and modular.get_meta("environment_identity") == &"industrial_district", "edited Map Editor presentation keeps industrial identity")
	editor.queue_free()
	await process_frame

func _test_failed_load_transaction() -> void:
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	var before: BattlefieldLayoutDocument = editor.custom_document
	var before_signature := before.signature()
	var rejected := LayoutStore.decode("{ corrupt", editor.editor_catalog)
	check(not editor._adopt_loaded_custom_layout(rejected), "Map Editor refuses a failed persistence result at its transaction boundary")
	check(editor.custom_document == before and editor.custom_document.signature() == before_signature, "failed load leaves the active editor document and composition untouched")
	editor.queue_free()
	await process_frame

func _test_rejections(source: BattlefieldLayoutDocument) -> void:
	var invalid := source.editable_copy()
	invalid.environment_id = "unsupported_world"
	var result := BattlefieldLayoutDocumentCompiler.compile(invalid)
	check(not result.ok and _has_code(result.errors, "UNSUPPORTED_ENVIRONMENT"), "unsupported document configuration is rejected before tactical compilation")
	var data := MapData.new()
	data.battlefield_layout_document = invalid
	var identity := ModularEnvironmentPresenter.resolve_environment_identity(data)
	check(not identity.ok and identity.source == "invalid_layout_document", "presenter explicitly rejects unsupported document identity")

func _clone_layout(source: EnvironmentModuleLayout, map_size: Vector2i, catalog: Dictionary) -> EnvironmentModuleLayout:
	var result := EnvironmentModuleLayout.new(source.layout_id, source.generation_seed)
	for placement in source.placements:
		var copy := EnvironmentModulePlacement.new(placement.component_id, placement.origin, placement.rotation, placement.variation, placement.elevation)
		if not result.try_add(catalog[copy.component_id], copy, map_size): return result
	return result

func _placement_signature(document: BattlefieldLayoutDocument) -> String:
	var parts: Array[String] = []
	for value in document.spatial_layout.placements: parts.append("%s:%s:%s:%s:%s:%s" % [value.placement_id, value.component_id, value.origin, value.rotation, value.variation, value.elevation])
	return "|".join(parts)

func _placement_ids(document: BattlefieldLayoutDocument) -> Array[String]:
	var result: Array[String] = []
	for value in document.spatial_layout.placements: result.append(value.placement_id)
	return result

func _relationship_signature(document: BattlefieldLayoutDocument) -> String:
	var parts: Array[String] = []
	for value in document.relationships: parts.append("%s:%s:%s" % [value.relationship_id, value.subject_ref, value.object_ref])
	return "|".join(parts)

func _zone_signature(data: MapData) -> String:
	var parts: Array[String] = []
	for zone_id in data.zones:
		var zone: MapZoneData = data.zones[zone_id]
		var cells: Array[String] = []
		for cell in zone.cells: cells.append("%d,%d,%d" % [cell.x, cell.y, cell.z])
		cells.sort()
		parts.append("%s:%d:%d:%s" % [zone.zone_id, zone.kind, zone.faction, ",".join(cells)])
	parts.sort()
	return "|".join(parts)

func _has_code(errors: Array, code: String) -> bool:
	return errors.any(func(value): return value.get("code", "") == code)

func _describe(errors: Array) -> String:
	var parts: Array[String] = []
	for error in errors: parts.append("%s:%s" % [error.get("code", ""), error.get("message", "")])
	return "; ".join(parts)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
