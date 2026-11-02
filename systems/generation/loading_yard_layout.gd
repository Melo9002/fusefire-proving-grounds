class_name LoadingYardLayout
extends RefCounted
const PARCEL := preload("res://art/environments/authored/parcels/loading_yard.tscn")
const SIZE := Vector2i(40, 48)

static func generate(map_seed: int, unit: float = 1.0, turn: int = 0) -> MapData:
	var data := FlatMapGenerator.generate(SIZE.x, SIZE.y, unit, map_seed)
	data.source_kind = "authored_loading_yard"
	var parcel := PARCEL.instantiate() as Node3D
	parcel.transform = pose(turn)
	Refinery2Layout._compile(parcel, Transform3D.IDENTITY, data, unit)
	parcel.free()
	data.rebuild_los_index()
	return data

static func pose(turn: int) -> Transform3D:
	var size := ParcelTransform.rotated_size(Vector2i(16, 32), turn)
	var origin := Vector3i((SIZE.x - size.x) / 2, 0, (SIZE.y - size.y) / 2)
	return ParcelTransform.scene_transform(Vector2i(16, 32), origin, turn, SIZE)

static func present(parent: Node3D, unit: float) -> void:
	var parcel := PARCEL.instantiate() as Node3D
	parcel.transform = pose(0)
	parcel.position *= unit
	parcel.scale *= unit
	parent.add_child(parcel)
