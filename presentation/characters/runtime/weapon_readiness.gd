class_name WeaponReadiness
extends RefCounted
## How ready the weapon is, independent of body posture. Presentation only.
##
## Levels are weapon concepts, not poses. Each weapon profile says what they look like
## (WeaponHandlingProfile: lowered carry, the Ready blend, the aimed pose), and the rig fits that
## to whatever the body is doing (standing, crouched, kneeling), so no clip exists per posture.
##
## The rig has one scalar, aim_blend, from 0 (lowered) to 1 (aimed). A level is a target for it.
## Actions ask for a level by source name and withdraw it when done; the highest request wins.
## A future Guard asks for READY or AIMED the same way an attack does, with no new machinery.
## STOWED is not requested here: the rig reports it while the unit carries someone.

enum Level { LOWERED, READY, AIMED, STOWED }

var _requests: Dictionary = {}

func request(source: StringName, level: Level) -> void:
	_requests[source] = level

func release(source: StringName) -> void:
	_requests.erase(source)

func has_request(source: StringName) -> bool:
	return _requests.has(source)

func clear() -> void:
	_requests.clear()

## Highest level any source is asking for. LOWERED when nothing asks.
func requested() -> Level:
	var highest := Level.LOWERED
	for source in _requests:
		var level: int = _requests[source]
		if level != Level.STOWED and level > highest:
			highest = level as Level
	return highest

## The aim blend a level asks for.
static func blend_for(level: Level, profile: WeaponHandlingProfile) -> float:
	match level:
		Level.AIMED: return 1.0
		Level.READY: return profile.ready_blend
		_: return 0.0

## The level the weapon is actually at, from the blend it has reached. AIMED means within the
## profile's alignment tolerance of the firing pose. Anything between lowered and aimed is READY
## (raised but not yet in the firing configuration), whether rising or falling.
static func level_for_blend(blend: float, profile: WeaponHandlingProfile) -> Level:
	if blend >= profile.aimed_blend_threshold():
		return Level.AIMED
	if blend > LOWERED_EPSILON:
		return Level.READY
	return Level.LOWERED

const LOWERED_EPSILON := 0.02

static func level_name(level: Level) -> StringName:
	match level:
		Level.LOWERED: return &"lowered"
		Level.READY: return &"ready"
		Level.AIMED: return &"aimed"
		_: return &"stowed"
