class_name EnvironmentResolutionContext
extends RefCounted
## One operation's content snapshot. Never writes or renews approval records.
const Assets = preload("res://tools/asset_lab/asset_catalog.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const BASELINE_PATH := "res://systems/generation/initial_environment_assembly_revisions.json"
var chunk_library := ChunkPublicationLibrary.new()
var chunk_revision_cache := {}
var composition_cache := {}
var catalog: Dictionary
var calibration_data: Dictionary
var semantic_data: Dictionary
var native_bounds: Dictionary
var baselines: Dictionary
var asset_cache := {}
var assembly_cache := {}
var visual_cache := {}
var visual_failures := {}
var module_cache := {}
var errors: Array[Dictionary] = []
var asset_reads := 0
var visual_resolutions := 0
var _library := {}
var _buildings := {}
var _paths := {}

func _init(source_catalog := {}) -> void:
	calibration_data = Assets.load_calibrations()
	semantic_data = Semantics.load_data()
	native_bounds = EnvironmentAssemblyContract._load_dictionary(EnvironmentAssemblyContract.NATIVE_BOUNDS_PATH)
	baselines = EnvironmentAssemblyContract._load_dictionary(BASELINE_PATH)
	var source: Dictionary = IndustrialModuleCatalog.create() if source_catalog.is_empty() else source_catalog
	catalog = {}
	for id in source:
		var original: EnvironmentModuleDefinition = source[id]
		var copy := EnvironmentModuleDefinition.new(original.component_id, original.family, original.size)
		for property in original.get_property_list():
			if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			var value = original.get(property.name)
			copy.set(property.name, value.duplicate(true) if value is Array or value is Dictionary else value)
		copy.connections.clear()
		for connection in original.connections: copy.connections.append(EnvironmentModuleConnection.new(connection.local_cell, connection.direction, connection.type, connection.elevation))
		catalog[id] = copy
	for id in Assets.all_ids(): _paths[Assets.path_for(id)] = str(id)

static func canonical(value) -> String:
	if value is Dictionary:
		var parts: Array[String] = []
		for key in value: parts.append(canonical(key) + ":" + canonical(value[key]))
		parts.sort()
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item in value: parts.append(canonical(item))
		return "[" + ",".join(parts) + "]"
	if value is Object:
		var properties := {}
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "validation_failures": properties[property.name] = value.get(property.name)
		return canonical(properties)
	return var_to_str(value)

static func fingerprint(value) -> String:
	return canonical(value).sha256_text()

func asset(id: String) -> Dictionary:
	if asset_cache.has(id): return asset_cache[id]
	asset_reads += 1
	var profile := Assets.profile(id, calibration_data)
	var payload := {"version": calibration_data.get("version", 0), "scale": float(profile.get("scale", 1.0)), "yaw_degrees": float(profile.get("yaw_degrees", 0.0)), "anchor": int(profile.get("anchor", 0)), "anchor_position": profile.get("anchor_position", [0.0, 0.0, 0.0]), "native_bounds": native_bounds.get(id, {})}
	var meaning := Semantics.effective(id, semantic_data)
	var path := Assets.path_for(id)
	var result := {"kind": "asset", "id": id, "path": path, "geometry_sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "", "calibration_signature": JSON.stringify(payload).sha256_text(), "semantic_signature": fingerprint(meaning), "generation_eligible": meaning.get("interpretation_source", "") == "confirmed" and meaning.get("generation_ready", false), "profile": profile.duplicate(true), "required_by": []}
	asset_cache[id] = result
	return result

func asset_dependency(id: String) -> Dictionary:
	var result := asset(id).duplicate(true)
	result.erase("profile")
	result.erase("path")
	return result

func module_dependency(id: StringName) -> Dictionary:
	if not module_cache.has(id):
		module_cache[id] = {"kind": "module", "id": str(id), "revision": fingerprint(catalog[id]) if catalog.has(id) else "", "required_by": []}
	return module_cache[id].duplicate(true)

func assembly_dependency(id: String) -> Dictionary:
	if assembly_cache.has(id): return assembly_cache[id].duplicate(true)
	if _buildings.is_empty(): _buildings = IndustrialBuildingCatalog.create()
	if _library.is_empty(): _library = InitialEnvironmentAssemblyLibrary.records(_buildings)
	var key := StringName(id)
	var valid := false
	var payload = null
	var legacy_signature := str(baselines.get("assemblies", {}).get(id, {}).get("legacy_signature", ""))
	var available := _library.has(key) or _buildings.has(key)
	if _library.has(key):
		var entry: Dictionary = _library[key]
		var contract: EnvironmentAssemblyContract = entry.contract
		valid = entry.technically_valid
		payload = {"contract": contract, "definition": entry.get("definition")}
	elif _buildings.has(key):
		payload = _buildings[key]
		valid = payload.validate().is_empty()
	var modules := {}
	for module_id in catalog:
		if str(catalog[module_id].structural_assembly_id) == id: modules[str(module_id)] = catalog[module_id]
	if _buildings.has(key):
		var building: EnvironmentBuildingDefinition = _buildings[key]
		if catalog.has(building.module.component_id): building.module = catalog[building.module.component_id]
		valid = building.validate().is_empty()
	if id == "pipe_receiver_unit":
		var transforms := {}
		for visual in catalog[&"factory_pipe_receiver_unit"].visuals:
			for component in visual.get("components", []): transforms[component.component_id] = component.transform
		valid = IndustrialEquipmentAssemblyCatalog.validate_contract(_library[key].contract).is_empty() and IndustrialEquipmentAssemblyCatalog.validate(transforms).is_empty()
		payload["sockets"] = [IndustrialEquipmentAssemblyCatalog.receiver_socket(), IndustrialEquipmentAssemblyCatalog.pipe_socket()]
	if id == "shipping_container_family":
		valid = InitialEnvironmentAssemblyLibrary.CargoAssembly.validate_contract(_library[key].contract).is_empty()
	if id == "certified_pipe_service_pad":
		for module_id in [&"paved_courtyard", &"factory_pipe_receiver_unit", &"cargo_container", &"yard_fence"]: modules[str(module_id)] = catalog[module_id]
	var revision := fingerprint({"source": payload, "modules": modules}) if available else ""
	var result := {"kind": "assembly", "id": id, "available": available, "valid": valid, "resolution": "certified_contract" if _library.has(key) else "building_definition", "certification_signature": revision, "legacy_signature": legacy_signature, "owner_visual_approval": false, "required_by": []}
	assembly_cache[id] = result
	return result.duplicate(true)

func _fail(code: String, id: String, message: String) -> void:
	errors.append({"code": code, "field": "dependencies", "reference": id, "message": message})

func check_baseline(kind: String, id: String, current: Dictionary) -> void:
	var expected: Dictionary = baselines.get(kind, {}).get(id, {})
	if expected.is_empty():
		_fail("UNREGISTERED_CONTENT_REVISION", id, "No frozen compatibility/approval baseline for %s" % id)
		return
	var fields := ["geometry_sha256", "calibration_signature", "semantic_signature"] if kind == "assets" else (["revision"] if kind == "modules" else ["certification_signature"])
	for field in fields:
		if str(current.get(field, "")).is_empty() or current.get(field) != expected.get(field): _fail("STALE_APPROVED_REVISION", id, "%s changed %s; technical validation cannot renew its eligibility" % [id, field])

func visuals(definition: EnvironmentModuleDefinition, variation: int) -> Array[Dictionary]:
	var key := "%s:%d" % [definition.component_id, variation]
	if visual_cache.has(key):
		for failure in visual_failures[key]:
			if failure not in errors: errors.append(failure)
		return visual_cache[key].duplicate(true)
	var first_error := errors.size()
	visual_resolutions += 1
	var result: Array[Dictionary] = []
	for source in definition.visuals:
		var visual: Dictionary = source.duplicate(true)
		if visual.get("kind", "asset") == "box":
			result.append(visual)
			continue
		if visual.get("kind", "asset") == "socket_assembly":
			for component in visual.components:
				var component_asset := asset(str(component.asset_id))
				check_baseline("assets", str(component.asset_id), component_asset)
				component["asset_path"] = component_asset.path
			result.append(visual)
			continue
		var id := ""
		var candidates: Array = visual.get("asset_ids", [])
		var path := str(visual.get("asset_path", ""))
		if not candidates.is_empty():
			var eligible: Array[String] = []
			for candidate in candidates:
				var candidate_asset := asset(str(candidate))
				check_baseline("assets", str(candidate), candidate_asset)
				if candidate_asset.generation_eligible: eligible.append(str(candidate))
			if eligible.is_empty():
				_fail("NO_ELIGIBLE_VISUAL", str(definition.component_id), "No eligible visual candidates")
				continue
			id = eligible[posmod(variation, eligible.size())]
		else:
			var variants: Array = visual.get("asset_variants", [])
			if not variants.is_empty(): path = str(variants[posmod(variation, variants.size())])
			id = str(_paths.get(path, ""))
		if id.is_empty():
			_fail("MISSING_ASSET_DEPENDENCY", path, "Visual path has no stable asset identity")
			continue
		var resolved := asset(id)
		check_baseline("assets", id, resolved)
		visual["asset_path"] = resolved.path
		visual["resolved_asset_id"] = id
		visual["saved_yaw"] = 0.0
		visual["saved_offset"] = Vector3.ZERO
		if not candidates.is_empty():
			visual["scale"] = float(resolved.profile.scale)
			visual["anchor"] = int(resolved.profile.anchor)
			visual.saved_yaw = deg_to_rad(float(resolved.profile.yaw_degrees))
			var offset: Array = resolved.profile.anchor_position
			visual.saved_offset = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		visual.erase("asset_variants")
		visual.erase("asset_ids")
		result.append(visual)
	visual_failures[key] = errors.slice(first_error)
	visual_cache[key] = result
	return result.duplicate(true)

func resolved_assets(definition: EnvironmentModuleDefinition, variation: int) -> Array[String]:
	var result: Array[String] = []
	for visual in visuals(definition, variation):
		if visual.has("resolved_asset_id") and visual.resolved_asset_id not in result: result.append(visual.resolved_asset_id)
		for component in visual.get("components", []):
			if str(component.asset_id) not in result: result.append(str(component.asset_id))
	return result

func resolve_layout(layout: EnvironmentModuleLayout) -> Array[Dictionary]:
	EnvironmentModulePlacement.ensure_identities(layout.placements)
	var result: Array[Dictionary] = []
	for placement in layout.placements:
		if not catalog.has(placement.component_id):
			_fail("MISSING_PLACEMENT_REFERENCE", str(placement.component_id), "Unknown module")
			continue
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		check_baseline("modules", str(placement.component_id), module_dependency(placement.component_id))
		if not definition.structural_assembly_id.is_empty():
			var assembly := assembly_dependency(str(definition.structural_assembly_id))
			if not assembly.valid: _fail("INVALID_ASSEMBLY_DEPENDENCY", str(definition.structural_assembly_id), "Substantive assembly validation failed")
			check_baseline("assemblies", str(definition.structural_assembly_id), assembly)
		result.append({"placement": placement.copy(), "definition": definition, "visuals": visuals(definition, placement.variation)})
	return result
