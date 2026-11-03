class_name ParcelPopulationRegion
extends RefCounted
## Authored parcel-local permission for bounded tactical population. This is
## placement intent only; accepted occupants still need explicit MapData rules.

var region_id: StringName
var role: StringName
var local_rect: Rect2i
var allowed_asset_ids: PackedStringArray
var min_count: int
var max_count: int

func validate(parcel_size: Vector2i) -> String:
	if region_id.is_empty() or role.is_empty():
		return "INVALID_POPULATION_IDENTITY"
	if local_rect.size.x <= 0 or local_rect.size.y <= 0 or local_rect.position.x < 0 or local_rect.position.y < 0 or local_rect.end.x > parcel_size.x or local_rect.end.y > parcel_size.y:
		return "POPULATION_REGION_OUT_OF_BOUNDS"
	if allowed_asset_ids.is_empty():
		return "EMPTY_POPULATION_ALLOW_LIST"
	if min_count < 0 or max_count < min_count:
		return "INVALID_POPULATION_COUNT"
	return ""
