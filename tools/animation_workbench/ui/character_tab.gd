class_name CharacterTab
extends VBoxContainer
## "What character and rig am I inspecting?" Identity and body proportions, which semantic roles map to which bones (required and optional), what the body can and cannot present and why, the equipment state, a way to
## switch character or go unarmed, and a compatibility check that explains why a profile does not fit a skeleton. Everything shown comes from RigInspection (read-only, rig-only).

var bench: Node3D
var _identity: Label
var _roles_box: VBoxContainer
var _caps: RichTextLabel
var _character_choice: OptionButton
var _armed: CheckBox
var _check_choice: OptionButton
var _check_result: RichTextLabel
var _role_choice: OptionButton
var _role_rows: Array = []
var _report: Dictionary = {}
var _loaded := false

const CANDIDATE_PROFILES := [
	["MIRA-0 profile", "res://art/characters/mira_0/mira_0_rig_profile.tres"],
	["Small MIRA-0 profile", "res://art/characters/small_mira_0/small_mira_0_rig_profile.tres"],
	["Alternate (test fixture)", "res://tests/fixtures/rigs/alternate_rig_profile.tres"],
]

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 5)
	var identity_box := WorkbenchUI.section(self, "Identity and body")
	_identity = WorkbenchUI.mono("", 12)
	identity_box.add_child(_identity)

	var choose := WorkbenchUI.section(self, "Choose a character")
	choose.add_child(WorkbenchUI.label("Switching rebuilds the workbench (a scene reload is the one clean reset); the choice is kept for the next launch.", 12, WorkbenchUI.DIM))
	_character_choice = OptionButton.new()
	var keys: Array = bench.CHARACTER_RIGS.keys()
	for key in keys:
		_character_choice.add_item(String(key))
	var current_key := WorkbenchSession.character
	if current_key == &"" and keys.size() > 0:
		current_key = keys[0]
	_character_choice.select(maxi(keys.find(current_key), 0))
	choose.add_child(_character_choice)
	_armed = WorkbenchUI.check("Armed (carries its weapon)", WorkbenchSession.armed, func(_on: bool) -> void: pass)
	choose.add_child(_armed)
	choose.add_child(WorkbenchUI.row([["Apply and reload", _apply_character]]))

	var roles := WorkbenchUI.section(self, "Semantic roles and bones")
	roles.add_child(WorkbenchUI.label("* required by FuseFire's animation code. Pick a role to mark its bone on the body.", 12, WorkbenchUI.DIM))
	_role_choice = OptionButton.new()
	_role_choice.item_selected.connect(_highlight_role)
	roles.add_child(_role_choice)
	_roles_box = VBoxContainer.new()
	roles.add_child(_roles_box)

	var caps := WorkbenchUI.section(self, "Capabilities")
	_caps = RichTextLabel.new()
	_caps.bbcode_enabled = true
	_caps.fit_content = true
	_caps.scroll_active = false
	_caps.add_theme_font_size_override("normal_font_size", 12)
	caps.add_child(_caps)

	var compat := WorkbenchUI.section(self, "Compatibility check", true)   # folded until a check is run
	compat.add_child(WorkbenchUI.label("Resolves a profile against THIS skeleton without building a rig, and says what is wrong and how to fix it.", 12, WorkbenchUI.DIM))
	_check_choice = OptionButton.new()
	for entry in CANDIDATE_PROFILES:
		_check_choice.add_item(entry[0])
	compat.add_child(_check_choice)
	compat.add_child(WorkbenchUI.row([["Check this profile", _check_profile], ["Break the mapping (demo)", _check_broken]]))
	_check_result = RichTextLabel.new()
	_check_result.bbcode_enabled = true
	_check_result.fit_content = true
	_check_result.scroll_active = false
	_check_result.add_theme_font_size_override("normal_font_size", 12)
	compat.add_child(_check_result)
	_load()

func _load() -> void:
	_report = RigInspection.report(bench.rig)
	_identity.text = RigInspection.text(_report)
	for child in _roles_box.get_children():
		child.queue_free()
	_role_choice.clear()
	_role_rows = _report.roles.rows if _report.has("roles") and _report.roles.has("rows") else []
	_role_choice.add_item("(no highlight)")
	for row: Dictionary in _role_rows:
		var line := WorkbenchUI.mono("%s%-17s %-26s %s" % ["*" if row.required else " ", row.role, row.bone if row.bone != "" else "-", "" if row.status == "ok" else row.status], 11)
		line.add_theme_color_override("font_color", WorkbenchUI.status_colour("ok" if row.status == "ok" else ("WARN" if not row.required else "bad")))
		_roles_box.add_child(line)
		_role_choice.add_item(row.role)
	var text := ""
	for row: Dictionary in _report.get("capabilities", []):
		var colour := WorkbenchUI.status_colour(row.status).to_html(false)
		text += "[color=#%s]%-12s[/color] %s%s\n" % [colour, row.status, row.name, ("  [color=#8a98a8]%s[/color]" % row.reason) if row.reason != "" else ""]
	for stage in _report.get("degraded", []):
		text += "[color=#ff6a5a]DEGRADED[/color] %s\n" % stage
	_caps.text = text if text != "" else "(no capabilities resolved)"
	_loaded = true

func _highlight_role(index: int) -> void:
	if index <= 0:
		bench.diagnostics.highlight_bones([])
		return
	var row: Dictionary = _role_rows[index - 1]
	var names: Array[String] = []
	if row.bone != "":
		names.append(row.bone)
	bench.diagnostics.highlight_bones(names)

func _apply_character() -> void:
	var keys: Array = bench.CHARACTER_RIGS.keys()
	WorkbenchSession.character = keys[_character_choice.selected]
	WorkbenchSession.armed = _armed.button_pressed
	WorkbenchSession.autostart_scenario = &""
	bench.get_tree().reload_current_scene()

func _show_check(result: Dictionary, title: String) -> void:
	var text := "[b]%s[/b]: %s\n" % [title, "COMPATIBLE" if result.ok else "INCOMPATIBLE"]
	for line: String in result.errors:
		text += "[color=#ff6a5a]error[/color] %s\n" % line
	for line: String in result.warnings:
		text += "[color=#ffcc55]warning[/color] %s\n" % line
	_check_result.text = text
	(_check_result.get_parent().get_parent() as FoldableContainer).folded = false   # the answer is why the button was pressed: show it

func _check_profile() -> void:
	var entry: Array = CANDIDATE_PROFILES[_check_choice.selected]
	var profile: Resource = load(entry[1])
	if profile == null:
		_check_result.text = "[color=#ff6a5a]Could not load %s[/color]" % entry[1]
		return
	_show_check(RigInspection.check_profile(profile, bench.rig.skeleton), entry[0])

## A deliberately broken copy of the current profile (its left-hand role mapped to a bone this skeleton does not have): the diagnostic has to say so.
func _check_broken() -> void:
	var profile: Resource = bench.rig.rig_profile.duplicate(true)
	if profile == null or profile.skeleton_map == null:
		_check_result.text = "The rig has no editable profile"
		return
	profile.skeleton_map.set_skeleton_bone_name(&"LeftHand", &"NoSuchBone_demo")
	_show_check(RigInspection.check_profile(profile, bench.rig.skeleton), "current profile with LeftHand -> NoSuchBone_demo")

func refresh() -> void:
	if not _loaded:
		_load()
