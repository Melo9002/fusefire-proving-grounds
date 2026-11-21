class_name PresentationIntent
extends RefCounted
## A SNAPSHOT of what a context is asking the character to be right now (persistent state, not one-shot actions). Built by CharacterPresenter.intent() for tests, diagnostics and
## replay reconstruction; changing a snapshot changes nothing. Readiness reuses WeaponReadiness.Level instead of a second vocabulary.

var velocity := Vector3.ZERO                                  ## world space, metres per second; zero is standing
var facing_mode: PresentationTypes.FacingMode = PresentationTypes.FacingMode.FOLLOW_VELOCITY
var facing_point := Vector3.ZERO                              ## FACE_POINT: a world point
var facing_yaw := 0.0                                         ## FACE_YAW: radians, world
var posture: PresentationTypes.Posture = PresentationTypes.Posture.STAND
var posture_yaw_offset := 0.0                                 ## a body offset the context wants held, radians
var posture_depth := 0.0                                      ## how far into the posture, metres of lowering the winning request asked for
var readiness: WeaponReadiness.Level = WeaponReadiness.Level.LOWERED
var equipment: PresentationTypes.EquipmentState = PresentationTypes.EquipmentState.HELD
