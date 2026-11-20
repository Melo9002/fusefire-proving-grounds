class_name TraversalSolver
extends RefCounted
## Deterministic contact targets for environmental traversal: a PURE function of (profile, geometry, progress). No time, no frame delta, no randomness, no state: the
## same inputs give the same contacts on every machine, at any playback speed, and from any replay position, because the unit's tactical position (its height up the
## ladder, its place along the route) IS the animation clock. Nothing here decides whether a traversal is legal; it only poses a body along a route it was given.
##
## Frame: rig-local, x = the character's LEFT, y = up from the floor under the root, z = forward (toward the ladder / obstacle). Index 0 = left, 1 = right.

const LEFT := 0
const RIGHT := 1


## Ladder pose when the character's floor level is `climbed` metres above the ladder's bottom floor. `length` is the ladder's rise (bottom floor to deck). `direction`
## is +1 climbing, -1 descending: it decides at which end of its window a limb is picked up (hands and feet lead the way they travel).
## Returns {weight, hips, lean_degrees, twist_degrees, head_pitch_degrees, hands[2], feet[2], hand_rung[2], foot_rung[2], hand_swing[2], foot_swing[2], on_ladder}.
## `weight` is how much of the pose applies (0 = ordinary standing/walking pose, 1 = fully on the ladder): it ramps in over `mount_length` from the bottom and out over
## `dismount_length` at the top. `*_rung` is the rung index a limb is on (-1 = the deck handhold); `*_swing` 0 planted .. 1 mid-way to the next rung.
static func ladder_pose(profile: TraversalProfile, climbed: float, length: float, direction: int) -> Dictionary:
	var up := direction >= 0
	var weight := smoothstep(0.0, profile.mount_length, climbed) * (1.0 - smoothstep(length - profile.dismount_length, length, climbed))
	if direction < 0:
		# Going down the weight is the same function of height (mount at the top end, dismount at the floor): it is symmetric by construction.
		weight = smoothstep(0.0, profile.dismount_length, climbed) * (1.0 - smoothstep(length - profile.mount_length, length, climbed))
	var result := {
		"weight": weight, "on_ladder": weight > 0.0,
		"hands": [Vector3.ZERO, Vector3.ZERO], "feet": [Vector3.ZERO, Vector3.ZERO],
		"hand_rung": [-1, -1], "foot_rung": [-1, -1], "hand_swing": [0.0, 0.0], "foot_swing": [0.0, 0.0], "hand_deck": [0.0, 0.0], "hand_weight": [0.0, 0.0],
	}
	var plane := profile.ladder_plane_ahead
	var scale := rung_scale(profile, length)
	var first := profile.first_rung_height * scale
	var spacing := profile.rung_spacing * scale
	var rung_count := rung_count_for(profile, length)
	# Parity classes: the left hand and the right foot share one, the right hand and the left foot the other (a contralateral climb).
	var hand_parity := [1, 0]
	var foot_parity := [0, 1]
	for side in 2:
		var x := profile.hand_half_spread * (1.0 if side == LEFT else -1.0)
		var hand := _limb_on_ladder(profile, climbed, rung_count, hand_parity[side], profile.hand_window_low, up, first, spacing)
		result.hand_rung[side] = hand.rung
		result.hand_swing[side] = hand.swing
		# Near the top the hands leave the last rungs for the deck edge (a blend over the last stretch of the climb; symmetric going down).
		var deck := smoothstep(length - profile.deck_handhold_start, length - profile.deck_handhold_start + profile.deck_handhold_blend, climbed)
		result.hand_deck[side] = deck
		var on_rung := Vector3(x, hand.height + sin(hand.swing * PI) * profile.swing_lift, plane)
		var on_deck := Vector3(x, length - climbed + profile.deck_handhold_height, plane + profile.deck_handhold_ahead)
		result.hands[side] = on_rung.lerp(on_deck, deck)
		if deck > 0.5:
			result.hand_rung[side] = -1
		var fx := profile.foot_half_spread * (1.0 if side == LEFT else -1.0)
		var foot := _limb_on_ladder(profile, climbed, rung_count, foot_parity[side], profile.foot_window_low, up, first, spacing)
		result.foot_rung[side] = foot.rung
		result.foot_swing[side] = foot.swing
		var foot_y: float = foot.height + profile.ankle_above_rung
		result.feet[side] = Vector3(fx, foot_y + sin(foot.swing * PI) * profile.swing_lift, plane - profile.ankle_behind_rung)
	# Pelvis: back from the rung plane, at the ladder pelvis height, with a small sway toward the planted side (weight transfer between the two feet).
	var cycle := (climbed / (2.0 * spacing)) * TAU
	var sway := sin(cycle) * profile.weight_shift
	result.hips = Vector3(sway, profile.hips_height, -profile.body_standoff)
	var release := smoothstep(length - profile.hand_release_start, length - profile.hand_release_start + profile.hand_release_length, climbed)
	result.hand_weight = [weight * (1.0 - release), weight * (1.0 - release)]
	result.lean_degrees = profile.climb_lean_degrees
	result.twist_degrees = -sin(cycle) * profile.shoulder_twist_degrees
	result.head_pitch_degrees = profile.head_pitch_degrees * (1.0 if up else -0.7)
	return result


## How much the rung layout is scaled for a ladder of rise `length` (1 for the reference 4 m ladder).
static func rung_scale(profile: TraversalProfile, length: float) -> float:
	return length / profile.reference_rise if profile.rungs_follow_rise and profile.reference_rise > 0.0 else 1.0


static func rung_count_for(profile: TraversalProfile, length: float) -> int:
	var scale := rung_scale(profile, length)
	return maxi(0, int(floor((length - 0.1 * scale - profile.first_rung_height * scale) / (profile.rung_spacing * scale))) + 1)


## Height of rung `index` above the ladder's bottom floor, for a ladder of rise `length` (default: the reference ladder).
static func rung_height(profile: TraversalProfile, index: int, length := -1.0) -> float:
	var scale := rung_scale(profile, length) if length > 0.0 else 1.0
	return (profile.first_rung_height + float(index) * profile.rung_spacing) * scale


## Where one limb is for a floor level `climbed`: the rung of its parity inside its window above the floor level, and how far it is through its swing to the next one.
## Climbing: picked up at the low end of its window (reaching up 2 rungs); descending: at the high end (reaching down). rung -1 = no rung left (the deck).
static func _limb_on_ladder(profile: TraversalProfile, climbed: float, rung_count: int, parity: int, window_low: float, up: bool, first: float, spacing: float) -> Dictionary:
	var window := 2.0 * spacing
	var wanted_low := climbed + window_low
	# Smallest rung index k >= 0 with this parity whose height is at or above the bottom of the window.
	var k := int(ceil((wanted_low - first) / spacing))
	k = maxi(k, 0)
	if (k % 2) != parity:
		k += 1
	var relative := (first + float(k) * spacing) - climbed   # in [window_low, window_low + window)
	var band := profile.swing_fraction * window
	var swing := 0.0
	var target := k
	if up:
		var into := relative - window_low   # 0 right after the pick-up point .. window
		if into < band:
			swing = 1.0 - into / band          # about to be released: already travelling up to rung k + 2
			target = k + 2
	else:
		var into_down := (window_low + window) - relative
		if into_down < band:
			swing = 1.0 - into_down / band
			target = k - 2
	swing = clampf(swing, 0.0, 1.0)
	var from_height := (first + float(k) * spacing)
	var to_height := (first + float(target) * spacing)
	if k >= rung_count:
		# Out of rungs (above the top): the limb stays on the highest rung of its parity.
		while k >= rung_count:
			k -= 2
		if k < 0:
			return {"rung": -1, "height": 0.0, "swing": 0.0}
		return {"rung": k, "height": (first + float(k) * spacing) - climbed, "swing": 0.0}
	if target >= rung_count or target < 0:
		# The next rung does not exist (above the top / below the bottom): stay on this one.
		return {"rung": k, "height": from_height - climbed, "swing": 0.0}
	var s := smoothstep(0.0, 1.0, swing)
	return {"rung": k, "height": lerpf(from_height, to_height, s) - climbed, "swing": swing}


## Hand support and body path for a hand-supported VAULT over an obstacle between two floor cells (the tactical route is up, across at the obstacle's height, down).
## `phase` runs 0..3 over those three route segments. `height` is the obstacle's top above the floor, `across` the horizontal distance between the cells, `edge` how far
## the obstacle's near face is from the start. The obstacle's top centre is the hands' world contact. Returns {weight, hands[2] (null where free), hips, lean_degrees,
## feet[2], hand_weight[2], tuck}. Rig-local, relative to the root as it travels (the caller subtracts the root's own position from the contact).
static func vault_pose(profile: TraversalProfile, phase: float, height: float, across: float, edge: float, root_offset: Vector3) -> Dictionary:
	var rising := clampf(phase, 0.0, 1.0)
	var dropping := clampf(phase - 2.0, 0.0, 1.0)
	# Hand contact: from the end of the rise until midway through the descent the hands are on the obstacle's top; they reach for it during the rise.
	var hand_weight := smoothstep(0.35, 0.95, rising) * (1.0 - smoothstep(0.1, 0.6, dropping))
	var weight := smoothstep(0.0, 0.25, rising) * (1.0 - smoothstep(0.7, 1.0, dropping))
	var top_centre := Vector3(0.0, height, edge + (across - 2.0 * edge) * 0.5)   # the obstacle's top, in the start frame
	var hands := [null, null]
	for side in 2:
		var x := profile.hand_half_spread * (1.0 if side == LEFT else -1.0) * 0.9
		var world := top_centre + Vector3(x, 0.0, -profile.vault_hand_inset)
		if hand_weight > 0.001:
			hands[side] = world - root_offset
	# The body goes over the obstacle. `tuck` raises the knees as the body leaves the floor and crosses, then opens again for the landing.
	var tuck := clampf(sin(rising * PI * 0.5) * (1.0 - dropping), 0.0, 1.0)
	var lean := profile.vault_torso_lean_degrees * smoothstep(0.2, 1.0, rising) * (1.0 - dropping)
	# Lead leg (left) is raised higher and forward, the trail leg (right) follows tucked closer; both ankles stay under the hips' reach.
	var feet: Array = []
	for side in 2:
		var lead := side == LEFT
		var x := 0.10 * (1.0 if lead else -1.0)
		feet.append(Vector3(x, lerpf(0.09, 0.46 if lead else 0.26, tuck), lerpf(0.0, 0.30 if lead else -0.05, tuck)))
	return {"weight": weight, "hands": hands, "hand_weight": [hand_weight, hand_weight], "hips": Vector3(0, -0.04 * tuck, 0), "lean_degrees": lean, "feet": feet, "tuck": tuck}
