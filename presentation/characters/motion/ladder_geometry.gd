class_name LadderGeometry
extends RefCounted
## The ONE definition of a ladder's physical layout, shared by everything that draws, poses or measures one: the authored components (`maintenance_ladder_4m.tscn`, `maintenance_ladder_3m.tscn`, checked
## against this by `ladder_geometry_test`), the humanoid's ladder solver, the exploration sandbox, the workbench and the tests. A character profile never restates it; it only decides how a body uses it.
##
## The rungs are a fixed pitch from a fixed first rung, whatever the ladder's rise (a taller ladder has more rungs; it is NOT a stretched mesh, which would change the pitch the climbers were planned
## for). Frame of every position here: the character's, x = left, y = up from the ladder's bottom floor, z = forward toward the ladder; `plane_ahead` is the rung plane's z in the character's frame.

## Rung pitch and the height of the first rung. 0.25 m is a standard ladder pitch and one a small body's arms and legs can use (0.33 m was beyond Small MIRA's reach, issue #55).
const SPACING := 0.25
const FIRST_RUNG := 0.25
## The top rung is at least this far below the deck.
const TOP_MARGIN := 0.10
## Rails: centre distance from the ladder's axis, and the bar sizes (half the box's side: radius of the bar).
const RAIL_HALF_SPAN := 0.35
const RAIL_RADIUS := 0.03
const RUNG_RADIUS := 0.0225
## A rung's half length (it passes through the rails).
const RUNG_HALF_LENGTH := 0.38
## Where the rung plane is relative to the character's root (the tactical cell centre), + = ahead. The authored ladder sits 5 cm behind the cell centre when facing the deck.
const PLANE_AHEAD := -0.05

var rise := 4.0
var plane_ahead := PLANE_AHEAD
var rail_half_span_m := RAIL_HALF_SPAN
var rail_radius := RAIL_RADIUS
var rung_radius := RUNG_RADIUS
## What-if overrides for experiments and tools (a sweep over pitch or first rung): they default to the authored constants and nothing in production sets them.
var pitch := SPACING
var first := FIRST_RUNG


static func for_rise(climb_rise: float, plane := PLANE_AHEAD) -> LadderGeometry:
	var geometry := LadderGeometry.new()
	geometry.rise = climb_rise
	geometry.plane_ahead = plane
	return geometry


func first_rung() -> float:
	return first


func spacing() -> float:
	return pitch


func rung_count() -> int:
	return maxi(0, int(floor((rise - TOP_MARGIN - first) / pitch + 0.0001)) + 1)


## Height of rung `index` above the ladder's bottom floor.
func rung_height(index: int) -> float:
	return first + float(index) * pitch


func rail_half_span() -> float:
	return rail_half_span_m


## The clear width between the rails' inner faces.
func clear_width() -> float:
	return 2.0 * (rail_half_span_m - rail_radius)


## Distance from a point to a segment.
static func segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.000001 else clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Distance between two segments (exact: the closest points of the two).
static func segments_distance(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var closest := Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
	return closest[0].distance_to(closest[1])


## How deep the volume (capsule a-b of `radius`, in the character's frame) is inside the ladder: <= 0 when clear (the negative of the free gap), else the deepest overlap with a rung or a rail.
## `floor_level` is how far the character's floor is above the ladder's bottom.
func penetration(a: Vector3, b: Vector3, radius: float, floor_level: float) -> float:
	var worst := -INF
	var half := rail_half_span_m
	var low := minf(a.y, b.y) - radius - rung_radius
	var high := maxf(a.y, b.y) + radius + rung_radius
	# Only the rungs near the volume matter (the rest are far).
	var first_index := maxi(0, int(floor((low + floor_level - first) / pitch)))
	var last_index := mini(rung_count() - 1, int(ceil((high + floor_level - first) / pitch)))
	for index in range(first_index, last_index + 1):
		var y := rung_height(index) - floor_level
		var d := segments_distance(a, b, Vector3(-half, y, plane_ahead), Vector3(half, y, plane_ahead))
		worst = maxf(worst, radius + rung_radius - d)
	for side in [-1.0, 1.0]:
		var d := segments_distance(a, b, Vector3(half * side, -floor_level, plane_ahead), Vector3(half * side, rise - floor_level, plane_ahead))
		worst = maxf(worst, radius + rail_radius - d)
	return worst


## Builds the ladder's meshes (rails and rungs) as a Node3D at the origin, in the character's frame, for tools and sandboxes that show one. `material` is optional.
func build_visual(material: Material = null) -> Node3D:
	var node := Node3D.new()
	node.name = "Ladder"
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(rail_radius * 2.0, rise, rail_radius * 2.0)
		rail.mesh = rail_mesh
		rail.material_override = material
		rail.position = Vector3(rail_half_span_m * side, rise * 0.5, plane_ahead)
		node.add_child(rail)
	for index in rung_count():
		var rung := MeshInstance3D.new()
		var rod := BoxMesh.new()
		rod.size = Vector3(RUNG_HALF_LENGTH * 2.0, rung_radius * 2.0, rung_radius * 2.0)
		rung.mesh = rod
		rung.material_override = material
		rung.position = Vector3(0.0, rung_height(index), plane_ahead)
		node.add_child(rung)
	return node
