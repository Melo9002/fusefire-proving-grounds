class_name AuthoredParcelCatalog
extends RefCounted
## Explicit shortlist of reviewed parcels. No directory or semantic scan occurs
## during battle initialization.

const Definition = preload("res://systems/generation/authored_parcel_definition.gd")
const LOADING_YARD_A := &"loading_yard_a"
const LOADING_YARD_B := &"loading_yard_b"
const PROCESS_PAD_A := &"process_pad_a"
const TANK_STORAGE_A := &"tank_storage_a"
const MAINTENANCE_GALLERY_A := &"maintenance_gallery_a"
const INDUSTRIAL_OFFICE_PARKING_A := &"industrial_office_parking_a"
const SIGNAL_COURTYARD_A := &"signal_courtyard_a"
const COURTYARD_GALLERY_A := &"courtyard_gallery_a"
const PARKING_GARAGE_A := &"parking_garage_a"
const LOADING_SERVICE := &"loading_service"
const PROCESS := &"process"
const STORAGE := &"storage"
const ELEVATED_PROCESS := &"elevated_process"
const URBAN_FRONTAGE := &"urban_frontage"
const URBAN_COURTYARD := &"urban_courtyard"
const URBAN_GALLERY := &"urban_gallery"
const PARKING_GARAGE := &"parking_garage"

const LoadingYardA = preload("res://art/environments/authored/parcels/loading_yard.tscn")
const LoadingYardB = preload("res://art/environments/authored/parcels/loading_yard_alt.tscn")
const ProcessPadA = preload("res://art/environments/authored/parcels/process_pad.tscn")
const TankStorageA = preload("res://art/environments/authored/parcels/tank_storage.tscn")
const MaintenanceGalleryA = preload("res://art/environments/authored/parcels/maintenance_gallery.tscn")
const IndustrialOfficeParkingA = preload("res://art/environments/authored/parcels/industrial_office_parking.tscn")
const SignalCourtyardA = preload("res://art/environments/authored/parcels/signal_courtyard.tscn")
const CourtyardGalleryA = preload("res://art/environments/authored/parcels/courtyard_gallery.tscn")
const ParkingGarageA = preload("res://art/environments/authored/parcels/parking_garage.tscn")

static func all() -> Array:
	return [
		Definition.new(LOADING_YARD_A, "Warehouse loading apron", LOADING_SERVICE, 2, Vector2i(16, 32), LoadingYardA),
		Definition.new(LOADING_YARD_B, "Container service apron", LOADING_SERVICE, 2, Vector2i(16, 32), LoadingYardB),
		Definition.new(PROCESS_PAD_A, "Factory process pad", PROCESS, 1, Vector2i(16, 16), ProcessPadA),
		Definition.new(TANK_STORAGE_A, "Tank storage pad", STORAGE, 1, Vector2i(16, 16), TankStorageA),
		Definition.new(MAINTENANCE_GALLERY_A, "Elevated maintenance gallery", ELEVATED_PROCESS, 1, Vector2i(16, 32), MaintenanceGalleryA),
		Definition.new(INDUSTRIAL_OFFICE_PARKING_A, "Industrial office and visitor parking", URBAN_FRONTAGE, 1, Vector2i(32, 32), IndustrialOfficeParkingA),
		Definition.new(SIGNAL_COURTYARD_A, "Industrial signal courtyard", URBAN_COURTYARD, 1, Vector2i(32, 32), SignalCourtyardA),
		Definition.new(COURTYARD_GALLERY_A, "Inward-facing courtyard gallery", URBAN_GALLERY, 1, Vector2i(16, 32), CourtyardGalleryA),
		Definition.new(PARKING_GARAGE_A, "Two-level service garage", PARKING_GARAGE, 1, Vector2i(32, 32), ParkingGarageA),
	]

static func get_definition(id: StringName):
	for definition in all():
		if definition.parcel_id == id:
			return definition
	return null

static func candidates(role: StringName, size: Vector2i) -> Array:
	var result := all().filter(func(definition): return definition.role == role and definition.size == size)
	result.sort_custom(func(a, b): return String(a.parcel_id) < String(b.parcel_id))
	return result

## Stable bounded choice for the pilot. Resolved plot records will store the
## selected ID and revision; replay must not rely on this algorithm forever.
static func choose(role: StringName, size: Vector2i, map_seed: int):
	var supported := candidates(role, size)
	return supported[posmod(map_seed, supported.size())] if not supported.is_empty() else null
