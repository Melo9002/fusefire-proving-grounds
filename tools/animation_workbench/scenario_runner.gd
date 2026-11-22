class_name WorkbenchScenarioRunner
extends RefCounted
## Plays one scripted workbench scenario: a list of timed steps, each a call on the workbench's PUBLIC controls (the same ones the panel buttons use). The runner owns no animation time: it advances by the delta
## the workbench hands it (zero while the workbench is paused, one frame when it steps), so a pause stops the script exactly as it stops the character, and it never reaches into the presenter's holds, handles or
## clocks. Every step is a request to the production presentation; nothing is posed here. A scenario always ends through the workbench's reset (finished, stopped or replaced), so no state outlives it.

signal step_run(index: int, label: String)
signal finished(completed: bool)

var bench: Node3D
var scenario: Dictionary = {}
var time := 0.0
var next_step := 0
var running := false
var log: Array[String] = []

func start(p_bench: Node3D, definition: Dictionary) -> void:
	stop()   # a scenario that is running is ended (and the bench reset) before another begins
	bench = p_bench
	scenario = definition
	bench.reset_scene()
	time = 0.0
	next_step = 0
	log.clear()
	running = true

func advance(delta: float) -> void:
	if not running or delta <= 0.0:
		return
	time += delta
	var steps: Array = scenario.steps
	while next_step < steps.size() and time >= float(steps[next_step].t):
		var step: Dictionary = steps[next_step]
		log.append("%.1f s  %s" % [time, step.label])
		next_step += 1
		(step.run as Callable).call(bench)
		step_run.emit(next_step - 1, step.label)
	if time >= float(scenario.duration):
		_end(true)

## Ends the scenario early and resets the workbench to a neutral state.
func stop() -> void:
	if running:
		_end(false)

func _end(completed: bool) -> void:
	running = false
	if is_instance_valid(bench):
		bench.reset_scene()
	finished.emit(completed)

func current_label() -> String:
	if scenario.is_empty():
		return ""
	var steps: Array = scenario.steps
	return String(steps[maxi(next_step - 1, 0)].label) if next_step > 0 else "(starting)"

func progress() -> float:
	return clampf(time / float(scenario.duration), 0.0, 1.0) if not scenario.is_empty() else 0.0
