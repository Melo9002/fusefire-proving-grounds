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
## Read-only ladder clearance (LadderClearance), sampled at skeleton_updated while a ladder is climbed.
var clearance: LadderClearance
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

## Empties the root trail (a new run should not continue the old one's line).
func clear_trail() -> void:
	if is_instance_valid(trail):
		trail.clear()

func contacts_on() -> bool:
	return is_instance_valid(contacts) and contacts.enabled

func trail_on() -> bool:
	return is_instance_valid(trail) and trail.enabled

## Switches every optional diagnostic off and frees what they made (the monitor included).
func shutdown() -> void:
	release_clearance()
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


## The ladder clearance tool, created when the panel first asks for it (nothing is connected before that).
func ensure_clearance() -> LadderClearance:
	if clearance == null:
		clearance = LadderClearance.new(rig)
		rig.skeleton.skeleton_updated.connect(_sample_clearance)
	return clearance

func _sample_clearance() -> void:
	if clearance != null and rig.ladder != null:
		clearance.sample()

## The panel's "Ladder landing" text: the rig's landing status and the measured clearances, or why there is nothing to show.
func ladder_text() -> String:
	if rig.ladder == null:
		return "no ladder in use"
	var tool := ensure_clearance()
	var phase := rig.ladder.pose.landing_phase if rig.ladder.pose != null else -1.0
	return tool.readout(rig.ladder.landing_status, rig.ladder.landing, rig.ladder.geometry, rig.ladder.climbed, phase)

func release_clearance() -> void:
	if clearance != null and is_instance_valid(rig.skeleton) and rig.skeleton.skeleton_updated.is_connected(_sample_clearance):
		rig.skeleton.skeleton_updated.disconnect(_sample_clearance)
	clearance = null
