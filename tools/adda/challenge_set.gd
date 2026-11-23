class_name ChallengeSet
extends RefCounted
## ADDA's diagnostic challenges: a symptom, a scenario and a configuration that anyone can run, and a SEALED known cause that is only used to inject the fault and to score an answer. The public index
## (tools/adda/challenges/index.json) holds what a solver may see: the id, the symptom in plain words, the scenario and the body. The sealed file (tools/adda/challenges/sealed/<id>.json) holds the fault and the
## answer key. A solver (a person or an agent) is asked not to open `sealed/`; the honour system is all that stops it, so a result is only "blind" if the solver says it did not look and its transcript shows it did not.
## The CLI injects the fault from the id (`adda run --challenge=<id>`) without printing it, and `adda score --challenge=<id> --stage=.. --bone=.. --kind=..` checks an answer.

const INDEX := "res://tools/adda/challenges/index.json"
const SEALED := "res://tools/adda/challenges/sealed/%s.json"


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func index() -> Array:
	var data = _read(INDEX)
	return data.challenges if data is Dictionary else []


static func public_of(id: String) -> Dictionary:
	for entry: Dictionary in index():
		if String(entry.id) == id:
			return entry
	return {}


## The fault to inject for a challenge ({} for a control with no fault, or an unknown id).
static func fault_of(id: String) -> Dictionary:
	var sealed = _read(SEALED % id)
	return (sealed.fault as Dictionary) if sealed is Dictionary and sealed.has("fault") else {}


## Scores an answer: {stage, bone, kind} each optional. Says which parts match; never prints the key itself on a miss.
static func score(id: String, answer: Dictionary) -> Dictionary:
	var sealed = _read(SEALED % id)
	if not (sealed is Dictionary):
		return {"ok": false, "error": "no such challenge '%s'" % id}
	var key: Dictionary = sealed.answer
	var parts := {}
	for field in ["stage", "bone", "kind"]:
		if key.has(field):
			parts[field] = answer.has(field) and String(answer[field]).to_lower() == String(key[field]).to_lower()
	var correct := true
	for field in parts:
		correct = correct and bool(parts[field])
	return {"ok": true, "challenge": id, "correct": correct, "fields": parts, "scored_fields": parts.keys()}
