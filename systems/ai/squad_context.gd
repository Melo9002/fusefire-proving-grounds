class_name SquadContext
extends RefCounted

## A cell an ally holds is forbidden outright; a cell merely beside one is only discouraged.
## Scoring must never outweigh the first kind: see block_reason().
const HARD_BLOCK := -1000.0
const CROWDING_PENALTY := -12.0
## Allied fire already on a target discourages more (spreading out), by this much per shooter, unless the shot would likely finish it (see target_adjustment).
const FOCUS_PENALTY := 15.0
## Every commitment lasts for the round it was made in (begin_round releases the rest), and ends sooner when its owner or its target is lost, the owner moves off its destination, or the lane it was reserved for
## stops being the carrier's route (revalidate). Nothing outlives a round.
const LIFETIME_ROUNDS := 1
## The most recent releases kept for inspection and tests: what was released, whose it was, and why.
const EXPIRY_LOG_LIMIT := 32

var round_number := -1
var reserved_destinations: Dictionary = {}
var intended_targets: Dictionary[StringName, int] = {}
var objective_handlers: Dictionary[StringName, Array] = {}
var reserved_corridor: Dictionary = {}
var corridor_owner: StringName = &""
var _actor_destinations: Dictionary[StringName, Vector3i] = {}
var _actor_targets: Dictionary[StringName, StringName] = {}
var _actor_objectives: Dictionary[StringName, StringName] = {}
## {round, kind, owner, reason} for the latest releases, oldest first. Read-only evidence; no decision reads it.
var expiry_log: Array[Dictionary] = []

func begin_round(current_round: int) -> void:
	if round_number == current_round:
		return
	var held := claim_count()
	if held > 0:
		_log(&"round", &"", "round %d ended: %d commitment(s) released" % [round_number, held])
	round_number = current_round
	reserved_destinations.clear()
	intended_targets.clear()
	objective_handlers.clear()
	reserved_corridor.clear()
	corridor_owner = &""
	_actor_destinations.clear()
	_actor_targets.clear()
	_actor_objectives.clear()

func begin_unit(actor: TacticalUnit) -> void:
	release_actor_id(_actor_id(actor))

## How many individual commitments are held: destinations, targets, objective handlers and a corridor.
func claim_count() -> int:
	return _actor_destinations.size() + _actor_targets.size() + _actor_objectives.size() + (1 if not corridor_owner.is_empty() else 0)

## A bounded copy of facts available at publication. Browsing it never looks up
## the live owner or runs the round/expiry logic.
func inspection_record() -> Dictionary:
	var destinations := {}
	for cell in reserved_destinations.keys().slice(0, 8):
		destinations[cell] = reserved_destinations[cell]
	var focus := {}
	for id in intended_targets.keys().slice(0, 8):
		if intended_targets[id] > 0:
			focus[id] = intended_targets[id]
	return {"round": round_number, "destinations": destinations, "destination_count": reserved_destinations.size(),
		"carrier": corridor_owner, "corridor": reserved_corridor.keys().slice(0, 8),
		"corridor_count": reserved_corridor.size(), "focus": focus,
		"expiry": expiry_log.slice(-3).duplicate(true)}

func _log(kind: StringName, owner: StringName, reason: String) -> void:
	expiry_log.append({"round": round_number, "kind": kind, "owner": owner, "reason": reason})
	if expiry_log.size() > EXPIRY_LOG_LIMIT:
		expiry_log.pop_front()

## An actor left the battle (defeated or removed): everything it held, everything aimed at it and its corridor go at once,
## instead of waiting for the next roster check. Idempotent.
func release_unit(actor_id: StringName, reason: String) -> void:
	var released := false
	if corridor_owner == actor_id or _actor_destinations.has(actor_id) or _actor_targets.has(actor_id) or _actor_objectives.has(actor_id):
		_log(&"owner", actor_id, reason)
		released = true
	release_actor_id(actor_id)
	for owner: StringName in _actor_targets.keys():
		if _actor_targets[owner] == actor_id:
			_log(&"target", owner, "target %s: %s" % [actor_id, reason])
			_release_target_claim(owner)
			released = true
	if released:
		intended_targets.erase(actor_id)

## Ends only `owner`'s fire on its target, leaving its destination and objective alone.
func _release_target_claim(owner: StringName) -> void:
	if not _actor_targets.has(owner):
		return
	var target_id := _actor_targets[owner]
	intended_targets[target_id] = maxi(0, intended_targets.get(target_id, 1) - 1)
	_actor_targets.erase(owner)

## An objective ended (completed or failed): nobody is handling it any more.
func release_objective(objective_id: StringName) -> void:
	var handlers: Array = objective_handlers.get(objective_id, [])
	if handlers.is_empty():
		return
	for handler: StringName in handlers:
		_actor_objectives.erase(handler)
	objective_handlers.erase(objective_id)
	_log(&"objective", objective_id, "objective %s ended: %d handler(s) released" % [objective_id, handlers.size()])

func release_actor_id(actor_id: StringName) -> void:
	if corridor_owner == actor_id:
		reserved_corridor.clear()
		corridor_owner = &""
	if _actor_destinations.has(actor_id):
		reserved_destinations.erase(_actor_destinations[actor_id])
		_actor_destinations.erase(actor_id)
	if _actor_targets.has(actor_id):
		var target_id := _actor_targets[actor_id]
		intended_targets[target_id] = maxi(0, intended_targets.get(target_id, 1) - 1)
		_actor_targets.erase(actor_id)
	if _actor_objectives.has(actor_id):
		var objective_id := _actor_objectives[actor_id]
		var handlers: Array = objective_handlers.get(objective_id, [])
		handlers.erase(actor_id)
		objective_handlers[objective_id] = handlers
		_actor_objectives.erase(actor_id)

func reserve_destination(actor: TacticalUnit, cell: Vector3i) -> void:
	var actor_id := _actor_id(actor)
	if reserved_destinations.has(cell) and reserved_destinations[cell] != actor_id: return
	if _actor_destinations.has(actor_id):
		var previous: Vector3i = _actor_destinations[actor_id]
		if reserved_destinations.get(previous) == actor_id:
			reserved_destinations.erase(previous)
	reserved_destinations[cell] = actor_id
	_actor_destinations[actor_id] = cell

## Why `actor` may not use `cell`, or "" when it may. These are genuine commitments (an ally's
## exact destination, an escort's carrier corridor), not preferences, and name their owner.
func block_reason(actor: TacticalUnit, cell: Vector3i) -> String:
	if reserved_corridor.has(cell) and corridor_owner != _actor_id(actor):
		return "Corridor reserved by %s" % corridor_owner
	if reserved_destinations.has(cell) and reserved_destinations[cell] != _actor_id(actor):
		return "Destination reserved by %s" % reserved_destinations[cell]
	return ""

## The soft crowding preference only: staying out of the immediate neighbourhood of allies' destinations.
func crowding_adjustment(actor: TacticalUnit, cell: Vector3i) -> float:
	var adjustment := 0.0
	for reserved_cell in reserved_destinations:
		if reserved_destinations[reserved_cell] != _actor_id(actor) and cell.distance_to(reserved_cell) <= 1.0:
			adjustment += CROWDING_PENALTY
	return adjustment

## Both together, kept for callers that want one number: a block is HARD_BLOCK, otherwise crowding.
func destination_adjustment(actor: TacticalUnit, cell: Vector3i) -> float:
	if not block_reason(actor, cell).is_empty():
		return HARD_BLOCK
	return crowding_adjustment(actor, cell)

## `cells` must be in route order, the carrier's own cell first (a Dictionary keeps insertion order). A lane with no cells is no commitment.
func reserve_corridor(actor: TacticalUnit, cells: Dictionary) -> void:
	if cells.is_empty():
		reserved_corridor.clear()
		corridor_owner = &""
		return
	reserved_corridor = cells.duplicate()
	corridor_owner = _actor_id(actor)

func is_reserved_for_other(actor: TacticalUnit, cell: Vector3i) -> bool:
	return reserved_corridor.has(cell) and corridor_owner != _actor_id(actor)

func reserve_target(actor: TacticalUnit, target: TacticalUnit) -> void:
	var actor_id := _actor_id(actor)
	var target_id := _actor_id(target)
	if _actor_targets.get(actor_id) == target_id:
		return
	if _actor_targets.has(actor_id):
		var previous_id := _actor_targets[actor_id]
		intended_targets[previous_id] = maxi(0, intended_targets.get(previous_id, 1) - 1)
	intended_targets[target_id] = intended_targets.get(target_id, 0) + 1
	_actor_targets[actor_id] = target_id

## How many allies have already fired on `target` this round, not counting `actor`'s own earlier shot.
func focus_count(actor: TacticalUnit, target: TacticalUnit) -> int:
	var target_id := _actor_id(target)
	var count: int = intended_targets.get(target_id, 0)
	if _actor_targets.get(_actor_id(actor)) == target_id:
		count = maxi(0, count - 1)
	return count

## Spreading fire is a preference, not a rule: each ally already on the target costs FOCUS_PENALTY, but a shot that is likely to finish it is
## not wasted fire, so the penalty fades with the kill chance (0 to 1) and is gone for a certain kill.
func target_adjustment(actor: TacticalUnit, target: TacticalUnit, kill_chance := 0.0) -> float:
	return -FOCUS_PENALTY * focus_count(actor, target) * (1.0 - clampf(kill_chance, 0.0, 1.0))

func reserve_objective(actor: TacticalUnit, objective_id: StringName) -> int:
	var actor_id := _actor_id(actor)
	if _actor_objectives.has(actor_id) and _actor_objectives[actor_id] != objective_id:
		var previous_handlers: Array = objective_handlers.get(_actor_objectives[actor_id], [])
		previous_handlers.erase(actor_id)
		_actor_objectives.erase(actor_id)
	if objective_id.is_empty(): return 0
	var handlers: Array = objective_handlers.get(objective_id, [])
	var existing := handlers.size() - (1 if handlers.has(actor_id) else 0)
	if not handlers.has(actor_id):
		handlers.append(actor_id)
		objective_handlers[objective_id] = handlers
		_actor_objectives[actor_id] = objective_id
	return existing

static func _actor_id(actor: TacticalUnit) -> StringName:
	return actor.tactical_id if not actor.tactical_id.is_empty() else StringName(actor.name)

## Claims last no later than the current round, and end sooner when what they depend on is gone. Kept for callers that only have a roster.
func prune(actors: Array[TacticalUnit]) -> void:
	revalidate(actors)

## Releases every commitment whose basis no longer holds, and says why in `expiry_log`:
##  - an owner or a target is defeated or no longer in the roster;
##  - an owner has moved off the destination it reserved;
##  - the carrier is no longer carrying, has left its lane, or the lane no longer ends in the current extraction zone (`extraction_cells`, a set; empty skips that check);
##  - and the lane's cells the carrier has already passed are given back, so escorts can stand there again.
func revalidate(actors: Array[TacticalUnit], extraction_cells := {}) -> void:
	var alive := {}
	var listed := {}
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		listed[_actor_id(actor)] = true
		if actor.stats and not actor.stats.is_defeated:
			alive[_actor_id(actor)] = actor
	for owner: StringName in _actor_destinations.keys():
		if alive.has(owner) and alive[owner].grid_position != _actor_destinations[owner]:
			_log(&"destination", owner, "owner left the reserved cell")
			reserved_destinations.erase(_actor_destinations[owner])
			_actor_destinations.erase(owner)
	var owners := _actor_destinations.keys() + _actor_targets.keys() + _actor_objectives.keys()
	if not corridor_owner.is_empty(): owners.append(corridor_owner)
	for owner: StringName in owners:
		if not alive.has(owner):
			_log(&"owner", owner, "owner defeated" if listed.has(owner) else "owner left the battle")
			release_actor_id(owner)
	_revalidate_corridor(alive, extraction_cells)
	for owner: StringName in _actor_targets.keys():
		var target_id := _actor_targets[owner]
		if not alive.has(target_id):
			_log(&"target", owner, "target %s %s" % [target_id, "defeated" if listed.has(target_id) else "left the battle"])
			intended_targets[target_id] = maxi(0, intended_targets.get(target_id, 1) - 1)
			_actor_targets.erase(owner)

func _revalidate_corridor(alive: Dictionary, extraction_cells: Dictionary) -> void:
	if corridor_owner.is_empty() or not alive.has(corridor_owner):
		return   # an absent owner was released above
	var carrier: TacticalUnit = alive[corridor_owner]
	if not carrier.is_carrying_unit():
		_log(&"corridor", corridor_owner, "carrier is no longer carrying")
		_clear_corridor()
		return
	var lane: Array = reserved_corridor.keys()
	if not extraction_cells.is_empty() and not extraction_cells.has(lane[-1]):
		_log(&"corridor", corridor_owner, "extraction zone changed")
		_clear_corridor()
		return
	var at: int = lane.find(carrier.grid_position)
	if at < 0:
		_log(&"corridor", corridor_owner, "carrier left the lane")
		_clear_corridor()
		return
	for index in at:
		reserved_corridor.erase(lane[index])
	if at > 0:
		_log(&"corridor", corridor_owner, "gave back %d cell(s) the carrier has passed" % at)

func _clear_corridor() -> void:
	reserved_corridor.clear()
	corridor_owner = &""
