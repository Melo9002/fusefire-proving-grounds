class_name LadderTestBodies
extends RefCounted
## The two humanoids' ladder measurements as constants, for tests of the pure planner that must not load a character. They are what CharacterRig.ladder_body() measures from the shipped skeletons;
## `ladder_body_test` (rig-based) checks they still are, so the constants cannot drift from the models.

static func mira() -> LadderBody:
	var body := LadderBody.new()
	body.ratio = 1.0
	body.thigh = 0.388
	body.shin = 0.379
	body.upper_arm = 0.251
	body.forearm = 0.212
	body.hip_offset = Vector3(0.093704, -0.056223, 0.006247)
	body.shoulder_offset = Vector3(0.124939, 0.349829, -0.037482)
	body.ankle_height = 0.109
	body.ball_length = 0.113
	return body


static func small_mira() -> LadderBody:
	var body := LadderBody.new()
	body.ratio = 0.695
	body.thigh = 0.261
	body.shin = 0.279
	body.upper_arm = 0.166
	body.forearm = 0.155
	body.hip_offset = Vector3(0.065593, -0.023426, 0.0)
	body.shoulder_offset = Vector3(0.098389, 0.220205, -0.032796)
	body.ankle_height = 0.096
	body.ball_length = 0.108
	return body
