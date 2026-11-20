class_name CoverPostureProfile
extends Resource
## Everything that shapes how a humanoid stands, crouches, turns and leans behind cover, in one editable place. PRESENTATION ONLY: cover eligibility,
## protection, visibility and facing rules belong to the tactical layer; this decides what the pose looks like once the tactical state says "in cover".
##
## FACING CONTRACT. The unit's facing (the rig node's yaw) is the tactical/observation facing: toward the cover wall while idle, toward the target
## while attacking. It is never rewritten here. The cover pose is a yaw OFFSET of the body relative to that facing (`CharacterRig.character_root`).
##  * Protected (weapon down): the body turns `protected_yaw_degrees` toward the chosen peek edge (0 when no edge is usable), so the unit
##    stands ready along the wall facing the way it would move to look, never with its back to the wall.
##  * Aiming over LOW cover: offset 0, i.e. squarely at the target facing, eyes over the top.
##  * Aiming around a FULL wall: offset `peek_yaw_degrees` toward the chosen edge and a lean to that side.
## A facing change that arrives at once (a shot's `face_world_position`) is absorbed into the offset, so the body never snaps: it eases at
## `turn_degrees_per_second`.

@export_group("Edge selection")
## How far along the wall (metres) an edge may be and still count as a usable peek position.
@export_range(0.5, 6.0, 0.05, "suffix:m") var edge_reach := 2.2
## When the two usable edges are within this many metres of each other, `tie_side` wins.
@export_range(0.0, 1.0, 0.01, "suffix:m") var tie_tolerance := 0.25
## +1 right, -1 left.
@export_range(-1, 1, 2) var tie_side := 1
## The current side is kept unless the other edge is nearer by more than this (stops flicker from tiny position changes).
@export_range(0.0, 1.5, 0.01, "suffix:m") var hysteresis := 0.35
## How many extra wall cells along the wall are scanned for its end (tile maps).
@export_range(1, 12) var wall_scan_limit := 6

@export_group("Body orientation")
@export_range(0.0, 90.0, 1.0, "suffix:°") var protected_yaw_degrees := 45.0
@export_range(0.0, 60.0, 1.0, "suffix:°") var peek_yaw_degrees := 20.0
@export_range(60.0, 720.0, 5.0, "suffix:°/s") var turn_degrees_per_second := 320.0

@export_group("Crouch")
## Standing behind full cover: how far the knees bend while protected and while aiming (metres of hip drop).
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


## Hip drop (metres, before the human limit) a cover pose asks for. FULL: a slight wary bend, a little less while aiming. LOW: hide so the head clears the
## top, rise so the eyes clear it when aiming. `standing_head_height` is the rig's (CoverCrouchModifier).
func crouch_request(full_cover: bool, cover_height: float, blend: float, standing_head_height: float) -> float:
	if full_cover:
		return lerpf(high_cover_crouch_depth, high_cover_aim_crouch_depth, blend)
	var hide := standing_head_height - (cover_height - head_clearance)
	var peek := standing_head_height - eye_below_head_top - (cover_height + eye_clearance)
	return maxf(lerpf(hide, peek, blend), 0.0)
