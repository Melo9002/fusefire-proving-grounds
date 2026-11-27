class_name PassengerDefinition
extends RefCounted
## Who a passive passenger is, described independently of the carrier: its character, model, scale and rig profile. The rig builds the carried body from it, the ground casualty is built from it, and the same
## definition travels with the body through pickup, carry, release and the next pickup, so a passenger keeps its identity at every stage.
##
## It reuses the identity the project already has: a character is a runtime rig scene (`art/characters/<id>/runtime/<id>_rig.tscn`, a CharacterRig whose `character_scene`, `character_scale` and `rig_profile` describe
## the body), which is also what the Workbench and the Exploration Playground select between. Nothing here lists characters or branches on a name: a compatible humanoid joins by having that scene. The body's
## proportions are never copied from the carrier: the passenger resolves its own bone roles from its own profile (RigBones) and its own skeleton.
##
## A rig built without a definition carries a passenger of its own kind (`from_rig`), which is what every caller that never mentions one gets.

const RIG_SCENE := "res://art/characters/%s/runtime/%s_rig.tscn"
const CHARACTER_ROOT := "res://art/characters"
## Used only when the character folder cannot be listed (an exported build).
const FALLBACK_KEYS: Array[StringName] = [&"mira_0", &"small_mira_0"]

static var _cache := {}

var character_id: StringName = &""
var scene: PackedScene
var scale := 1.0
var rig_profile: Resource


## The passenger that is the same character as `rig`'s own (what a rig carries when nobody says otherwise).
static func from_rig(rig: CharacterRig) -> PassengerDefinition:
	var definition := PassengerDefinition.new()
	definition.character_id = _id_of(rig.character_scene.resource_path if rig.character_scene != null else "", StringName(rig.name))
	definition.scene = rig.character_scene
	definition.scale = rig.character_scale
	definition.rig_profile = rig.rig_profile
	return definition


## The passenger for the character with this id (`mira_0`, `small_mira_0`, any folder under art/characters with a runtime rig scene). Cached; null when there is no such character.
static func for_character(id: StringName) -> PassengerDefinition:
	if _cache.has(id):
		return _cache[id]
	var path := RIG_SCENE % [id, id]
	if not ResourceLoader.exists(path):
		return null
	var definition := from_rig_scene(load(path) as PackedScene)
	if definition != null:
		definition.character_id = id
		_cache[id] = definition
	return definition


## The character id a model path belongs to (`res://art/characters/<id>/...`), or `fallback`.
static func _id_of(path: String, fallback: StringName) -> StringName:
	var parts := path.split("/")
	var at := parts.find("characters")
	return StringName(parts[at + 1]) if at >= 0 and at + 1 < parts.size() else fallback


## Reads the body a rig scene describes without keeping the rig: it is instantiated once outside the tree and freed.
static func from_rig_scene(rig_scene: PackedScene) -> PassengerDefinition:
	if rig_scene == null:
		return null
	var rig := rig_scene.instantiate() as CharacterRig
	if rig == null:
		return null
	var definition := from_rig(rig)
	rig.free()
	return definition


## Every character with a runtime rig scene, in a stable order.
static func known_characters() -> Array[StringName]:
	var found: Array[StringName] = []
	var directory := DirAccess.open(CHARACTER_ROOT)
	if directory != null:
		for folder in directory.get_directories():
			if ResourceLoader.exists(RIG_SCENE % [folder, folder]):
				found.append(StringName(folder))
	if found.is_empty():
		found.assign(FALLBACK_KEYS)
	found.sort()
	return found


## What a carried body of this identity looks like to diagnostics: its id and the scale it keeps.
func describe() -> Dictionary:
	return {"character": String(character_id), "scale": scale, "profile": rig_profile.resource_path if rig_profile != null else ""}


## True for the definition that describes `rig`'s own body.
func is_same_body_as(rig: CharacterRig) -> bool:
	return scene == rig.character_scene and rig_profile == rig.rig_profile and is_equal_approx(scale, rig.character_scale)
