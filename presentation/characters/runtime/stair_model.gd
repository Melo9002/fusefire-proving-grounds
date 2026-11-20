class_name StairModel
extends RefCounted
## The physical profile of a straight staircase as the presentation needs it, in world space: where the floor is at any distance along the stair, where the treads and risers
## are, and the polyline a body rides up or down it. PURE geometry (no scene, no map, no time). It never decides whether a stair may be used: the tactical route does that;
## this only describes the surface under a route that was already authorized.
##
## Alignment convention, VERIFIED against the real physical treads of the Tactical Test Range (physics rays, `traversal_surface_alignment_test`): a cell centre lies at the FOOT of a
## riser, standing on the tread below it, so the floor under a cell centre is the lower tread's top and the first riser is at the lower cell's own centre. With `count` treads over
## the links the risers lie at s = (k - 1) * depth from the lower cell centre (k = 1..count) and tread k (top at k * rise) spans s in [(k - 1) * depth, k * depth]. (An earlier
## version put the first riser half a link up the stair, which placed every foothold one tread too low; the tactical block stand-ins that version was checked against are not
## the visible stairs.)
##
## `s` is the distance along `direction` (horizontal, unit) from `low`, the floor point under the centre of the lowest cell. Heights are floor heights (the tread tops).

var low := Vector3.ZERO
var direction := Vector3.FORWARD
var tread_depth := 0.5
var tread_rise := 0.5
## Distance of the first riser from `low` (0 for the authored stairs: the foot cell's centre is at the first riser).
var first_riser := 0.0
var count := 2
var width := 1.0


## A model for `links` consecutive one-cell links of run `run` and rise `rise`, `treads_per_link` treads each, from the lower cell centre `low_point` toward `toward` (any
## point in the climbing direction). Returns null when the numbers cannot describe a stair.
static func from_links(low_point: Vector3, toward: Vector3, run: float, rise: float, treads_per_link: int, links: int, stair_width := 1.0) -> StairModel:
	if treads_per_link <= 0 or links <= 0 or run <= 0.001 or rise <= 0.001:
		return null
	var flat := Vector3(toward.x - low_point.x, 0.0, toward.z - low_point.z)
	if flat.length() < 0.001:
		return null
	var model := StairModel.new()
	model.low = low_point
	model.direction = flat.normalized()
	model.tread_depth = run / float(treads_per_link)
	model.tread_rise = rise / float(treads_per_link)
	model.first_riser = 0.0
	model.count = treads_per_link * links
	model.width = stair_width
	return model


## s of riser k (k = 1..count); riser k rises to tread k.
func riser_s(k: int) -> float:
	return first_riser + float(k - 1) * tread_depth


## Floor height (world y) at distance s: the tread top under it. On a riser line (a cell centre) it is the LOWER tread: the floor of the cell standing at the foot of that riser.
func height_at(s: float) -> float:
	if s <= first_riser + 0.000001:
		return low.y
	var k := mini(count, int(ceil((s - first_riser) / tread_depth - 0.000001)))
	return low.y + float(k) * tread_rise


## Height of the surface as a SMOOTH body path: the floor rises over `blend` metres centred on each riser instead of in a step (what the root rides).
func ride_height_at(s: float, blend: float) -> float:
	var height := low.y
	for k in count:
		var edge := riser_s(k + 1)
		height += tread_rise * smoothstep(edge - blend * 0.5, edge + blend * 0.5, s)
	return height


func progress_of(world: Vector3) -> float:
	return (world - low).dot(direction)


func point_at(s: float, height: float) -> Vector3:
	return low + direction * s + Vector3.UP * (height - low.y)


## Tread k (1..count): its near edge and far edge as distances along the stair; the top tread's far edge is the landing's near edge (the stair's end).
func tread_span(k: int) -> Vector2:
	return Vector2(riser_s(k), riser_s(k) + tread_depth)


func tread_top(k: int) -> float:
	return low.y + float(k) * tread_rise


func top() -> float:
	return low.y + float(count) * tread_rise


func end_s() -> float:
	return riser_s(count) + tread_depth


## The floor polyline of a walk over the stair, in travel order (`ascending` true = from the bottom): a level run to each riser line and then a ramp of up to `ramp` metres
## over the riser onto the next tread (the body rises as it passes the riser, so every cell centre, which lies on a riser line, keeps its exact floor). The caller adds the
## body's standing height. Endpoints are exactly the bottom point and the point `tail` metres past the top (the upper cell centre when tail = 0).
func path_points(ascending: bool, ramp: float, tail: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(low)
	var reach := minf(maxf(ramp, 0.001), tread_depth)
	var last_s := 0.0
	for k in count:
		var edge := riser_s(k + 1)
		if edge > last_s + 0.0001:
			points.append(point_at(edge, low.y + float(k) * tread_rise))
		points.append(point_at(edge + reach, low.y + float(k + 1) * tread_rise))
		last_s = edge + reach
	var end := end_s() + tail
	if end > last_s + 0.0001:
		points.append(point_at(end, top()))
	if not ascending:
		var reversed := PackedVector3Array()
		for index in range(points.size() - 1, -1, -1):
			reversed.append(points[index])
		return reversed
	return points


## The floor height of the ride path (the polyline path_points walks) at distance s.
func ride_path_height_at(s: float, ramp: float) -> float:
	var reach := minf(maxf(ramp, 0.001), tread_depth)
	var height := low.y
	for k in count:
		var edge := riser_s(k + 1)
		if s <= edge:
			break
		if s >= edge + reach:
			height = low.y + float(k + 1) * tread_rise
		else:
			height = low.y + float(k) * tread_rise + tread_rise * (s - edge) / reach
			break
	return height
