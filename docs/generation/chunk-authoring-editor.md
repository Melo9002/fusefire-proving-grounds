# T06: chunk authoring in the Map Editor

T07 adds the [Publish workflow and industrial pilot library](chunk-publication.md); use that guide for current validation, visual-only declarations and owner review/registration gates.

Open `tools/map_editor.tscn` (F6 in Godot), then choose **Author — Chunk Authoring** in the preset selector. This uses the existing viewport/camera. The older **Editable — Custom Layout** remains the battlefield compatibility workspace; it is not the chunk source editor.

## Construct and reopen a draft

1. In **Browse**, search for a component, downloaded asset or saved draft. Click an entry: its translucent preview follows the mouse over the grid. Click to place, or press Escape / **Cancel**. The **Place here** button or Enter confirms the current preview position.
2. Select a placed object. **Move** picks it up as a preview; **Duplicate** previews a fresh copy. Neither changes the saved source until placement. Cancel restores the original. A positioned duplicate is one undo step.
3. Use **Rotate left/right**, **Lower/Raise**, or Q/E and PgUp/PgDn. In **Selected**, precise X/Z/Y and quarter-turn inputs remain available. While a preview is active, **Apply snapped transform** updates the preview rather than moving the original. Outside preview, arrows and numeric transforms edit the selected object directly.
4. **Undo/Redo**, Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y and Delete operate on the source session. Ctrl+D begins a duplicate preview. Overlaps/out-of-bounds module previews turn red and explain the conflict; an unfinished chunk may still retain that placement as a draft.
5. **Chunk details** contains dimensions and boundary ports. **Selected** contains the instance list and exact transforms. Everyday Move/Duplicate/Delete/Rotate/Height controls remain above the tabs.
6. Enter a filename and **Save draft** (Ctrl+S); **Open name** reopens it. Finish/cancel a preview before saving. Opening another source or starting New offers Keep editing or Discard changes and continue. Rejected open preserves the current source; successful open starts fresh history.
7. Saved drafts appear in Browse. Placing one inserts an independent flattened copy with remapped references. Draft copies currently preserve their authored orientation; rotate individual objects after placement. This does not publish/register the source.

Camera orbit/pan/zoom and gallery inspection are preview-only. Object commands, dimensions and ports are persisted edits. Calibration remains owned by Asset Lab.

## Validation and representation

- Structurally valid incomplete, overlapping, out-of-bounds and stale drafts save normally. Transform/schema errors reject transactionally. Live module diagnostics identify the affected stable ID, origin/elevation and geometric reason. **Validate / refresh assets** refreshes the content snapshot and runs the shared source/dependency diagnostics. This is not publication or play certification; full explicit tactical/port compilation remains T07.
- Cyan shows the chunk volume and boundary ports; magenta shows the selected module's visual envelope; amber shows clearance; yellow shows calibrated working faces and module connection directions. Missing geometry has a magenta placeholder. Whole-column reservations span the draft height.
- The reserved local-source identifier `asset:<AssetCatalog ID>` represents a directly authored visual. It reuses the shared placement record and calibrated asset presenter. It does **not** imply a tactical footprint, eligibility, dependency approval or publication. Such records report `UNRESOLVED_VISUAL_TACTICAL_ROLE`; publication must resolve explicit behavior/dependencies in T07. Existing component IDs retain their existing meaning.
- Selection and commands use placement IDs, never array indices. History is bounded to 100 before/after source snapshots; these keep local references together. ID allocation uses the shared allocator, reserves dangling references, and does not reuse an abandoned ID after branching undo history within the session. File load resets session history.
- Draft composition, raw-asset authoring and previews share source records, AssetCatalog, canonical module transforms, spatial queries and the resolved visual cache. No second tactical writer, approval store or calibration catalog was introduced. Refreshing content is explicit; ordinary transforms do not compile a battlefield or rebuild dependency hashes.
- The battlefield compatibility composer is retained for current runtime presets and comparison, as required by the redesign migration plan. Its pending-placement commit policy is different from an incomplete local draft. Retire it when those callers move to the later resolved-source workflow; do not remove that runtime path in T06.

## Evidence and limits

- `tests/chunk_editor_session_test.gd`: stable-ID transform/duplicate/delete undo/redo, membership references, invalid draft round-trip, rejected load, copy independence, undo branching and dangling-reference safety.
- `tests/chunk_editor_workflow_test.gd`: actual gallery/button signals and viewport ray placement; construct, duplicate, diagnostic, move/undo/redo, save/reopen, port, raw asset, draft preview/copy/undo. Runs headless or rendered; screenshots are emitted only in a graphics run.
- Rendered captures inspected: `artifacts/t06-invalid-draft.png`, `artifacts/t06-chunk-authoring.png`, `artifacts/t06-construction-controls.png`. These demonstrate the scripted UI workflow, not broad human usability certification.
- Compatibility suites: chunk source/store, map editor layout store, existing pending-placement preview, placement identity and resolution-context negatives. Logs: `artifacts/t06-*.log`.
- Existing certificate-store startup diagnostic persists. A debugger-exit crash occurred during an initial failed parse check; subsequent verification uses normal, non-debugger processes. Final rendered workflow and actual editor scene startup are checked separately.
- No wall drawing, arbitrary scaling, nested published-chunk instances, publication UI or runtime tactical certification was added. Clearance/tactical records are preserved and displayed where applicable; this task does not add a full tactical-contribution painting interface.

## Owner playtest

Try the seven steps above with two containers and one downloaded raw asset. Check that mouse selection feels correct, the working-face arrows match the visible faces, rotation/elevation respond promptly, and reopening preserves what you built. Deliberately overlap the containers and save: the source should remain editable with an object-specific warning. Undo/redo and delete/undo should restore the same objects. Report the draft filename plus a screenshot for any discrepancy. Aesthetic approval and later publication remain separate decisions.

## Mouse-placement follow-up (2026-10-27)

The owner requested more intuitive construction. Placement, movement and duplication now share a cancellable mouse preview, with one source command on confirmation. Replaced the immediate overlapping-copy UI and obsolete click-placement handler. Reused the existing calibrated renderer and spatial queries; no new persistence or identity system.

Session regression and the updated real-control workflow passed, including mouse motion, cancel, preview rotation/height, one-step duplicate undo, identity-preserving movement and save/reopen. Rendered screenshots inspected, including `artifacts/t06-mouse-preview.png`. Logs: `artifacts/t06-mouse-session.log`, `artifacts/t06-mouse-rendered.log`. The graphics run also emitted a shader-cache file-write error; rendering and assertions completed. That cache-write failure and the existing certificate-store diagnostic are not reported as fixed.


### Saved chunk browsing

Use **Browse saved chunks** near the top to clear old searches and list saved drafts and industrial examples. The category dropdown separates saved chunks, examples, components and assets. Search accepts visible names with spaces; no prefix is required. Selecting a saved chunk previews it only: choose **Open selected draft for editing** or **Place selected content** explicitly. Default saved drafts remain discoverable after opening an industrial example. Restart the running editor scene to load updated controls.
