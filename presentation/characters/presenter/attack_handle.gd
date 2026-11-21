class_name AttackHandle
extends ActionHandle
## The handle of one attack presentation (Task 07 package 6). It settles when the whole sequence is over (COMPLETED at the end of the release, SKIPPED when the character could not sequence and the shot
## was shown at once, INTERRUPTED when a hit, a defeat, a newer attack or the character's removal ended it). `shot` is the earlier milestone the tactical layer waits on before it shows the target's
## reaction: it settles when the shot is shown (COMPLETED, or SKIPPED when forced) or INTERRUPTED if the attack ended before it. Both settle exactly once and are safe to observe late.
## Neither decides anything: the attack's result was committed before presentation began.

var shot := ActionHandle.new()
