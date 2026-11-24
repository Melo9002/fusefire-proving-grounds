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
var _file_time := {}  # profile index -> modified time of its file when last read or written (an edit saved in Godot shows up as a newer time)
var _clip_choice: OptionButton
var _clip_status: Label
var _clips_time := 0

func setup(workbench: Node3D) -> void:
	bench = workbench
	add_theme_constant_override("separation", 6)
	add_child(WorkbenchUI.label("Change how she moves. A change shows at once. Press Save to keep it: the game uses saved values too. 'Edit in Godot' opens the same thing in the Godot editor; what you save there shows up here by itself.", 14))
	var clips := WorkbenchUI.section(self, "Animation clips (keyframes, edited in Godot)")
	clips.add_child(WorkbenchUI.label("Her clips are made by code. 'Edit this clip in Godot' saves the clip she plays as a file and opens it on her body in Godot's Animation panel. Save there (Ctrl+S) and it plays here and in the game.", 13, WorkbenchUI.DIM))
	_clip_choice = OptionButton.new()
	clips.add_child(_clip_choice)
	clips.add_child(WorkbenchUI.row([["Edit this clip in Godot", edit_clip, "Copies the clip into the character's clips.tres (if it is not there yet) and opens it in the Godot editor"], ["Use the generated clip", _forget_clip, "Removes your edited version of this clip; the code-made one plays again after the character reloads"]]))
	_clip_status = WorkbenchUI.label("", 13, WorkbenchUI.ACCENT)
	clips.add_child(_clip_status)
	_fill_clips()
	_clips_time = ClipFiles.modified_time(bench.rig)
	var settings := WorkbenchUI.section(self, "Settings (numbers)")
	_choice = OptionButton.new()
	for profile in PROFILES:
		_choice.add_item(profile.title)
	_choice.item_selected.connect(func(index: int) -> void:
		_picked = index
		_build())
	settings.add_child(_choice)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a setting (for example: crouch)"
	_search.text_changed.connect(func(_text: String) -> void: _filter())
	settings.add_child(_search)
	_replay = WorkbenchUI.button("Play the scenario again", _play_again, "Restarts the scenario that ran last, so you see the change from the start")
	var buttons := HBoxContainer.new()
	for node: Button in [WorkbenchUI.button("Save", save, "Keeps these values for this character (the game uses them too)"), WorkbenchUI.button("Undo my changes", undo, "Back to the last saved values")]:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(node)
	settings.add_child(buttons)
	var more := HBoxContainer.new()
	for node: Button in [WorkbenchUI.button("Edit in Godot", edit_in_godot, "Opens these settings in the Godot editor's Inspector (saves them first if they have no file yet)"), _replay]:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		more.add_child(node)
	settings.add_child(more)
	_status = WorkbenchUI.label("", 13, WorkbenchUI.ACCENT)
	settings.add_child(_status)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	settings.add_child(_rows)
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
	_file_time[_picked] = FileAccess.get_modified_time(path)
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
	pick_up_outside_edits()

## Edits saved in the Godot editor reach the live character: a settings file newer than the last read or save is read again (unless there are unsaved changes here, which would be lost), and a newer
## clips file is put into the player.
func pick_up_outside_edits() -> void:
	var path := save_path()
	if path != "" and FileAccess.file_exists(path):
		var time := FileAccess.get_modified_time(path)
		if not _file_time.has(_picked):
			_file_time[_picked] = time
		elif time != int(_file_time[_picked]):
			_file_time[_picked] = time
			if changed_count() > 0:
				_update_status("The file changed in Godot, but you have unsaved changes here: Undo to take Godot's values, or Save to keep yours.")
			else:
				var count := reload_from_file(path)
				_update_status("Picked up %d value%s saved in Godot." % [count, "" if count == 1 else "s"])
	var clips_time := ClipFiles.modified_time(bench.rig)
	if clips_time != _clips_time:
		_clips_time = clips_time
		var result := ClipFiles.apply_saved(bench.rig)
		_fill_clips()
		_clip_status.text = "Picked up the clips saved in Godot: %s%s." % [", ".join(result.applied) if not result.applied.is_empty() else "none", (" (skipped, not a bone clip of this body: %s)" % ", ".join(result.skipped)) if not result.skipped.is_empty() else ""]

## Reads the profile's file and copies every value into the live profile (so everything holding it sees the change). Returns how many values changed.
func reload_from_file(path: String) -> int:
	var disk := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if disk == null or profile() == null or disk.get_script() != profile().get_script():
		return 0
	var changed := 0
	for entry in _entries:
		var value: Variant = value_at(disk, String(entry.path))
		if value != null and value != entry.owner.get(entry.name):
			entry.owner.set(entry.name, value)
			changed += 1
	if PROFILES[_picked].property == &"stair_profile":
		bench.rig.reapply_stair_profile()
	_saved[_picked] = _snapshot(_picked)
	_build()
	return changed

## The value at a dotted path ("walk.stride") of a resource, or null.
static func value_at(resource: Resource, path: String) -> Variant:
	var at: Variant = resource
	for part in path.split("."):
		if not (at is Object):
			return null
		at = (at as Object).get(part)
	return at

## Saves first when the settings have no file yet (or have unsaved changes), then asks the Godot editor to open that file in its Inspector.
func edit_in_godot() -> void:
	var path := save_path()
	if path == "":
		_update_status("This character has no folder to keep settings in.")
		return
	if not FileAccess.file_exists(path) or changed_count() > 0:
		if save() == "":
			return
	_update_status(EditorBridge.send(EditorBridge.request(path)) + " Change values in the Inspector, then Ctrl+S: they show up here.")

func _fill_clips() -> void:
	var keep := String(_clip_choice.get_item_metadata(_clip_choice.selected)) if _clip_choice.selected >= 0 else ""
	_clip_choice.clear()
	var current := String(bench.rig.animation_controller.current_state) if is_instance_valid(bench.rig.animation_controller) else ""
	var edited := ClipFiles.load_library(bench.rig)
	for name in ClipFiles.clip_names(bench.rig):
		_clip_choice.add_item("%s%s" % [name, "   (edited by hand)" if edited.has_animation(name) else ""])
		_clip_choice.set_item_metadata(_clip_choice.item_count - 1, String(name))
		if String(name) == (keep if keep != "" else current):
			_clip_choice.select(_clip_choice.item_count - 1)

func _picked_clip() -> StringName:
	return StringName(String(_clip_choice.get_item_metadata(_clip_choice.selected))) if _clip_choice.selected >= 0 else &""

## Picks a clip by name (tests).
func pick_clip(clip: StringName) -> void:
	for index in _clip_choice.item_count:
		if String(_clip_choice.get_item_metadata(index)) == String(clip):
			_clip_choice.select(index)

## Copies the chosen clip into the character's clips file (when needed) and opens it in the Godot editor on her body. `launch` false only queues the request (tests).
func edit_clip(launch := true) -> void:
	var clip := _picked_clip()
	var prepared := ClipFiles.prepare(bench.rig, clip)
	if not prepared.ok:
		_clip_status.text = prepared.message
		return
	_clips_time = ClipFiles.modified_time(bench.rig)
	_fill_clips()
	var sent := EditorBridge.send(EditorBridge.request(prepared.scene, ClipFiles.PLAYER, String(clip)), launch)
	_clip_status.text = "%s %s\nIn Godot: the Animation panel shows %s. Click Model > Skeleton3D, press 'Edit Mode' above the 3D view, rotate a bone, press the key icon next to it, then Ctrl+S. It plays here by itself." % [prepared.message, sent, clip]

func _forget_clip() -> void:
	var clip := _picked_clip()
	if ClipFiles.forget(bench.rig, clip):
		_clips_time = ClipFiles.modified_time(bench.rig)
		_fill_clips()
		_clip_status.text = "%s goes back to the generated clip when the character reloads (Character tab > Apply and reload, or restart)." % clip
	else:
		_clip_status.text = "%s is not an edited clip." % clip
