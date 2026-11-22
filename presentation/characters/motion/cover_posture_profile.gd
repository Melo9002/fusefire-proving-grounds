class_name CoverPostureProfile
extends Resource
## Everything that shapes how a humanoid stands, crouches, turns and leans behind cover, in one editable place: REUSABLE BODY-MOTION PARAMETERS. PRESENTATION ONLY: cover eligibility,
## protection, visibility and facing rules belong to the tactical layer, and which wall edge to peek around is the tactical host's CoverEdgePolicy; this decides what the pose looks like once a host says "in cover".
##
## FACING CONTRACT. The unit's facing (the rig node's yaw) is the tactical/observation facing: toward the cover wall while idle, toward the target
## while attacking. It is never rewritten here. The cover pose is a yaw OFFSET of the body relative to that facing (`CharacterRig.character_root`).
##  * Protected (weapon down): the body turns `protected_yaw_degrees` toward the chosen peek edge (0 when no edge is usable), so the unit
##    stands ready along the wall facing the way it would move to look, never with its back to the wall.
##  * Aiming over LOW cover: offset 0, i.e. squarely at the target facing, eyes over the top.
##  * Aiming around a FULL wall: offset `peek_yaw_degrees` toward the chosen edge and a lean to that side.
## A facing change that arrives at once (a shot's `face_world_position`) is absorbed into the offset, so the body never snaps: it eases at
## `turn_degrees_per_second`.

@export_group("Body orientation")
@export_range(0.0, 90.0, 1.0, "suffix:°") var protected_yaw_degrees := 45.0
@export_range(0.0, 60.0, 1.0, "suffix:°") var peek_yaw_degrees := 20.0
@export_range(60.0, 720.0, 5.0, "suffix:°/s") var turn_degrees_per_second := 320.0

@export_group("Attack posture")
## Body yaw offset toward the firing edge while aiming at a target. 0 = square to the target (the facing already points at it, so the rifle does too); the
## lean toward the edge comes from the shoot_left / shoot_right clips.
@export_range(0.0, 45.0, 1.0, "suffix:°") var attack_aim_yaw_degrees := 0.0

@export_group("Crouch")
## Standing behind full cover: how far the knees bend while protected and while aiming (metres of hip drop on the reference body, scaled per body: see crouch_request).
@export_range(0.0, 0.4, 0.01, "suffix:m") var high_cover_crouch_depth := 0.12
@export_range(0.0, 0.4, 0.01, "suffix:m") var high_cover_aim_crouch_depth := 0.04
## Low cover: clearance of the head when hiding and of the eyes when looking over the top.
@export_range(0.0, 0.3, 0.01, "suffix:m") var head_clearance := 0.05
@export_range(0.0, 0.3, 0.01, "suffix:m") var eye_clearance := 0.05
@export_range(0.0, 0.3, 0.01, "suffix:m") var eye_below_head_top := 0.12
## Hip drop and kneel speeds.
@export_range(0.1, 5.0, 0.05, "suffix:m/s") var crouch_speed := 1.1
@export_range(0.5, 6.0, 0.1) var kneel_speed := 2.5


## Body yaw OFFSET (radians, relative to the unit's tactical facing) for a cover pose at a weapon blend (0 protected, 1 aiming). `side` is the chosen peek
## side (+1 right, -1 left, 0 none). Protected: toward the edge by `protected_yaw_degrees`. Aiming over LOW cover: square to the facing. Aiming around FULL
## cover: `peek_yaw_degrees` toward the edge. Turning right is a negative yaw. Shared by the game's adapter and the workbench so they cannot diverge.
func yaw_offset(full_cover: bool, side: int, blend: float) -> float:
	var toward_edge := -float(side)
	var protected := deg_to_rad(protected_yaw_degrees) * toward_edge
	var aimed := deg_to_rad(peek_yaw_degrees) * toward_edge if full_cover else 0.0
	return lerpf(protected, aimed, blend)


## Body yaw OFFSET while presenting an attack: the protected turn is toward `protected_side` (the passive choice, so the body does not jump when the weapon
## starts to rise), the aimed one toward `aimed_side` (the firing edge; usually a square-on 0).
func attack_yaw_offset(protected_side: int, aimed_side: int, blend: float) -> float:
	var protected := deg_to_rad(protected_yaw_degrees) * -float(protected_side)
	var aimed := deg_to_rad(attack_aim_yaw_degrees) * -float(aimed_side)
	return lerpf(protected, aimed, blend)


## Hip drop (metres, before the human limit) a cover pose asks for. FULL: a slight wary bend, a little less while aiming. LOW: hide so the head clears the
## top, rise so the eyes clear it when aiming. `standing_head_height` and `body_ratio` are the rig's (CoverCrouchModifier): the FULL bend is authored in metres for the
## reference body and scales with the leg; the LOW one already follows from this body's head height.
func crouch_request(full_cover: bool, cover_height: float, blend: float, standing_head_height: float, body_ratio := 1.0) -> float:
	if full_cover:
		return lerpf(high_cover_crouch_depth, high_cover_aim_crouch_depth, blend) * body_ratio
	var hide := standing_head_height - (cover_height - head_clearance)
	var peek := standing_head_height - eye_below_head_top - (cover_height + eye_clearance)
	return maxf(lerpf(hide, peek, blend), 0.0)
