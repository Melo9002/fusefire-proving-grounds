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

## Rank of a timed hold (CharacterPresenter.begin_hold): a hold is refused (SKIPPED) while a higher-ranked one runs, and supersedes an equal or lower one (the older settles INTERRUPTED).
## Defeat is not a hold: it is terminal and outranks all of these. The default for a hold is REACTION, so a request that names no rank supersedes any other, as every hold did before ranks existed.
const HOLD_GESTURE := 10        ## a free expressive gesture (acknowledge): yields to anything else
const HOLD_INTERACTION := 20    ## a context interaction (an inspection)
const HOLD_REACTION := 30       ## a reaction or a state the body is put into (a hit, a landing, a pickup clip)
