class_name HandContact
extends RefCounted
## ONE hand's contact for this pass, as typed data (Task 11): where the wrist target goes, which way the fingers and the palm face, and how fully the contact owns the hand. Whoever PLANS the contact (the ladder's
## rungs, the carried body, the relaxed hang) builds one of these in WORLD space with its own formulas; CharacterRig.claim_hand_contact is the single place that turns it into the wrist target and the grip
## modifier's contact slots (the skeleton-space conversion, the left/right indexing and the release all live there, once). It carries no solver: the specialised planners stay specialised.
##
## Ownership: a hand has at most one claim per pass, and the LAST claim of the pass wins (carry, ladder and relaxed hang are mutually exclusive producers; the weapon's grip is not a claim, it is what is left when
## no contact claims the hand). A hand nobody claims is released at the start of the next pass, so no contact outlives its producer.
## The one left/right convention: the grip modifier's (0 left, 1 right).
enum Hand { LEFT, RIGHT }
const NO_CURL := -1.0

var hand: Hand = Hand.RIGHT
## Where the wrist target goes (world). The planner has already blended it from where the hand was, so this is the final point of the pass.
var point := Vector3.ZERO
## The fingers' direction and the palm's facing direction (world, unit).
var finger_direction := Vector3.FORWARD
var palm_normal := Vector3.DOWN
## How fully the contact owns the hand's orientation (0 leaves it to the weapon or the animation, 1 fully).
var weight := 0.0
## The grip's closure, or NO_CURL to leave whatever the pose inputs set (the relaxed hand's own curl).
var curl := NO_CURL


static func make(for_hand: Hand, at: Vector3, fingers: Vector3, palm: Vector3, owned: float, closure := NO_CURL) -> HandContact:
	var contact := HandContact.new()
	contact.hand = for_hand
	contact.point = at
	contact.finger_direction = fingers
	contact.palm_normal = palm
	contact.weight = owned
	contact.curl = closure
	return contact
