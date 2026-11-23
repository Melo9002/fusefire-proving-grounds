class_name LadderLanding
extends RefCounted
## The top of a ladder as the HOST knows it: the one description a supported transfer onto a deck needs, whoever supplies it (the exploration sandbox from its tower and posts, the workbench from a
## configured test deck, a tactical map once its ladders carry authored landing metadata). Presentation only: it says nothing about legality, routes or AP. A pure value object: no nodes, no clock.
##
## Frame: the ladder's own, the one `LadderGeometry` uses: x = the climber's left, y = up (`deck_height` is the deck's height above the ladder's bottom floor), z = forward in the climbing direction, with
## the rung plane at `LadderGeometry.plane_ahead`. Distances below are from the rung plane unless they say otherwise.
##
## What makes a landing SUPPORTED is not the deck alone: the deck gives the feet somewhere to go, but the hands need something real to hold while the body crosses the lip (a post, or the ladder's own
## rails run on above the deck). A landing with a verified deck and NO handhold is reported as unsupported with that reason, and the rig keeps the ordinary height-only climb-out; nothing is invented.

## How far ahead of the rung plane the deck's edge (lip) is, metres.
var lip_from_rungs := 0.0
## The continuous usable deck beyond the lip, centred on the ladder's axis: its half width (x) and its depth (z).
var deck_half_width := 0.0
var deck_depth := 0.0
## The genuine handholds above the deck: x (signed lateral place), y (height above the deck), z (relative to the LIP, + = ahead), and the bar's radius. A hand takes the grip on its own side.
var grips: Array[Vector3] = []
var grip_radius := 0.025
## Where the landing came from, for reports ("sandbox tower posts", "authored rails"...).
var source := ""


## A deck with two upright posts at the edge (x = distance of each post from the axis).
static func with_posts(lip: float, half_width: float, depth: float, post_x: float, post_height: float, radius := 0.025, origin := "posts") -> LadderLanding:
	var landing := LadderLanding.new()
	landing.lip_from_rungs = lip
	landing.deck_half_width = half_width
	landing.deck_depth = depth
	landing.grip_radius = radius
	landing.grips = [Vector3(post_x, post_height, 0.0), Vector3(-post_x, post_height, 0.0)]
	landing.source = origin
	return landing


## A deck whose ladder's rails run on `extension` metres above it: the rails (at the rung plane, so `lip_from_rungs` in front of the lip) are the handholds.
static func with_extended_rails(geometry: LadderGeometry, lip: float, half_width: float, depth: float, extension: float, origin := "extended rails") -> LadderLanding:
	var landing := LadderLanding.new()
	landing.lip_from_rungs = lip
	landing.deck_half_width = half_width
	landing.deck_depth = depth
	landing.grip_radius = geometry.rail_radius
	var height := extension * 0.64
	landing.grips = [Vector3(geometry.rail_half_span(), height, -lip), Vector3(-geometry.rail_half_span(), height, -lip)]
	landing.source = origin
	return landing


## A verified deck with nothing to hold: reported unsupported, never posed as supported.
static func deck_only(lip: float, half_width: float, depth: float, origin := "deck only") -> LadderLanding:
	var landing := LadderLanding.new()
	landing.lip_from_rungs = lip
	landing.deck_half_width = half_width
	landing.deck_depth = depth
	landing.source = origin
	return landing


func has_grips() -> bool:
	return not grips.is_empty()


## The grip a hand on `side` (0 = left, +x) takes, or null when that side has none.
func grip_for(side: int) -> Variant:
	var wanted := 1.0 if side == 0 else -1.0
	var best: Variant = null
	for grip in grips:
		if signf(grip.x) == wanted and (best == null or absf(grip.x) < absf((best as Vector3).x)):
			best = grip
	return best


## "" when a supported transfer is verified for this body on this ladder, else the reason it is not (the host's request then keeps the height-only climb-out). The numbers come from the body.
func unsupported_reason(geometry: LadderGeometry, body: LadderBody) -> String:
	if lip_from_rungs < 0.0 or lip_from_rungs > body.arm_length() * 0.5:
		return "the deck lip is %.2f m from the rungs, outside this body's reach budget (%.2f m)" % [lip_from_rungs, body.arm_length() * 0.5]
	var needed_half_width := body.hip_offset.x + 0.1 * body.ratio
	if deck_half_width < needed_half_width:
		return "the deck is %.2f m wide each side of the axis, this body needs %.2f m" % [deck_half_width, needed_half_width]
	var needed_depth := body.ball_length * 2.6
	if deck_depth < needed_depth:
		return "the deck is %.2f m deep, this body needs %.2f m for both feet" % [deck_depth, needed_depth]
	if not has_grips():
		return "no genuine handhold above the deck (no posts, no extended rails)"
	for side in 2:
		if grip_for(side) == null:
			return "no handhold on the %s side" % ("left" if side == 0 else "right")
	return ""


## How far a capsule (a-b, `radius`, in the ladder frame, y relative to the ladder's bottom) is inside the deck solid, metres: 0 when clear. The deck is everything beyond the lip below the deck
## surface, `rise` high; the depth is how far the volume would have to move to leave through the nearest face.
func penetration(a: Vector3, b: Vector3, radius: float, geometry: LadderGeometry) -> float:
	var lip := geometry.plane_ahead + lip_from_rungs
	var worst := 0.0
	for i in 5:
		var p := a.lerp(b, float(i) / 4.0)
		if absf(p.x) - radius > deck_half_width:
			continue
		var into_face := p.z + radius - lip
		var into_top := geometry.rise - (p.y - radius)
		worst = maxf(worst, minf(into_face, into_top))
	return maxf(worst, 0.0)
