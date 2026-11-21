extends Resource
## Task 05 PROTOTYPE. The authored (not derivable) facts about a body. No gameplay role, faction, class, AP or mission field belongs here.
const JointSpec := preload("res://presentation/characters/rig_profile/rig_joint_spec.gd")
## Multiplies the skeleton's native units to metres, exactly once. Must equal the scale the model is actually shown at (checked when the skeleton is in a scene tree).
@export var character_scale := 1.0
## The bone at the very top of the head (an end bone), when the skeleton has one.
@export var head_top_bone: StringName = &""
## Standing height in metres when the skeleton has no head-top bone (manual authoring). 0 means "not declared".
@export var declared_height := 0.0
@export var joints: Array[JointSpec] = []
