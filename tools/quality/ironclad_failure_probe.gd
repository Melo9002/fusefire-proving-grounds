extends SceneTree
## Invoked only by tools/run_tests.ps1 -ProbeFailureHandling.
func _initialize() -> void:
	print("Project Ironclad intentional failure probe: expected exit 7")
	quit(7)
