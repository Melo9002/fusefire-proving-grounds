# Parcel workflow playtest follow-up — 2026-11-15

The owner reported successful ambulance placement, combined Preview, named Save/Open, local battle and return. This follow-up addresses the confusing feedback without changing tactical geometry or combat balance.

## Changes

- Collision with a hidden population guide highlights the reserved object's complete current solid bounds in gold and labels it “Reserved container/vehicle position.” The placement hint explains that another seed may occupy it. Legal movement, leaving the canvas or cancelling clears the marker. The reservation still prevents fixed/procedural overlaps.
- The shared footer owns Preview. Population fields keep Next seed and Show guides; the source comparison is called Compare original, with an explanation that it temporarily hides edits.
- Everyday wording uses Ready to preview, Saved test copy, edited layout and gameplay/object boundaries. Source-check details remain in the readiness tooltip; Preview still validates current edits and Test battle validates the tactical map.
- A visible hint explains that the seed is saved. Discard protection remains intact.
- The [everyday guide](../generation-2.md) is separated from [historical audit evidence](../generation-2-history.md). Its stale “complete save/open/play” to-do was removed.

## Executed verification

- Final smoke: **11 passed, 0 failed, 0 skipped**, 37.18 seconds (`artifacts/test-results/20261115-133145-smoke/`).

- UI subsystem: **23 passed, 0 failed, 1 policy skip**, 62.37 seconds (`artifacts/test-results/20261115-132758-subsystem-ui/`). The skip is the explicit-only editor capture. A targeted rendered reservation test ran separately, passed, and its screenshot was inspected (`artifacts/parcel-ux-review/reserved-container.png`). Final wording/marker-size tweaks received focused reruns.
- Mesh boundaries and mixed population runtime parity focused checks passed. The latter covers seeds 17/18 and 0/65/100% rules; this is automated coverage, not a claim that new paint was exercised manually.
- `mesh_boundary_battle_test.gd` passed with actual Generation 2 battle initialization, live pathfinding and real shot queries. Separate arch parts preserve the opening. The same visible arch combined into one mesh fills its opening with its bounding box. A raised body reserves standing space while leaving shots under its visible body clear. These are diagnostic fixture shapes; they do not expand the ordinary asset palette or change the fallback.
- `parcel_local_battle_completion_test.gd` passed against the owner's saved `artifacts/playtest_cleanup_20261115_ambulance.parcel.json`, without overwriting it. The ambulance appears once, prevents standing in its body, blocks shots through its body, and retains a path around it. AI movement/shooting reached defeat. Saving and reopening the recording verified **53/53 actions** and the same defeat, then returned with the editor fingerprint unchanged. The portable default fixture recreating that ambulance also passed.
- No complete Ironclad rerun was made for this UI/documentation pass. The previous full run remains 122/0/14; it predates the three new suites. Headless checks do not establish visual correctness for every asset or camera angle. Final focused/UI logs have no script errors or new leak warnings; direct sandbox runs retain certificate/user-log filesystem diagnostics.

## Limits and next checks

Automatic boundaries remain per-mesh boxes. A single concave/open mesh can therefore block visibly empty space. This is now reproduced in a real battle; no geometry rewrite or new authoring step was introduced. Inspect further real models before deciding how to improve that fallback.

Normal tactical camera occlusion follows the active soldier (or an explicitly inspected floor), not all squad members. A hidden unselected soldier is not proof of a bad spawn. Rotation/selection can help inspection; no camera-policy change is claimed here. A dedicated all-squad visibility playtest remains useful.

The full local battle is one fixed seed and layout. Broader completion, hand-painted content, other mission types and normal-map visual checks remain separate evidence. Local replay portability still requires its snapshot cache and matching project dependencies.


## Second pass: painting scope and preview navigation

The next owner playtest found that parking paint removed delivery trucks and containers from Preview. This was caused by whole-parcel permission replacement, not missing assets. The editor now scopes permission replacement to the painted object type and floor. Parking targets sedan/SUV/taxi rules; delivery trucks, containers and other floors keep their own rules. Protected paint still excludes any movable type where it overlaps. Density only changes affected rules/new positions. Several allowed strokes of the same type combine into one permission area; matching original positions outside it are excluded. This consequence is explained before painting.

A new export signature tag distinguishes this behavior from earlier whole-parcel exports. Existing exported scenes and immutable recordings are not rewritten. Older editable sessions still open; new previews/exports use the clarified type/floor interpretation. Changing content identity can reroll choices at the same seed even when an unrelated region's rules are retained; retaining a rule does not promise every original chosen position remains identical.

Tab navigation now preserves Preview and Compare original. Starting an editing gesture returns to the edited guides. The comparison's guide button reads Return to my parcel. Preview failures use one message, and the unsaved badge says object changes for placement, removal, rotation and movement.

`parcel_paint_scope_test.gd` exercises an automatically bounded ambulance with parking paint: too-small areas leave unrelated permission intact; fitting 8 × 8 paint previews a car beside the truck/container; runtime accepted choices match Preview; 0% parking retains the unrelated population; tabs preserve the same preview instance; comparison return preserves the session; floor scope is checked separately. Rendered captures were inspected under `artifacts/paint-scope-review/`.

The previous handoff test expected only its new container because the old global permission filter also removed the delivery truck. Its count assertion now requires both the fitted container and the unrelated delivery rule. The rest of its Save/Open, exact Preview/battle parity, action replay and return assertions remain unchanged. The unsaved-label assertion was updated to the requested object changes wording. Existing combined-preview, field, and density/parity focused suites passed.

The agent did not deliberately open, save or discard the running owner session, but did not independently verify that its in-memory edits survived. On reconnecting, the owner found a clean warehouse with No unsaved changes; the previous in-memory ambulance/paint session was unavailable. Its separately saved ambulance draft remained available. The timing and cause of the reset are unknown. The owner’s next retest used fresh temporary, unsaved edits. Earlier statements that could imply verified survival of the live session were too broad; isolated automated editor-session preservation checks do not establish that live session’s state.


Second-pass final verification: **126 suites passed, 0 failed, 14 explicit-only skipped** in **653.44 seconds** (`artifacts/test-results/20261115-134546-full/`). This includes the new scope regression, all six seed/density parity cases, complete local ambulance battle/replay, and the updated handoff. The final defensive UI-handle checks also passed a focused scope rerun. Optional rendered scope captures passed and were inspected separately; they do not constitute visual review of all maps/assets. No new script errors or leak warnings were found; the known four-instance allied-faction warning and sandbox certificate/user-log diagnostics remain. The five existing texture-import edits remain excluded.


## Third pass: plain paint examples and camera ownership

The owner independently confirmed that parking no longer removes the truck/container, tabs preserve the preview, the object changes badge is appropriate, comparison return restores the edited content, and Test battle shows the same visible arrangement. Their uncompleted independent checks remain separate from the earlier automated evidence. The paint explanation now uses concrete examples: existing parking spaces outside the painted areas on this floor won't spawn cars. The everyday guide uses the same wording.

The owner also reported a stuck camera after changing the editor view and launching Test battle. A dedicated regression reproduced eight failures: the viewport kept the editor camera while orbit/zoom controlled a different battle camera, and rewatch could retain the wrong camera as well. The battle scene's Camera3D now explicitly sets `current = true`, selecting it when each battle/rewatch enters the viewport. The existing editor return callback selects the original editor camera again. No camera manager, new input system, or tactical rule change was added.

`parcel_camera_handoff_test.gd` checks top view and a manually orbited/panned/zoomed editor view, actual viewport camera identity, visible orbit/zoom, matching mouse-picking camera, replacement-camera ownership on rewatch, and exact editor transform/horizontal-offset restoration with a real unsaved fixed-object edit and unchanged parcel fingerprint. The regression passed headless after the fix; its rendered form also passed. Captures under `artifacts/camera-handoff-review/` were inspected, including changed editor views, actual battle views and restored editor views. This verifies ownership/transitions, not every camera angle or all-squad visibility.

The earlier claim about the owner's previous live session has been corrected above: no deliberate save/discard action was issued, but survival was not verified and the owner found it unavailable on reconnect. The reason is unknown. No claim is made that isolated automated sessions prove persistence of that live session.


Third-pass verification: **24 UI suites passed, 0 failed, 1 explicit-only skip** in 69.53 seconds (`artifacts/test-results/20261115-144255-subsystem-ui/`); **14 replay suites passed, 0 failed, 0 skipped** in 118.21 seconds (`artifacts/test-results/20261115-144439-subsystem-replay/`). The strengthened camera regression passed a final rendered rerun with an unsaved object edit; the paint-scope check passed with the concrete wording. No new script errors or leak warnings were found in these final logs. Direct runs retain the known sandbox certificate/user-log filesystem diagnostics. No full-tier rerun was made for this camera-activation and wording patch; the earlier 126/0/14 full result predates it. The five pre-existing texture-import edits remain outside the commit.
