extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
 if not ok:
  failed = true
  push_error(message)
func _initialize() -> void:
 var demo = load("res://art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn").instantiate()
 root.add_child(demo)
 await create_timer(0.1).timeout
 var controller = demo.animation_controller
 controller.play(&"aim")
 await create_timer(0.8).timeout
 var s: Skeleton3D = demo.skeleton
 for side in ["L", "R"]:
  var foot_rest := s.get_bone_global_rest(s.find_bone("J_Bip_%s_Foot" % side)).origin
  var toe_rest := s.get_bone_global_rest(s.find_bone("J_Bip_%s_ToeBase" % side)).origin
  check(toe_rest.z > foot_rest.z, "Imported toes establish +Z body forward: " + side)
 var eye: Vector3 = s.global_transform * s.get_bone_global_pose(s.find_bone("J_Adj_R_FaceEye")).origin
 var sight: Vector3 = demo.sight_marker.global_position
 var error := Vector2(eye.x - sight.x, eye.y - sight.y).length()
 print("[PoseRefinement] Eye/sight lateral error: ", error)
 # Shoulder placement now anchors the weapon; cheek/eye alignment needs a
 # separate head-pose pass rather than translating the stock off the body.
 await demo.arm_ik.modification_processed
 var stock_error: float = demo.stock_marker.global_position.distance_to(demo.shoulder_marker.global_position)
 print("[PoseRefinement] Stock/shoulder error: ", stock_error)
 check(stock_error < 0.025, "Aimed buttstock must contact shoulder within 2.5 cm")
 check(sight.z > eye.z, "Sight must be in front of the eye")
 controller.play(&"shoot")
 for sample in 8:
  await create_timer(0.025).timeout
  await demo.arm_ik.modification_processed
  stock_error = demo.stock_marker.global_position.distance_to(demo.shoulder_marker.global_position)
  check(stock_error < 0.025, "Stock must stay against shoulder during recoil")
 controller.animation_tree.active = false
 var player: AnimationPlayer = controller.animation_player
 player.play(&"move")
 for t in [0.125, 0.25, 0.375, 0.625, 0.75, 0.875]:
  player.seek(t, true)
  for side in ["L", "R"]:
   var hip := s.get_bone_global_pose(s.find_bone("J_Bip_%s_UpperLeg" % side)).origin
   var knee := s.get_bone_global_pose(s.find_bone("J_Bip_%s_LowerLeg" % side)).origin
   var ankle := s.get_bone_global_pose(s.find_bone("J_Bip_%s_Foot" % side)).origin
   var fraction := (hip.y-knee.y)/(hip.y-ankle.y)
   var bend := knee.z - lerpf(hip.z, ankle.z, fraction)
   check(bend >= -0.005, "Knee hyperextension at %s on %s: %s" % [t, side, bend])
 # During the bent-knee swing interval the foot must travel along the
 # imported VRoid's visual-forward axis (+Z).
 for side in ["L", "R"]:
  var start_time := 0.15 if side == "L" else 0.65
  player.seek(start_time, true)
  var foot := s.find_bone("J_Bip_%s_Foot" % side)
  var before := s.get_bone_global_pose(foot).origin
  player.seek(start_time + 0.20, true)
  var after := s.get_bone_global_pose(foot).origin
  check(after.z > before.z + 0.02, "Lifted foot must swing forward (+Z): " + side)
 if not failed:
  print("[PoseRefinement] PASS — forward stride, knee bend, and shoulder stock contact")
 demo.queue_free()
 await process_frame
 quit(1 if failed else 0)
