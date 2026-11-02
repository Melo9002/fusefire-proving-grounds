extends SceneTree
const Connection = preload("res://systems/generation/parcel_connection.gd")
func _initialize() -> void:
	var failures := 0
	var port = Connection.new()
	port.cell = Vector3i(4, 0, 0)
	port.width = 3
	if not port.validate(Vector2i(16, 32)).is_empty(): failures += 1
	port.cell.z = 2
	if port.validate(Vector2i(16, 32)).is_empty(): failures += 1
	port.cell = Vector3i(15, 0, 0)
	if port.validate(Vector2i(16, 32)).is_empty(): failures += 1
	port.width = 1
	port.outward = Vector2i(1, 1)
	if port.validate(Vector2i(16, 32)).is_empty(): failures += 1
	port.outward = Vector2i.RIGHT
	if not port.validate(Vector2i(16, 32)).is_empty(): failures += 1
	print("Parcel connections: %d failure(s)" % failures)
	quit(1 if failures else 0)
