class_name TraversalProfile
extends Resource
## Every number that shapes how a humanoid climbs a ladder, vaults an obstacle or mantles, in one editable place. PRESENTATION ONLY: which traversals are legal,
## their routes, AP cost and destinations belong to the tactical layer (SurfaceNavigation / TacticalActionService); this only decides what the body does along a route
## it has been given. All lengths are metres; rig-local frame: x = the character's left, y = up (from the floor under the root), z = forward (toward the ladder).

@export_group("Ladder geometry")
## Height of the lowest rung above the ladder's bottom floor, and the distance between rungs (maintenance_ladder_4m: 0.20 and 0.33). The rung positions are NOT exposed by
## MapData (only the bottom/top cells), so they are authored here; a ladder with other rungs needs its own profile or exposed metadata.
@export_range(0.05, 1.0, 0.01, "suffix:m") var first_rung_height := 0.20
@export_range(0.15, 0.6, 0.01, "suffix:m") var rung_spacing := 0.33
## Distance from the character's root (the tactical cell centre) to the rung plane, along the facing (+ = ahead). The authored ladder (maintenance_ladder_4m at z 7.45 in the
## 7.5 cell) sits 5 cm BEHIND the cell centre when facing the deck, so the climber's body hangs back from it (body_standoff) with the arms reaching to the plane.
@export_range(-0.5, 1.0, 0.01, "suffix:m") var ladder_plane_ahead := -0.05
## Half the distance between the hands / the feet on the rungs.
@export_range(0.1, 0.35, 0.01, "suffix:m") var hand_half_spread := 0.20
@export_range(0.05, 0.3, 0.01, "suffix:m") var foot_half_spread := 0.14

## The rung layout above is for a ladder of this rise (the authored asset is 4 m, 12 rungs). Authored parcels scale the asset to the climb they need (the test range's 3 m
## ladders are scaled 0.75), so with `rungs_follow_rise` the first rung and the spacing scale by rise / reference_rise. The route's rise is the only ladder fact the
## tactical map exposes; where the rungs really are is an environment metadata requirement.
@export_range(1.0, 8.0, 0.1, "suffix:m") var reference_rise := 4.0
@export var rungs_follow_rise := true
## A vertical route segment shorter than this is not a ladder (the one-metre ledge links of the test range are stepped climbs, not rungs).
@export_range(0.5, 4.0, 0.1, "suffix:m") var ladder_min_rise := 1.8

@export_group("Ladder body")
## How far behind the root (away from the ladder) the pelvis hangs, so the body clears the rungs. A controlled presentation offset inside the cell, never a tactical move.
@export_range(0.0, 0.5, 0.01, "suffix:m") var body_standoff := 0.30
## Pelvis height above the floor level under the root while climbing (the legs are bent against the rungs).
@export_range(0.5, 1.2, 0.01, "suffix:m") var hips_height := 0.90
## Height above that floor level at which a hand / a foot is picked up and put on the next rung of its parity (a rung 2 spacings up). Hands lead, feet follow.
@export_range(0.5, 1.6, 0.01, "suffix:m") var hand_window_low := 0.82
@export_range(-0.3, 0.5, 0.01, "suffix:m") var foot_window_low := -0.14
## Fraction of the window (from the end where the limb is picked up) over which the limb travels between rungs.
@export_range(0.1, 1.0, 0.01) var swing_fraction := 0.45
## Peak height the limb lifts clear of the rungs in a swing.
@export_range(0.0, 0.2, 0.005, "suffix:m") var swing_lift := 0.06
## Ankle height above the rung when the ball of the foot is on it, and how far behind the rung line the ankle sits.
@export_range(0.0, 0.2, 0.005, "suffix:m") var ankle_above_rung := 0.09
@export_range(0.0, 0.3, 0.005, "suffix:m") var ankle_behind_rung := 0.05
@export_range(0.0, 30.0, 0.5, "suffix:°") var climb_lean_degrees := 20.0
@export_range(0.0, 20.0, 0.5, "suffix:°") var shoulder_twist_degrees := 6.0
@export_range(0.0, 0.08, 0.005, "suffix:m") var weight_shift := 0.025
## The head looks up while climbing and down while descending.
@export_range(0.0, 40.0, 1.0, "suffix:°") var head_pitch_degrees := 14.0

@export_group("Mount and dismount")
## Climbed height over which the climber transfers from the floor to the ladder (hands first), and from the ladder to the top.
@export_range(0.1, 1.5, 0.01, "suffix:m") var mount_length := 0.5
@export_range(0.1, 1.5, 0.01, "suffix:m") var dismount_length := 0.5
## Where the hands rest on the deck while the climber comes over the top: how far past the rung plane, and the height above the deck.
@export_range(0.0, 0.8, 0.01, "suffix:m") var deck_handhold_ahead := 0.10
@export_range(0.0, 0.1, 0.005, "suffix:m") var deck_handhold_height := 0.02
## The hands let go of the last rungs and take the deck edge over this stretch of the climb, starting this far below the top.
@export_range(0.3, 2.0, 0.01, "suffix:m") var deck_handhold_start := 1.35
## The arms are short: once the shoulders are more than an arm's length above the deck the hands let go. They are released over this stretch of climb starting this far
## below the top (the hand contact weight; the legs and pelvis stay on the ladder until the dismount weight takes them off).
@export_range(0.3, 2.0, 0.01, "suffix:m") var hand_release_start := 0.85
@export_range(0.05, 1.0, 0.01, "suffix:m") var hand_release_length := 0.2
@export_range(0.1, 1.0, 0.01, "suffix:m") var deck_handhold_blend := 0.4

@export_group("Presentation speed")
## The tactical layer moves a unit along its route at one constant speed (5 m/s), so a 4 m ladder is over in 0.8 s: no readable climb. With this on, the unit's VISUAL
## travel along a ladder segment uses these speeds instead. Tactical state (cells, AP, replay) is unaffected; only how long the move takes to present changes. Off = the
## route speed, unchanged.
@export var slow_ladder_enabled := true
@export_range(0.2, 3.0, 0.05, "suffix:m/s") var climb_speed := 0.85
@export_range(0.2, 3.0, 0.05, "suffix:m/s") var descend_speed := 0.75

@export_group("Obstacles")
## Step-over: obstacle height at or below this is stepped over (hands stay free).
@export_range(0.05, 0.6, 0.01, "suffix:m") var step_over_max_height := 0.40
## Vault (hand-supported): up to this height; above it a mantle.
@export_range(0.3, 1.5, 0.01, "suffix:m") var vault_max_height := 1.10
@export_range(0.0, 0.4, 0.01, "suffix:m") var vault_hand_inset := 0.10
@export_range(0.0, 40.0, 1.0, "suffix:°") var vault_torso_lean_degrees := 22.0
## Hips clearance above the obstacle top while crossing.
@export_range(0.0, 0.6, 0.01, "suffix:m") var vault_hips_clearance := 0.22
@export_range(0.2, 2.0, 0.05, "suffix:m") var mantle_pull_height := 0.45
