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
	# Single writers (Task 07 package 3): the posture ramps and the locomotion feed have ONE owner. Only the rig applies the crouch/kneel (rescue requests its posture like everyone else, see below),
	# and only the presenter and the rig reach the locomotion feed; no host (adapter, workbench, panels) bypasses them.
	var ramp_writer := RegEx.create_from_string("crouch_modifier\\.(depth|kneel)\\s*=[^=]")
	var feed_caller := RegEx.create_from_string("update_locomotion_presentation\\(")
	var hosts := _scripts("presentation") + _scripts("art/characters")
	for path in hosts:
		var code := _code(path)
		if path != "presentation/characters/runtime/character_rig.gd":
			check(ramp_writer.search(code) == null, "%s writes the crouch depth or kneel directly: only CharacterRig applies the posture ramps" % path)
		if path != "presentation/characters/runtime/character_rig.gd" and path != "presentation/characters/presenter/character_presenter.gd":
			check(feed_caller.search(code) == null, "%s calls the locomotion feed directly: it goes through CharacterPresenter.tick" % path)
	# Rescue posture ownership (Task 07 package 5): the rescue lift and the carry's reset used to write the crouch directly. They request posture from the arbiter now, so inside the rig only
	# apply_posture_target writes the modifier's depth and kneel (the two assignments of the applied ramps), and the retired completion signal and polling are gone everywhere.
	var rig_code := _code("presentation/characters/runtime/character_rig.gd")
	var rig_writes := ramp_writer.search_all(rig_code)
	check(rig_writes.size() == 2, "CharacterRig writes the crouch depth/kneel in %d places: only apply_posture_target (2 assignments) may; rescue and carry request posture instead" % rig_writes.size())
	check(rig_code.contains("PRIORITY_ACTION") and rig_code.contains("RESCUE_POSTURE_SOURCE"), "The rescue lift requests its posture from the arbiter at ACTION priority")
	var retired := RegEx.create_from_string("rescue_interaction_finished|_on_rescue_interaction_finished")
	var sources: Array[String] = _scripts("presentation") + _scripts("art/characters") + _scripts("units") + _scripts("systems") + _scripts("levels") + _scripts("tests")
	for path in sources:
		if path == "tests/animation_module_boundaries_test.gd":
			continue
		check(retired.search(_code(path)) == null, "%s still uses the retired rescue_interaction_finished signal: observe the ActionHandle that begin_pickup/begin_release/present_pickup return" % path)
		# Combat presentation ownership (Task 07 package 6): the attack, the aim hold, the timed hit return and the rescue clock live in the presenter. The adapter, the rig and the workbench keep no clock,
	# timer or lifecycle state of their own for them, and nothing observes the retired signals or polls the retired "pending" accessor.
	var retired_state := RegEx.create_from_string("_return_generation|_return_to_idle_after|\battack_phase\b|\bAttackPhase\b|_aim_held|_aim_release_left|_presentation_clock|_attack_shot_state|_recover_left|\bshot_fired\b|attack_sequence_ended|is_attack_pending|_retarget_aim_blend|ATTACK_SOURCE|AIM_RELEASE_GRACE")
	for path in ["presentation/characters/runtime/unit_visual_adapter.gd", "presentation/characters/runtime/character_rig.gd", "art/characters/mira_0/demo/mira_0_pose_workbench.gd", "units/tactical_unit.gd", "presentation/actions/tactical_action_presenter.gd"]:
		var found := retired_state.search(_code(path))
		check(found == null, "%s still uses retired combat-presentation state (%s): it belongs to CharacterPresenter now" % [path, found.get_string() if found else ""])
	check(not _code("presentation/characters/runtime/unit_visual_adapter.gd").contains("create_timer("), "The adapter starts no scene-tree timer: timed states are the presenter's (begin_hold)")
	var advances := RegEx.create_from_string("rescue_interaction\\.advance\\(").search_all(rig_code + _code("presentation/characters/runtime/unit_visual_adapter.gd") + _code("art/characters/mira_0/demo/mira_0_pose_workbench.gd"))
	check(advances.size() == 1 and rig_code.contains("func advance_rescue_clock("), "The rescue clock is advanced in exactly one place (%d), CharacterRig.advance_rescue_clock, which only the presenter's action stage calls" % advances.size())
	var stage_callers := RegEx.create_from_string("advance_rescue_clock\\(")
	for path in _scripts("presentation") + _scripts("art/characters"):
		if path != "presentation/characters/runtime/character_rig.gd" and path != "presentation/characters/presenter/character_presenter.gd":
			check(stage_callers.search(_code(path)) == null, "%s advances the rescue clock itself: it is the presenter's action stage" % path)
	# Facing and persistent-action ownership (Task 07 package 7): the presenter decides facing and the rig applies it. Only the rig writes a yaw (its three appliers and the cover-yaw ramp); no host, adapter or
	# tactical unit writes the visual root yaw or the cover yaw; the committed Aim's progression and the pending pickup are the presenter's; TacticalUnit keeps no defeat timer for a character that has a lifecycle.
	var yaw_writer := RegEx.create_from_string("(^|[^_A-Za-z.])rotation\\.y\\s*=[^=]|character_root\\.rotation\\.y\\s*=[^=]|global_rotation\\.y\\s*=[^=]|_cover_yaw\\s*=[^=]")
	for path in ["presentation/characters/runtime/unit_visual_adapter.gd", "art/characters/mira_0/demo/mira_0_pose_workbench.gd", "units/tactical_unit.gd", "presentation/actions/tactical_action_presenter.gd"]:
		var found_yaw := yaw_writer.search(_code(path))
		check(found_yaw == null, "%s writes a yaw itself (%s): facing goes through CharacterPresenter and is applied by the rig" % [path, found_yaw.get_string() if found_yaw else ""])
	check(yaw_writer.search_all(rig_code).size() == 5, "CharacterRig writes a yaw in %d places: the cover-yaw setter, the ramp, apply_facing_yaw, apply_root_yaw and absorb_facing_change are the only ones (5)" % yaw_writer.search_all(rig_code).size())
	var presenter_code := _code("presentation/characters/presenter/character_presenter.gd")
	check(yaw_writer.search_all(presenter_code).size() == 1, "The presenter writes a yaw directly only to follow velocity (everything else goes through the rig's appliers)")
	check(RegEx.create_from_string("tactical_state|TacticalUnit|TacticalAction").search(presenter_code + _code("presentation/characters/presenter/aim_hold.gd")) == null, "The presenter reads no tactical state: the committed Aim arrives as a typed input")
	var retired_adapter := RegEx.create_from_string("_pending_pickup_world|_pending_lying_basis|_pending_handle|_sync_aim_hold|_on_pending_pickup_settled|_clear_pending_pickup")
	var found_retired := retired_adapter.search(_code("presentation/characters/runtime/unit_visual_adapter.gd"))
	check(found_retired == null, "The adapter still holds retired pending-pickup or aim-hold state (%s)" % [found_retired.get_string() if found_retired else ""])
	check(_code("units/tactical_unit.gd").count("create_timer(") == 1, "TacticalUnit keeps exactly one timer: the floor for a unit whose visual does not process (the presenter's removal handle covers every other defeat)")
	check(not _code("systems/replay/battle_replay_player.gd").contains("visual_adapter.global_basis"), "The replay player does not read the adapter's transform")
	# Route and traversal ownership (Task 07 package 8): TacticalUnit executes the walk and keeps no route-construction algorithm (TacticalRouteBuilder, in presentation/tactical, is the only one, and it
	# reaches into no unit, adapter or node); the rig's ladder climb and stair walk are typed objects, not dictionaries.
	var unit_code := _code("units/tactical_unit.gd")
	var route_algorithms := RegEx.create_from_string("PathRefiner|StairModel|SurfaceNavigation|_stair_run_end|_refine_flat_runs|_stair_model|VAULT_KIND|_leg_kind|_stair_ids|_stair_runs|_leg_kinds|last_path_report|_visual_segments|_ladder_toward_deck")
	var found_route := route_algorithms.search(unit_code)
	check(found_route == null, "TacticalUnit still holds route-construction code or state (%s): it belongs to TacticalRouteBuilder" % [found_route.get_string() if found_route else ""])
	check(unit_code.contains("TacticalRouteBuilder.expand(") and unit_code.contains("TacticalRouteBuilder.passthrough("), "TacticalUnit builds its presented route through TacticalRouteBuilder")
	var route_builder_code := _code("presentation/tactical/tactical_route_builder.gd")
	check(route_builder_code.contains("extends RefCounted") and RegEx.create_from_string("TacticalUnit|visual_adapter|UnitVisualAdapter|get_node|get_tree|add_child").search(route_builder_code) == null, "TacticalRouteBuilder is pure: no unit, adapter, node or scene-tree access")
	var traversal_dicts := RegEx.create_from_string("var (traversal|traversal_pose|stair_state|stair_pose)\\b")
	check(traversal_dicts.search(rig_code) == null and RegEx.create_from_string("\\b(traversal_pose|stair_state|stair_pose)\\b").search(rig_code + _code("presentation/characters/runtime/unit_visual_adapter.gd") + _code("art/characters/mira_0/demo/mira_0_pose_workbench.gd")) == null,
		"The rig, the adapter and the workbench keep no traversal or stair dictionary: the state is LadderClimb and StairWalk (typed)")
	# Rig independence (Task 07 package 9): no skeleton bone name in production code (the rig profile holds them), no required weapon, no dictionary-configured modifier, and the foot-point convention in the
	# composition: the visual scene has no origin offset and TacticalUnit places it.
	var skeleton_names := RegEx.create_from_string("mixamorig|J_Bip")
	for directory in ["presentation", "units", "systems", "art/characters"]:
		for path in _scripts(directory):
			var literal := skeleton_names.search(_code(path))
			check(literal == null, "%s names a skeleton bone (%s): asset-specific names belong in the rig profile (RigBones)" % [path, literal.get_string() if literal else ""])
	check(not rig_code.contains('preload("res://art/weapons') and not rig_code.contains("assert(weapon_scene") and not rig_code.contains("@export var right_arm_bones") and not rig_code.contains("@export var left_arm_bones"),
		"CharacterRig carries no default weapon, no weapon assertion and no exported bone names")
	for modifier_path in ["cover_crouch_modifier", "locomotion_pose_modifier", "hand_grip_modifier"]:
		var setup_line := RegEx.create_from_string("func setup\\([^)]*\\)").search(_code("presentation/characters/runtime/%s.gd" % modifier_path))
		check(setup_line != null and not setup_line.get_string().contains("Dictionary"), "%s is configured with typed inputs, not a dictionary" % modifier_path)
	check(not FileAccess.get_file_as_string("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").contains("Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -1, 0)") and unit_code.contains("func _place_visual()"),
		"The character visual scene has no origin offset (feet at its origin) and TacticalUnit composes it standing_height below the unit's origin")
	# The skeleton modifiers (Task 07 package 4): no lookup by name into any other object, the supported callback only, and no knowledge of the rig, the presenter or gameplay.
	var dynamic_access := RegEx.create_from_string("\\b(rig|owner|host|binding)\\.(get|set|call|callv)\\(|has_method\\(|get_indexed\\(")
	var owner_types := RegEx.create_from_string("\\b(CharacterRig|UnitVisualAdapter|CharacterPresenter|TacticalUnit)\\b")
	for path in ["cover_crouch_modifier", "hand_grip_modifier", "locomotion_pose_modifier", "traversal_pose_modifier", "weapon_pose_modifier"]:
		var file := "presentation/characters/runtime/%s.gd" % path
		var code := _code(file)
		var accesses := dynamic_access.search_all(code)
		var hit: String = accesses[0].get_string() if not accesses.is_empty() else ""
		check(accesses.is_empty(), "%s looks something up by name in another object (%s): modifiers use typed inputs" % [file, hit])
		check(not code.contains("_process_modification()"), "%s still uses the deprecated _process_modification() callback" % file)
		check(code.contains("func _process_modification_with_delta("), "%s does not implement the supported modifier callback" % file)
		check(owner_types.search(code) == null, "%s depends on the rig, the presenter or gameplay: a modifier consumes typed inputs only" % file)
	print("Animation module boundaries: %d checks, %d failure(s); %d known gameplay importer(s) remain" % [checks, failures, importers.size()])
	quit(1 if failures else 0)
