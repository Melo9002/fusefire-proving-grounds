extends SceneTree
## Invoked only by tools/run_tests.ps1 -ProbeFailureHandling: never finishes, so the runner must report a TIMEOUT.
func _initialize() -> void:
	print("Project Ironclad timeout probe: waiting forever")
