class_name EnvironmentAssemblyContract
extends RefCounted
## A compact certification record that binds one reusable environment assembly
## to its imported geometry, resolved calibration and authored spatial rules.
## Tactical behavior remains in EnvironmentModuleDefinition/MapData.

const AssetCatalog = preload("res://tools/asset_lab/asset_catalog.gd")
const SemanticCatalog = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const NATIVE_BOUNDS_PATH := "res://tools/asset_lab/native_bounds.json"

enum AssemblyRole {
	SEALED_BUILDING_SHELL,
	OPEN_SHELTER,
	MODULAR_STRUCTURE,
	EQUIPMENT_PARCEL,
	TACTICAL_OBSTACLE_FAMILY,
}

enum Completeness {
	COMPLETE_EXTERIOR,
	INTENTIONALLY_OPEN,
	INCOMPLETE,
	COMPLETE_OBJECT,
}

enum CertificationState {
	UNCERTIFIED,
	CERTIFIED,
}

var assembly_id: StringName
var role := AssemblyRole.SEALED_BUILDING_SHELL
var completeness := Completeness.INCOMPLETE
var components: Array[Dictionary] = []
var tactical_footprint: Array[Vector2i] = []
var approved_visual_envelope := AABB()
var required_clearance_cells: Array[Vector2i] = []
var relationships: Dictionary = {}
var supported_rotations: Array[int] = []
var certification_state := CertificationState.UNCERTIFIED
var validation_failures := PackedStringArray()

func _init(id: StringName = &"") -> void:
	assembly_id = id

func validate(building, semantic_data := {}) -> PackedStringArray:
	validation_failures = PackedStringArray()
	if building == null or building.module == null:
		_fail("MISSING_MODULE", "assembly has no building module")
		return validation_failures
	if assembly_id != building.assembly_id:
		_fail("ASSEMBLY_ID_MISMATCH", "contract %s is attached to %s" % [assembly_id, building.assembly_id])
	if components.is_empty():
		_fail("MISSING_REQUIRED_ASSET", "assembly has no imported components")
	for component in components:
		_validate_component(component, building, semantic_data)
	if completeness == Completeness.COMPLETE_EXTERIOR and building.enclosure != building.Enclosure.PREBUILT_SHELL:
		_fail("UNSUPPORTED_COMPLETENESS", "complete exterior must use the prebuilt-shell enclosure contract")
	if tactical_footprint != building.module.footprint_cells:
		_fail("TACTICAL_FOOTPRINT_MISMATCH", "contract footprint differs from the explicitly authored module footprint")
	if not approved_visual_envelope.is_equal_approx(building.module.visual_envelope):
		_fail("VISUAL_ENVELOPE_MISMATCH", "approved envelope %s differs from module envelope %s" % [approved_visual_envelope, building.module.visual_envelope])
	if not _same_cells(required_clearance_cells, building.module.clearance_cells):
		_fail("INVALID_CLEARANCE", "required clearance differs from the module's protected cells")
	_validate_frontage(building)
	for rotation in supported_rotations:
		if rotation < 0 or rotation > 3 or rotation not in building.module.allowed_rotations:
			_fail("UNSUPPORTED_ROTATION", "rotation %d is not supported by the module" % rotation)
	if supported_rotations.is_empty():
		_fail("UNSUPPORTED_ROTATION", "assembly has no supported orientation")
	return validation_failures

func is_certified(building, semantic_data := {}) -> bool:
	return certification_state == CertificationState.CERTIFIED and validate(building, semantic_data).is_empty()

func duplicate_contract() -> EnvironmentAssemblyContract:
	var copy := EnvironmentAssemblyContract.new(assembly_id)
	copy.role = role
	copy.completeness = completeness
	copy.components = components.duplicate(true)
	copy.tactical_footprint.assign(tactical_footprint)
	copy.approved_visual_envelope = approved_visual_envelope
	copy.required_clearance_cells.assign(required_clearance_cells)
	copy.relationships = relationships.duplicate(true)
	copy.supported_rotations.assign(supported_rotations)
	copy.certification_state = certification_state
	return copy

static func current_geometry_sha256(asset_id: String) -> String:
	var path := AssetCatalog.path_for(asset_id)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)

static func current_calibration_signature(asset_id: String) -> String:
	var calibration := AssetCatalog.profile(asset_id)
	var native_data := _load_dictionary(NATIVE_BOUNDS_PATH)
	var payload := {
		"version": AssetCatalog.load_calibrations().get("version", 0),
		"scale": float(calibration.get("scale", 1.0)),
		"yaw_degrees": float(calibration.get("yaw_degrees", 0.0)),
		"anchor": int(calibration.get("anchor", 0)),
		"anchor_position": calibration.get("anchor_position", [0.0, 0.0, 0.0]),
		"native_bounds": native_data.get(asset_id, {}),
	}
	return JSON.stringify(payload).sha256_text()

func _validate_component(component: Dictionary, building, semantic_data: Dictionary) -> void:
	var asset_id := str(component.get("asset_id", ""))
	if asset_id.is_empty():
		if bool(component.get("required", true)):
			_fail("MISSING_REQUIRED_ASSET", "required component has no stable asset ID")
		return
	var asset_path := AssetCatalog.path_for(asset_id)
	if not FileAccess.file_exists(asset_path):
		if bool(component.get("required", true)):
			_fail("MISSING_REQUIRED_ASSET", "%s does not resolve to an imported asset" % asset_id)
		return
	if asset_id not in building.source_assets:
		_fail("MISSING_REQUIRED_ASSET", "%s is not included by the building definition" % asset_id)
	var expected_geometry := str(component.get("geometry_sha256", ""))
	var actual_geometry := current_geometry_sha256(asset_id)
	if expected_geometry.is_empty() or expected_geometry != actual_geometry:
		_fail("STALE_GEOMETRY_DEPENDENCY", "%s geometry dependency expected %s, got %s" % [asset_id, expected_geometry, actual_geometry])
	var expected_calibration := str(component.get("calibration_signature", ""))
	var actual_calibration := current_calibration_signature(asset_id)
	if expected_calibration.is_empty() or expected_calibration != actual_calibration:
		_fail("STALE_CALIBRATION_DEPENDENCY", "%s calibration dependency expected %s, got %s" % [asset_id, expected_calibration, actual_calibration])
	var meaning := SemanticCatalog.effective(asset_id, semantic_data)
	var source_face := str(component.get("source_working_face", "unknown"))
	if source_face not in meaning.get("working_faces", []):
		_fail("FRONTAGE_MISMATCH", "%s pinned working face %s is not supported by reviewed geometry semantics %s" % [asset_id, source_face, meaning.get("working_faces", [])])
	if completeness == Completeness.COMPLETE_EXTERIOR:
		if meaning.get("interpretation_source", "") != "confirmed" or meaning.get("asset_kind", "") != "complete_building" or meaning.get("completeness", "") != "complete":
			_fail("UNSUPPORTED_COMPLETENESS", "%s is not confirmed as a complete exterior building" % asset_id)
	var matching_visuals: Array[Dictionary] = []
	for visual: Dictionary in building.module.visuals:
		if asset_id in visual.get("asset_ids", []):
			matching_visuals.append(visual)
	if matching_visuals.size() != 1:
		_fail("COMPONENT_TRANSFORM_MISMATCH", "%s must resolve to exactly one authored module visual" % asset_id)
		return
	var visual := matching_visuals[0]
	var local_cell: Vector2 = visual.get("local_cell", Vector2.ZERO)
	var offset: Vector3 = visual.get("offset", Vector3.ZERO)
	var actual_position := Vector3(local_cell.x, 0.0, local_cell.y) + offset
	if not actual_position.is_equal_approx(component.get("local_position", Vector3.ZERO)) or int(visual.get("yaw_quarters", 0)) != int(component.get("yaw_quarters", 0)):
		_fail("COMPONENT_TRANSFORM_MISMATCH", "%s module transform does not match the certified local transform" % asset_id)

func _validate_frontage(building) -> void:
	var frontage: Dictionary = relationships.get("street_frontage", {})
	if frontage.is_empty():
		_fail("FRONTAGE_MISMATCH", "assembly has no named street frontage")
		return
	var direction: Vector2i = frontage.get("direction", Vector2i.ZERO)
	if direction not in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		_fail("FRONTAGE_MISMATCH", "street frontage direction %s is invalid" % direction)
	var access_cells: Array = frontage.get("access_cells", [])
	if access_cells.is_empty():
		_fail("INVALID_CLEARANCE", "street frontage has no exterior access region")
	for cell in access_cells:
		if cell not in required_clearance_cells:
			_fail("INVALID_CLEARANCE", "frontage access cell %s is outside protected clearance" % cell)
	for component in components:
		if str(component.get("role", "")) != "shell":
			continue
		var source_face := str(component.get("source_working_face", "unknown"))
		var normalized := _rotate_face(_face_direction(source_face), int(component.get("yaw_quarters", 0)))
		if normalized != direction:
			_fail("FRONTAGE_MISMATCH", "%s normalized face %s does not match authored frontage %s" % [component.get("asset_id", ""), normalized, direction])
		return
	_fail("FRONTAGE_MISMATCH", "street frontage has no structural shell component")

func _fail(code: String, detail: String) -> void:
	validation_failures.append("%s: %s" % [code, detail])

static func _face_direction(face: String) -> Vector2i:
	match face.to_lower():
		"+x": return Vector2i.RIGHT
		"-x": return Vector2i.LEFT
		"+z": return Vector2i.DOWN
		"-z": return Vector2i.UP
		_: return Vector2i.ZERO

static func _rotate_face(direction: Vector2i, quarter_turns: int) -> Vector2i:
	match posmod(quarter_turns, 4):
		1: return Vector2i(-direction.y, direction.x)
		2: return Vector2i(-direction.x, -direction.y)
		3: return Vector2i(direction.y, -direction.x)
		_: return direction

static func _same_cells(first: Array[Vector2i], second: Array[Vector2i]) -> bool:
	if first.size() != second.size():
		return false
	for cell in first:
		if cell not in second:
			return false
	return true

static func _load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
