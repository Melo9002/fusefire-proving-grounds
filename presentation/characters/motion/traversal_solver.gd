class_name TraversalSolver
extends RefCounted
## Deterministic contact targets for environmental traversal: a PURE function of (profile, geometry, body, progress). No time, no frame delta, no randomness, no state: the
## same inputs give the same contacts on every machine, at any playback speed, and from any replay position, because the unit's tactical position (its height up the
## ladder, its place along the route) IS the animation clock. Nothing here decides whether a traversal is legal; it only poses a body along a route it was given.
##
## Frame: rig-local, x = the character's LEFT, y = up from the floor under the root, z = forward (toward the ladder / obstacle). Index 0 = left, 1 = right.
##
## A ladder pose uses three things and invents none of them: the LADDER (LadderGeometry: where the rungs, rails and plane are), the BODY (LadderBody: measured limb lengths and joint offsets) and the
## PROFILE (how a body climbs: lean, swing, sway, mount lengths). Where a limb can reach comes from the body, so a short body takes the same ladder with its own windows.

const LEFT := 0
const RIGHT := 1
## The share of a limb's full length it may be asked to span (a fully straight limb is not a planted contact).
const REACH_FRACTION := 0.95
## Arms are planned a little shorter: the shoulder is where the lean and the rifle's or the hang's pose leave it, which the plan only models.
const HAND_REACH_FRACTION := 0.92
## How much of a forward lean moves the shoulders (the spine shares the lean with the hips and the head: measured on both bodies, 0.64 to 0.7 of T sin(lean)).
const LEAN_SHOULDER_GAIN := 0.68
## Air between the torso and the rungs, and between the knee and the rungs (metres).
const TORSO_GAP := 0.025
const KNEE_GAP := 0.02
## How far behind the rung's centre the wrist sits when the hand holds it (the palm's own thickness, scaled by the body), and how far below it along the fingers.
const GRIP_BEHIND := 0.04
const GRIP_BELOW := 0.05
## A limb steps over two rungs at a time only when the body's reach spans this share of two pitches; otherwise it steps one rung at a time.
const TWO_RUNG_SHARE := 0.85
## Spare reach kept on the hand span when the pelvis hangs back (metres).
const HAND_SPAN_MARGIN := 0.03
## The hands start letting go of the last rungs this far before the arm runs out of reach (metres of climb).
const RELEASE_LEAD := 0.12


## The ladder plan for a body: where the pelvis hangs, how far each limb steps and the windows the limbs work in. Pure; cheap (a few dozen operations).
## {hips: Vector3, hand_step, foot_step (rungs per move), hand_window_low, foot_window_low (rung heights above the floor level at which a limb is picked up), shoulder_height,
##  hand_reach (vertical half range), shoulder_z, ankle_above, ankle_behind, d_max, d_min, hand_depth}
static func plan_ladder(profile: TraversalProfile, geometry: LadderGeometry, body: LadderBody) -> Dictionary:
	var k := body.ratio
	var plane := geometry.plane_ahead
	var pitch := geometry.spacing()
	var hips_y := profile.hips_height * k
	var lean := deg_to_rad(profile.climb_lean_degrees)
	# Shoulders at lean: the rest offset plus the share of the lean that reaches them.
	var shoulder_rel := Vector3(body.shoulder_offset.x, body.shoulder_offset.y, body.shoulder_offset.z + body.shoulder_offset.y * sin(lean) * LEAN_SHOULDER_GAIN)
	# The torso's front surface clears the rungs: the shoulder joint's depth behind the plane, and so where the pelvis hangs at the closest.
	var shoulder_back := geometry.rung_radius + TORSO_GAP + body.torso_radius()
	var torso_hips_z := plane - shoulder_back - shoulder_rel.z
	# Hands: the vertical span an arm can hold over the shoulder at that depth, then how many rungs a move covers (a limb steps two rungs only if its reach spans most of two pitches).
	var hand_x := profile.hand_half_spread * k
	# The pelvis sways sideways a little with each step (weight_shift), which a limb planned at its reach has to afford.
	var sway := profile.weight_shift * k
	var hand_dx := absf(hand_x - shoulder_rel.x) + sway
	var arm_reach := body.arm_length() * HAND_REACH_FRACTION
	var grip_plane := plane - GRIP_BEHIND * k
	var depth := grip_plane - (torso_hips_z + shoulder_rel.z)
	var vertical := sqrt(maxf(arm_reach * arm_reach - depth * depth - hand_dx * hand_dx, 0.0))
	var hand_step := 2 if 2.0 * pitch <= 2.0 * vertical * TWO_RUNG_SHARE else 1
	var window := float(hand_step) * pitch
	# Two hands that step one rung at a time are a quarter window apart, so together they span one and a quarter windows.
	var hand_span := window * (1.25 if hand_step == 1 else 1.0)
	# How far back the pelvis may hang: until the arms can only just hold the whole span (the hands are what keep the climber on).
	var span_half := hand_span * 0.5 + HAND_SPAN_MARGIN
	var max_depth := sqrt(maxf(arm_reach * arm_reach - span_half * span_half - hand_dx * hand_dx, 0.0))
	var hang_limit := minf(torso_hips_z, grip_plane - max_depth - shoulder_rel.z)
	# The knee of the foot that is highest must stay behind the rungs (frog-leg turn included): how far the pelvis has to hang for that, as far as the arms allow.
	var hips_z := torso_hips_z
	var hip_rel := Vector3(body.hip_offset.x, body.hip_offset.y, body.hip_offset.z)
	var ankle_behind := body.ball_length * 0.5
	var ankle_above := geometry.rung_radius + body.ankle_height * 0.85
	var foot_step := 1
	var reach_leg := body.leg_length() * REACH_FRACTION
	var ankle_z := plane - ankle_behind
	var foot_x := profile.foot_half_spread * k
	var dz := ankle_z - (hips_z + hip_rel.z)
	var dx := absf(foot_x - hip_rel.x) + sway
	var d_max := sqrt(maxf(reach_leg * reach_leg - dz * dz - dx * dx, 0.0))
	var d_min := maxf(d_max - float(foot_step) * pitch * 1.25, absf(body.thigh - body.shin) + 0.05)
	var knee_z_max := plane - geometry.rung_radius - body.knee_radius() - KNEE_GAP
	var knee_turn := deg_to_rad(profile.knee_turn_degrees)
	var knee_x_max := geometry.rail_half_span() - geometry.rail_radius - body.knee_radius() - KNEE_GAP
	for pass_index in 3:
		var distance := sqrt(d_min * d_min + dz * dz + dx * dx)
		var along := (body.thigh * body.thigh - body.shin * body.shin + distance * distance) / (2.0 * distance)
		var offset := sqrt(maxf(body.thigh * body.thigh - along * along, 0.0))
		var turn := minf(knee_turn, asin(clampf((knee_x_max - hip_rel.x) / maxf(offset, 0.001), 0.0, 1.0)))
		var fraction := along / distance
		var needed_hip_z := (knee_z_max - ankle_z * fraction - offset * cos(turn) * 0.9) / (1.0 - fraction)
		hips_z = minf(torso_hips_z, maxf(needed_hip_z - hip_rel.z, hang_limit))
		dz = ankle_z - (hips_z + hip_rel.z)
	var shoulder_z := hips_z + shoulder_rel.z
	var hand_depth := grip_plane - shoulder_z
	vertical = sqrt(maxf(arm_reach * arm_reach - hand_depth * hand_depth - hand_dx * hand_dx, 0.0))
	var shoulder_height := hips_y + shoulder_rel.y
	# The wrist is below the rung it holds (GRIP_BELOW): the hand window is centred on the shoulder, in rung heights.
	var hand_low := shoulder_height - hand_span * 0.5 + GRIP_BELOW * k + profile.hand_window_bias
	var ankle_floor_low := hips_y + hip_rel.y - d_max
	var foot_low := ankle_floor_low - ankle_above
	return {
		"hips": Vector3(0.0, hips_y, hips_z), "hand_step": hand_step, "foot_step": foot_step, "hand_window_low": hand_low, "foot_window_low": foot_low + profile.foot_window_bias,
		"shoulder_height": shoulder_height, "hand_reach": vertical, "shoulder_z": shoulder_z, "ankle_above": ankle_above, "ankle_behind": ankle_behind, "d_max": d_max, "d_min": d_min,
		"hand_depth": hand_depth,
	}


## Ladder pose when the character's floor level is `climbed` metres above the ladder's bottom floor. `direction` is +1 climbing, -1 descending: it decides at which end of its window a limb is
## picked up (hands and feet lead the way they travel).
## Returns {weight, hips, lean_degrees, twist_degrees, head_pitch_degrees, hands[2], feet[2], hand_rung[2], foot_rung[2], hand_swing[2], foot_swing[2], hand_deck[2], hand_weight[2], on_ladder,
## hand_reachable[2], foot_reachable[2]}. `weight` is how much of the pose applies (0 = ordinary standing/walking pose, 1 = fully on the ladder): it ramps in over `mount_length` from the bottom and
## out over `dismount_length` at the top. `*_rung` is the rung index a limb is on (-1 = the deck handhold); `*_swing` 0 planted .. 1 mid-way to the next rung. `*_reachable` says whether the planned
## target is within the limb's length from where the plan puts the shoulder or hip (an unreachable target is reported, never presented as a success).
static func ladder_pose(profile: TraversalProfile, geometry: LadderGeometry, body: LadderBody, climbed: float, direction: int) -> Dictionary:
	var length := geometry.rise
	var up := direction >= 0
	var weight := smoothstep(0.0, profile.mount_length, climbed) * (1.0 - smoothstep(length - profile.dismount_length, length, climbed))
	if direction < 0:
		# Going down the weight is the same function of height (mount at the top end, dismount at the floor): it is symmetric by construction.
		weight = smoothstep(0.0, profile.dismount_length, climbed) * (1.0 - smoothstep(length - profile.mount_length, length, climbed))
	var result := {
		"weight": weight, "on_ladder": weight > 0.0,
		"hands": [Vector3.ZERO, Vector3.ZERO], "feet": [Vector3.ZERO, Vector3.ZERO],
		"hand_rung": [-1, -1], "foot_rung": [-1, -1], "hand_swing": [0.0, 0.0], "foot_swing": [0.0, 0.0], "hand_deck": [0.0, 0.0], "hand_weight": [0.0, 0.0],
		"hand_reachable": [true, true], "foot_reachable": [true, true],
	}
	var k := body.ratio
	var plan := plan_ladder(profile, geometry, body)
	var plane := geometry.plane_ahead
	var first := geometry.first_rung()
	var spacing := geometry.spacing()
	var rung_count := geometry.rung_count()
	var hand_step: int = plan.hand_step
	var foot_step: int = plan.foot_step
	var hips: Vector3 = plan.hips
	# Staggers: the left hand and the right foot share a phase, the right hand and the left foot the other (a contralateral climb). With a two-rung step the stagger is one rung (a parity); with a
	# one-rung step it is a fraction of the window.
	var hand_phase := [0.25, 0.0] if hand_step == 1 else [0.5, 0.0]
	# The feet are a quarter window apart and each swings for at most a quarter of it, so one foot is always on a rung while the other moves.
	var foot_phase := [0.0, 0.25]
	var hand_back := GRIP_BEHIND * k
	var hand_below := GRIP_BELOW * k
	for side in 2:
		var x := profile.hand_half_spread * k * (1.0 if side == LEFT else -1.0)
		var hand := _limb_on_ladder(climbed, rung_count, hand_step, hand_phase[side], plan.hand_window_low, up, first, spacing, profile.swing_fraction)
		result.hand_rung[side] = hand.rung
		result.hand_swing[side] = hand.swing
		# Near the top the hands leave the last rungs for the deck edge (a blend over the last stretch of the climb; symmetric going down).
		var deck_start: float = float(plan.shoulder_height) + 0.1
		var deck := smoothstep(length - deck_start, length - deck_start + profile.deck_handhold_blend, climbed)
		result.hand_deck[side] = deck
		var on_rung := Vector3(x, hand.height - hand_below + sin(hand.swing * PI) * profile.swing_lift * 0.5 * k, plane - hand_back)
		var on_deck := Vector3(x, length - climbed + profile.deck_handhold_height, plane + profile.deck_handhold_ahead)
		result.hands[side] = on_rung.lerp(on_deck, deck)
		if deck > 0.5:
			result.hand_rung[side] = -1
		var fx := profile.foot_half_spread * k * (1.0 if side == LEFT else -1.0)
		var foot := _limb_on_ladder(climbed, rung_count, foot_step, foot_phase[side], plan.foot_window_low, up, first, spacing, minf(profile.swing_fraction, 0.25))
		result.foot_rung[side] = foot.rung
		result.foot_swing[side] = foot.swing
		var foot_y: float = foot.height + float(plan.ankle_above)
		result.feet[side] = Vector3(fx, foot_y + sin(foot.swing * PI) * profile.swing_lift, plane - float(plan.ankle_behind))
		var shoulder := Vector3((1.0 if side == LEFT else -1.0) * body.shoulder_offset.x, float(plan.shoulder_height), float(plan.shoulder_z))
		var hand_target: Vector3 = result.hands[side]
		# The deck handhold is let go of by the hand weight below, so only a hand that is meant to hold a rung is judged.
		result.hand_reachable[side] = deck > 0.5 or hand_target.distance_to(shoulder) <= body.arm_length() * 0.97
		var hip_joint := body.hip_joint(hips, side)
		result.foot_reachable[side] = (result.feet[side] as Vector3).distance_to(hip_joint) <= body.leg_length() * 0.97
	# Pelvis: back from the rung plane, at the ladder pelvis height, with a small sway toward the planted side (weight transfer between the two feet).
	var cycle := (climbed / (2.0 * spacing)) * TAU
	var sway := sin(cycle) * profile.weight_shift * k
	result.hips = Vector3(sway, hips.y, hips.z)
	# The hands let go once the rung they hold is below the reach of the arm (the arm is short): from the shoulder's height minus the span, over `hand_release_length`.
	var release_start: float = float(plan.shoulder_height) - float(plan.hand_reach) + RELEASE_LEAD
	var release := smoothstep(length - release_start, length - release_start + profile.hand_release_length, climbed)
	result.hand_weight = [weight * (1.0 - release), weight * (1.0 - release)]
	result.lean_degrees = profile.climb_lean_degrees
	result.twist_degrees = -sin(cycle) * profile.shoulder_twist_degrees
	result.head_pitch_degrees = profile.head_pitch_degrees * (1.0 if up else -0.7)
	return result


## Last section shared by climb-out and its reverse. The host supplies a real
## deck lip and horizontal progress. Foot and palm holds are deck-relative.
static func landing_start(geometry: LadderGeometry, body: LadderBody) -> float:
	return maxf(0.0, geometry.rise - maxf(0.62, body.shoulder_offset.y + body.arm_length()))


static func ladder_landing_pose(profile: TraversalProfile, geometry: LadderGeometry, body: LadderBody, climbed: float, direction: int, lip_from_rungs: float, across: float, brace_posts := Vector2.ZERO) -> Dictionary:
	var start := landing_start(geometry, body)
	var vertical := clampf(inverse_lerp(start, geometry.rise, climbed), 0.0, 1.0)
	var phase := vertical * 0.72 + clampf(across, 0.0, 1.0) * 0.28
	var pose := ladder_pose(profile, geometry, body, start, direction)
	var to_root := Vector3.UP * (start - climbed)
	var deck_y := geometry.rise - climbed
	var lip := geometry.plane_ahead + lip_from_rungs
	var lead := smoothstep(0.30, 0.65, phase)
	var trail := smoothstep(0.64, 0.91, phase)
	var rise := smoothstep(0.76, 1.0, phase)
	pose["foot_deck"] = [0.0, 0.0]
	for side in 2:
		var sign_side := 1.0 if side == LEFT else -1.0
		var progress := lead if side == LEFT else trail
		var from: Vector3 = pose.feet[side] + to_root
		var end := Vector3(sign_side * body.hip_offset.x, deck_y + body.ankle_height, lip + body.ball_length * (0.75 if side == LEFT else 1.55))
		# Bring the toe above the deck before carrying it through the lip.
		var lift := smoothstep(0.0, 0.32, progress)
		var reach := smoothstep(0.44, 1.0, progress)
		pose.feet[side] = Vector3(lerpf(from.x, end.x, reach), lerpf(from.y, end.y, lift) + sin(progress * PI) * body.ankle_height * 1.6, lerpf(from.z, end.z, reach))
		pose.foot_swing[side] = sin(progress * PI)
		pose.foot_deck[side] = smoothstep(0.35, 0.85, progress)
		if progress >= 1.0:
			pose.foot_rung[side] = -1

		var brace := smoothstep(0.05 + side * 0.06, 0.32 + side * 0.06, phase)
		var palm := Vector3(sign_side * body.shoulder_offset.x, deck_y + body.arm_length() * 0.10, lip + body.arm_length() * 0.21)
		if brace_posts.x > 0.0:
			palm = Vector3(sign_side * (brace_posts.x - body.arm_length() * 0.12), deck_y + brace_posts.y, lip - body.arm_length() * 0.06)
		pose.hands[side] = (pose.hands[side] as Vector3).lerp(palm - to_root, brace) + to_root
		pose.hand_deck[side] = brace
		# Release the trailing-side hand first as the pelvis shifts toward
		# the lead foot. It otherwise runs out of reach behind the shoulder.
		var release := smoothstep(0.73, 0.88, phase) if side == LEFT else smoothstep(0.64, 0.76, phase)
		pose.hand_weight[side] = lerpf(float(pose.hand_weight[side]), 1.0, brace) * (1.0 - release)

	var start_hips: Vector3 = pose.hips + to_root
	var pull := smoothstep(0.0, 0.76, phase)
	# The chest leans over the brace. Keep the pelvis above the lip rather
	# than fitting the shoulder reach by sinking the hips into the deck.
	var brace_height := body.arm_length() * 0.86 - body.shoulder_offset.y + 0.015 * body.ratio
	brace_height += brace_posts.y
	var hips := start_hips.lerp(Vector3(body.hip_offset.x * 0.45, deck_y + brace_height, lip + body.ball_length * 0.95), pull)
	hips.z = lerpf(start_hips.z, lip + body.ball_length * 0.95, smoothstep(0.36, 0.85, phase))
	var standing_height := body.ankle_height + body.leg_length() * 0.95 - body.hip_offset.y
	hips = hips.lerp(Vector3(0.0, deck_y + standing_height, 0.0), rise)
	# Respect the planted legs before the ordinary standing pose takes over.
	for side in 2:
		var ankle: Vector3 = pose.feet[side]
		var hip := body.hip_joint(hips, side)
		var reach := body.leg_length() * 0.98
		var horizontal := Vector2(hip.x - ankle.x, hip.z - ankle.z).length_squared()
		hips.y = minf(hips.y, ankle.y - body.hip_offset.y + sqrt(maxf(0.0, reach * reach - horizontal)))
	pose.hips = hips
	pose.weight = lerpf(float(pose.weight), 1.0, smoothstep(0.0, 0.25, phase)) * (1.0 - smoothstep(0.91, 1.0, phase))
	pose.on_ladder = pose.weight > 0.001
	pose["landing_phase"] = phase
	pose.lean_degrees = lerpf(float(pose.lean_degrees), 43.0, sin(phase * PI))
	for side in 2:
		pose.hand_reachable[side] = (pose.hands[side] as Vector3).distance_to(body.shoulder_joint(hips, side)) <= body.arm_length()
		pose.foot_reachable[side] = (pose.feet[side] as Vector3).distance_to(body.hip_joint(hips, side)) <= body.leg_length()
	return pose


## Where one limb is for a floor level `climbed`: the rung of its phase inside its window above the floor level, and how far it is through its swing to the next one. The limb moves `step` rungs
## (1 or 2) per move; its window is `step` pitches long and starts `window_low` above the floor level, shifted by `phase` windows so the limbs move one after another.
## Climbing: picked up at the low end of its window (reaching up); descending: at the high end (reaching down). rung -1 = no rung left (the deck).
static func _limb_on_ladder(climbed: float, rung_count: int, step: int, phase: float, window_low: float, up: bool, first: float, spacing: float, swing_fraction: float) -> Dictionary:
	var window := float(step) * spacing
	var low := window_low + (phase * window if step == 1 else 0.0)
	var wanted_low := climbed + low
	# Smallest rung index k >= 0 at or above the bottom of the window, on this limb's lattice (a two-rung step has two: odd and even rungs).
	var k := int(ceil((wanted_low - first) / spacing - 0.00001))
	k = maxi(k, 0)
	if step == 2 and (k % 2) != (1 if phase >= 0.5 else 0):
		k += 1
	var relative := (first + float(k) * spacing) - climbed
	var band := swing_fraction * window
	var swing := 0.0
	var target := k
	if up:
		var into := relative - low   # 0 right after the pick-up point .. window
		if into < band:
			swing = 1.0 - into / band          # about to be released: already travelling up to rung k + step
			target = k + step
	else:
		var into_down := (low + window) - relative
		if into_down < band:
			swing = 1.0 - into_down / band
			target = k - step
	swing = clampf(swing, 0.0, 1.0)
	if rung_count <= 0:
		return {"rung": -1, "height": 0.0, "swing": 0.0}
	# The rungs there are: past the top or the bottom a limb holds the last rung (both limbs may share it, they are a hand's width apart) instead of staying on one the body has left behind. The lattice
	# above the top is used only to time the swing off the last rung, so the same rule is continuous in both directions.
	var top := rung_count - 1
	var from_rung := clampi(k, 0, top)
	var to_rung := clampi(target, 0, top)
	var from_height := first + float(from_rung) * spacing
	var to_height := first + float(to_rung) * spacing
	if from_rung == to_rung:
		return {"rung": from_rung, "height": from_height - climbed, "swing": 0.0}
	var s := smoothstep(0.0, 1.0, swing)
	return {"rung": from_rung, "height": lerpf(from_height, to_height, s) - climbed, "swing": swing}


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
