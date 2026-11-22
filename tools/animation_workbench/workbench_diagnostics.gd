class_name WorkbenchDiagnostics
extends RefCounted
## The workbench's set of optional diagnostics for its one rig, created on demand and freed on demand: the presentation monitor (state and history), contact-error measurement and overlay, the root motion trail, the bone
## highlight. Every one of them is a read-only, rig-only tool from presentation/diagnostics/; this class only owns their lifetime for the workbench. Nothing here is created unless a toggle asks for it, and
## `shutdown()` leaves no node, listener or overlay behind.

var rig: CharacterRig
var monitor: PresentationMonitor
var contacts: ContactErrorDiagnostics
var trail: MotionTrail
var highlight: BoneHighlight
var paused := false

func _init(p_rig: CharacterRig) -> void:
	rig = p_rig

## The monitor is on from the start (it is the compact live view); the heavier ones are opt-in.
func ensure_monitor() -> PresentationMonitor:
	if not is_instance_valid(monitor):
		monitor = PresentationMonitor.attach(rig)
	return monitor

func set_contacts(on: bool) -> void:
	if on and not is_instance_valid(contacts):
		contacts = ContactErrorDiagnostics.attach(rig)
	if is_instance_valid(contacts):
		contacts.set_enabled(on)

func set_trail(on: bool) -> void:
	if on and not is_instance_valid(trail):
		trail = MotionTrail.attach(rig)
	if is_instance_valid(trail):
		trail.set_sampling_paused(paused)
		trail.set_enabled(on)

## Highlights bones (empty clears it).
func highlight_bones(names: Array[String], colour := Color(1.0, 0.35, 0.95)) -> void:
	if not is_instance_valid(highlight):
		if names.is_empty():
			return
		highlight = BoneHighlight.attach(rig)
	if is_instance_valid(highlight):
		highlight.set_bones(names, colour)

## A workbench pause stops diagnostic sampling as well as animation; single steps are recorded explicitly.
func set_paused(on: bool) -> void:
	paused = on
	if is_instance_valid(trail):
		trail.set_sampling_paused(on)

func record_step(delta: float) -> void:
	if is_instance_valid(trail) and paused:
		trail.record_step(delta)

func contacts_on() -> bool:
	return is_instance_valid(contacts) and contacts.enabled

func trail_on() -> bool:
	return is_instance_valid(trail) and trail.enabled

## Switches every optional diagnostic off and frees what they made (the monitor included).
func shutdown() -> void:
	for node: Node in [contacts, trail, highlight]:
		if is_instance_valid(node):
			if node is ContactErrorDiagnostics:
				(node as ContactErrorDiagnostics).set_enabled(false)
			elif node is MotionTrail:
				(node as MotionTrail).set_enabled(false)
			elif node is BoneHighlight:
				(node as BoneHighlight).set_bones([])
			node.queue_free()
	if is_instance_valid(monitor):
		monitor.shutdown()
	contacts = null
	trail = null
	highlight = null
	monitor = null

## True when nothing of the diagnostics is still attached (every overlay, listener and node gone).
func is_clean() -> bool:
	return not is_instance_valid(monitor) and not is_instance_valid(contacts) and not is_instance_valid(trail) and not is_instance_valid(highlight)
