class_name StairProfile
extends Resource
## Presentation settings for walking stairs: which treads get a foot (the contact policy), how the swing foot travels, and the speed the walk is shown at. PRESENTATION ONLY.
## Which links are stairs, and their tread layout, comes from the map (TraversalLinkData.surface_kind / treads_per_step, declared on the authored ElevationPath).

enum ContactPolicy { EVERY_TREAD, ALTERNATE, AUTO }

@export var enabled := true
@export var policy: ContactPolicy = ContactPolicy.AUTO
@export_group("Auto policy")
## AUTO puts a foot on every tread unless the unit is moving at least this fast (jog / run), when it puts one on every second tread (the stride is longer than the tread).
@export_range(1.0, 8.0, 0.1, "suffix:m/s") var alternate_from_speed := 3.0
## Skipping a tread puts the feet two treads apart: only allowed when that rise is at most this (the legs cannot span more; MIRA's are 0.84 m).
@export_range(0.1, 1.2, 0.01, "suffix:m") var max_step_rise := 0.55
## A carrier with a passenger always uses every tread (balance, load).
@export var loaded_uses_every_tread := true
@export_group("Swing")
## The swing foot rises this far above the higher of its two treads at mid-swing.
@export_range(0.0, 0.3, 0.005, "suffix:m") var swing_lift := 0.04
## The swing foot lifts first (over the first part of the swing) and travels after (the last part), so it clears the riser: fractions of the swing.
@export_range(0.0, 0.8, 0.01) var lift_phase := 0.6
@export_range(0.0, 0.8, 0.01) var travel_start := 0.3
## Ankle height above the tread when the sole is flat on it.
@export_range(0.0, 0.2, 0.005, "suffix:m") var ankle_height := 0.09
## Toe-in of the foot target on the tread (the ankle is this far back from the tread centre toward the heel).
@export_range(0.0, 0.2, 0.005, "suffix:m") var ankle_setback := 0.03
## Half the distance between the feet across the stair.
@export_range(0.03, 0.3, 0.005, "suffix:m") var foot_half_spread := 0.10
@export_group("Stance")
## A planted foot is not nailed to one point: through its stance it ROLLS (the ankle drifts forward as the body passes over it and the heel comes up toward toe-off), where it lands varies a little from tread to tread,
## and the pelvis shifts toward the foot that carries the weight. All of it is a pure function of where the body is along the stair (nothing accumulates), so replay, seeking and frame rate are unaffected. Off, the feet
## are locked at one point per hold and the pelvis keeps the gait's sideways motion (the earlier behaviour).
@export var stance_motion_enabled := true
## How far the ankle drifts forward over a whole stance, heel strike to toe-off (metres, along the travel direction). Kept small: the sole stays on its tread.
@export_range(0.0, 0.15, 0.005, "suffix:m") var stance_roll := 0.06
## How far the ankle rises by toe-off (the heel comes up), over the second half of the stance.
@export_range(0.0, 0.08, 0.0025, "suffix:m") var heel_lift := 0.03
## Where a foot lands varies by up to this much (along and across the tread), the same every time for the same tread: no two steps are identical copies.
@export_range(0.0, 0.04, 0.001, "suffix:m") var placement_variation := 0.012
## The pelvis shifts this far sideways toward the supporting foot (metres at full single support).
@export_range(0.0, 0.08, 0.0025, "suffix:m") var pelvis_sway := 0.025
@export_group("Pelvis")
## The pelvis is placed from the FEET (not from the floor under the root): high enough that no knee flexes past the limit, low enough that no leg overreaches. Leg length is the
## hip-to-ankle distance of the rig (CharacterRig measures it); the defaults are MIRA's.
@export_range(0.4, 1.4, 0.01, "suffix:m") var leg_length := 0.84
@export_range(0.5, 1.0, 0.01) var max_leg_extension := 0.97
@export_range(10.0, 90.0, 1.0, "suffix:°") var min_knee_interior_degrees := 45.0
## Where in its allowed range the pelvis sits: 0 = as low (bent) as allowed, 1 = as high as the legs reach.
@export_range(0.0, 1.0, 0.01) var pelvis_preference := 1.0
## The pelvis follows a SMOOTHED floor (the stair's own profile averaged over +-this much travel) plus this standing height, and is only pushed off it where a planted leg
## demands (overreach or a folded knee). That keeps it from jumping a whole riser each time a foot lands.
@export_range(0.0, 1.5, 0.05, "suffix:m") var pelvis_smoothing := 0.5
@export_range(0.5, 1.2, 0.01, "suffix:m") var pelvis_standing_height := 0.86
@export_group("Body path")
## The root rides the stair surface: it rises over this much run around each riser.
@export_range(0.05, 0.5, 0.01, "suffix:m") var riser_ramp := 0.50
## Level run past the last riser before the walk continues on the landing.
@export_range(0.0, 0.5, 0.01, "suffix:m") var landing_tail := 0.0
@export_group("Presentation speed")
## The route speed (5 m/s) would put a foot on a 0.5 m tread seven times a second. With this on, a stair is shown at `speed` m/s along its slope (replay scaling still applies);
## only the time the move takes to present changes, never cells, AP, positions or the replay record.
@export var slow_stairs_enabled := true
@export_range(0.3, 5.0, 0.05, "suffix:m/s") var speed := 1.4


## How many treads one step spans for a unit moving at `unit_speed` on treads of rise `tread_rise`. A forced ALTERNATE is honoured as given (a deliberate test of the limit);
## AUTO skips a tread only when the unit is fast, unloaded and the double rise is something the legs can span.
func step_treads(unit_speed: float, loaded: bool, tread_rise := 0.0) -> int:
	match policy:
		ContactPolicy.EVERY_TREAD:
			return 1
		ContactPolicy.ALTERNATE:
			return 2
	if loaded and loaded_uses_every_tread:
		return 1
	if tread_rise > 0.0 and tread_rise * 2.0 > max_step_rise:
		return 1
	return 2 if unit_speed >= alternate_from_speed else 1
