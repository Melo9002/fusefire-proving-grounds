class_name WeaponPoseSettings
extends RefCounted
## The live limits of the support arm's reach adjustment (see WeaponPoseModifier). They are the rig's inspector values (CharacterRig exposes them as properties that read and write this one
## object), shared by reference with the modifier, so the character's own limits apply and tests can tune them at run time. Defaults are the tuned production values.

## Most the support shoulder may be protracted in total (base reach plus what a target needs), degrees.
var protraction_limit_degrees := 18.0
## Elbow bend (interior angle, degrees) the support arm is eased toward when its target is nearly out of reach. 180 is a locked elbow.
var elbow_comfort_degrees := 165.0
## Bisection steps used to find the least extra protraction.
var solve_iterations := 8
