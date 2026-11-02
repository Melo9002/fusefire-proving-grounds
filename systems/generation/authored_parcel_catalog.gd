class_name AuthoredParcelCatalog
extends RefCounted
## Explicit shortlist of reviewed parcels. No directory or semantic scan occurs
## during battle initialization.

const Definition = preload("res://systems/generation/authored_parcel_definition.gd")
const LOADING_YARD_A := &"loading_yard_a"
const LOADING_YARD_B := &"loading_yard_b"
const PROCESS_PAD_A := &"process_pad_a"
const TANK_STORAGE_A := &"tank_storage_a"
const LOADING_SERVICE := &"loading_service"
const PROCESS := &"process"
const STORAGE := &"storage"

const LoadingYardA = preload("res://art/environments/authored/parcels/loading_yard.tscn")
const LoadingYardB = preload("res://art/environments/authored/parcels/loading_yard_alt.tscn")
const ProcessPadA = preload("res://art/environments/authored/parcels/process_pad.tscn")
const TankStorageA = preload("res://art/environments/authored/parcels/tank_storage.tscn")

static func all() -> Array:
	return [
		Definition.new(LOADING_YARD_A, "Warehouse loading apron", LOADING_SERVICE, 1, Vector2i(16, 32), LoadingYardA),
		Definition.new(LOADING_YARD_B, "Container service apron", LOADING_SERVICE, 1, Vector2i(16, 32), LoadingYardB),
		Definition.new(PROCESS_PAD_A, "Factory process pad", PROCESS, 1, Vector2i(16, 16), ProcessPadA),
		Definition.new(TANK_STORAGE_A, "Tank storage pad", STORAGE, 1, Vector2i(16, 16), TankStorageA),
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
static func choose(role: StringName, size: Vector2i, seed: int):
	var supported := candidates(role, size)
	return supported[posmod(seed, supported.size())] if not supported.is_empty() else null
