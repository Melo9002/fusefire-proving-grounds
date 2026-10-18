class_name AssetPlacementConventions
extends RefCounted
## Planning metadata derived from verified visual calibration. None of these
## records mutate MapData; authored modules remain tactical authority.

const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const BOUNDS_PATH := "res://tools/asset_lab/native_bounds.json"

const AUTHORED_FOOTPRINTS := {
	"city_kit_roads/road-straight": [10, 10],
	"city_kit_roads/road-curve": [20, 20],
	"city_kit_roads/road-intersection": [10, 10],
	"city_kit_roads/road-crossroad": [10, 10],
	"city_kit_roads/road-slant": [10, 10],
	"city_kit_roads/tile-low": [10, 10],
	"factory_kit/structure-wall": [4, 1],
	"factory_kit/structure-corner-inner": [2, 2],
	"factory_kit/structure-corner-outer": [2, 2],
	"factory_kit/structure-doorway-wide": [4, 1],
	"factory_kit/structure-window-wide": [4, 1],
	"factory_kit/machine": [2, 2],
	"factory_kit/machine-fortified": [2, 2],
	"factory_kit/catwalk-stairs": [4, 3],
	"factory_kit/catwalk-straight": [2, 6],
	"city_kit_industrial/shipping-container-a": [2, 5],
	"city_kit_industrial/shipping-container-b": [2, 5],
	"city_kit_industrial/shipping-container-c": [2, 5],
	"city_kit_roads/construction-barrier": [1, 1],
}

static func load_bounds(path := BOUNDS_PATH) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func record(id: String, calibration_data := {}, bounds_data := {}) -> Dictionary:
	if calibration_data.is_empty(): calibration_data = Catalog.load_calibrations()
	if bounds_data.is_empty(): bounds_data = load_bounds()
	var profile := Catalog.profile(id, calibration_data)
	var native := Vector3.ZERO
	if bounds_data.has(id):
		var values: Array = bounds_data[id].size
		native = Vector3(float(values[0]), float(values[1]), float(values[2]))
	var calibrated := _rotated_size(native * float(profile.scale), deg_to_rad(float(profile.yaw_degrees)))
	var envelope := Vector2i(maxi(1, ceili(calibrated.x - 0.0001)), maxi(1, ceili(calibrated.z - 0.0001)))
	var authored: Array = AUTHORED_FOOTPRINTS.get(id, [])
	var tactical_policy := "none_decorative"
	if not authored.is_empty(): tactical_policy = "authored_component"
	elif profile.classification == "tactical_obstacle": tactical_policy = "author_before_gameplay"
	elif profile.classification in ["structural", "ground", "entrance"]: tactical_policy = "module_definition_required"
	return {
		"id": id,
		"semantic_category": profile.semantic_category,
		"classification": profile.classification,
		"calibrated_size": [calibrated.x, calibrated.y, calibrated.z],
		"visual_envelope_cells": [envelope.x, envelope.y],
		"authored_tactical_footprint": authored,
		"tactical_policy": tactical_policy,
		"origin_snap": _origin_snap(id),
		"assembly_pitch": _assembly_pitch(id),
		"allowed_yaw_degrees": [0, 90, 180, 270],
		"anchor": profile.anchor,
		"note": _note(id, tactical_policy),
	}

static func _rotated_size(size: Vector3, yaw: float) -> Vector3:
	var cosine := absf(cos(yaw))
	var sine := absf(sin(yaw))
	return Vector3(size.x * cosine + size.z * sine, size.y, size.x * sine + size.z * cosine)

static func _origin_snap(id: String) -> Array:
	if id.begins_with("city_kit_roads/"): return [1.0, 1.0]
	if id.begins_with("factory_kit/"): return [1.0, 1.0]
	if id.begins_with("modular_space_kit/"): return [1.0, 1.0]
	return [0.5, 0.5]

static func _assembly_pitch(id: String) -> Array:
	var semantic := Catalog.semantic_category(id)
	if semantic in ["road_modules", "paving_tiles"]: return [10.0, 10.0]
	if semantic in ["factory_structure_modules", "factory_entrances"]: return [2.0, 2.0]
	if id.begins_with("modular_space_kit/"): return [8.0, 8.0]
	return [0.0, 0.0]

static func _note(id: String, policy: String) -> String:
	if id.begins_with("factory_kit/"):
		return "Integer visual anchors preserve the calibrated 2-unit Factory bay rhythm."
	if id.begins_with("city_kit_roads/"):
		return "Road origins stay on integer cells; compatible road tiles connect on the 10-unit pitch."
	if id.begins_with("modular_space_kit/"):
		return "Space Kit uses a separate 8-unit construction pitch; do not mix it with Factory bays automatically."
	if policy == "author_before_gameplay":
		return "Visual envelope is a reservation aid only; author solid cells, cover and clearance separately."
	return "Presentation placement only; no tactical footprint is implied."
