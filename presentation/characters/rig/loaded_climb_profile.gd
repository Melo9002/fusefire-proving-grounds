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
## Where the passenger's abdomen lies in the climbing carry, from the carrier's neck bone, in the carrier's frame (x left, y up, z forward), reference body.
@export var anchor_from_neck := Vector3(0.04, -0.12, -0.28)
## The passenger's turn relative to the ordinary carry's orientation, about the carrier's x (pitch), y (yaw) and z (roll) axes. A negative roll lifts the head end and lowers the legs.
@export var orientation_degrees := Vector3(0.0, 0.0, -55.0)
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
