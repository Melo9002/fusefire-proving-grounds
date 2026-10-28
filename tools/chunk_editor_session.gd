class_name ChunkEditorSession
extends RefCounted
## One editable draft and stable-ID command history; no renderer/runtime state.
var source := EnvironmentChunkSource.new("new_chunk", "New chunk")
var selected_id := ""
var filename := "new_chunk"
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var last_error := ""
var saved_signature := ""
var _next_id_floor := 1
const HISTORY_LIMIT := 100

func dirty() -> bool: return signature() != saved_signature
func signature() -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(source.to_dictionary())), "", true)
func selected() -> Dictionary:
	for record in source.data.instances:
		if record.placement_id == selected_id: return record.duplicate(true)
	return {}
func select(id: String) -> void:
	selected_id = id
	if selected().is_empty(): selected_id = ""
func _commit(candidate: EnvironmentChunkSource, selection: String, label: String) -> bool:
	var errors := EnvironmentChunkSource.source_errors(candidate.data)
	if not errors.is_empty():
		last_error = "%s: %s" % [errors[0].field, errors[0].message]
		return false
	if candidate.to_dictionary() == source.to_dictionary(): return true
	undo_stack.append({"before": source.to_dictionary(), "after": candidate.to_dictionary(), "before_selection": selected_id, "after_selection": selection, "label": label})
	if undo_stack.size() > HISTORY_LIMIT: undo_stack.pop_front()
	redo_stack.clear()
	source = candidate.copy()
	_next_id_floor = maxi(_next_id_floor, int(source.data.next_placement_id))
	selected_id = selection
	last_error = ""
	return true
func undo() -> bool:
	if undo_stack.is_empty(): return false
	var command: Dictionary = undo_stack.pop_back()
	redo_stack.append(command)
	source.data = command.before.duplicate(true)
	selected_id = command.before_selection
	return true
func redo() -> bool:
	if redo_stack.is_empty(): return false
	var command: Dictionary = redo_stack.pop_back()
	undo_stack.append(command)
	source.data = command.after.duplicate(true)
	selected_id = command.after_selection
	return true
func _add_candidate() -> EnvironmentChunkSource:
	var candidate := source.copy()
	var floor_id := maxi(_next_id_floor, int(candidate.data.next_placement_id))
	# A new object must not accidentally repair a dangling draft reference.
	var reserved: Array = candidate.data.tactical.components.duplicate()
	reserved.append_array(candidate.data.tactical.get("visual_only", []))
	for dependency in candidate.data.dependencies: reserved.append_array(dependency.get("required_by", []))
	for id in reserved:
		if str(id).begins_with("placement_"): floor_id = maxi(floor_id, str(id).trim_prefix("placement_").to_int() + 1)
	candidate.data.next_placement_id = floor_id
	return candidate
func add(component_id: String, at: Vector2i, rotation := 0, elevation := 0) -> bool:
	var candidate := _add_candidate()
	var id := candidate.add_instance(EnvironmentModulePlacement.new(StringName(component_id), at, rotation, 0, elevation), not component_id.begins_with("asset:"))
	return _commit(candidate, id, "Place")
func transform_selected(at: Vector2i, rotation: int, elevation: int, variation: int) -> bool:
	if selected().is_empty(): return false
	var candidate := source.copy()
	for record in candidate.data.instances:
		if record.placement_id != selected_id: continue
		record.origin = [at.x, at.y]
		record.rotation = posmod(rotation, 4)
		record.elevation = elevation
		record.variation = variation
	return _commit(candidate, selected_id, "Transform")
func duplicate_selected() -> bool:
	var record := selected()
	if record.is_empty(): return false
	var candidate := _add_candidate()
	var id := candidate.add_instance(EnvironmentModulePlacement.from_record(record), selected_id in source.data.tactical.components)
	if selected_id in candidate.data.tactical.get("visual_only", []): candidate.data.tactical.visual_only.append(id)
	for dependency in candidate.data.dependencies:
		if selected_id in dependency.get("required_by", []): dependency.required_by.append(id)
	return _commit(candidate, id, "Duplicate")
func delete_selected() -> bool:
	if selected().is_empty(): return false
	var candidate := source.copy()
	candidate.data.instances = candidate.data.instances.filter(func(record): return record.placement_id != selected_id)
	candidate.data.tactical.components.erase(selected_id)
	if candidate.data.tactical.has("visual_only"): candidate.data.tactical.visual_only.erase(selected_id)
	for dependency in candidate.data.dependencies:
		if dependency.get("required_by") is Array: dependency.required_by.erase(selected_id)
	return _commit(candidate, "", "Delete")
func set_bounds(width: int, depth: int, height: int) -> bool:
	var candidate := source.copy()
	candidate.data.bounds = [width, depth]
	candidate.data.height = height
	return _commit(candidate, selected_id, "Bounds")
func set_port(port: Dictionary) -> bool:
	var candidate := source.copy()
	candidate.data.ports = candidate.data.ports.filter(func(record): return record.id != port.get("id", ""))
	candidate.data.ports.append(port.duplicate(true))
	return _commit(candidate, selected_id, "Port")
func remove_port(id: String) -> bool:
	var candidate := source.copy()
	candidate.data.ports = candidate.data.ports.filter(func(record): return record.id != id)
	return _commit(candidate, selected_id, "Delete port")
func insert_copy(other: EnvironmentChunkSource, offset: Vector3i) -> bool:
	var errors := EnvironmentChunkSource.source_errors(other.data)
	if not errors.is_empty():
		last_error = errors[0].message
		return false
	var source_ids := {}
	for record in other.data.instances: source_ids[record.placement_id] = true
	var referenced: Array = other.data.tactical.components.duplicate()
	referenced.append_array(other.data.tactical.get("visual_only", []))
	for dependency in other.data.dependencies: referenced.append_array(dependency.get("required_by", []))
	for id in referenced:
		if not source_ids.has(id):
			last_error = "Cannot insert draft copy: missing referenced instance " + str(id) + ". Open the source to repair it."
			return false
	var candidate := _add_candidate()
	var id_map := {}
	for record in other.data.instances:
		var placement := EnvironmentModulePlacement.from_record(record)
		placement.origin += Vector2i(offset.x, offset.z)
		placement.elevation += offset.y
		id_map[record.placement_id] = candidate.add_instance(placement, record.placement_id in other.data.tactical.components)
	for id in other.data.tactical.get("visual_only", []):
		if not candidate.data.tactical.has("visual_only"): candidate.data.tactical["visual_only"] = []
		candidate.data.tactical.visual_only.append(id_map[id])
	for category in ["ports", "clearances"]:
		var used := {}
		for record in candidate.data[category]: used[record.id] = true
		for original in other.data[category]:
			var record: Dictionary = original.duplicate(true)
			while used.has(record.id): record.id += "_copy"
			used[record.id] = true
			for cell in record.cells:
				cell[0] += offset.x
				if category == "ports": cell[1] += offset.z
				else:
					cell[1] += offset.y
					cell[2] += offset.z
			if category == "ports": record.elevation += offset.y
			candidate.data[category].append(record)
	for category in ["surfaces", "effects", "links"]:
		for original in other.data.tactical[category]:
			var record: Dictionary = original.duplicate(true)
			for key in (["from", "to"] if category == "links" else ["cell"]):
				record[key] = [int(record[key][0]) + offset.x, int(record[key][1]) + offset.y, int(record[key][2]) + offset.z]
			candidate.data.tactical[category].append(record)
	for original in other.data.dependencies:
		var dependency: Dictionary = original.duplicate(true)
		dependency.required_by = dependency.get("required_by", []).map(func(id): return id_map.get(id, id))
		var matched := false
		for existing in candidate.data.dependencies:
			if existing.kind != dependency.kind or existing.id != dependency.id: continue
			var left: Dictionary = existing.duplicate(true)
			var right := dependency.duplicate(true)
			left.erase("required_by")
			right.erase("required_by")
			if JSON.stringify(left, "", true) != JSON.stringify(right, "", true):
				last_error = "Conflicting dependency revision: " + str(dependency.id)
				return false
			for id in dependency.required_by:
				if id not in existing.get("required_by", []): existing.get_or_add("required_by", []).append(id)
			matched = true
		if not matched: candidate.data.dependencies.append(dependency)
	return _commit(candidate, str(id_map.values()[0]) if not id_map.is_empty() else "", "Insert draft copy")
func save(directory: String, name: String) -> bool:
	var result := ChunkSourceStore.save_named(source, directory, name)
	if not result.ok:
		last_error = result.error
		return false
	filename = name
	saved_signature = signature()
	last_error = ""
	return true
func load_draft(directory: String, name: String) -> bool:
	var result := ChunkSourceStore.load_named(directory, name)
	if not result.ok:
		last_error = result.error
		return false
	source = result.source.copy()
	_next_id_floor = int(source.data.next_placement_id)
	filename = name
	selected_id = ""
	undo_stack.clear()
	redo_stack.clear()
	saved_signature = signature()
	last_error = ""
	return true
func new_draft() -> void:
	_next_id_floor = 1
	last_error = ""
	source = EnvironmentChunkSource.new("chunk_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()], "New chunk")
	source.data.bounds = [20, 20]
	source.data.height = 12
	filename = "new_chunk"
	selected_id = ""
	undo_stack.clear()
	redo_stack.clear()
	saved_signature = ""


func declare_visual_only() -> bool:
	if selected().is_empty():
		last_error = "Select an instance first"
		return false
	var candidate := source.copy()
	candidate.data.tactical.components.erase(selected_id)
	if not candidate.data.tactical.has("visual_only"): candidate.data.tactical["visual_only"] = []
	if selected_id not in candidate.data.tactical.visual_only: candidate.data.tactical.visual_only.append(selected_id)
	return _commit(candidate, selected_id, "Declare visual-only")
func declare_component_behavior() -> bool:
	if selected().is_empty(): return false
	var candidate := source.copy()
	if candidate.data.tactical.has("visual_only"): candidate.data.tactical.visual_only.erase(selected_id)
	if selected_id not in candidate.data.tactical.components: candidate.data.tactical.components.append(selected_id)
	return _commit(candidate, selected_id, "Declare component behavior")
func add_ground() -> bool:
	var candidate := source.copy()
	candidate.data.tactical.surfaces = candidate.data.tactical.surfaces.filter(func(spec): return int(spec.cell[1]) != 0)
	for x in int(candidate.data.bounds[0]):
		for z in int(candidate.data.bounds[1]): candidate.data.tactical.surfaces.append({"cell": [x, 0, z], "values": {"walkable": true}})
	return _commit(candidate, selected_id, "Author ground surface")
