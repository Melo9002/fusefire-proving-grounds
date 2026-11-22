extends SceneTree
## Enforceable module boundaries for character animation (Task 06 rules, Task 07 safety net). A ratchet: today's known violations are listed and may only shrink, so a NEW dependency fails here.
##   1. Shared character presentation (presentation/characters) must not import gameplay (units/, systems/, levels/, ui/, TacticalUnit). Known violators are allowlisted until they move to presentation/tactical.
##   2. The rig-profile data layer must not depend on runtime nodes (CharacterRig, TacticalCharacterAdapter, modifiers) or gameplay.
##   3. Pure solvers stay pure: no Node base class and no scene-tree access.
## Text-based on purpose: it needs no scene tree and fails with the file and the offending token.
const GAMEPLAY_PATTERN := "res://(units|systems|levels|ui)/|\\bTacticalUnit\\b|\\bTacticalAction"
## Shared character presentation (presentation/characters/) imports no gameplay. The tactical adapter and its policy live in presentation/tactical/ and may.
const KNOWN_GAMEPLAY_IMPORTERS: Array[String] = []
const RIG_PROFILE_DIRECTORIES := ["presentation/characters/rig_profile", "presentation/characters/equipment"]
const RUNTIME_NODE_PATTERN := "\\b(CharacterRig|TacticalCharacterAdapter|CoverCrouchModifier|LocomotionPoseModifier|WeaponPoseModifier|HandGripModifier|TraversalPoseModifier)\\b"
const PURE_SOLVER_FILES := [
	"presentation/characters/motion/stair_foot_planner.gd",
	"presentation/characters/motion/stair_model.gd",
	"presentation/characters/motion/traversal_solver.gd",
	"presentation/characters/motion/path_refiner.gd",
	"presentation/characters/motion/locomotion_gait.gd",
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
		check(path in KNOWN_GAMEPLAY_IMPORTERS, "%s imports gameplay; shared character presentation must not (the allowlist is empty: tactical code lives in presentation/tactical/)" % path)
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
		if path != "presentation/characters/rig/character_rig.gd":
			check(ramp_writer.search(code) == null, "%s writes the crouch depth or kneel directly: only CharacterRig applies the posture ramps" % path)
		if path != "presentation/characters/rig/character_rig.gd" and path != "presentation/characters/presenter/character_presenter.gd":
			check(feed_caller.search(code) == null, "%s calls the locomotion feed directly: it goes through CharacterPresenter.tick" % path)
	# Rescue posture ownership (Task 07 package 5): the rescue lift and the carry's reset used to write the crouch directly. They request posture from the arbiter now, so inside the rig only
	# apply_posture_target writes the modifier's depth and kneel (the two assignments of the applied ramps), and the retired completion signal and polling are gone everywhere.
	var rig_code := _code("presentation/characters/rig/character_rig.gd")
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
	for path in ["presentation/tactical/tactical_character_adapter.gd", "presentation/characters/rig/character_rig.gd", "tools/animation_workbench/pose_workbench.gd", "units/tactical_unit.gd", "presentation/tactical/tactical_action_presenter.gd"]:
		var found := retired_state.search(_code(path))
		check(found == null, "%s still uses retired combat-presentation state (%s): it belongs to CharacterPresenter now" % [path, found.get_string() if found else ""])
	check(not _code("presentation/tactical/tactical_character_adapter.gd").contains("create_timer("), "The adapter starts no scene-tree timer: timed states are the presenter's (begin_hold)")
	var advances := RegEx.create_from_string("rescue_interaction\\.advance\\(").search_all(rig_code + _code("presentation/tactical/tactical_character_adapter.gd") + _code("tools/animation_workbench/pose_workbench.gd"))
	check(advances.size() == 1 and rig_code.contains("func advance_rescue_clock("), "The rescue clock is advanced in exactly one place (%d), CharacterRig.advance_rescue_clock, which only the presenter's action stage calls" % advances.size())
	var stage_callers := RegEx.create_from_string("advance_rescue_clock\\(")
	for path in _scripts("presentation") + _scripts("art/characters"):
		if path != "presentation/characters/rig/character_rig.gd" and path != "presentation/characters/presenter/character_presenter.gd":
			check(stage_callers.search(_code(path)) == null, "%s advances the rescue clock itself: it is the presenter's action stage" % path)
	# Facing and persistent-action ownership (Task 07 package 7): the presenter decides facing and the rig applies it. Only the rig writes a yaw (its three appliers and the cover-yaw ramp); no host, adapter or
	# tactical unit writes the visual root yaw or the cover yaw; the committed Aim's progression and the pending pickup are the presenter's; TacticalUnit keeps no defeat timer for a character that has a lifecycle.
	var yaw_writer := RegEx.create_from_string("(^|[^_A-Za-z.])rotation\\.y\\s*=[^=]|character_root\\.rotation\\.y\\s*=[^=]|global_rotation\\.y\\s*=[^=]|_cover_yaw\\s*=[^=]")
	for path in ["presentation/tactical/tactical_character_adapter.gd", "tools/animation_workbench/pose_workbench.gd", "units/tactical_unit.gd", "presentation/tactical/tactical_action_presenter.gd"]:
		var found_yaw := yaw_writer.search(_code(path))
		check(found_yaw == null, "%s writes a yaw itself (%s): facing goes through CharacterPresenter and is applied by the rig" % [path, found_yaw.get_string() if found_yaw else ""])
	check(yaw_writer.search_all(rig_code).size() == 5, "CharacterRig writes a yaw in %d places: the cover-yaw setter, the ramp, apply_facing_yaw, apply_root_yaw and absorb_facing_change are the only ones (5)" % yaw_writer.search_all(rig_code).size())
	var presenter_code := _code("presentation/characters/presenter/character_presenter.gd")
	check(yaw_writer.search_all(presenter_code).size() == 1, "The presenter writes a yaw directly only to follow velocity (everything else goes through the rig's appliers)")
	check(RegEx.create_from_string("tactical_state|TacticalUnit|TacticalAction").search(presenter_code + _code("presentation/characters/presenter/aim_hold.gd")) == null, "The presenter reads no tactical state: the committed Aim arrives as a typed input")
	var retired_adapter := RegEx.create_from_string("_pending_pickup_world|_pending_lying_basis|_pending_handle|_sync_aim_hold|_on_pending_pickup_settled|_clear_pending_pickup")
	var found_retired := retired_adapter.search(_code("presentation/tactical/tactical_character_adapter.gd"))
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
	check(route_builder_code.contains("extends RefCounted") and RegEx.create_from_string("TacticalUnit|visual_adapter|TacticalCharacterAdapter|get_node|get_tree|add_child").search(route_builder_code) == null, "TacticalRouteBuilder is pure: no unit, adapter, node or scene-tree access")
	var traversal_dicts := RegEx.create_from_string("var (traversal|traversal_pose|stair_state|stair_pose)\\b")
	check(traversal_dicts.search(rig_code) == null and RegEx.create_from_string("\\b(traversal_pose|stair_state|stair_pose)\\b").search(rig_code + _code("presentation/tactical/tactical_character_adapter.gd") + _code("tools/animation_workbench/pose_workbench.gd")) == null,
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
		var setup_line := RegEx.create_from_string("func setup\\([^)]*\\)").search(_code("presentation/characters/rig/modifiers/%s.gd" % modifier_path))
		check(setup_line != null and not setup_line.get_string().contains("Dictionary"), "%s is configured with typed inputs, not a dictionary" % modifier_path)
	check(not FileAccess.get_file_as_string("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").contains("Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -1, 0)") and unit_code.contains("func _place_visual()"),
		"The character visual scene has no origin offset (feet at its origin) and TacticalUnit composes it standing_height below the unit's origin")
	# Composition (Task 07 package 10): the tactical adapter and the workbench are HOSTS of a CharacterRig, not CharacterRigs. A host owns its context (tactical reads, workbench controls) and drives its rig child
	# and that rig's presenter once per frame; the rig owns the skeleton, the modifiers, the targets and the poses and has no frame callback of its own.
	var adapter_code := _code("presentation/tactical/tactical_character_adapter.gd")
	var workbench_code := _code("tools/animation_workbench/pose_workbench.gd")
	check(adapter_code.contains("extends Node3D") and workbench_code.contains("extends Node3D"), "The tactical adapter and the workbench are plain Node3D hosts of a CharacterRig")
	for path in _scripts("presentation") + _scripts("art") + _scripts("units") + _scripts("tools") + _scripts("research"):
		check(RegEx.create_from_string("(?m)^extends\\s+(CharacterRig|TacticalCharacterAdapter)\\b").search(_code(path)) == null, "%s inherits the rig or the adapter: hosts compose a CharacterRig" % path)
	check(RegEx.create_from_string("(?m)^func _(physics_)?process\\(").search(rig_code) == null, "CharacterRig has no frame callback: its host advances it (the presenter tick and update_weapon_pose) exactly once per frame")
	for builder in ["_build_character", "_build_weapon_attachment", "_build_arm_ik", "_build_animation_controller"]:
		check(not adapter_code.contains(builder) and not workbench_code.contains(builder), "A host does not build the skeleton (%s): the rig builds itself" % builder)
	check(not adapter_code.contains("skeleton.add_child") or adapter_code.contains("CLASS_MARKER_NAME"), "The adapter attaches only its class marker to the skeleton")
	for scene_path in ["art/characters/mira_0/runtime/mira_0_unit_visual.tscn", "tools/animation_workbench/pose_workbench.tscn"]:
		var scene_text := FileAccess.get_file_as_string("res://" + scene_path)
		var hosts_rig := scene_text.contains('[node name="Rig" type="Node3D" parent="."]') and scene_text.contains("character_rig.gd")
		hosts_rig = hosts_rig or (scene_text.contains('[node name="Rig" parent="." instance=') and scene_text.contains("mira_0_rig.tscn"))
		check(hosts_rig, "%s hosts its CharacterRig as the Rig child" % scene_path)
	# Context independence (Task 08): the exploration host reads no tactical type, nothing shared knows the exploration host, the playground asks the presenter instead of reaching for clip states or facing,
	# and both hosts instance the same rig scene.
	var tactical_words := RegEx.create_from_string("Tactical|tactical_|GridManager|MapCellData|TurnManager|action_points|AIController|CoverEdge")
	for path in _scripts("presentation/exploration"):
		check(tactical_words.search(_code(path)) == null, "%s reads a tactical type: the exploration host knows no unit, turn, AP, grid or combat state" % path)
		check(_code(path).contains("extends Node3D") or _code(path).contains("extends"), "%s extends a node" % path)
	for path in _scripts("presentation/characters"):
		check(not _code(path).contains("ExplorationCharacterHost"), "%s (shared character presentation) names the exploration host" % path)
	var playground_code := _code("research/exploration_playground/exploration_playground.gd")
	check(not playground_code.contains("present_move") and not playground_code.contains("present_idle") and not playground_code.contains("update_locomotion") and not playground_code.contains("face_world_position") 			and not playground_code.contains("TacticalCharacterAdapter") and not playground_code.contains("animation_controller.play"),
		"The playground asks its host (report_velocity, face_point, set_crouched, inspect): no clip-state requests, no facing logic and no tactical adapter of its own")
	check(not playground_code.contains("func _physics_process"), "The playground moves its body per rendered frame, not on 60 Hz physics ticks (uneven steps are visible as a tremor at higher frame rates)")
	for scene_path in ["art/characters/mira_0/runtime/mira_0_unit_visual.tscn", "art/characters/mira_0/runtime/mira_0_exploration_visual.tscn"]:
		check(FileAccess.get_file_as_string("res://" + scene_path).contains("mira_0_rig.tscn"), "%s instances the shared rig scene (one MIRA setup for every context)" % scene_path)
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://research").path_join("animation_host_probe")), "The Task 03 host probe is retired: its checks live in exploration_host_test")
	# Cover (Task 07 package 10): the reusable body-motion parameters (CoverPostureProfile) are separate from the tactical edge-selection policy (CoverEdgePolicy, read by CoverEdgeSelector).
	var cover_profile_code := _code("presentation/characters/motion/cover_posture_profile.gd")
	var edge_fields := RegEx.create_from_string("var (edge_reach|tie_tolerance|tie_side|hysteresis|wall_scan_limit|open_side_threshold|straight_ahead_threshold|attack_side_hysteresis)\\b")
	check(edge_fields.search(cover_profile_code) == null, "CoverPostureProfile carries no edge-selection numbers: they are the tactical host's CoverEdgePolicy")
	check(not _code("presentation/tactical/cover_edge_selector.gd").contains("CoverPostureProfile") and _code("presentation/tactical/cover_edge_policy.gd").contains("extends Resource"),
		"CoverEdgeSelector reads a CoverEdgePolicy, never the body's CoverPostureProfile")
	# The skeleton modifiers (Task 07 package 4): no lookup by name into any other object, the supported callback only, and no knowledge of the rig, the presenter or gameplay.
	var dynamic_access := RegEx.create_from_string("\\b(rig|owner|host|binding)\\.(get|set|call|callv)\\(|has_method\\(|get_indexed\\(")
	var owner_types := RegEx.create_from_string("\\b(CharacterRig|TacticalCharacterAdapter|CharacterPresenter|TacticalUnit)\\b")
	for path in ["cover_crouch_modifier", "hand_grip_modifier", "locomotion_pose_modifier", "traversal_pose_modifier", "weapon_pose_modifier"]:
		var file := "presentation/characters/rig/modifiers/%s.gd" % path
		var code := _code(file)
		var accesses := dynamic_access.search_all(code)
		var hit: String = accesses[0].get_string() if not accesses.is_empty() else ""
		check(accesses.is_empty(), "%s looks something up by name in another object (%s): modifiers use typed inputs" % [file, hit])
		check(not code.contains("_process_modification()"), "%s still uses the deprecated _process_modification() callback" % file)
		check(code.contains("func _process_modification_with_delta("), "%s does not implement the supported modifier callback" % file)
		check(owner_types.search(code) == null, "%s depends on the rig, the presenter or gameplay: a modifier consumes typed inputs only" % file)
	# Motion families (Task 13): the shared contract (presentation/motion) and the non-humanoid examples (research/motion_families) must not depend on the humanoid stack or on tactical gameplay. The rule is for THESE
	# modules only: the humanoid implementation keeps all of those dependencies. The humanoid bridge is the one file that knows both the contract and the presenter.
	var humanoid_only := RegEx.create_from_string("\\b(CharacterRig|CharacterPresenter|CharacterAnimationController|Skeleton3D|SkeletonModifier3D|BoneAttachment3D|AnimationTree|TwoBoneIK3D|RigBones|RigProfile|RigResolver|PoseOwnership|HandContact|HandGripModifier|LocomotionPoseModifier|CoverCrouchModifier|TraversalPoseModifier|TraversalFootModifier|WeaponPoseModifier|StairFootPlanner|PostureArbiter|WeaponReadiness|AttackSequence|RescueInteraction|ExplorationCharacterHost|TacticalUnit|TacticalCharacterAdapter|TacticalAction\\w*)\\b")
	check(humanoid_only.search("var s: Skeleton3D") != null and humanoid_only.search("var r: CharacterRig") != null and humanoid_only.search("var o: PresentationTypes.Outcome") == null and humanoid_only.search("var h: ActionHandle") == null,
		"(control) the family gate matches humanoid and tactical types and lets the shared vocabulary through")
	var family_scripts := _scripts("presentation/motion") + _scripts("research/motion_families")
	check(family_scripts.size() >= 5, "the contract and the family examples are scanned (%d scripts)" % family_scripts.size())
	for path in family_scripts:
		var found_dependency := humanoid_only.search(_code(path))
		check(found_dependency == null, "%s depends on the humanoid stack or tactical gameplay (%s): a body family reaches the contract only" % [path, found_dependency.get_string() if found_dependency else ""])
	for path in _scripts("presentation/motion"):
		check(RegEx.create_from_string("\\b(WheeledPresenter|DronePresenter|PrimitiveBodies|HumanoidMotionBridge)\\b").search(_code(path)) == null, "%s (the shared contract) names a particular family: families extend it, it does not know them" % path)
	var contract_and_presenter: Array[String] = []
	for path in _scripts("presentation") + _scripts("research") + _scripts("units"):
		var text := _code(path)
		if RegEx.create_from_string("\\b(MotionRequest|MotionPresenter)\\b").search(text) != null and RegEx.create_from_string("\\bCharacterPresenter\\b").search(text) != null:
			contract_and_presenter.append(path)
	check(contract_and_presenter == ["presentation/characters/presenter/humanoid_motion_bridge.gd"], "only the humanoid bridge knows both the motion contract and CharacterPresenter (%s)" % [contract_and_presenter])
	for path in ["presentation/characters/presenter/character_presenter.gd", "presentation/characters/rig/character_rig.gd", "presentation/exploration/exploration_character_host.gd", "presentation/tactical/tactical_character_adapter.gd", "tools/animation_workbench/pose_workbench.gd"]:
		check(RegEx.create_from_string("\\b(MotionRequest|MotionPresenter|HumanoidMotionBridge)\\b").search(_code(path)) == null, "%s does not route through the motion contract: the humanoid per-frame path has no extra indirection" % path)
	# Architecture gates (Task 14). INVARIANTS, each with a control proving the pattern can fail.
	# A. Production never depends on research: research/ is evidence and sandboxes. The one allowed mention is Match Setup OPENING the playground by path string (it never loads a research class).
	var research_ref := RegEx.create_from_string("res://research/|\\b(WheeledPresenter|DronePresenter|PrimitiveBodies|MotionFamiliesDemo|ExplorationPlayground\\w*|Playground[A-Z]\\w*)\\b")
	check(research_ref.search("const X := \"res:" + "//research/a.tscn\"") != null and research_ref.search("var d: DronePresenter") != null and research_ref.search("var r: CharacterRig") == null, "(control) the production-isolation pattern matches research paths and families")
	var research_users: Array[String] = []
	for root in ["systems", "units", "presentation", "ui", "levels", "art", "content"]:
		for path in _scripts(root):
			if research_ref.search(_code(path)) != null:
				research_users.append(path)
	check(research_users == ["ui/match_setup.gd"], "production code must not depend on research/ (only ui/match_setup.gd may open the playground by path): %s" % [research_users])
	# B. Authority: the contract, the diagnostics, the family examples and the workbench read and draw; they never import gameplay or its authoritative state.
	var gameplay_ref := RegEx.create_from_string("res://(systems|units|levels)/|\\b(TacticalUnit|TacticalActionService|BattleController|ActionPointPool)\\b")
	check(gameplay_ref.search("preload(\"res:" + "//units/tactical_unit.gd\")") != null and gameplay_ref.search("var u: TacticalUnit") != null and gameplay_ref.search("var h: ActionHandle") == null, "(control) the authority pattern matches gameplay imports and lets the shared vocabulary through")
	var authority_scripts := _scripts("presentation/motion") + _scripts("presentation/diagnostics") + _scripts("research/motion_families") + _scripts("research/motion_families_demo") + _scripts("tools/animation_workbench")
	check(authority_scripts.size() >= 25, "the authority gate scans the contract, diagnostics, families, demo and workbench (%d scripts)" % authority_scripts.size())
	for path in authority_scripts:
		var gameplay_hit := gameplay_ref.search(_code(path))
		check(gameplay_hit == null, "%s reaches gameplay (%s): presentation and tools never read or change authoritative state" % [path, gameplay_hit.get_string() if gameplay_hit else ""])
	# C. Diagnostics are observational: they call no method that advances, drives, poses or tears down what they inspect, and write no bone.
	var driving_call := RegEx.create_from_string("\\.(apply_posture|begin_hold|begin_gesture|cancel_hold|cancel_gesture|report_velocity|set_scripted_motion|set_movement_authority|claim_hand_contact|release_hand_contacts|advance_actions|update_weapon_pose|teardown|tick|present|set_bone_pose\\w*|set_bone_global_pose\\w*|request_action)\\(")
	check(driving_call.search("rig.presenter.tick(delta)") != null and driving_call.search("skeleton.set_bone_pose_rotation(0, q)") != null and driving_call.search("presenter.hold_report()") == null, "(control) the observation pattern matches driving calls and lets read accessors through")
	for path in _scripts("presentation/diagnostics"):
		var driving := driving_call.search(_code(path))
		check(driving == null, "%s calls a driving or writing method (%s): diagnostics observe through read accessors only" % [path, driving.get_string() if driving else ""])
	# D. Hosts, diagnostics and tools use the rig and the presenter through PUBLIC members: a leading underscore is the owner's private state (Task 14 found two reaches in the tactical adapter and gave them public faces).
	var private_reach := RegEx.create_from_string("\\b(rig|presenter|character_rig)\\._[a-z]")
	check(private_reach.search("rig._cover_yaw") != null and private_reach.search("presenter._holds") != null and private_reach.search("rig.cover_yaw()") == null and private_reach.search("rig_scene._ready()") == null, "(control) the private-reach pattern matches underscore members and lets public ones through")
	var host_scripts := _scripts("presentation/tactical") + _scripts("presentation/exploration") + _scripts("presentation/diagnostics") + _scripts("tools/animation_workbench") + _scripts("research")
	check(host_scripts.size() >= 40, "the private-reach gate scans hosts, diagnostics, the workbench and research (%d scripts)" % host_scripts.size())
	for path in host_scripts:
		var reach := private_reach.search(_code(path))
		check(reach == null, "%s reaches into private state of the rig or presenter (%s): ask the owner for a public accessor" % [path, reach.get_string() if reach else ""])
	print("Animation module boundaries: %d checks, %d failure(s); %d known gameplay importer(s) remain" % [checks, failures, importers.size()])
	quit(1 if failures else 0)
