extends SceneTree

const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data := Semantics.load_data()
	for id in Catalog.all_ids():
		var record := Semantics.effective(id, data)
		check(record.asset_kind in Semantics.KINDS, id + " has a valid semantic kind")
		check(record.structural_role in Semantics.STRUCTURAL_ROLES, id + " has a valid structural role")
		check(record.completeness in Semantics.COMPLETENESS, id + " has a valid completeness state")
		check(record.front_face in Semantics.FRONT_FACES, id + " has a valid facing state")
		check(record.attachment in Semantics.ATTACHMENTS, id + " has a valid attachment state")
	check(Semantics.compatible_as_complete_building("city_kit_industrial/building-h", data), "Confirmed monolithic shell is eligible as a complete building visual")
	check(not Semantics.compatible_as_complete_building("factory_kit/structure-wall", data), "A filename-classified structural fragment cannot masquerade as a complete building")
	var candidates := Semantics.generation_candidates(["factory_kit/structure-wall", "city_kit_industrial/building-h"], data, "complete_building")
	check(candidates == ["city_kit_industrial/building-h"], "Procedural selection retains only confirmed candidates of the required kind")

	var fixture_path := "res://tests/_asset_semantics_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	check(Semantics.save_data(Semantics.default_data(), fixture_path) == OK, "Empty semantic fixture saves")
	var lab = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	lab.semantic_path = fixture_path
	root.add_child(lab)
	await process_frame
	lab.select_asset("factory_kit/oopi")
	check("NEEDS IDENTIFICATION" in lab.semantic_status.text, "Unknown asset is clearly presented for human identification")
	lab._select_option_value(lab.semantic_kind, "equipment")
	lab._select_option_value(lab.semantic_role, "machinery")
	lab._select_option_value(lab.semantic_completeness, "complete")
	lab._select_option_value(lab.semantic_front, "+z")
	lab._select_option_value(lab.semantic_attachment, "ground")
	lab.semantic_contexts.text = "industrial, mixed service"
	lab.semantic_connections.text = "factory bay"
	lab.semantic_generation_ready.button_pressed = true
	lab.semantic_notes.text = "Developer identified fixture."
	lab._save_semantic_annotation()
	var persisted := Semantics.load_data(fixture_path)
	var confirmed := Semantics.effective("factory_kit/oopi", persisted)
	check(confirmed.interpretation_source == "confirmed" and not confirmed.needs_identification, "Human annotation overrides inference and persists")
	check(confirmed.contexts == ["industrial", "mixed_service"] and confirmed.connections == ["factory_bay"], "Editable semantic tags normalize and persist")
	check(confirmed.generation_ready, "Procedural approval is explicit and persisted")
	lab._clear_semantic_annotation()
	check(Semantics.effective("factory_kit/oopi", Semantics.load_data(fixture_path)).needs_identification, "Reset returns to provisional inference")
	lab.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	print("Semantic asset catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error(message)
