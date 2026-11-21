extends SceneTree
## Enforceable module boundaries for character animation (Task 06 rules, Task 07 safety net). A ratchet: today's known violations are listed and may only shrink, so a NEW dependency fails here.
##   1. Shared character presentation (presentation/characters) must not import gameplay (units/, systems/, levels/, ui/, TacticalUnit). Known violators are allowlisted until they move to presentation/tactical.
##   2. The rig-profile data layer must not depend on runtime nodes (CharacterRig, UnitVisualAdapter, modifiers) or gameplay.
##   3. Pure solvers stay pure: no Node base class and no scene-tree access.
## Text-based on purpose: it needs no scene tree and fails with the file and the offending token.
const GAMEPLAY_PATTERN := "res://(units|systems|levels|ui)/|\\bTacticalUnit\\b|\\bTacticalAction"
const KNOWN_GAMEPLAY_IMPORTERS := [
	"presentation/characters/runtime/tactical_pose_context.gd",
	"presentation/characters/runtime/unit_visual_adapter.gd",
]
const RIG_PROFILE_DIRECTORIES := ["presentation/characters/rig_profile", "presentation/characters/equipment"]
const RUNTIME_NODE_PATTERN := "\\b(CharacterRig|UnitVisualAdapter|CoverCrouchModifier|LocomotionPoseModifier|WeaponPoseModifier|HandGripModifier|TraversalPoseModifier)\\b"
const PURE_SOLVER_FILES := [
	"presentation/characters/runtime/stair_foot_planner.gd",
	"presentation/characters/runtime/stair_model.gd",
	"presentation/characters/runtime/traversal_solver.gd",
	"presentation/characters/runtime/path_refiner.gd",
	"presentation/characters/runtime/locomotion_gait.gd",
]
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _scripts(directory: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open("res://" + directory)
	if dir == null:
		return result
	for entry in dir.get_directories():
		result.append_array(_scripts(directory + "/" + entry))
	for file in dir.get_files():
		if file.get_extension() == "gd":
			result.append(directory + "/" + file)
	return result

func _code(path: String) -> String:
	# Comments are not dependencies: strip them before matching.
	var lines: Array[String] = []
	for line in FileAccess.get_file_as_string("res://" + path).split("\n"):
		var cut := line.find("#")
		lines.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(lines)

func _run() -> void:
	var gameplay := RegEx.create_from_string(GAMEPLAY_PATTERN)
	var runtime_nodes := RegEx.create_from_string(RUNTIME_NODE_PATTERN)
	var scanned := 0
	var importers: Array[String] = []
	for path in _scripts("presentation/characters"):
		scanned += 1
		if gameplay.search(_code(path)) != null:
			importers.append(path)
	check(scanned > 20, "The character presentation scan found its scripts (%d)" % scanned)
	for path in importers:
		check(path in KNOWN_GAMEPLAY_IMPORTERS, "%s imports gameplay; shared character presentation must not (the allowlist is only for the known two)" % path)
	for path in KNOWN_GAMEPLAY_IMPORTERS:
		check(FileAccess.file_exists("res://" + path), "Allowlisted file %s no longer exists: delete it from KNOWN_GAMEPLAY_IMPORTERS" % path)
		check(path in importers or not FileAccess.file_exists("res://" + path), "%s no longer imports gameplay: remove it from KNOWN_GAMEPLAY_IMPORTERS so the ratchet tightens" % path)
	var profile_files := 0
	for directory in RIG_PROFILE_DIRECTORIES:
		for path in _scripts(directory):
			profile_files += 1
			var code := _code(path)
			check(runtime_nodes.search(code) == null, "%s (rig-profile layer) depends on a runtime node class" % path)
			check(gameplay.search(code) == null, "%s (rig-profile layer) imports gameplay" % path)
	check(profile_files >= 8, "The rig-profile layer scan found its scripts (%d)" % profile_files)
	for path in PURE_SOLVER_FILES:
		if not FileAccess.file_exists("res://" + path):
			check(false, "Pure solver %s is missing; update PURE_SOLVER_FILES with its new path" % path)
			continue
		var code := _code(path)
		var base := RegEx.create_from_string("(?m)^extends\\s+(\\w+)").search(code)
		check(base != null and base.get_string(1) in ["RefCounted", "Resource", "Object"], "%s must stay a pure RefCounted/Resource solver (extends %s)" % [path, base.get_string(1) if base else "nothing"])
		check(RegEx.create_from_string("\\bget_tree\\(|\\bget_node\\(|\\badd_child\\(|\\$[A-Za-z]").search(code) == null, "%s touches the scene tree; solvers take numbers and return data" % path)
	print("Animation module boundaries: %d checks, %d failure(s); %d known gameplay importer(s) remain" % [checks, failures, importers.size()])
	quit(1 if failures else 0)
