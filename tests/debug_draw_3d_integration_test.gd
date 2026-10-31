extends SceneTree

const Draw = preload("res://tools/diagnostics/fusefire_debug_draw_3d.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var record := Draw.dependency_record()
	check(record.name == "Debug Draw 3D" and record.version == "1.7.3", "Wrapper pins the reviewed add-on version")
	check(record.license == "MIT", "Wrapper exposes the recorded license")
	check(FileAccess.file_exists(Draw.ADDON_PATH), "Vendored GDExtension descriptor is present")
	check(Draw.is_available(), "Debug Draw 3D loads in the current Godot runtime")
	var scope := Draw.begin_scope(root, true, 0.02)
	check(scope != null, "A viewport-scoped diagnostic configuration can be created")
	check(Draw.draw_aabb(AABB(Vector3.ZERO, Vector3.ONE), Color.MAGENTA, 0.01), "AABB diagnostics reach the add-on")
	check(Draw.draw_arrow(Vector3.ZERO, Vector3.RIGHT, Color.CYAN, 0.01), "Socket-arrow diagnostics reach the add-on")
	check(Draw.clear_all(), "Diagnostics can be cleared explicitly")
	# Generator 2 editor checks are preserved in the local quarantine.
	print("Debug Draw 3D integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
