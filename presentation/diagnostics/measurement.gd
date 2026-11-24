class_name Measurement
extends RefCounted
## ADDA's measurement envelope: one reading, with the identity, time, space, pose, method, units and limits that say what it is and what it is NOT. It is plain data (to_dict() is JSON-friendly) and read-only:
## nothing here touches a rig. The point is to stop one kind of measurement being read as proof of another (the ladder investigation read a skinned mesh outside `skeleton_updated`, got the base pose, and drew a
## geometric conclusion from it; a reading that carried "pose: base" and status STALE or UNAVAILABLE could not have done that silently).
##
## KIND says what was measured. A kind never stands for another: `establishes(other)` is true only for itself.
enum Kind { JOINT_POSITION, TARGET_ERROR, REACH_FEASIBILITY, SUPPORT_CLAIM, CAPSULE_OVERLAP, VERTEX_OVERLAP, MESH_INTERSECTION, PHYSICAL_COLLISION }
## STATUS says whether the number may be used. Only FRESH is evidence.
##   FRESH        taken inside the skeleton's `skeleton_updated` for the update it is being read in
##   STALE        taken for an earlier update (the pose has moved on), or outside an update at all
##   UNAVAILABLE  nothing could be read (no sample yet, no surface, nothing to measure against)
##   UNSUPPORTED  this body, context or method cannot produce this measurement at all
enum Status { FRESH, STALE, UNAVAILABLE, UNSUPPORTED }
## Which pose the value came from. FINAL = after every modifier; INTENDED = what a solver asked for; BASE = the animation pose WITHOUT the modifiers (never evidence of what is drawn); UNKNOWN.
enum Pose { FINAL, INTENDED, BASE, UNKNOWN }

## What each kind establishes and what it does not. Written into every exported report.
const MEANING := {
	Kind.JOINT_POSITION: ["where a bone is in the final pose", "that anything is in contact, or that the drawn mesh follows the bone"],
	Kind.TARGET_ERROR: ["how far a limb ended from the point a solver asked for", "that the target is reachable, correct, or a physical support"],
	Kind.REACH_FEASIBILITY: ["whether a point lies within the limb's length from its root (a display convention, 97% of the arm)", "that the pose reaches it, or that the rig enforces the limit"],
	Kind.SUPPORT_CLAIM: ["that the animation system CLAIMS a contact (owner, weight, plan)", "that the body is physically supported or touching anything"],
	Kind.CAPSULE_OVERLAP: ["overlap of approximate limb volumes (capsules from bone lengths and measured radii) with a shape", "that the drawn mesh intersects it: armor can be thicker or thinner than the capsule"],
	Kind.VERTEX_OVERLAP: ["how many sampled vertices of the drawn skinned mesh lie inside a shape", "a full intersection: a thin crossing between two vertices can be missed, and a vertex on a bar's axis reads the bar's whole radius"],
	Kind.MESH_INTERSECTION: ["triangle against shape intersection of the drawn mesh", "physical collision"],
	Kind.PHYSICAL_COLLISION: ["a physics engine's contact", "anything about the drawn mesh unless the shapes are the mesh"],
}

var kind: Kind = Kind.JOINT_POSITION
var status: Status = Status.FRESH
var pose: Pose = Pose.UNKNOWN
var name := ""
var value: Variant = null
var unit := ""
## Tolerance the value is meaningful to, in `unit`; negative = not stated.
var tolerance := -1.0
## "world", "character" (the rig's character_root frame, x left, y up, z forward) or "skeleton".
var space := ""
## What produced it: the class and entry point.
var source := ""
## How: one line a reader can check.
var method := ""
var limitations := ""
## Why it is not FRESH, when it is not.
var reason := ""
var character := ""
var scenario := ""
var frame := -1
var update := -1
var msec := -1


static func make(p_kind: Kind, p_name: String, p_value: Variant, p_unit: String) -> Measurement:
	var m := Measurement.new()
	m.kind = p_kind
	m.name = p_name
	m.value = p_value
	m.unit = p_unit
	m.limitations = String(MEANING[p_kind][1])
	return m


## A measurement that could not be taken, with the reason; its value is null on purpose.
static func missing(p_kind: Kind, p_name: String, p_status: Status, p_reason: String) -> Measurement:
	var m := make(p_kind, p_name, null, "")
	m.status = p_status
	m.reason = p_reason
	return m


func usable() -> bool:
	return status == Status.FRESH and value != null


## True only when this measurement is of the kind asked: a vertex count is not a mesh intersection, a capsule is not a vertex count, a claim is not a contact.
func establishes(claim: Kind) -> bool:
	return usable() and kind == claim


## Takes the sample's stamp and judges it against the witness (FRESH, STALE or UNAVAILABLE).
func stamped(witness: PoseWitness, p_stamp: Dictionary) -> Measurement:
	frame = int(p_stamp.get("frame", -1))
	update = int(p_stamp.get("update", -1))
	msec = int(p_stamp.get("msec", -1))
	if witness != null:
		var verdict := witness.judge(p_stamp)
		if verdict.status != Status.FRESH:
			status = verdict.status
			reason = verdict.reason
	return self


func with_identity(rig: CharacterRig, p_scenario := "") -> Measurement:
	character = identity_of(rig)
	scenario = p_scenario
	return self


static func identity_of(rig: CharacterRig) -> String:
	if not is_instance_valid(rig):
		return "(no rig)"
	var profile := "(no profile)"
	if rig.rig_profile != null:
		profile = String(rig.rig_profile.get("display_name"))
	return "%s | %s | %s" % [rig.get_parent().name if rig.get_parent() != null else rig.name, profile, "armed" if rig.has_weapon() else "unarmed"]


func to_dict() -> Dictionary:
	return {
		"name": name, "kind": Kind.keys()[kind], "status": Status.keys()[status], "pose": Pose.keys()[pose],
		"value": value, "unit": unit, "tolerance": tolerance, "space": space, "source": source, "method": method,
		"establishes": MEANING[kind][0], "does_not_establish": MEANING[kind][1], "limitations": limitations, "reason": reason,
		"character": character, "scenario": scenario, "frame": frame, "update": update, "msec": msec,
	}


func text() -> String:
	if not usable():
		return "%s: %s (%s)" % [name, Status.keys()[status], reason if reason != "" else "no value"]
	return "%s = %s %s [%s, %s pose, %s]" % [name, str(value), unit, Kind.keys()[kind], Pose.keys()[pose].to_lower(), space]
