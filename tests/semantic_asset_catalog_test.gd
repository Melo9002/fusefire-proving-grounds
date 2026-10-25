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
		check(record.working_faces.size() <= 2, id + " has at most two equal working faces")
		for face in record.working_faces:
			check(face in Semantics.DIRECTIONAL_FACES, id + " working face is cardinal")
		check(record.attachment in Semantics.ATTACHMENTS, id + " has a valid attachment state")
		check(record.has("orientation_notes") and record.has("clearance_notes") and record.has("assembly_notes"), id + " exposes placement guidance")
		for value in record.get("sockets", []):
			var socket: Dictionary = value
			check(socket.has("name") and socket.has("type") and socket.has("position") and socket.has("normal"), id + " socket has a complete semantic contract")
			check(socket.position is Array and socket.position.size() == 3 and socket.normal in Semantics.SOCKET_NORMALS, id + " socket has a local position and cardinal normal")
			if socket.has("example_mate"):
				var mate: Dictionary = socket.example_mate
				check(mate.has("asset") and mate.asset_socket is Array and mate.asset_socket.size() == 3, id + " example mate names an asset-local socket")
				check(mate.rotation_degrees is Array and mate.rotation_degrees.size() == 3 and mate.origin_offset is Array and mate.origin_offset.size() == 3, id + " example mate records its required transform")
		for flag in record.review_flags:
			check(flag in Semantics.REVIEW_FLAGS, id + " has a valid unresolved-field flag")
	var audit := Semantics.audit(Catalog.all_ids(), data)
	check(audit.total == 315 and audit.confirmed == 315, "All 315 stable IDs retain the completed human semantic review")
	check(audit.unknown_identity == 0 and not Semantics.needs_identification("factory_kit/oopi", data), "Every stable asset now has a supported catalog identity")
	check(audit.needs_review == 0 and audit.review_flags.is_empty(), "All scoped working-face and machine-connection questions are evidence-resolved")
	check(Semantics.effective("factory_kit/oopi", data).asset_kind == "character_reference", "Oopi remains an easter-egg character rather than an environment prop")
	check(Semantics.effective("factory_kit/oopi", data).working_faces == ["-x"], "Oopi's rendered face points toward local -X")
	check(audit.generation_ready == 35, "Only assets backed by explicit procedural placement contracts are approved")
	check(Semantics.effective("city_kit_roads/road-straight-barrier", data).semantic_category == "road_barrier_modules", "Road barrier overlays are not mistaken for complete road surfaces")
	check(Semantics.effective("factory_kit/structure-high", data).structural_role == "railing", "Rendered Factory rail modules are not mistaken for building walls")
	check(Semantics.effective("factory_kit/scanner-high", data).completeness == "intentionally_open", "Scanner arches preserve their pass-through opening")
	check(Semantics.effective("modular_space_kit/room-large", data).asset_kind == "open_structure", "Space rooms retain their intentional tactical cutaway")
	check(Semantics.effective("factory_kit/structure-corner-inner", data).working_faces == ["+z", "+x"], "The reviewed inner corner exposes two equal working faces")
	check(Semantics.effective("factory_kit/structure-corner-outer", data).working_faces == ["-z", "-x"], "The rendered outer corner exposes its opposite pair of equal working faces")
	check(Semantics.effective("city_kit_industrial/building-a", data).working_faces == ["-z"] and Semantics.effective("city_kit_industrial/building-g", data).working_faces == ["+z"], "Industrial shell facades retain model-local reviewed directions")
	check(Semantics.effective("city_kit_roads/road-sign-empty", data).front_face == "axis_neutral" and Semantics.effective("city_kit_roads/road-sign-warning", data).working_faces == ["-x"], "Empty sign mounts remain neutral while colored panels retain their visible face")
	check(Semantics.effective("city_kit_roads/light-curved", data).working_faces == ["-z"] and Semantics.effective("city_kit_roads/light-square", data).working_faces == ["-z"], "Streetlight heads retain their carriageway-facing local direction")
	check(Semantics.generation_candidates(["city_kit_roads/road-straight", "city_kit_roads/road-crossroad", "city_kit_roads/road-intersection", "city_kit_roads/road-curve", "city_kit_roads/tile-low"], data).size() == 5, "Reviewed kit road surfaces are approved through explicit module contracts")
	check(Semantics.effective("factory_kit/button-floor-round", data).front_face == "axis_neutral" and Semantics.effective("factory_kit/lever-single", data).working_faces == ["+z"], "Floor buttons and lever controls use distinct operator-direction rules")
	check(Semantics.effective("factory_kit/screen-wide", data).working_faces == ["-z"], "Factory screens face their dark display surface")
	check(Semantics.effective("modular_space_kit/gate-lasers", data).working_faces == ["+z", "-z"], "Space gates expose equal bidirectional passage faces")
	var hole := Semantics.effective("factory_kit/machine-connection-hole", data)
	var pipe := Semantics.effective("factory_kit/machine-connection-pipe", data)
	check(hole.connections == ["factory_pipe"] and hole.sockets.size() == 1 and hole.sockets[0].role == "receiver", "Machine connection hole exposes the reviewed opaque-pipe receiver")
	check(pipe.connections == ["factory_pipe"] and pipe.sockets.size() == 1 and pipe.sockets[0].role == "outlet", "Machine connection pipe exposes the reviewed opaque-pipe outlet")
	check(hole.sockets[0].example_mate.rotation_degrees == [0.0, 0.0, 90.0] and hole.sockets[0].example_mate.origin_offset == [0.5, 0.5, 0.0], "Machine pipe example preserves the reviewed rotation and pivot compensation")
	check(Semantics.effective("factory_kit/cog-a", data).connections.is_empty() and Semantics.effective("factory_kit/piston-round", data).connections.is_empty(), "Cog and piston envelopes do not manufacture machine compatibility")
	check(Semantics.effective("factory_kit/piston-round", data).completeness == "complete" and Semantics.effective("factory_kit/piston-round", data).attachment == "ground", "Animated pistons remain standalone equipment")
	check(Semantics.compatible_as_complete_building("city_kit_industrial/building-h", data), "Confirmed monolithic shell is eligible as a complete building visual")
	check(not Semantics.compatible_as_complete_building("factory_kit/structure-wall", data), "A filename-classified structural fragment cannot masquerade as a complete building")
	var candidates := Semantics.generation_candidates(["factory_kit/structure-wall", "city_kit_industrial/building-h"], data, "complete_building")
	check(candidates == ["city_kit_industrial/building-h"], "Procedural selection retains only confirmed candidates of the required kind")

	var fixture_path := "res://tests/_asset_semantics_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	var fixture := Semantics.default_data()
	fixture.confirmed["factory_kit/oopi"] = {"review_flags": ["working_faces"], "front_face": "unknown", "working_faces": []}
	check(Semantics.save_data(fixture, fixture_path) == OK, "Semantic fixture with a scoped human review flag saves")
	var lab = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	lab.semantic_path = fixture_path
	root.add_child(lab)
	await process_frame
	lab.select_asset("factory_kit/oopi")
	check("REVIEW: working_faces" in lab.semantic_status.text, "Partially understood assets expose only their unresolved fields")
	lab._select_option_value(lab.semantic_kind, "equipment")
	lab._select_option_value(lab.semantic_role, "machinery")
	lab._select_option_value(lab.semantic_completeness, "complete")
	lab._select_option_value(lab.semantic_front, "+z")
	lab._select_option_value(lab.semantic_secondary_front, "+x")
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
	check(confirmed.working_faces == ["+z", "+x"] and confirmed.front_face == "+z", "Two equal working faces persist with legacy primary-facing compatibility")
	check(confirmed.generation_ready, "Procedural approval is explicit and persisted")
	lab._clear_semantic_annotation()
	check(not Semantics.effective("factory_kit/oopi", Semantics.load_data(fixture_path)).needs_review, "Reset returns to the evidence-resolved catalog interpretation")
	lab.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	print("Semantic coverage: total=%d confirmed=%d catalog=%d review=%d unknown=%d procedural=%d" % [audit.total, audit.confirmed, audit.catalog_classified, audit.needs_review, audit.unknown_identity, audit.generation_ready])
	print("Semantic categories: ", audit.categories)
	print("Semantic review flags: ", audit.review_flags)
	print("Semantic asset catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error(message)
