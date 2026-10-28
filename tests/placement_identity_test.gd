extends SceneTree

const Store = preload("res://tools/map_editor_layout_store.gd")
class EditorHarness extends "res://tools/map_editor.gd":
	func _rebuild() -> void: pass
	func _select_placement_index(index: int) -> void:
		inspection_module.set_meta("placement_id", custom_layout.placements[index].placement_id)

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(&"identity_fixture")
	for point in [Vector2i(3, 3), Vector2i(12, 3)]:
		check(layout.try_add(catalog.street_light, EnvironmentModulePlacement.new(&"street_light", point), Vector2i(30, 30)), "fixture placement")
	var document := BattlefieldLayoutDocument.from_authored(layout, Vector2i(30, 30), &"industrial_district", "identity_fixture")
	var first: String = layout.placements[0].placement_id
	var second: String = layout.placements[1].placement_id
	check(not first.is_empty() and first != second, "capture assigns distinct IDs to original placements")
	document.relationships.append({"relationship_id": "pair", "kind": "paired_fixture", "subject_ref": first, "object_ref": second, "required": true, "properties": {"placement_ref": first, "related_refs": [second], "label": first}})
	var edited := document.to_module_layout(catalog)
	edited.placements.reverse()
	var changed := edited.placements[1]
	changed.origin += Vector2i(0, 3)
	changed.rotation = 1
	changed.variation = 1
	check(document.apply_edited_layout(edited).is_empty(), "transform/variant/reorder accepts persistent IDs")
	check(document.spatial_layout.placements[1].placement_id == first, "identity survives every mutable placement field")
	check(document.relationships[0].subject_ref == first and document.relationships[0].object_ref == second, "access references preserved")
	var owned := BattlefieldLayoutDocument.from_dictionary(document.to_dictionary())
	owned.spatial_layout["parcels"] = [{"occupants": [{"placement_ref": first, "required": true}]}]
	var owned_layout := owned.to_module_layout(catalog)
	owned_layout.placements[0].variation += 1
	check(owned.apply_edited_layout(owned_layout).is_empty() and owned.spatial_layout.parcels[0].occupants[0].placement_ref == first, "parcel ownership preserved on edit")
	var before := document.to_json()
	var removed := document.to_module_layout(catalog)
	removed.placements.remove_at(0)
	check(document.apply_edited_layout(removed).any(func(e): return e.code == "REQUIRED_REFERENCE_LOSS"), "required deletion is explicit")
	check(document.to_json() == before, "required deletion leaves document untouched")
	var ids: Array[String] = [first, second]
	var duplicated := document.duplicate_placements(ids, Vector2i(0, 10), catalog)
	check(duplicated.ok, "group duplication succeeds")
	if duplicated.ok:
		var copy: BattlefieldLayoutDocument = duplicated.document
		var relation: Dictionary = copy.relationships.back()
		check(relation.subject_ref == duplicated.id_map[first] and relation.object_ref == duplicated.id_map[second], "duplicate remaps relationship endpoints")
		check(relation.properties.placement_ref == duplicated.id_map[first] and relation.properties.related_refs[0] == duplicated.id_map[second] and relation.properties.label == first, "only typed references remap, not arbitrary text")
		check(document.to_json() == before, "duplication returns an independent candidate")
		var decoded := Store.decode(Store.encode(copy), catalog)
		check(decoded.ok, "duplicated relations round-trip")
		if decoded.ok:
			check(decoded.layout.placements.map(func(p): return p.placement_id) == copy.to_module_layout(catalog).placements.map(func(p): return p.placement_id), "save/load preserves IDs")
	# Optional relationships are removed when their target is deleted; IDs never recycle.
	var optional := BattlefieldLayoutDocument.from_dictionary(document.to_dictionary())
	optional.relationships[0] = optional.relationships[0].duplicate(true)
	optional.relationships[0].required = false
	var deletion := optional.to_module_layout(catalog)
	deletion.placements.remove_at(0)
	check(optional.apply_edited_layout(deletion).is_empty() and optional.relationships.is_empty(), "optional deletion removes dangling relation")
	var restored := Store.decode(Store.encode(optional), catalog)
	check(restored.ok, "deleted document round-trips")
	if restored.ok:
		var added: EnvironmentModuleLayout = restored.layout
		check(added.try_add(catalog.street_light, EnvironmentModulePlacement.new(&"street_light", Vector2i(22, 22)), Vector2i(30, 30)), "new placement fits")
		restored.document.apply_edited_layout(added)
		check(added.placements.back().placement_id not in [first, second], "deleted IDs not reused after reload")
	# Genuine old schema has no IDs; only its explicit importer assigns them.
	var legacy := '{"schema_version":1,"layout_id":"legacy","map_size":[30,30],"placements":[{"component_id":"street_light","origin":[3,3]}]}'
	var a := Store.decode(legacy, catalog, &"legacy_compatibility")
	var b := Store.decode(legacy, catalog, &"legacy_compatibility")
	check(a.ok and b.ok and a.layout.placements[0].placement_id == b.layout.placements[0].placement_id, "legacy migration is deterministic")
	check(a.document.provenance.identity_status == "explicit_legacy_compatibility", "legacy identity does not claim approval")
	var invalid := JSON.parse_string(Store.encode(document)) as Dictionary
	invalid.layout_document.spatial_layout.placements[0].erase("placement_id")
	var bad := Store.decode(JSON.stringify(invalid), catalog)
	check(not bad.ok, "current-format missing IDs reject instead of inferred repair")
	_test_editor(document, catalog, bad)
	print("Placement identity: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_editor(document: BattlefieldLayoutDocument, catalog: Dictionary, rejected: Dictionary) -> void:
	var editor := EditorHarness.new()
	editor.editor_catalog = catalog
	editor.preview_map_size = Vector2i(30, 30)
	editor.custom_document = BattlefieldLayoutDocument.from_dictionary(document.to_dictionary())
	editor.custom_layout = editor.custom_document.to_module_layout(catalog)
	editor.inspection_module = Node3D.new()
	editor.variation_input = SpinBox.new()
	editor._select_placement_index(0)
	var id: String = editor.custom_layout.placements[0].placement_id
	editor._move_selected_placement(Vector2i(1, 0))
	editor._rotate_selected_placement(1)
	check(editor._confirm_placement_preview(), "editor confirms transform preview")
	editor.variation_input.value = 2
	editor._change_selected_variation()
	check(editor.custom_layout.placements[0].placement_id == id and editor.custom_layout.placements[0].variation == 2, "editor move/rotate/variant use stable identity")
	var before := editor.custom_document.to_json()
	editor._delete_selected_placement()
	check(editor.custom_document.to_json() == before, "editor required deletion is transactional")
	check(not editor._adopt_loaded_custom_layout(rejected) and editor.custom_document.to_json() == before, "rejected editor load preserves current state")
	editor._duplicate_selected_placement()
	check(editor.custom_layout.placements.size() == 2, "duplicate preview does not commit overlap")
	editor._move_selected_placement(Vector2i(5, 0))
	check(editor._confirm_placement_preview(), "editor confirms duplicate at a valid position")
	check(editor.custom_layout.placements.size() == 3 and editor.custom_layout.placements.back().placement_id != id, "editor duplicates with fresh identity")
	editor._delete_selected_placement()
	check(editor.custom_layout.placements.size() == 2, "editor can delete independent duplicate")
	editor.inspection_module.free()
	editor.variation_input.free()
	editor.free()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
