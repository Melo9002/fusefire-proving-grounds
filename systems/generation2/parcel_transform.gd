class_name ParcelTransform
extends RefCounted

## Maps parcel-local grid cells to a plot. Origin is the minimum corner of the
## rotated footprint; rotation is clockwise in the X/Z plane.
static func rotated_size(size: Vector2i, quarter_turns: int) -> Vector2i:
	return size if posmod(quarter_turns, 2) == 0 else Vector2i(size.y, size.x)

static func cell(local: Vector3i, size: Vector2i, origin: Vector3i, quarter_turns: int) -> Vector3i:
	var x := local.x
	var z := local.z
	match posmod(quarter_turns, 4):
		1:
			x = size.y - 1 - local.z
			z = local.x
		2:
			x = size.x - 1 - local.x
			z = size.y - 1 - local.z
		3:
			x = local.z
			z = size.x - 1 - local.x
	return origin + Vector3i(x, local.y, z)

static func direction(local: Vector2i, quarter_turns: int) -> Vector2i:
	match posmod(quarter_turns, 4):
		1: return Vector2i(-local.y, local.x)
		2: return -local
		3: return Vector2i(local.y, -local.x)
	return local

## Scene coordinates use cell centres (x, elevation, z), matching cell().
## The returned transform also applies the battlefield's centred world origin.
static func scene_transform(size: Vector2i, origin: Vector3i, quarter_turns: int, map_size: Vector2i, cell_size: float = 1.0) -> Transform3D:
	var rotation := Basis(Vector3.UP, -posmod(quarter_turns, 4) * PI * 0.5)
	var zero := cell(Vector3i.ZERO, size, origin, quarter_turns)
	var offset := Vector3(zero.x - map_size.x * 0.5 + 0.5, zero.y, zero.z - map_size.y * 0.5 + 0.5) * cell_size
	return Transform3D(rotation.scaled(Vector3.ONE * cell_size), offset)
