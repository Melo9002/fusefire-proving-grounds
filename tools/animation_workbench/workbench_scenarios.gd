class_name WorkbenchScenarios
extends RefCounted
## The workbench's scenario presets. Each is DATA: a title, what it demonstrates, whether it needs a weapon, and timed steps that call the workbench's public controls. They compose capabilities the workbench
## already had (locomotion, turns, cover, attack, ladders, stairs, gestures); none sets up a match, a unit or a mission, and none adds a presentation capability.
##
## SYNTHETIC CONTEXT. A scenario stands in for a host. "Tactical-style" supplies what a tactical adapter would (a wall, an authorised target, a posture request) through the same production selectors and profiles,
## and says so; it is not combat and decides no outcome. "Exploration-style" drives the shared presenter's public API the way an exploration host does, with no tactical state at all.

const TACTICAL := &"tactical"
const EXPLORATION := &"exploration"
const CONTACTS := &"contacts"
const LANDING := &"landing"
const RESCUE := &"rescue"

static func all() -> Array[Dictionary]:
	return [tactical(), exploration(), contacts(), landing(), rescue()]

static func find(id: StringName) -> Dictionary:
	for scenario in all():
		if scenario.id == id:
			return scenario
	return {}

## Whether `scenario` can run on a rig: {ok, reason}. Unsupported combinations are named, never silently skipped.
static func supported(scenario: Dictionary, rig: CharacterRig) -> Dictionary:
	if scenario.needs_weapon and not rig.has_weapon():
		return {"ok": false, "reason": "needs a weapon (aiming and firing); this configuration is unarmed"}
	return {"ok": true, "reason": ""}

static func _step(t: float, label: String, run: Callable) -> Dictionary:
	return {"t": t, "label": label, "run": run}

static func tactical() -> Dictionary:
	var wall := {"full": false, "height": 0.9, "left": 1.5, "right": 1.5, "left_ok": true, "right_ok": true, "aim": false}
	return {"id": TACTICAL, "title": "A  Tactical-style presentation", "short": "A  Walk, take cover, aim and fire", "needs_weapon": true, "duration": 15.0,
		"summary": "Move, turn, take low cover, aim at an authorised target, fire, recover. Cover side, crouch and the shot choice come from the production CoverEdgeSelector and CoverPostureProfile.",
		"context": "SYNTHETIC tactical context: a wall and an authorised target position stand in for the tactical layer. No match, AP, grid or AI; the outcome of the shot is not decided here.",
		"steps": [
			_step(0.0, "advance at 2.4 m/s (side view)", func(b: Node3D) -> void:
				b.look_from(Vector3(3.6, 1.4, 0.2), Vector3(0, 0.85, 0.3))
				b.command_move(2.4)),
			_step(2.2, "turn left 90 deg while moving", func(b: Node3D) -> void: b.turn_by(90.0)),
			_step(4.2, "stop, take low cover", func(b: Node3D) -> void:
				b.command_stop()
				b.set_cover_demo(wall)),
			_step(6.0, "authorised target to the left: aim", func(b: Node3D) -> void: b.set_cover_target(Vector3(5, 0, 1.5))),
			_step(8.2, "fire", func(b: Node3D) -> void: b.fire_cover_shot()),
			_step(10.5, "end the attack, back to passive cover", func(b: Node3D) -> void: b.set_cover_target(null)),
			_step(12.5, "leave cover", func(b: Node3D) -> void: b.set_cover_demo({})),
		]}

static func exploration() -> Dictionary:
	return {"id": EXPLORATION, "title": "B  Exploration-style activity", "short": "B  Walk, crouch, gestures, a reaction", "needs_weapon": false, "duration": 17.0,
		"summary": "Walk, turn, crouch, stand, acknowledge, nod, inspect, then a reaction that interrupts a gesture. Armed or unarmed.",
		"context": "No tactical state. The steps use the shared CharacterPresenter's public API (postures, begin_gesture, begin_hold) the way an exploration host does. The reaction at the end shows an ActionHandle settling INTERRUPTED in the history.",
		"steps": [
			_step(0.0, "walk at 1.3 m/s", func(b: Node3D) -> void: b.command_move(1.3)),
			_step(2.5, "turn left 90 deg", func(b: Node3D) -> void: b.turn_by(90.0)),
			_step(4.5, "stop", func(b: Node3D) -> void: b.command_stop()),
			_step(5.0, "crouch", func(b: Node3D) -> void: b.set_pose_preset(1)),
			_step(6.8, "stand", func(b: Node3D) -> void: b.set_pose_preset(0)),
			_step(7.6, "gesture: acknowledge", func(b: Node3D) -> void: b.request_gesture(&"acknowledge")),
			_step(10.0, "gesture: nod", func(b: Node3D) -> void: b.request_gesture(&"nod")),
			_step(11.6, "inspect (interaction hold, crouches)", func(b: Node3D) -> void: b.request_inspect(1.8)),
			_step(14.0, "gesture, then a reaction interrupts it", func(b: Node3D) -> void: b.request_gesture(&"acknowledge")),
			_step(14.6, "reaction hold (rank 30)", func(b: Node3D) -> void: b.request_reaction(0.9)),
		]}

static func contacts() -> Dictionary:
	return {"id": CONTACTS, "title": "C  Contacts and traversal", "short": "C  Stairs, then climb a ladder", "needs_weapon": false, "duration": 13.0,
		"summary": "Climb a stair, then a ladder, interrupt the climb, and watch the contacts release. Contact diagnostics switch on: planned against final feet, target against wrist, reach margin.",
		"context": "The workbench supplies the progress the game would supply (distance along the stair, height up the ladder); the stair planner, leg IK, ladder solver and hand contacts are the production ones. Small MIRA's ladder reach deficit (issue 55) is visible here and is not fixed by this task.",
		"steps": [
			_step(0.0, "stairs up (0.17 rise, 0.33 tread, 12 treads)", func(b: Node3D) -> void:
				b.look_from(Vector3(3.4, 1.2, 0.3), Vector3(0, 0.8, 0.3))
				b.diagnostics_for_contacts()
				b.start_stair_demo(0.1667, 0.3333, 12, true, 1.4)),
			_step(5.0, "stairs end", func(b: Node3D) -> void: b.end_stair_demo()),
			_step(5.4, "ladder climb 4 m (three-quarter inspection view)", func(b: Node3D) -> void:
				b.look_from(Vector3(3.5, 2.2, 3.1), Vector3(0.0, 1.0, 0.05))
				b.start_ladder_demo(4.0, 1, 0.85)),
			_step(9.4, "interrupt the climb (release hands)", func(b: Node3D) -> void: b.end_ladder_demo()),
			_step(11.0, "free again", func(b: Node3D) -> void: b.command_stop()),
		]}


## The supported ladder transfer, on the production solver and rig (Issue #55 follow-up): a deck with posts, the ladder's own rails run on above the deck, and the landings that must NOT be treated as
## supported. Each supported landing is climbed and then entered from the deck in reverse. The unsupported ones show the fallback and why the rig refused them (Diagnostics tab, "Ladder landing").
static func landing() -> Dictionary:
	return {"id": LANDING, "title": "D  Ladder landing (supported transfer)", "short": "D  Get off the top of a ladder (several ways)", "needs_weapon": false, "duration": 17.0,
		"summary": "Climb onto a deck and come back down from it with the ladder's own rails running on above the deck as the handholds, then with free-standing posts instead. Then two landings that must stay on the fallback.",
		"context": "The workbench plays what a host plays: the climb, then the crossing of the deck's lip. The pose is the production TraversalSolver, rig and hand contacts; the landing is a LadderLanding (the same description the sandbox supplies). A landing the body cannot use is refused by the rig with the reason, and the ordinary climb-out plays.",
		"steps": [
			_step(0.0, "rails: climb and cross (the ladder's own rails run on above the deck; side-front inspection view)", func(b: Node3D) -> void:
				b.look_from(Vector3(3.2, 2.3, 2.4), Vector3(0.0, 1.1, 0.3))
				b.diagnostics_for_contacts()
				b.start_ladder_demo(3.0, 1, 0.85, 1.9, "rails")),
			_step(2.8, "rails: reverse entry from the deck", func(b: Node3D) -> void: b.start_ladder_demo(3.0, -1, 0.75, -1.0, "rails")),
			_step(5.4, "alternative: free-standing posts at the deck edge, climb and cross", func(b: Node3D) -> void: b.start_ladder_demo(3.0, 1, 0.85, 1.9, "posts")),
			_step(8.2, "posts: reverse entry from the deck", func(b: Node3D) -> void: b.start_ladder_demo(3.0, -1, 0.75, -1.0, "posts")),
			_step(10.8, "deck only (nothing to hold): fallback, ordinary climb-out", func(b: Node3D) -> void: b.start_ladder_demo(3.0, 1, 0.85, 1.9, "deck only")),
			_step(13.4, "lip too far for the arm: fallback, ordinary climb-out", func(b: Node3D) -> void: b.start_ladder_demo(3.0, 1, 0.85, 1.9, "too far")),
			_step(16.0, "free again", func(b: Node3D) -> void:
				b.end_ladder_demo()
				b.command_stop()),
		]}


## Rescue and carry: lift a casualty from the floor, carry it, set it down. The pickup, carry pose and release are the production RescueInteraction and carry poses; the bench only presses the same buttons the R, P, M and Q keys do.
static func rescue() -> Dictionary:
	return {"id": RESCUE, "title": "E  Rescue and carry", "short": "E  Pick someone up, carry, set down", "needs_weapon": false, "duration": 15.0,
		"summary": "Pick a casualty up from the floor, carry it walking, stop, then set it down. Armed or unarmed.",
		"context": "The workbench supplies the passenger a metre ahead, as the game supplies the rescued actor's place; the lift, carry contacts and release are the rig's. Hand contacts on the passenger show in the contact measurement.",
		"steps": [
			_step(0.0, "pickup from the floor (side view)", func(b: Node3D) -> void:
				b.look_from(Vector3(3.4, 1.3, 0.4), Vector3(0, 0.8, 0.5))
				b.diagnostics_for_contacts()
				b.rescue_pickup()),
			_step(5.0, "carry: walk at 1.0 m/s", func(b: Node3D) -> void: b.rescue_carry(1.0)),
			_step(9.0, "carry: stop", func(b: Node3D) -> void: b.rescue_carry(0.0)),
			_step(10.0, "set the casualty down", func(b: Node3D) -> void: b.rescue_release()),
			_step(14.0, "free again", func(b: Node3D) -> void: b.command_stop()),
		]}
