class_name TuneTab
extends VBoxContainer
## "Change how she moves." Every number the animation code exposes on the character's motion profiles (cover, walking, ladders, stairs, weapon hold), as sliders built from the profiles' own `@export` ranges and units.
## A change applies to the live character at once. Save writes the profile to `art/characters/<id>/tuning/<profile>.tres` (or back into the profile's own file when it already has one), and CharacterRig loads that
## folder when it is built, so the game uses the saved numbers too. Undo returns to the last saved values. Nothing here changes code.

const PROFILES: Array[Dictionary] = [
	{"property": &"cover_profile", "title": "Cover: crouch, lean and turn"},
	{"property": &"locomotion_profile", "title": "Walking and running"},
	{"property": &"traversal_profile", "title": "Ladders and climbing"},
	{"property": &"stair_profile", "title": "Stairs"},
	{"property": &"handling", "title": "Holding the weapon"},
]
## Stair values the rig measures from the body when it is built: editing them would do nothing, so they are not offered.
const MEASURED: Array[StringName] = [&"leg_length", &"ankle_height", &"hip_joint_offset", &"foot_front", &"foot_back", &"foot_half_width"]
const MAX_DEPTH := 1   # nested settings one level down (the walk, jog and run gaits)

var bench: Node3D
var _picked := 0
var _choice: OptionButton
var _search: LineEdit
var _rows: VBoxContainer
var _status: Label
var _replay: Button
var _saved := {}      # profile index -> {path: value} at load or the last save
var _entries: Array[Dictionary] = []
var _resets := {}     # path -> its "reset" button

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 6)
	add_child(WorkbenchUI.label("Change how she moves. A change shows at once. Press Save to keep it: the game uses saved values too.", 14))
	_choice = OptionButton.new()
	for profile in PROFILES:
		_choice.add_item(profile.title)
	_choice.item_selected.connect(func(index: int) -> void:
		_picked = index
		_build())
	add_child(_choice)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a setting (for example: crouch)"
	_search.text_changed.connect(func(_text: String) -> void: _filter())
	add_child(_search)
	_replay = WorkbenchUI.button("Play the scenario again", _play_again, "Restarts the scenario that ran last, so you see the change from the start")
	var buttons := HBoxContainer.new()
	for node: Button in [WorkbenchUI.button("Save", save, "Keeps these values for this character (the game uses them too)"), WorkbenchUI.button("Undo my changes", undo, "Back to the last saved values"), _replay]:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(node)
	add_child(buttons)
	_status = WorkbenchUI.label("", 13, WorkbenchUI.ACCENT)
	add_child(_status)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)
	_build()

## The profile being edited. For stairs it is the authored one (the rig copies it and adds this body's measurements; see CharacterRig.reapply_stair_profile).
func profile() -> Resource:
	var property: StringName = PROFILES[_picked].property
	if property == &"stair_profile" and bench.rig.stair_profile_source != null:
		return bench.rig.stair_profile_source
	return bench.rig.get(property)

## Picks a profile by its rig property name (tests and the Start tab).
func pick(property: StringName) -> void:
	for index in PROFILES.size():
		if PROFILES[index].property == property:
			_picked = index
			_choice.select(index)
			_build()

## Every editable number, switch and vector of `resource`, in declaration order with its group: {owner, name, path, type, hint, hint_string, group}.
static func entries_of(resource: Resource, prefix := "", group := "", depth := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if resource == null:
		return out
	var current := group
	for info: Dictionary in resource.get_property_list():
		var usage := int(info.usage)
		if usage & PROPERTY_USAGE_GROUP:
			current = String(info.name) if String(info.name) != "" else group
			continue
		if usage & PROPERTY_USAGE_SUBGROUP or not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var name := StringName(info.name)
		if MEASURED.has(name) and resource is StairProfile:
			continue
		var type := int(info.type)
		if type in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_VECTOR3]:
			out.append({"owner": resource, "name": name, "path": prefix + String(name), "type": type, "hint": int(info.hint), "hint_string": String(info.hint_string), "group": current})
		elif type == TYPE_OBJECT and depth < MAX_DEPTH and resource.get(name) is Resource:
			out.append_array(entries_of(resource.get(name), prefix + String(name) + ".", humanize(String(name)), depth + 1))
	return out

## "high_cover_crouch_depth" -> "High cover crouch depth".
static func humanize(name: String) -> String:
	var words := name.replace("_", " ").strip_edges()
	return words.substr(0, 1).to_upper() + words.substr(1) if words != "" else name

## A row's title with its unit once: "protected_yaw_degrees" with "°" -> "Protected yaw (°)", "raise_seconds" with "s" -> "Raise (s)".
static func label_of(name: String, suffix: String) -> String:
	var words := humanize(name)
	for unit_word in [" degrees per second", " per second", " degrees", " seconds", " metres", " meters"]:
		if suffix != "" and words.to_lower().ends_with(unit_word):
			words = words.substr(0, words.length() - unit_word.length())
			break
	return words + ((" (%s)" % suffix) if suffix != "" else "")

## The range hint of a property: {min, max, step, suffix, greater, lesser, ok}.
static func range_of(entry: Dictionary) -> Dictionary:
	var result := {"min": 0.0, "max": 0.0, "step": 0.001 if int(entry.type) == TYPE_FLOAT else 1.0, "suffix": "", "greater": true, "lesser": true, "ok": false}
	var parts := String(entry.hint_string).split(",")
	if int(entry.hint) == PROPERTY_HINT_RANGE and parts.size() >= 2:
		result.min = float(parts[0])
		result.max = float(parts[1])
		result.step = float(parts[2]) if parts.size() > 2 and String(parts[2]).is_valid_float() else result.step
		result.greater = false
		result.lesser = false
		result.ok = true
		for extra in parts.slice(2):
			var flag := String(extra).strip_edges()
			if flag.begins_with("suffix:"):
				result.suffix = flag.trim_prefix("suffix:")
			elif flag == "or_greater":
				result.greater = true
			elif flag == "or_less":
				result.lesser = true
	return result

func _snapshot(index: int) -> Dictionary:
	var values := {}
	for entry in entries_of(_profile_at(index)):
		values[entry.path] = entry.owner.get(entry.name)
	return values

func _profile_at(index: int) -> Resource:
	var keep := _picked
	_picked = index
	var resource := profile()
	_picked = keep
	return resource

func _build() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_resets.clear()
	if not _saved.has(_picked):
		_saved[_picked] = _snapshot(_picked)
	_entries = entries_of(profile())
	if _entries.is_empty():
		_rows.add_child(WorkbenchUI.label("This character has nothing to tune here.", 13, WorkbenchUI.DIM))
	var group := "\u0000"
	for entry in _entries:
		if String(entry.group) != group:
			group = String(entry.group)
			if group != "":
				var heading := WorkbenchUI.label(group, 14, WorkbenchUI.ACCENT)
				heading.set_meta("group", group)
				_rows.add_child(heading)
		_rows.add_child(_row(entry))
	_filter()
	_update_status()

func _row(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.set_meta("text", (String(entry.group) + " " + String(entry.path)).to_lower().replace("_", " "))
	box.add_theme_constant_override("separation", 0)
	var limits := range_of(entry)
	var title := label_of(String(entry.name), String(limits.suffix))
	var line := HBoxContainer.new()
	var reset := WorkbenchUI.button("reset", func() -> void: _apply(entry, _saved[_picked].get(entry.path), true), "Back to the saved value")
	_resets[entry.path] = reset
	var value: Variant = entry.owner.get(entry.name)
	match int(entry.type):
		TYPE_BOOL:
			var check := WorkbenchUI.check(title, bool(value), func(on: bool) -> void: _apply(entry, on))
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.set_meta("path", entry.path)
			line.add_child(check)
		TYPE_INT when int(entry.hint) == PROPERTY_HINT_ENUM:
			box.add_child(WorkbenchUI.label(title, 14))
			var options := OptionButton.new()
			for item in String(entry.hint_string).split(","):
				options.add_item(humanize(String(item).split(":")[0].to_lower()))
			options.select(clampi(int(value), 0, options.item_count - 1))
			options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			options.item_selected.connect(func(index: int) -> void: _apply(entry, index))
			options.set_meta("path", entry.path)
			line.add_child(options)
		TYPE_VECTOR3:
			box.add_child(WorkbenchUI.label(title + "  (x, y, z in metres)", 14))
			var spins: Array[SpinBox] = []
			for axis in 3:
				var spin := _spin({"min": -10.0, "max": 10.0, "step": 0.001, "suffix": "", "greater": true, "lesser": true})
				spin.value = (value as Vector3)[axis]
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spins.append(spin)
				line.add_child(spin)
			for spin in spins:
				spin.value_changed.connect(func(_v: float) -> void: _apply(entry, Vector3(spins[0].value, spins[1].value, spins[2].value)))
			line.set_meta("spins", spins)
		_:
			box.add_child(WorkbenchUI.label(title, 14))
			var spin := _spin(limits)
			spin.value = float(value)
			spin.custom_minimum_size.x = 96
			if limits.ok:
				var slider := HSlider.new()
				slider.min_value = limits.min
				slider.max_value = limits.max
				slider.step = limits.step
				slider.value = float(value)
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				slider.focus_mode = Control.FOCUS_NONE
				slider.value_changed.connect(func(v: float) -> void:
					spin.set_value_no_signal(v)
					_apply(entry, int(round(v)) if int(entry.type) == TYPE_INT else v))
				spin.value_changed.connect(func(v: float) -> void:
					slider.set_value_no_signal(v)
					_apply(entry, int(round(v)) if int(entry.type) == TYPE_INT else v))
				line.add_child(slider)
				line.set_meta("slider", slider)
			else:
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spin.value_changed.connect(func(v: float) -> void: _apply(entry, int(round(v)) if int(entry.type) == TYPE_INT else v))
			line.add_child(spin)
			line.set_meta("spin", spin)
	line.add_child(reset)
	box.add_child(line)
	box.set_meta("line", line)
	box.set_meta("path", entry.path)
	reset.visible = _changed(entry)
	return box

func _spin(limits: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = limits.min
	spin.max_value = limits.max
	spin.step = limits.step
	spin.allow_greater = limits.greater
	spin.allow_lesser = limits.lesser
	spin.select_all_on_focus = true
	return spin

## Writes one value to the live profile. `refresh_row` puts the controls back in step (a reset or an undo, not the control that sent it).
func _apply(entry: Dictionary, value: Variant, refresh_row := false) -> void:
	if value == null:
		return
	entry.owner.set(entry.name, value)
	if PROFILES[_picked].property == &"stair_profile":
		bench.rig.reapply_stair_profile()
	if refresh_row:
		_sync_row(entry)
	if _resets.has(entry.path) and is_instance_valid(_resets[entry.path]):
		_resets[entry.path].visible = _changed(entry)
	_update_status()

func _sync_row(entry: Dictionary) -> void:
	for box in _rows.get_children():
		if not box.has_meta("path") or String(box.get_meta("path")) != String(entry.path):
			continue
		var line: HBoxContainer = box.get_meta("line")
		var value: Variant = entry.owner.get(entry.name)
		if line.has_meta("slider"):
			(line.get_meta("slider") as HSlider).set_value_no_signal(float(value))
		if line.has_meta("spin"):
			(line.get_meta("spin") as SpinBox).set_value_no_signal(float(value))
		if line.has_meta("spins"):
			var spins: Array = line.get_meta("spins")
			for axis in 3:
				(spins[axis] as SpinBox).set_value_no_signal((value as Vector3)[axis])
		for child in line.get_children():
			if child is CheckBox:
				(child as CheckBox).set_pressed_no_signal(bool(value))
			elif child is OptionButton:
				(child as OptionButton).select(int(value))

func _changed(entry: Dictionary) -> bool:
	var saved: Variant = _saved.get(_picked, {}).get(entry.path)
	var now: Variant = entry.owner.get(entry.name)
	if now is float or saved is float:
		return absf(float(now) - float(saved)) > 0.000001
	return now != saved

## How many values differ from the last save, on the profile shown.
func changed_count() -> int:
	var count := 0
	for entry in _entries:
		if _changed(entry):
			count += 1
	return count

func _update_status(message := "") -> void:
	var count := changed_count()
	if message != "":
		_status.text = message
	elif count == 0:
		_status.text = "%d settings. Nothing changed yet." % _entries.size()
	else:
		_status.text = "%d changed, not saved yet. Save keeps them; Undo puts them back." % count
	_status.add_theme_color_override("font_color", WorkbenchUI.WARN if count > 0 and message == "" else WorkbenchUI.ACCENT)

func _filter() -> void:
	var query := _search.text.strip_edges().to_lower() if is_instance_valid(_search) else ""
	var group_visible := {}
	for box in _rows.get_children():
		if box.has_meta("text"):
			var shown := query == "" or String(box.get_meta("text")).contains(query)
			box.visible = shown
	# A group heading shows when any of its rows does.
	var heading: Control = null
	var any := false
	for node in _rows.get_children():
		if node.has_meta("group"):
			if heading != null:
				heading.visible = any
			heading = node
			any = false
		elif node.visible:
			any = true
	if heading != null:
		heading.visible = any

## Where Save writes: the profile's own file when it has one (a .tres the scene already uses), otherwise the character's tuning folder.
func save_path() -> String:
	var resource := profile()
	var own := resource.resource_path if resource != null else ""
	if own.ends_with(".tres") and not own.contains("::"):
		return own
	var folder: String = bench.rig.tuning_folder()
	return folder.path_join("%s.tres" % PROFILES[_picked].property) if folder != "" else ""

## Saves the profile shown. Returns the path written, or "" (and says why).
func save() -> String:
	var path := save_path()
	if path == "":
		_update_status("Cannot save: this character has no folder to keep tuning in.")
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var resource := profile()
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		_update_status("Could not save (%s) to %s." % [error_string(error), path])
		return ""
	_saved[_picked] = _snapshot(_picked)
	for entry in _entries:
		if _resets.has(entry.path) and is_instance_valid(_resets[entry.path]):
			_resets[entry.path].visible = false
	var in_tuning := path.get_base_dir() == String(bench.rig.tuning_folder())
	_update_status(("Saved to %s. The game uses it too. Delete that file to go back to the defaults." if in_tuning else "Saved into %s, the file this character already uses (the game too). Git can restore the old values.") % path)
	return path

## Puts every value of the profile shown back to the last save.
func undo() -> void:
	var saved: Dictionary = _saved.get(_picked, {})
	for entry in _entries:
		if saved.has(entry.path):
			entry.owner.set(entry.name, saved[entry.path])
	if PROFILES[_picked].property == &"stair_profile":
		bench.rig.reapply_stair_profile()
	_build()
	_update_status("Back to the saved values.")

func _play_again() -> void:
	var id := StringName(String(bench.scenario_runner.scenario.get("id", "")))
	if id == &"" or not bench.start_scenario(id):
		_update_status("Play a scenario first (Start tab), then this replays it.")

## The Tune tab follows the character: a rebuilt workbench builds a new tab, so nothing to do per frame.
func refresh() -> void:
	_replay.disabled = String(bench.scenario_runner.scenario.get("id", "")) == ""
