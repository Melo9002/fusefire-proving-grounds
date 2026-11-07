class_name ParcelSlotContract
extends RefCounted
## Shared exact compatibility check between one authored plot slot and one
## registered parcel. Selection policy remains owned by each bounded family.

static func validate(slot: Dictionary, parcel, offered: ParcelConnection = null) -> String:
	if parcel == null or parcel.role != slot.role or parcel.size != slot.size:
		return "INCOMPATIBLE_PARCEL_ROLE_OR_SIZE"
	if not parcel.allowed_rotations().has(int(slot.rotation)):
		return "UNSUPPORTED_PARCEL_ROTATION"
	if offered == null:
		offered = parcel.connection()
	var required: Dictionary = slot.required_interface
	if offered == null or offered.kind != StringName(required.kind) or offered.width != int(required.width):
		return "INCOMPATIBLE_PARCEL_INTERFACE"
	if offered.world_cell(parcel.size, slot.origin, slot.rotation) != required.cell:
		return "MISALIGNED_PARCEL_INTERFACE"
	if offered.world_outward(slot.rotation) != required.outward:
		return "MISORIENTED_PARCEL_INTERFACE"
	return ""

static func validate_plot_footprints(plot: Dictionary) -> Dictionary:
	var bounds := Rect2i(Vector2i.ZERO, plot.map_size)
	var footprints := {}
	for slot: Dictionary in plot.slots:
		var slot_id: StringName = slot.slot_id
		var footprint := Rect2i(Vector2i(slot.origin.x, slot.origin.z), ParcelTransform.rotated_size(slot.size, slot.rotation))
		if slot_id.is_empty() or footprints.has(slot_id):
			return {"code": "INVALID_PLOT_SLOT_ID", "detail": "%s/%s" % [plot.plot_id, slot_id]}
		if not bounds.encloses(footprint):
			return {"code": "SLOT_OUTSIDE_PLOT", "detail": "%s/%s %s" % [plot.plot_id, slot_id, footprint]}
		for other_id in footprints:
			if footprint.intersects(footprints[other_id]):
				return {"code": "OVERLAPPING_PLOT_SLOTS", "detail": "%s/%s overlaps %s" % [plot.plot_id, slot_id, other_id]}
		for road: Rect2i in plot.get("road_rects", []):
			if footprint.intersects(road):
				return {"code": "SLOT_OVERLAPS_ROAD", "detail": "%s/%s overlaps %s" % [plot.plot_id, slot_id, road]}
		footprints[slot_id] = footprint
	return {}

static func validate_approach(plot: Dictionary, slot: Dictionary, connection: ParcelConnection) -> Dictionary:
	var bounds := Rect2i(Vector2i.ZERO, plot.map_size)
	var circulation: Array = plot.get("road_rects", []) + plot.get("circulation_rects", [])
	var external := bool(slot.required_interface.get("external", false))
	var outward := connection.world_outward(slot.rotation)
	for inside in connection.world_span(slot.size, slot.origin, slot.rotation):
		var approach := Vector2i(inside.x, inside.z) + outward
		var inside_plot := bounds.has_point(approach)
		var supported := not inside_plot if external else inside_plot and circulation.any(func(rect: Rect2i): return rect.has_point(approach))
		if not supported:
			return {"code": "MISSING_INTERFACE_APPROACH", "detail": "%s/%s at %s faces %s" % [plot.plot_id, slot.slot_id, inside, approach]}
	return {}

## A same-elevation cardinal seam is traversable under the existing grid rules
## when both stopping cells are present. External seams end at the playable edge.
static func validate_compiled_span(data: MapData, slot_path: String, span: Array[Vector3i], outward: Vector2i) -> Dictionary:
	var bounds := Rect2i(Vector2i.ZERO, data.map_size)
	for inside in span:
		if not _is_stopping_cell(data, inside):
			return {"code": "BLOCKED_PARCEL_INTERFACE", "detail": "%s at %s" % [slot_path, inside]}
		var approach := inside + Vector3i(outward.x, 0, outward.y)
		if bounds.has_point(Vector2i(approach.x, approach.z)) and not _is_stopping_cell(data, approach):
			return {"code": "BLOCKED_INTERFACE_APPROACH", "detail": "%s at %s" % [slot_path, approach]}
	return {}

static func _is_stopping_cell(data: MapData, position: Vector3i) -> bool:
	var cell := data.get_cell(position)
	return cell != null and cell.walkable and cell.can_stop
