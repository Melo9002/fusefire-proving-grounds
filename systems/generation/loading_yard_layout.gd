class_name LoadingYardLayout
extends RefCounted
const AuthoredSceneMapCompiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
const PARCEL := preload("res://art/environments/authored/parcels/loading_yard.tscn")
const SIZE := Vector2i(40, 48)
const PARCEL_SIZE := Vector2i(16, 32)
const SOURCE_KIND := "authored_loading_yard"
const REVISION := 1

static func validate() -> PackedStringArray:
	var failures := PackedStringArray()
	var parcel := PARCEL.instantiate() as Node3D
	if parcel.get_meta("parcel_size", Vector2i.ZERO) != PARCEL_SIZE: failures.append("PARCEL_SIZE_MISMATCH")
	if int(parcel.get_meta("revision", 0)) != REVISION: failures.append("PARCEL_REVISION_MISMATCH")
	var connection := ParcelConnection.from_scene(parcel)
	var connection_error := connection.validate(PARCEL_SIZE)
	if not connection_error.is_empty(): failures.append("INVALID_CONNECTION: " + connection_error)
	if not parcel.get_children().any(func(child): return child.has_meta("asset_id")): failures.append("MISSING_IMPORTED_CONTENT")
	parcel.free()
	return failures

static func generate(map_seed: int, unit: float = 1.0, turn: int = 0) -> MapData:
	var data := FlatMapGenerator.generate(SIZE.x, SIZE.y, unit, map_seed)
	data.source_kind = SOURCE_KIND
	var failures := validate()
	if not failures.is_empty(): push_error("Loading Yard contract invalid: " + "; ".join(failures))
	var parcel := PARCEL.instantiate() as Node3D
	parcel.transform = pose(turn)
	AuthoredSceneMapCompiler.compile(parcel, data, unit)
	parcel.free()
	return data

static func pose(turn: int) -> Transform3D:
	var size := ParcelTransform.rotated_size(PARCEL_SIZE, turn)
	var origin := Vector3i((SIZE.x - size.x) / 2, 0, (SIZE.y - size.y) / 2)
	return ParcelTransform.scene_transform(PARCEL_SIZE, origin, turn, SIZE)

static func present(parent: Node3D, unit: float) -> void:
	var parcel := PARCEL.instantiate() as Node3D
	parcel.transform = pose(0)
	parcel.position *= unit
	parcel.scale *= unit
	parent.add_child(parcel)
