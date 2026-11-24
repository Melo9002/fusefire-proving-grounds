class_name TuningFiles
extends RefCounted
## Drafts and the game for the Tune tab. An EXPERIMENT changes the live character and can be kept as a DRAFT (`tuning/drafts/<profile>.tres`, read only by the Workbench: CharacterRig.use_drafts). The game
## changes only through APPLY TO GAME, which writes the profile where the game reads it (CharacterRig.tuning_game_file) after the person has seen the list of changes. Discard puts the game's values back.
## The drafts folder is not committed (.gitignore): experiments stay on the machine they were made on.

## Where the draft of `property` lives ("" when the character has no tuning folder).
static func draft_path(rig: CharacterRig, property: StringName) -> String:
	var folder := rig.tuning_folder()
	return folder.path_join(CharacterRig.DRAFTS).path_join("%s.tres" % property) if folder != "" else ""

static func game_path(rig: CharacterRig, property: StringName) -> String:
	return String(rig.tuning_game_file.get(property, ""))

static func has_draft(rig: CharacterRig, property: StringName) -> bool:
	var path := draft_path(rig, property)
	return path != "" and FileAccess.file_exists(path)

## Keeps `live` as the draft. Returns the path, or "" on failure.
static func save_draft(rig: CharacterRig, property: StringName, live: Resource) -> String:
	var path := draft_path(rig, property)
	if path == "" or live == null:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return path if ResourceSaver.save(live.duplicate(true), path) == OK else ""   # a copy: the file never takes over the live profile

## Writes `live` where the game reads it, makes it the new game baseline and removes the draft. Returns the path written, or "".
static func apply_to_game(rig: CharacterRig, property: StringName, live: Resource) -> String:
	var path := game_path(rig, property)
	if path == "" or live == null:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if ResourceSaver.save(live.duplicate(true), path) != OK:
		return ""
	rig.tuning_game[property] = live.duplicate(true)
	_remove(draft_path(rig, property))
	return path

## Removes the draft and copies the game's values back into `live` (so everything holding it sees them).
static func discard(rig: CharacterRig, property: StringName, live: Resource) -> void:
	_remove(draft_path(rig, property))
	var game: Resource = rig.tuning_game.get(property)
	if game == null or live == null:
		return
	for entry in TuneTab.entries_of(live):
		var value: Variant = TuneTab.value_at(game, String(entry.path))
		if value != null:
			entry.owner.set(entry.name, value)

## Every value of `live` that differs from the game: [{path, label, game, now}], in declaration order.
static func changes(rig: CharacterRig, property: StringName, live: Resource) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var game: Resource = rig.tuning_game.get(property)
	if game == null or live == null:
		return out
	for entry in TuneTab.entries_of(live):
		var was: Variant = TuneTab.value_at(game, String(entry.path))
		var now: Variant = entry.owner.get(entry.name)
		if not same(was, now):
			out.append({"path": String(entry.path), "label": TuneTab.label_of(String(entry.name), String(TuneTab.range_of(entry).suffix)), "game": was, "now": now})
	return out

## Every tuned property's changes from the game, for a report: {property: [{path, game, now}]} (only properties with changes).
static func all_changes(rig: CharacterRig) -> Dictionary:
	var out := {}
	for property in CharacterRig.TUNED_PROFILES:
		var live: Resource = rig.stair_profile_source if property == &"stair_profile" and rig.stair_profile_source != null else rig.get(property)
		var list := changes(rig, property, live)
		if not list.is_empty():
			out[String(property)] = list.map(func(c: Dictionary) -> Dictionary: return {"path": c.path, "game": var_to_str(c.game), "now": var_to_str(c.now)})
	return out

static func same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 0.000001
	if a is Vector3 and b is Vector3:
		return (a as Vector3).is_equal_approx(b)
	return a == b

static func _remove(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
