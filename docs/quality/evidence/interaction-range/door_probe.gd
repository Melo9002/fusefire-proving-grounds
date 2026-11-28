extends SceneTree
## Dynamic door geometry vs the independently compiled static maps: toggles door_a closed -> open -> closed on the compiled map and compares the geometry signature with a fresh compile of the other state.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")


func _initialize() -> void:
	var closed := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 2, 1.0)
	var open := Catalog.generate(Catalog.INTERACTION_RANGE, Vector2i.ZERO, 3, 1.0)
	print("errors closed ", closed.generation_errors, " open ", open.generation_errors)
	print("doors: ", MapDoors.states(closed), " | ", MapDoors.states(open))
	var door: DoorData = closed.doors[&"door_a"]
	print("region: ", door.region(), " captured ", door.is_captured(), " parts closed ", door.movement_parts.get(&"closed"), " open ", door.movement_parts.get(&"open"))
	print("hinge ", door.hinge, " radius ", door.swing_radius, " from ", rad_to_deg(door.swing_from), " to ", rad_to_deg(door.swing_to))
	var sig_closed := SurfaceNavigation.signature(closed)
	var sig_open_static := SurfaceNavigation.signature(open)
	print("static signatures differ: ", sig_closed != sig_open_static)
	var backup := MapDoors.apply(closed, &"door_a", &"open")
	print("applied: ", not backup.is_empty(), " dynamic-open == static-open signature: ", SurfaceNavigation.signature(closed) == sig_open_static, " consistent ", MapDoors.consistent(closed, &"door_a"))
	var backup2 := MapDoors.apply(closed, &"door_a", &"closed")
	print("closed again == original: ", SurfaceNavigation.signature(closed) == sig_closed)
	quit()
