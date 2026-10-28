extends SceneTree
## T04 contract: frozen compatibility is not new human approval.
var failures := 0
var source_catalog: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	source_catalog = IndustrialModuleCatalog.create()
	var context := EnvironmentResolutionContext.new(source_catalog)
	var layout := _layout()
	var document := BattlefieldLayoutDocument.from_authored(layout, Vector2i(30, 30), &"industrial_district", "revision_fixture", null, context)
	check(document.validate(context.catalog, context).is_empty(), "unchanged baseline validates")
	var legacy := BattlefieldLayoutDocument.from_dictionary(document.to_dictionary())
	legacy.spatial_layout.erase("resolution_version")
	legacy.dependencies = legacy.dependencies.filter(func(value): return value.kind != "module")
	for dependency in legacy.dependencies: dependency.erase("semantic_signature")
	check(legacy.validate(context.catalog, context).is_empty(), "known legacy document imports without approval")
	var records := context.resolve_layout(layout)
	var reads := context.asset_reads
	var selections := context.visual_resolutions
	context.resolve_layout(layout)
	check(context.asset_reads == reads and context.visual_resolutions == selections and selections == 1, "repeated instances reuse asset reads and visual selection")
	check(not context.baselines.owner_visual_approval, "compatibility baseline grants no owner visual approval")
	# Baseline divergence models the exact geometry bytes read from disk differing
	# from the approved hash, without modifying a downloaded asset in the test.
	for mutation in ["geometry", "calibration", "transform", "clearance", "effects", "envelope"]:
		var changed := EnvironmentResolutionContext.new(source_catalog)
		var module: EnvironmentModuleDefinition = changed.catalog.street_light
		var asset_id: String = document.spatial_layout.placements[0].asset_refs[0]
		match mutation:
			"geometry": changed.baselines.assets[asset_id].geometry_sha256 = "older_geometry_revision"
			"calibration": changed.calibration_data.asset_overrides[asset_id] = {"scale": 123.0}
			"transform": module.visuals[0]["offset"] = Vector3(0.2, 0.0, 0.0)
			"clearance": module.clearance_height += 1.0
			"effects": module.cell_effects[Vector2i.ZERO] = {"walkable": false}
			"envelope": module.visual_envelope.size.y += 1.0
		var old_failures: Array[Dictionary] = []
		legacy._validate_dependencies(old_failures, changed)
		check(_has(old_failures, "STALE_APPROVED_REVISION"), mutation + " invalidates legacy load")
		changed.errors.clear()
		var fresh := BattlefieldLayoutDocument.from_authored(_layout(), Vector2i(30, 30), &"industrial_district", "fresh", null, changed)
		var fresh_failures: Array[Dictionary] = []
		fresh._validate_dependencies(fresh_failures, changed)
		check(_has(fresh_failures, "STALE_APPROVED_REVISION"), mutation + " cannot acquire approval through fresh capture")
		changed.errors.clear()
		changed.resolve_layout(_layout())
		check(_has(changed.errors, "STALE_APPROVED_REVISION"), mutation + " rejects fresh generator resolution")
	# Test real socket attachment validation, not merely a certification flag.
	var pipe_context := EnvironmentResolutionContext.new(source_catalog)
	var pipe_layout := EnvironmentModuleLayout.new(&"pipe")
	pipe_layout.placements.append(EnvironmentModulePlacement.new(&"factory_pipe_receiver_unit", Vector2i(5, 5)))
	var pipe_document := BattlefieldLayoutDocument.from_authored(pipe_layout, Vector2i(30, 30), &"industrial_district", "pipe", null, pipe_context)
	var old_pipe := BattlefieldLayoutDocument.from_dictionary(pipe_document.to_dictionary())
	old_pipe.spatial_layout.erase("resolution_version")
	old_pipe.dependencies = old_pipe.dependencies.filter(func(value): return value.kind != "module")
	for dependency in old_pipe.dependencies:
		if dependency.kind == "assembly": dependency.certification_signature = pipe_context.baselines.assemblies[dependency.id].legacy_signature
	check(old_pipe.validate(pipe_context.catalog, pipe_context).is_empty(), "frozen legacy assembly signature remains importable")
	var broken := EnvironmentResolutionContext.new(source_catalog)
	broken.catalog.factory_pipe_receiver_unit.visuals[0].components[1].transform.origin += Vector3(1, 0, 0)
	var bad: Array[Dictionary] = []
	old_pipe._validate_dependencies(bad, broken)
	check(_has(bad, "INVALID_ASSEMBLY_DEPENDENCY") and _has(bad, "STALE_APPROVED_REVISION"), "misaligned socket fails substantive validation despite certified flag")
	broken.errors.clear()
	broken.resolve_layout(pipe_layout)
	check(_has(broken.errors, "INVALID_ASSEMBLY_DEPENDENCY"), "misaligned socket also rejects new generation")
	var rewired := EnvironmentResolutionContext.new(source_catalog)
	rewired._library = InitialEnvironmentAssemblyLibrary.records()
	rewired._library[&"pipe_receiver_unit"].contract.relationships.required_attachment.to = &"wrong_socket"
	var rewired_failures: Array[Dictionary] = []
	old_pipe._validate_dependencies(rewired_failures, rewired)
	check(_has(rewired_failures, "STALE_APPROVED_REVISION"), "changed socket relationship invalidates old document")
	rewired.errors.clear()
	rewired.resolve_layout(pipe_layout)
	check(_has(rewired.errors, "STALE_APPROVED_REVISION"), "changed socket relationship rejects new generation")
	var generation_context := EnvironmentResolutionContext.new(source_catalog)
	generation_context.catalog.road_straight.clearance_height += 1.0
	var generation_data := FlatMapGenerator.generate(40, 30, 1.0, 17, 5)
	var rejected := ModularIndustrialLayoutBuilder.apply(generation_data, 1.0, 17, &"asset_first_frontage", generation_context)
	check(not rejected.errors.is_empty() and generation_data.environment_modules.is_empty(), "production generator rejects changed module before publishing map metadata")
	var socket := IndustrialEquipmentAssemblyCatalog.receiver_socket()
	var socket_hash := EnvironmentResolutionContext.fingerprint(socket)
	socket.local_frame.origin.y += 0.1
	check(socket_hash != EnvironmentResolutionContext.fingerprint(socket), "socket geometry participates in assembly fingerprint")
	# Snapshot survives changes to the source objects; renderer uses exact records.
	var data := FlatMapGenerator.generate(30, 30, 1.0, 17, 5)
	data.environment_modules.assign(layout.placements)
	data.resolved_environment_modules = records
	var expected_path: String = records[0].visuals[0].asset_path
	source_catalog.street_light.visuals[0]["asset_ids"] = ["not/a/real/asset"]
	context.semantic_data.clear()
	var holder := Node3D.new()
	root.add_child(holder)
	ModularEnvironmentPresenter.build(data, holder, 1.0)
	var shown: Array[String] = []
	_collect_assets(holder, shown)
	check(shown.size() == 2 and shown[0] == expected_path and shown[1] == expected_path, "renderer uses frozen exact choices without consulting mutated live source")
	holder.free()
	print("Environment resolution context: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _layout() -> EnvironmentModuleLayout:
	var result := EnvironmentModuleLayout.new(&"revision_fixture")
	for x in [3, 12]: result.placements.append(EnvironmentModulePlacement.new(&"street_light", Vector2i(x, 3)))
	return result

func _has(errors: Array[Dictionary], code: String) -> bool:
	return errors.any(func(value): return value.code == code)

func _collect_assets(node: Node, output: Array[String]) -> void:
	if node.has_meta("asset_path"): output.append(str(node.get_meta("asset_path")))
	for child in node.get_children(): _collect_assets(child, output)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
