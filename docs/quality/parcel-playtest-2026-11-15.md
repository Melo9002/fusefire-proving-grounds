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
