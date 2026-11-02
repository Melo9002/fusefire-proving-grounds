class_name RefineryPlotResolver
extends RefCounted
## Resolves one bounded authored plot before battle activation. The returned
## placements are durable choices; replay must not rely on the seed alone.

const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")

static func resolve(seed: int, population_enabled: bool = true, requested: Dictionary = {}) -> Dictionary:
	var plot := _resolve_plot(seed, requested)
	if plot.is_empty():
		return _failure(seed, population_enabled, "UNKNOWN_PLOT", String(requested.get("plot_id", "")))
	var result := {"schema": 1, "plot_id": plot.plot_id, "plot_revision": plot.revision, "map_size": plot.map_size, "seed": seed, "population_enabled": population_enabled, "placements": [], "errors": []}
	if int(requested.get("plot_revision", plot.revision)) != int(plot.revision):
		result.errors.append(_error("STALE_PLOT_REVISION", String(plot.plot_id)))
		return result
	if not population_enabled:
		return result
	var requested_placements: Dictionary = {}
	for placement in requested.get("placements", []):
		requested_placements[StringName(placement.get("slot_id", &""))] = placement
	for slot: Dictionary in plot.slots:
		var parcel = _parcel_for_slot(slot, seed, requested_placements.get(slot.slot_id, {}))
		if parcel == null:
			result.errors.append(_error("MISSING_COMPATIBLE_PARCEL", String(slot.slot_id)))
			continue
		var validation := _validate_slot(slot, parcel)
		if not validation.is_empty():
			result.errors.append(_error(validation, "%s/%s" % [plot.plot_id, slot.slot_id]))
			continue
		result.placements.append({"slot_id": slot.slot_id, "parcel_id": parcel.parcel_id, "parcel_revision": parcel.revision, "origin": slot.origin, "rotation": slot.rotation})
	return result

static func is_valid(resolved: Dictionary) -> bool:
	return resolved.has("errors") and resolved.errors.is_empty()

static func _resolve_plot(seed: int, requested: Dictionary) -> Dictionary:
	return PlotCatalog.get_definition(StringName(requested.plot_id)) if requested.has("plot_id") else PlotCatalog.choose(seed)

static func _parcel_for_slot(slot: Dictionary, seed: int, requested: Dictionary):
	if not requested.is_empty():
		var parcel = ParcelCatalog.get_definition(StringName(requested.get("parcel_id", &"")))
		if parcel == null or parcel.revision != int(requested.get("parcel_revision", 0)):
			return null
		return parcel
	if slot.role == ParcelCatalog.LOADING_SERVICE:
		# Plot identity and content variation use different seed bits.
		return ParcelCatalog.choose(slot.role, slot.size, floori(seed / 2.0))
	var candidates := ParcelCatalog.candidates(slot.role, slot.size)
	return candidates[0] if not candidates.is_empty() else null

static func _validate_slot(slot: Dictionary, parcel) -> String:
	if parcel.role != slot.role or parcel.size != slot.size:
		return "INCOMPATIBLE_PARCEL_ROLE_OR_SIZE"
	if not parcel.allowed_rotations().has(int(slot.rotation)):
		return "UNSUPPORTED_PARCEL_ROTATION"
	var offered = parcel.connection()
	var required: Dictionary = slot.required_interface
	if offered == null or offered.kind != StringName(required.kind) or offered.width != int(required.width):
		return "INCOMPATIBLE_SERVICE_INTERFACE"
	if offered.world_cell(parcel.size, slot.origin, slot.rotation) != required.cell:
		return "MISALIGNED_SERVICE_INTERFACE"
	if offered.world_outward(slot.rotation) != required.outward:
		return "MISORIENTED_SERVICE_INTERFACE"
	return ""

static func _failure(seed: int, population_enabled: bool, code: String, detail: String) -> Dictionary:
	return {"schema": 1, "seed": seed, "population_enabled": population_enabled, "placements": [], "errors": [_error(code, detail)]}

static func _error(code: String, detail: String) -> Dictionary:
	return {"code": code, "detail": detail}
