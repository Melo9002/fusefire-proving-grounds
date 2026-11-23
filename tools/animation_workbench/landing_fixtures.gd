class_name LandingFixtures
extends RefCounted
## The landings the workbench (and the tests that stand on it) can put at the top of a ladder, so a supported transfer, its reverse and the cases that must stay on the fallback can be reproduced from a
## name. Each is a LadderLanding (the shared description the exploration sandbox and, later, a tactical map supply) plus a drawing of the deck and of what the hands hold. The pose comes from the
## production solver and rig: nothing here poses a body.

const KINDS := ["posts", "rails", "deck only", "too far", "too close", "too small"]
const DECK_HALF_WIDTH := 1.5
const DECK_DEPTH := 3.0
const LIP := 0.22
## What each kind is, for the panel and the report.
const SUMMARY := {
	"posts": "A deck with two upright posts at its edge: supported.",
	"rails": "The ladder's own rails run on 0.9 m above the deck: supported.",
	"deck only": "A deck with nothing to hold: unsupported, keeps the height-only climb-out.",
	"too far": "A lip too far from the rungs for the leg to step: unsupported, keeps the height-only climb-out.",
	"too close": "A wall nearer the rungs than the boot reaches: unsupported (the boot would be in the wall), keeps the height-only climb-out.",
	"too small": "A deck too small for the body's feet: unsupported, keeps the height-only climb-out.",
}


static func make(kind: String, geometry: LadderGeometry) -> LadderLanding:
	match kind:
		"posts":
			return LadderLanding.with_posts(LIP, DECK_HALF_WIDTH, DECK_DEPTH, 0.24, 0.416, 0.025, "workbench posts")
		"rails":
			return LadderLanding.with_extended_rails(geometry, LIP, DECK_HALF_WIDTH, DECK_DEPTH, 0.9, "workbench extended rails")
		"deck only":
			return LadderLanding.deck_only(LIP, DECK_HALF_WIDTH, DECK_DEPTH)
		"too far":
			return LadderLanding.with_posts(0.6, DECK_HALF_WIDTH, DECK_DEPTH, 0.24, 0.416)
		"too close":
			return LadderLanding.with_posts(0.05, DECK_HALF_WIDTH, DECK_DEPTH, 0.24, 0.416)
		"too small":
			return LadderLanding.with_posts(LIP, 0.1, 0.1, 0.24, 0.416)
	return null


## The deck (translucent, so an inspection camera sees through it) and the bars the hands hold, in the ladder's frame (the ladder's bottom at y = 0, the rung plane at geometry.plane_ahead).
static func build_visual(landing: LadderLanding, geometry: LadderGeometry, bar_material: Material) -> Node3D:
	var node := Node3D.new()
	node.name = "Landing"
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(landing.deck_half_width * 2.0, 0.2, landing.deck_depth)
	deck.mesh = deck_mesh
	var deck_material := StandardMaterial3D.new()
	deck_material.albedo_color = Color(0.45, 0.47, 0.5, 0.35)
	deck_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	deck.material_override = deck_material
	deck.position = Vector3(0.0, geometry.rise - 0.1, geometry.plane_ahead + landing.lip_from_rungs + landing.deck_depth * 0.5)
	node.add_child(deck)
	for grip in landing.grips:
		# A grip is a bar's centre at its HOLD height; the bar itself stands from the deck, taller than the hold (the hold is 64% up the sandbox posts and the rails' extension).
		var height := (grip as Vector3).y / 0.64
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(landing.grip_radius * 2.0, height, landing.grip_radius * 2.0)
		bar.mesh = bar_mesh
		bar.material_override = bar_material
		bar.position = Vector3((grip as Vector3).x, geometry.rise + height * 0.5, geometry.plane_ahead + landing.lip_from_rungs + (grip as Vector3).z)
		node.add_child(bar)
	return node
