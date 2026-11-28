class_name PlaygroundPlacement
extends RefCounted
## Where a body can be put down (sandbox package). The shared release (`CharacterRig.begin_release`) always lowers the body in front of the carrier, whatever is there, and the body it leaves has no collider of its own,
## so a carrier standing at a wall or a tower laid the body INTO it. This is the playground's check, made before the put-down starts: it looks at the floor and the free space the lying body will occupy, tries the
## directions around the carrier in a fixed order, and says which one to face (or that there is none). Nothing here moves the body: the carrier turns, and the shared release does the rest.

## The release lowers the body this far ahead of the carrier's root (CharacterRig.RELEASE_STEP + the interaction's stand-off), and it lies across the carrier's heading: the lying body's long axis is the carrier's right.
const AHEAD := 0.95
## The lying body's size at scale 1 (measured on the released body's bones: about 1.6 m long, 0.55 m wide, 0.35 m high) with a small margin each way.
const HALF_LENGTH := 0.90
const HALF_WIDTH := 0.34
const HEIGHT := 0.30
## How far above or below the carrier's floor the supporting surface may be, at the centre and the corners, and how much the surface may tilt.
const SUPPORT_TOLERANCE := 0.07
const MIN_NORMAL_Y := 0.92
## The directions tried, as turns away from the way the carrier faces, in order: straight ahead first, the nearest alternatives next, behind last.
const TURNS_DEGREES := [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]


## The first direction (a yaw about the vertical, +Z is zero) in which the body can be put down from `feet`, or NAN when there is none. `facing` is the carrier's heading as a flat unit vector,
## `scale` the body's own scale, `exclude` the bodies that are not obstacles (the carrier's own), `others` the bodies already lying about, [{position, axis (the long axis, flat unit), scale}]: they have no collider,
## so the physics query cannot see them and the footprints are compared here.
static func find_direction(world: World3D, feet: Vector3, facing: Vector3, scale: float, exclude: Array[RID], others: Array = []) -> float:
	var base_yaw := atan2(facing.x, facing.z)
	for turn in TURNS_DEGREES:
		var yaw := base_yaw + deg_to_rad(float(turn))
		if is_clear(world, feet, yaw, scale, exclude, others):
			return yaw
	return NAN


## Whether a body put down from `feet` facing `yaw` lies on firm ground with nothing in the way.
static func is_clear(world: World3D, feet: Vector3, yaw: float, scale: float, exclude: Array[RID], others: Array = []) -> bool:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)   # forward.cross(up) with +Z forward: the carrier's right
	var centre := feet + forward * AHEAD
	var space := world.direct_space_state
	var half_length := HALF_LENGTH * scale
	var half_width := HALF_WIDTH * scale
	# Supported: the centre and the four corners all have the carrier's floor under them (no edge, no step, no slope).
	for offset in [Vector2(0, 0), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var point: Vector3 = centre + right * offset.x * half_length + forward * offset.y * half_width
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 0.6)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or absf(float(hit.position.y) - feet.y) > SUPPORT_TOLERANCE or float(hit.normal.y) < MIN_NORMAL_Y:
			return false
	# Free: the box the lying body fills, held just clear of the floor, touches no solid.
	var box := BoxShape3D.new()
	box.size = Vector3(half_length * 2.0, HEIGHT * scale, half_width * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(centre.x, feet.y + 0.04 + HEIGHT * scale * 0.5, centre.z))
	query.exclude = exclude
	if not space.intersect_shape(query, 1).is_empty():
		return false
	for other in others:
		if _footprints_overlap(centre, right, half_length, half_width, other.position, other.axis, HALF_LENGTH * float(other.scale), HALF_WIDTH * float(other.scale)):
			return false
	return true


## Whether two lying bodies' footprints (rectangles on the floor: centre, long axis, half length, half width) overlap, with a hand's width of margin between them (separating-axis test).
static func _footprints_overlap(centre_a: Vector3, long_a: Vector3, half_length_a: float, half_width_a: float, centre_b: Vector3, long_b: Vector3, half_length_b: float, half_width_b: float) -> bool:
	const MARGIN := 0.10
	var short_a := Vector3(-long_a.z, 0.0, long_a.x)
	var short_b := Vector3(-long_b.z, 0.0, long_b.x)
	var between := centre_b - centre_a
	for axis in [long_a, short_a, long_b, short_b]:
		var reach_a := absf(long_a.dot(axis)) * half_length_a + absf(short_a.dot(axis)) * half_width_a
		var reach_b := absf(long_b.dot(axis)) * half_length_b + absf(short_b.dot(axis)) * half_width_b
		if absf(between.dot(axis)) > reach_a + reach_b + MARGIN:
			return false
	return true
