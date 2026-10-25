class_name IndustrialCargoAssemblyCatalog
extends RefCounted
## Certification for the three interchangeable City Industrial shipping
## containers. They are complete standalone obstacles, not socket assemblies.

const SemanticCatalog = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const ASSEMBLY_ID := &"shipping_container_family"
const ASSET_IDS: Array[String] = [
	"city_kit_industrial/shipping-container-a",
	"city_kit_industrial/shipping-container-b",
	"city_kit_industrial/shipping-container-c",
]
const SUPPORTED_CONTEXTS := [&"industrial_district", &"commercial_street", &"mixed_service"]
const APPROVED_ENVELOPE := AABB(Vector3(-0.15, 0.0, -0.15), Vector3(2.3, 2.0, 5.3))

static func module() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"cargo_container", &"industrial_cargo", Vector2i(2, 5))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.PROP)
	item.set_visual_convention(Vector2(0.5, 0.5), Vector2.ZERO, "Certified calibrated container variants share one complete-object placement contract.")
	for cell in item.footprint_cells:
		item.set_effect(cell, {"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED, "cover_type": MapCellData.CoverType.FULL, "cover_height": 1.74, "walkable": false, "can_stop": false, "blocks_los": true, "movement_cost": 1})
	item.set_visual_envelope(APPROVED_ENVELOPE)
	item.structural_assembly_id = ASSEMBLY_ID
	item.architectural_purpose = &"cargo_storage"
	item.assembly_enclosure = &"complete_standalone_object"
	item.assembly_complete = true
	item.assembly_notes = "Three reviewed imported variants; no artificial sockets or inferred tactical geometry."
	item.add_catalog_visual(ASSET_IDS, Vector2(0.5, 2.0), 0, Vector3.ZERO, &"tactical_obstacle")
	return item

static func contract() -> EnvironmentAssemblyContract:
	var result := EnvironmentAssemblyContract.new(ASSEMBLY_ID)
	result.role = EnvironmentAssemblyContract.AssemblyRole.TACTICAL_OBSTACLE_FAMILY
	result.completeness = EnvironmentAssemblyContract.Completeness.COMPLETE_OBJECT
	for asset_id in ASSET_IDS:
		result.components.append({
			"asset_id": asset_id,
			"role": "variant",
			"required": true,
			"source_working_face": "+z",
			"local_position": Vector3(0.5, 0.0, 2.0),
			"yaw_quarters": 0,
			"geometry_sha256": EnvironmentAssemblyContract.current_geometry_sha256(asset_id),
			"calibration_signature": EnvironmentAssemblyContract.current_calibration_signature(asset_id),
		})
	result.tactical_footprint.assign(module().footprint_cells)
	result.approved_visual_envelope = APPROVED_ENVELOPE
	result.relationships = {"attachment": "ground", "contexts": SUPPORTED_CONTEXTS.duplicate(), "variant_policy": "deterministic_seeded_choice"}
	result.supported_rotations = [0, 1, 2, 3]
	result.certification_state = EnvironmentAssemblyContract.CertificationState.CERTIFIED
	return result

static func validate_contract(value: EnvironmentAssemblyContract, semantic_data := {}) -> PackedStringArray:
	var failures := PackedStringArray()
	if value.assembly_id != ASSEMBLY_ID: failures.append("ASSEMBLY_ID_MISMATCH")
	if value.role != EnvironmentAssemblyContract.AssemblyRole.TACTICAL_OBSTACLE_FAMILY: failures.append("ROLE_MISMATCH")
	if value.completeness != EnvironmentAssemblyContract.Completeness.COMPLETE_OBJECT: failures.append("UNSUPPORTED_COMPLETENESS")
	if value.supported_rotations != [0, 1, 2, 3]: failures.append("UNSUPPORTED_ROTATION")
	if value.components.size() != ASSET_IDS.size(): failures.append("MISSING_REQUIRED_COMPONENT")
	var seen: Array[String] = []
	for component in value.components:
		var asset_id := str(component.get("asset_id", ""))
		if asset_id not in ASSET_IDS or asset_id in seen:
			failures.append("INVALID_VARIANT:%s" % asset_id)
			continue
		seen.append(asset_id)
		if component.get("geometry_sha256", "") != EnvironmentAssemblyContract.current_geometry_sha256(asset_id): failures.append("STALE_GEOMETRY_DEPENDENCY:%s" % asset_id)
		if component.get("calibration_signature", "") != EnvironmentAssemblyContract.current_calibration_signature(asset_id): failures.append("STALE_CALIBRATION_DEPENDENCY:%s" % asset_id)
		var meaning := SemanticCatalog.effective(asset_id, semantic_data)
		if meaning.get("interpretation_source", "") != "confirmed" or meaning.get("asset_kind", "") != "tactical_obstacle" or meaning.get("completeness", "") != "complete": failures.append("UNSUPPORTED_SEMANTICS:%s" % asset_id)
		if "+z" not in meaning.get("working_faces", []): failures.append("WORKING_FACE_MISMATCH:%s" % asset_id)
		if not bool(meaning.get("generation_ready", false)): failures.append("NOT_PROCEDURALLY_APPROVED:%s" % asset_id)
	var definition := module()
	if value.tactical_footprint != definition.footprint_cells: failures.append("TACTICAL_FOOTPRINT_MISMATCH")
	if not value.approved_visual_envelope.is_equal_approx(definition.visual_envelope): failures.append("VISUAL_ENVELOPE_MISMATCH")
	if definition.visuals.size() != 1 or definition.visuals[0].get("asset_ids", []) != ASSET_IDS: failures.append("CATALOG_VISUAL_MISMATCH")
	for cell in definition.footprint_cells:
		var effect: Dictionary = definition.cell_effects.get(cell, {})
		if bool(effect.get("walkable", true)) or not bool(effect.get("blocks_los", false)) or effect.get("cover_type", MapCellData.CoverType.NONE) != MapCellData.CoverType.FULL:
			failures.append("TACTICAL_CONTRACT_MISMATCH:%s" % cell)
			break
	return failures

static func certification_signature() -> String:
	var parts: Array[String] = [String(ASSEMBLY_ID), str(EnvironmentAssemblyContract.AssemblyRole.TACTICAL_OBSTACLE_FAMILY), str(EnvironmentAssemblyContract.Completeness.COMPLETE_OBJECT)]
	for component in contract().components:
		parts.append("%s:%s:%s" % [component.asset_id, component.geometry_sha256, component.calibration_signature])
	return "|".join(parts).sha256_text()
