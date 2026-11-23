class_name TraversalProfile
extends Resource
## Every number that shapes how a humanoid climbs a ladder, vaults an obstacle or mantles, in one editable place. PRESENTATION ONLY: which traversals are legal,
## their routes, AP cost and destinations belong to the tactical layer (SurfaceNavigation / TacticalActionService); this only decides what the body does along a route
## it has been given. All lengths are metres; rig-local frame: x = the character's left, y = up (from the floor under the root), z = forward (toward the ladder).

@export_group("Ladder geometry")
## The ladder itself (rung pitch, first rung, rails, plane) is NOT here: it is LadderGeometry, shared by the environment, the tools and every body. This is only how a body spreads its limbs on it.
## Half the distance between the hands / the feet on the rungs, for the reference body (a smaller body takes the same share of its own size: it is scaled by body_ratio).
@export_range(0.1, 0.35, 0.01, "suffix:m") var hand_half_spread := 0.20
@export_range(0.05, 0.3, 0.01, "suffix:m") var foot_half_spread := 0.14


@export_group("Ladder body")
## Pelvis height above the floor level under the root while climbing (the legs are bent against the rungs).
@export_range(0.5, 1.2, 0.01, "suffix:m") var hips_height := 0.90
## Nudges of the hand and foot windows from where the body puts them (the windows come from the body: where its shoulders are and how far its legs reach). Tuning only; 0 is the anatomy plan.
@export_range(-0.2, 0.2, 0.005, "suffix:m") var hand_window_bias := 0.0
@export_range(-0.2, 0.2, 0.005, "suffix:m") var foot_window_bias := 0.0
## How far the thigh may turn outward (the frog-leg stance that keeps a raised knee off the rungs) when the pelvis is placed.
@export_range(0.0, 60.0, 1.0, "suffix:°") var knee_turn_degrees := 35.0
## Fraction of the window (from the end where the limb is picked up) over which the limb travels between rungs.
@export_range(0.1, 1.0, 0.01) var swing_fraction := 0.45
## Peak height the limb lifts clear of the rungs in a swing.
@export_range(0.0, 0.2, 0.005, "suffix:m") var swing_lift := 0.06
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
@export_range(0.0, 0.8, 0.01, "suffix:m") var deck_handhold_ahead := 0.0
@export_range(0.0, 0.1, 0.005, "suffix:m") var deck_handhold_height := 0.02
## The hands let go of the last rungs over this stretch of the climb, starting where the arm can no longer reach them (from the body: shoulders minus arm span); likewise the deck handhold starts a hand above the shoulder.
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
