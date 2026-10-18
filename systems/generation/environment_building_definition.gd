class_name EnvironmentBuildingDefinition
extends RefCounted
## Structural contract for a reusable, parcel-sized building assembly.
##
## Imported assets remain presentation ingredients.  This definition records
## the architectural promise made by their assembly: enclosure intent, usable
## floor, entrances and roof coverage.  MapData remains authoritative after the
## associated module's cell effects are translated into the generated map.

enum Enclosure {
	CLOSED,
	OPEN_SHELTER,
	PREBUILT_SHELL,
}

var assembly_id: StringName
var purpose: StringName
var enclosure: Enclosure
var parcel_size: Vector2i
var module: EnvironmentModuleDefinition
var wall_cells: Array[Vector2i] = []
var entrance_cells: Array[Vector2i] = []
var usable_floor_cells: Array[Vector2i] = []
var roof_cells: Array[Vector2i] = []
var entrance_directions: Dictionary = {}
var source_assets: Array[String] = []
var notes := ""

func _init(id: StringName, building_purpose: StringName, enclosure_kind: Enclosure, size: Vector2i) -> void:
	assembly_id = id
	purpose = building_purpose
	enclosure = enclosure_kind
	parcel_size = size

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if module == null:
		errors.append("%s has no reusable module" % assembly_id)
		return errors
	if module.size != parcel_size:
		errors.append("%s parcel and module sizes differ" % assembly_id)
	if enclosure == Enclosure.PREBUILT_SHELL:
		if source_assets.is_empty():
			errors.append("%s prebuilt shell has no source assets" % assembly_id)
		return errors
	if usable_floor_cells.is_empty():
		errors.append("%s has no usable floor" % assembly_id)
	if roof_cells.is_empty():
		errors.append("%s has no authored roof coverage" % assembly_id)
	var walls := _lookup(wall_cells)
	var entrances := _lookup(entrance_cells)
	var roofs := _lookup(roof_cells)
	var usable := _lookup(usable_floor_cells)
	for cell in wall_cells:
		if entrances.has(cell):
			errors.append("%s marks %s as both wall and entrance" % [assembly_id, cell])
		var effect: Dictionary = module.cell_effects.get(cell, {})
		if effect.get("walkable", true):
			errors.append("%s wall %s is not blocked in the tactical module" % [assembly_id, cell])
	for cell in usable_floor_cells:
		if walls.has(cell):
			errors.append("%s usable floor overlaps wall at %s" % [assembly_id, cell])
		if not roofs.has(cell):
			errors.append("%s usable floor lacks roof coverage at %s" % [assembly_id, cell])
	if enclosure == Enclosure.CLOSED:
		if entrance_cells.is_empty():
			errors.append("%s closed building has no entrance" % assembly_id)
		for cell in _boundary_cells():
			if not walls.has(cell) and not entrances.has(cell):
				errors.append("%s enclosure is open at %s" % [assembly_id, cell])
		for cell in entrance_cells:
			var outward: Vector2i = entrance_directions.get(cell, Vector2i.ZERO)
			if outward == Vector2i.ZERO or not _is_boundary(cell):
				errors.append("%s entrance %s has no valid outward edge" % [assembly_id, cell])
			elif not usable.has(cell - outward):
				errors.append("%s entrance %s does not lead to usable interior floor" % [assembly_id, cell])
	elif enclosure == Enclosure.OPEN_SHELTER and wall_cells.size() >= _boundary_cells().size():
		errors.append("%s is declared open but seals its entire boundary" % assembly_id)
	return errors

func is_complete() -> bool:
	return validate().is_empty()

func enclosure_name() -> StringName:
	return StringName(Enclosure.keys()[enclosure].to_lower())

func apply_metadata() -> EnvironmentModuleDefinition:
	if module == null:
		return null
	module.structural_assembly_id = assembly_id
	module.architectural_purpose = purpose
	module.assembly_enclosure = enclosure_name()
	module.assembly_complete = is_complete()
	module.assembly_notes = notes
	return module

func _boundary_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in parcel_size.x:
		result.append(Vector2i(x, 0))
		if parcel_size.y > 1:
			result.append(Vector2i(x, parcel_size.y - 1))
	for z in range(1, parcel_size.y - 1):
		result.append(Vector2i(0, z))
		if parcel_size.x > 1:
			result.append(Vector2i(parcel_size.x - 1, z))
	return result

func _is_boundary(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == parcel_size.x - 1 or cell.y == parcel_size.y - 1

static func _lookup(cells: Array[Vector2i]) -> Dictionary:
	var result := {}
	for cell in cells:
		result[cell] = true
	return result
