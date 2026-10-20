class_name IndustrialBuildingPlacementProfiles
extends RefCounted
## Reviewed placement contracts for the monolithic City Kit Industrial shells.
##
## Dimensions are calibrated world-space bounds rounded outward to tactical
## cells.  Every shell is exterior-only: the footprint is a conservative solid
## obstacle and the facade apron is placement clearance, not an entrance or an
## implied playable interior.  All profiles normalize their reviewed working
## face to the module-local +Z frontage used by coherent parcels.

const PROFILES := {
	"a": {"bounds": Vector3(20.8359, 14.70, 12.4201), "face": "-z"},
	"b": {"bounds": Vector3(20.8359, 14.70, 12.6201), "face": "-z"},
	"c": {"bounds": Vector3(18.76, 12.50, 21.08), "face": "-z"},
	"d": {"bounds": Vector3(8.84, 14.15, 14.20), "face": "-z"},
	"e": {"bounds": Vector3(16.84, 16.50, 12.90), "face": "-z"},
	"f": {"bounds": Vector3(17.90, 19.25, 12.80), "face": "-z"},
	"g": {"bounds": Vector3(16.78, 12.80, 12.84), "face": "+z"},
	"h": {"bounds": Vector3(13.22, 7.34, 13.10), "face": "-z"},
	"i": {"bounds": Vector3(10.28, 7.34, 13.00), "face": "-z"},
	"j": {"bounds": Vector3(10.27, 8.61, 13.00), "face": "-z"},
	"k": {"bounds": Vector3(13.03, 7.73, 9.14), "face": "-z"},
	"l": {"bounds": Vector3(20.84, 19.25, 18.70), "face": "-z"},
	"m": {"bounds": Vector3(13.16, 15.19, 17.00), "face": "+z"},
	"n": {"bounds": Vector3(9.77, 19.05, 14.20), "face": "-z"},
	"o": {"bounds": Vector3(8.84, 9.18, 12.40), "face": "-z"},
	"p": {"bounds": Vector3(16.84, 7.15, 9.92), "face": "-z"},
	"q": {"bounds": Vector3(21.40, 8.80, 17.70), "face": "-z"},
	"r": {"bounds": Vector3(24.84, 13.93, 12.72), "face": "-z"},
	"s": {"bounds": Vector3(21.20, 8.37, 9.16), "face": "-z"},
	"t": {"bounds": Vector3(17.22, 10.15, 13.90), "face": "-z"},
}

const FRONTAGE_DEPTH := 3
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")

static func ids() -> Array[String]:
	var result: Array[String] = []
	for suffix in PROFILES:
		result.append("city_kit_industrial/building-%s" % suffix)
	result.sort()
	return result

static func profile_for_asset(asset_id: String) -> Dictionary:
	var suffix := asset_id.trim_prefix("city_kit_industrial/building-")
	var result := (PROFILES.get(suffix, {}) as Dictionary).duplicate(true)
	if result.has("bounds"):
		var bounds: Vector3 = result.bounds
		result["size"] = Vector2i(ceili(bounds.x), ceili(bounds.z))
	return result

static func module_id_for_asset(asset_id: String) -> StringName:
	return StringName("industrial_shell_%s" % asset_id.get_file().trim_prefix("building-"))

static func fitting_module_ids(parcel_size: Vector2i, environment_id: StringName = &"industrial_district", frontage_depth := FRONTAGE_DEPTH) -> Array[StringName]:
	var result: Array[StringName] = []
	var semantic_data := Semantics.load_data()
	var required_context := _semantic_context(environment_id)
	for asset_id in ids():
		var profile := profile_for_asset(asset_id)
		var size: Vector2i = profile.size
		var meaning := Semantics.effective(asset_id, semantic_data)
		var confirmed: bool = meaning.get("interpretation_source", "") == "confirmed"
		var usable: bool = confirmed and bool(meaning.get("generation_ready", false)) \
			and meaning.get("asset_kind", "") == "complete_building" \
			and meaning.get("completeness", "") == "complete" \
			and required_context in meaning.get("contexts", []) \
			and not meaning.get("working_faces", []).is_empty()
		if usable and size.x <= parcel_size.x - 2 and size.y + frontage_depth <= parcel_size.y:
			result.append(module_id_for_asset(asset_id))
	return result

static func _semantic_context(environment_id: StringName) -> String:
	match environment_id:
		&"commercial_street": return "commercial"
		&"mixed_service": return "mixed_service"
		_: return "industrial"

static func asset_id_for_module(module_id: StringName) -> String:
	return "city_kit_industrial/building-%s" % String(module_id).trim_prefix("industrial_shell_")

