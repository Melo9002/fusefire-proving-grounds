class_name LoadingYardLayout
extends RefCounted
const SceneMapCompiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const SIZE := Vector2i(40, 48)
const PARCEL_SIZE := Vector2i(16, 32)
const SOURCE_KIND := "authored_loading_yard"

static func parcel_definition():
	return ParcelCatalog.get_definition(ParcelCatalog.LOADING_YARD_A)

static func validate() -> PackedStringArray:
	var definition = parcel_definition()
	if definition == null:
		return PackedStringArray(["MISSING_PARCEL_DEFINITION"])
	var failures: PackedStringArray = definition.validate()
	if definition.size != PARCEL_SIZE:
		failures.append("PARCEL_SIZE_MISMATCH")
	return failures

static func generate(map_seed: int, unit: float = 1.0, turn: int = 0) -> MapData:
	var data := FlatMapGenerator.generate(SIZE.x, SIZE.y, unit, map_seed)
	data.source_kind = SOURCE_KIND
	var failures := validate()
	if not failures.is_empty(): push_error("Loading Yard contract invalid: " + "; ".join(failures))
	var parcel: Node3D = parcel_definition().instantiate()
	parcel.transform = pose(turn)
	SceneMapCompiler.compile(parcel, data, unit)
	parcel.free()
	return data

static func pose(turn: int) -> Transform3D:
	var size := ParcelTransform.rotated_size(PARCEL_SIZE, turn)
	var origin := Vector3i(floori(float(SIZE.x - size.x) / 2.0), 0, floori(float(SIZE.y - size.y) / 2.0))
	return ParcelTransform.scene_transform(PARCEL_SIZE, origin, turn, SIZE)

static func present(parent: Node3D, unit: float) -> void:
	var parcel: Node3D = parcel_definition().instantiate()
	parcel.transform = pose(0)
	parcel.position *= unit
	parcel.scale *= unit
	parent.add_child(parcel)
