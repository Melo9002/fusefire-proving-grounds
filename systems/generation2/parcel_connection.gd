class_name ParcelConnection
extends Resource

## An interface is a boundary cell and outward cardinal direction, not an
## inferred mesh socket. Clearance is the usable width in tactical tiles.
@export var kind: StringName = &"path"
@export var cell := Vector3i.ZERO
@export var outward := Vector2i(0, -1)
@export_range(1, 32) var width: int = 1

func validate(size: Vector2i) -> String:
	if kind.is_empty() or width < 1:
		return "Connection needs a kind and positive width"
	if cell.y < 0 or cell.x < 0 or cell.z < 0 or cell.x >= size.x or cell.z >= size.y:
		return "Connection cell is outside parcel bounds"
	if outward not in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		return "Connection direction must be cardinal"
	if (outward.x == -1 and cell.x != 0) or (outward.x == 1 and cell.x != size.x - 1) or (outward.y == -1 and cell.z != 0) or (outward.y == 1 and cell.z != size.y - 1):
		return "Connection must face outward from its boundary"
	var along := cell.z if outward.x != 0 else cell.x
	var limit := size.y if outward.x != 0 else size.x
	if along + width > limit:
		return "Connection width exceeds parcel edge"
	return ""

static func from_scene(root: Node) -> ParcelConnection:
	var result := ParcelConnection.new()
	result.kind = StringName(root.get_meta("access_kind", &"path"))
	result.cell = root.get_meta("access_cell", Vector3i.ZERO)
	result.outward = root.get_meta("access_direction", Vector2i.ZERO)
	result.width = int(root.get_meta("access_width", 0))
	return result

func world_cell(size: Vector2i, origin: Vector3i, quarter_turns: int) -> Vector3i:
	return ParcelTransform.cell(cell, size, origin, quarter_turns)

## Walk the span in local order so a rotated tangent can run backward in world space.
func world_span(size: Vector2i, origin: Vector3i, quarter_turns: int) -> Array[Vector3i]:
	var along := Vector3i.RIGHT if outward.y != 0 else Vector3i.BACK
	var result: Array[Vector3i] = []
	for offset in width:
		result.append(ParcelTransform.cell(cell + along * offset, size, origin, quarter_turns))
	return result

func world_outward(quarter_turns: int) -> Vector2i:
	return ParcelTransform.direction(outward, quarter_turns)
