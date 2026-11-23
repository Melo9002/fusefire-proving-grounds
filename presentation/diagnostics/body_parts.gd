class_name BodyParts
extends RefCounted
## Plain-language names for a rig's bones ("right shin", "left forearm"), from the rig's own role table (RigBones), never from bone-name strings: the same words work for every humanoid whose profile maps its roles.
## ADDA uses it so a finding says "Right shin" and carries the bone it means, instead of a skeleton name a newcomer cannot read.

const LEG_PARTS := ["thigh", "shin", "foot"]
const ARM_PARTS := ["upper arm", "forearm", "hand"]

## {side: "left"|"right"|"", part: "shin", limb: "leg"|"arm"|"torso"|"head", text: "right shin", bone: the bone name}. A bone the rig does not map answers part "" and text of the bone name itself.
static func describe(rig: CharacterRig, bone: String) -> Dictionary:
	var out := {"side": "", "part": "", "limb": "", "text": bone, "bone": bone}
	if not is_instance_valid(rig) or rig.bones == null:
		return out
	var b := rig.bones
	var chains := [["left", "leg", b.left_leg, LEG_PARTS], ["right", "leg", b.right_leg, LEG_PARTS], ["left", "arm", b.left_arm, ARM_PARTS], ["right", "arm", b.right_arm, ARM_PARTS]]
	for chain: Array in chains:
		var names: Array = chain[2]
		for i in names.size():
			if String(names[i]) == bone and i < (chain[3] as Array).size():
				return _make(chain[0], chain[1], chain[3][i], bone)
	for pair in [["left", b.left_toes, "toes"], ["right", b.right_toes, "toes"], ["left", b.left_shoulder, "shoulder"], ["right", b.right_shoulder, "shoulder"]]:
		if String(pair[1]) == bone and bone != "":
			return _make(pair[0], "leg" if pair[2] == "toes" else "arm", pair[2], bone)
	for pair in [[b.hips, "pelvis", "torso"], [b.spine, "spine", "torso"], [b.chest, "chest", "torso"], [b.upper_chest, "upper chest", "torso"], [b.neck, "neck", "head"], [b.head, "head", "head"]]:
		if String(pair[0]) == bone and bone != "":
			return _make("", pair[2], pair[1], bone)
	return out

static func _make(side: String, limb: String, part: String, bone: String) -> Dictionary:
	return {"side": side, "part": part, "limb": limb, "text": ("%s %s" % [side, part]).strip_edges(), "bone": bone}

## The sentence form with a capital ("Right shin").
static func title(rig: CharacterRig, bone: String) -> String:
	var text: String = describe(rig, bone).text
	return text.substr(0, 1).to_upper() + text.substr(1)

## The bones a plain name refers to ("right shin" -> its one bone; "left leg" -> its three), for selection and highlighting. Empty when the name means nothing on this rig.
static func bones_of(rig: CharacterRig, text: String) -> Array[String]:
	var found: Array[String] = []
	if not is_instance_valid(rig) or rig.skeleton == null:
		return found
	for index in rig.skeleton.get_bone_count():
		var name := rig.skeleton.get_bone_name(index)
		var d := describe(rig, name)
		if d.part == "":
			continue
		if d.text == text or ("%s %s" % [d.side, d.limb]).strip_edges() == text:
			found.append(name)
	return found

## Every nameable part of this rig, for a picker: ["left thigh", "left shin", ...], limbs first.
static func parts(rig: CharacterRig) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(rig) or rig.skeleton == null:
		return out
	for index in rig.skeleton.get_bone_count():
		var d := describe(rig, rig.skeleton.get_bone_name(index))
		if d.part != "" and not out.has(d.text):
			out.append(d.text)
	return out
