class_name LoadedClimbProfile
extends Resource
## How a carrier holds its passenger while it climbs a ladder: tuning DATA for the shared loaded-ladder presentation (LoadedLadderCarry), in the same spirit as the rig's other profiles. A character that needs
## different numbers supplies its own resource; the solver never names a character. Lengths are for the reference body and are scaled by the carrier's `body_ratio()`; angles are degrees.
##
## The technique is a shoulder-and-back carry: from the ordinary carry (the passenger lying across the shoulders, the right hand on its wrist and the left on its thigh) the passenger rolls onto the upper back,
## the body running diagonally across it with the legs drawn up, the LEFT hand keeps its hold on the thigh (the supporting arm) and the RIGHT hand lets go of the wrist and takes the rungs, with both legs climbing as
## they do unloaded. The transfer is continuous: the same anchor, orientation and limb pose are blended, never swapped.

## Seconds the transfer takes, each way (on the simulation clock).
@export_range(0.2, 3.0, 0.05, "suffix:s") var transfer_seconds := 0.9
## Which way the passenger's spine points (head end) and which way its belly faces, in the carrier's frame (x left, y up, z forward). The default is a back carry: the passenger upright on the carrier's back, leaning a little
## to the carrier's right, its back against the carrier's back (belly facing away, so its head lolls away from the ladder), narrow enough to pass between a ladder's rails.
@export var body_up := Vector3(-0.2, 1.0, 0.0)
@export var body_face := Vector3(0.0, 0.0, -1.0)
## An extra turn applied after the two above, degrees about the carrier's x, y and z (for fine tuning).
@export var orientation_degrees := Vector3.ZERO


## The turn of the ordinary carry's orientation that gives the passenger `body_up` and `body_face`, for a body whose ordinary carry mapping is `ordinary` (RescuePassenger.body_basis_in_carrier()).
func orientation_from(ordinary: Basis) -> Basis:
	var up := body_up.normalized()
	var face := (body_face - up * body_face.dot(up)).normalized()
	var wanted := Basis(up.cross(face).normalized(), up, face)   # the passenger's x, y and z in the carrier's frame
	return Basis.from_euler(orientation_degrees * (PI / 180.0)) * wanted * ordinary.inverse()


## Where the passenger's abdomen lies in the climbing carry, from the carrier's neck bone, in the carrier's frame (x left, y up, z forward), reference body.
@export var anchor_from_neck := Vector3(0.04, -0.12, -0.28)
## Pose-table overrides for the climbing carry. The limbs' own hang is derived from the turn (they hang along the real down); anything named here replaces that.
@export var pose_overrides := {}
## Which carrier hand lets go of the passenger to climb ("right" or "left"); the other keeps its hold throughout.
@export var free_hand: StringName = &"right"
## How far the trunk leans into the ladder with the load on it, degrees (the unloaded climb's own lean applies to the rest).
@export_range(0.0, 45.0, 0.5, "suffix:°") var climb_lean_degrees := 22.0
## How far across the deck lip a carrier is (0 to 1) when the passenger starts coming back to the ordinary carry, going up. Going down it starts this far (metres of climb) above the floor.
@export_range(0.0, 1.0, 0.05) var restore_across := 0.2
@export_range(0.0, 2.0, 0.05, "suffix:m") var restore_height := 0.55
## How far the passenger's transfer lifts it over the carrier's shoulder on its way (metres), so it passes over the neck and head, not through them.
@export_range(0.0, 0.3, 0.005, "suffix:m") var transfer_arc := 0.09
