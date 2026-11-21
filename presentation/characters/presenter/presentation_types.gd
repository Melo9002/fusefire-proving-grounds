class_name PresentationTypes
extends RefCounted
## The shared vocabulary of character presentation (Task 04 contracts). Only enums and named constants live here: no state, no behaviour, no gameplay types.
## Weapon readiness is NOT repeated here; its vocabulary is WeaponReadiness.Level, which the presenter uses as it is.

## A body posture. The numeric values mean nothing to arbitration (priority is separate and explicit).
enum Posture { STAND, CROUCH, KNEEL }
## How the character's yaw is decided. Facing is presentation-owned unless gameplay authority supplies a yaw (FACE_YAW).
enum FacingMode { FOLLOW_VELOCITY, FACE_POINT, FACE_YAW, HOLD }
## What the body is physically holding. It grants or denies nothing: whether an action is allowed is decided by gameplay.
enum EquipmentState { NONE, HELD, SLUNG }
## How a one-shot action ended (see ActionHandle). Settled exactly once.
enum Outcome { COMPLETED, CANCELLED, INTERRUPTED, SKIPPED }

## Posture priority tiers, explicit integers with gaps for later insertion; independent of the Posture enum values.
const PRIORITY_BASE := 0        ## a context's ordinary posture
const PRIORITY_CONTEXT := 100   ## a context policy such as cover
const PRIORITY_ACTION := 200    ## a posture an action needs for its duration
const PRIORITY_FORCED := 300    ## a scripted or debug override
