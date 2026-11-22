class_name DiagnosticsTab
extends VBoxContainer
## "What is the animation system actually doing?" Live presentation state and a bounded event history (PresentationMonitor), the pose stages in execution order with their live state and declared writes
## (PoseStageReport), "why is this bone moving", and the contact, trail and weapon-grip overlays, each switchable on its own. RUNTIME values and DECLARED ownership are labelled apart: a declaration is never shown as a measurement.

var bench: Node3D
var _live: Label
var _history: Label
var _stages: Label
var _stage_choice: OptionButton
var _bone_choice: OptionButton
var _explain: Label
var _contact: Label
var _recording: Label
var _layer_checks: Dictionary = {}
var _master: CheckBox
var _trail: CheckBox
var _grip: CheckBox
var _bones: Array[String] = []

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 5)
	# What a developer looks at first is first: the live state, then the contact measurement, then what just happened.
	var live := WorkbenchUI.section(self, "Live presentation  (runtime values)")
	_live = WorkbenchUI.mono("", 12)
	live.add_child(_live)
	var measured := WorkbenchUI.section(self, "Contact measurement  (final pose)")
	_contact = WorkbenchUI.mono("", 12)
	measured.add_child(_contact)
	measured.add_child(WorkbenchUI.row([["Record contacts", _start_recording], ["Stop and summarise", _stop_recording]]))
	_recording = WorkbenchUI.mono("", 12)
	measured.add_child(_recording)
	var events := WorkbenchUI.section(self, "Recent events  (presenter clock)")
	_history = WorkbenchUI.mono("", 12)
	events.add_child(_history)

	var overlays := WorkbenchUI.section(self, "Overlays  (each on its own)")
	_master = WorkbenchUI.check("Contact error diagnostics (master)", bench.diagnostics.contacts_on(), func(on: bool) -> void: bench.diagnostics.set_contacts(on),
		"Targets, final wrists and ankles, error, reach margin. Works armed or unarmed.")
	overlays.add_child(_master)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	overlays.add_child(grid)
	for layer in ContactErrorDiagnostics.LAYERS:
		var check := WorkbenchUI.check(ContactErrorDiagnostics.LAYER_SHORT[layer], layer != "frames", func(on: bool) -> void:
			if is_instance_valid(bench.diagnostics.contacts):
				bench.diagnostics.contacts.set_layer(layer, on), ContactErrorDiagnostics.LAYERS[layer])
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_layer_checks[layer] = check
		grid.add_child(check)
	_grip = WorkbenchUI.check("Weapon grip (H)", false, func(_on: bool) -> void: bench._toggle_diagnostics(), "The existing palm and grip diagnostics; needs a weapon.")
	_trail = WorkbenchUI.check("Root trail", false, func(on: bool) -> void: bench.diagnostics.set_trail(on), "Where the root went; colour is speed.")
	for node: CheckBox in [_grip, _trail]:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(node)
	for entry in [["Cover lines", bench.cover_diagnostics, func(on: bool) -> void: bench.cover_diagnostics = on, "Facing, weapon direction, wall normal"],
			["Ladder markers", bench.traversal_diagnostics, func(on: bool) -> void: bench.traversal_diagnostics = on, "Ladder solver's hand and foot targets"],
			["Stair markers", bench.stair_diagnostics, func(on: bool) -> void: bench.stair_diagnostics = on, "Planned and actual feet"]]:
		var node := WorkbenchUI.check(entry[0], entry[1], entry[2], entry[3])
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(node)
	overlays.add_child(WorkbenchUI.label("Yellow diamond = intended target, cyan cross = solved wrist, red line = error, green line = reach within the arm, red = beyond it. Feet: green diamond = planned, orange cross = ankle.", 11, WorkbenchUI.DIM))

	var stages := WorkbenchUI.section(self, "Pose stages  (order, declared, live)")
	_stages = WorkbenchUI.mono("", 11)
	stages.add_child(_stages)
	stages.add_child(WorkbenchUI.label("Highlight the bones a stage is DECLARED to write:", 12, WorkbenchUI.DIM))
	_stage_choice = OptionButton.new()
	_stage_choice.add_item("(none)")
	for stage in PoseOwnership.STAGE_ORDER:
		_stage_choice.add_item(String(stage))
	_stage_choice.item_selected.connect(_pick_stage)
	stages.add_child(_stage_choice)
	stages.add_child(WorkbenchUI.label("Why is this bone moving? (bones that play an ownership role)", 12, WorkbenchUI.DIM))
	_bone_choice = OptionButton.new()
	_bone_choice.add_item("(pick a bone)")
	for index in bench.rig.skeleton.get_bone_count():
		var bone_name: String = bench.rig.skeleton.get_bone_name(index)
		var role := PoseOwnership.role_of(bench.rig.bones, bone_name)
		if role != &"" and role != &"fingers":
			_bones.append(bone_name)
			_bone_choice.add_item("%s  (%s)" % [bone_name, role])
	_bone_choice.item_selected.connect(_pick_bone)
	stages.add_child(_bone_choice)
	_explain = WorkbenchUI.mono("", 11)
	stages.add_child(_explain)

func sync() -> void:
	_master.set_pressed_no_signal(bench.diagnostics.contacts_on())
	_trail.set_pressed_no_signal(bench.diagnostics.trail_on())

func _pick_stage(index: int) -> void:
	if index <= 0:
		bench.diagnostics.highlight_bones([])
		return
	bench.diagnostics.highlight_bones(PoseStageReport.bones_of_stage(bench.rig, PoseOwnership.STAGE_ORDER[index - 1]), Color(1.0, 0.6, 0.2))

func _pick_bone(index: int) -> void:
	if index <= 0:
		_explain.text = ""
		bench.diagnostics.highlight_bones([])
		return
	var bone_name := _bones[index - 1]
	bench.diagnostics.highlight_bones([bone_name] as Array[String])
	var info: Dictionary = PoseStageReport.explain_bone(bench.rig, bone_name)
	var lines: Array[String] = ["%s  role %s" % [bone_name, info.role]]
	if info.clip_only:
		lines.append("no stage declares a write to it: only the clip moves it")
	for writer: Dictionary in info.declared_writers:
		lines.append("%s: %s %s/%s  %s" % [writer.stage, writer.op, writer.domain, writer.component, "ENGAGED now" if writer.engaged else "idle now"])
	for overlap: Dictionary in info.overlaps:
		lines.append("overlap %s: %s" % [overlap.domain, overlap.rule])
	lines.append("(declared ownership and live weights, not a measured bone change)")
	_explain.text = "\n".join(lines)

func _start_recording() -> void:
	bench.diagnostics.set_contacts(true)
	bench.diagnostics.contacts.start_recording()
	sync()

func _stop_recording() -> void:
	if not is_instance_valid(bench.diagnostics.contacts):
		return
	var summary: Dictionary = bench.diagnostics.contacts.stop_recording()
	var lines: Array[String] = ["%d frames" % summary.frames]
	for hand_name in summary.hands:
		var row: Dictionary = summary.hands[hand_name]
		lines.append("%s hand: contact frames %d, worst reachable error %.1f mm, unreachable frames %d (worst deficit %.1f cm)" % [hand_name, row.contact_frames, row.worst_reachable_error_mm, row.unreachable_frames, row.worst_deficit_cm])
	for foot_name in summary.feet:
		lines.append("%s foot: worst planned-to-ankle %.1f mm (%s)" % [foot_name, summary.feet[foot_name].worst_error_mm, summary.feet[foot_name].source])
	_recording.text = "\n".join(lines)

func refresh() -> void:
	var monitor: PresentationMonitor = bench.diagnostics.monitor
	if is_instance_valid(monitor):
		monitor.refresh()
		_live.text = monitor.live_text()
		_history.text = monitor.history_text(10)
	_stages.text = PoseStageReport.text(bench.rig)
	var contacts: ContactErrorDiagnostics = bench.diagnostics.contacts
	_contact.text = ContactErrorDiagnostics.format_readout(contacts.latest) if is_instance_valid(contacts) and contacts.enabled else "contact diagnostics off"
	_grip.set_pressed_no_signal(is_instance_valid(bench._diagnostics) and bench._diagnostics.enabled)
