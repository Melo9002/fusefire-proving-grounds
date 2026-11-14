# Mesh-derived boundary drafts

The Asset Lab's **Boundaries** tab fits convex candidate boundaries to actual calibrated imported triangles. It is an authoring tool. Exported profiles are unreviewed drafts and are not consumed by the tactical compiler or registered automatically.

## Workflow

1. Open `tools/asset_lab/asset_lab.tscn` in Godot and run it. Select an individual asset. Assembly/duplicate comparison views cannot bake a profile.
2. Open **Boundaries**. **Use whole model bounds** resets the green clipping region to the model. Adjust X/Y/Z limits to isolate a meaningful part, such as cargo, cab, hood or planter.
3. Name the part, choose its intended role, and press **Fit mesh / replace**. The yellow wireframe shows the fitted convex hull. Use **New part** for another region; selecting a listed part restores its clipping limits. Changed bounds/names require another Fit before export.
4. Inspect the result against the visible model. Convex hulls close concavities and openings: one hull around a truck can bridge the hood/cargo gap; one around an open doorway can seal the doorway. Split those regions before treating the result as gameplay-ready.
5. **Export draft** saves an editable `.tscn`; **Open draft** restores its fitted points, clipping regions and roles. The controls and status stay visible below the clipping editor. Removal, replacement and role edits have bounded Undo history. Fitted drafts are retained per asset/calibration during the current session. Fit commits clipping/name edits; unfitted form edits are not saved.

Intended roles are unclassified, solid, movement-only, shot-only, low cover and visual-only. Choosing a role records intent. It does not certify height, clearance, access, cover behavior or tactical occupancy. Unclassified parts cannot be exported.

The profile records its asset identity, source GLB/import SHA-256 hashes, current scale/yaw/anchor/position, convex points, projected footprint, clipping region and role. Opening a different/stale dependency fails without replacing the current draft. Calibration preview edits are captured in this dependency record but do not write calibration or semantic catalogs; save calibration separately through Adjust when intended. Restart/reimport the Asset Lab after changing source files externally, then re-bake affected profiles.

Coordinates are the calibrated asset parent's local frame. Exported nodes deliberately have no `solid_size` or automatic physics body: the existing runtime does not silently reinterpret a new draft as occupancy. A later reviewed adapter must translate fitted profiles into the movement/cover/shot contracts and version that change. Mesh-derived authoring is implemented; automatic runtime migration and catalog-wide conversion remain pending.

The baker clips triangle polygons against the region before fitting, rather than merely keeping existing vertices or replacing the mesh with an AABB. It ignores its own preview geometry, hidden descendants and the lab's MIRA reference. Skinned geometry requires a static snapshot. Budgets are 200,000 source triangles, 50,000 fitted points, 32 parts and 32 Undo entries. Very thin/coplanar, empty, reversed and non-finite regions fail explicitly. This first tool does not perform automatic convex decomposition or preserve every concavity.

## Verification — 2026-11-14

Commands from the repository root:

```powershell
godot_console --headless --path . --script res://tests/asset_boundary_baker_test.gd
godot_console --path . --resolution 1440x900 --script res://tests/asset_boundary_baker_test.gd -- capture
.\tools\run_tests.ps1 full
godot_console --headless --path . --script res://tests/playable_battlefield_validation_matrix.gd
godot_console --path . --resolution 1440x900 --script res://tests/playable_battlefield_validation_matrix.gd -- capture
godot_console --headless --path . --script res://tests/loading_yard_presentation_test.gd
godot_console --path . --resolution 1440x900 --script res://tests/loading_yard_capture.gd -- res://artifacts/loading-yard-fixed
```

The focused authoring regression exercises the real delivery GLB, calibrated bounds, deterministic refitting, clipping a low front region, empty/reversed rejection, export/reopen, changed geometry/calibration, wrong-asset recovery, Undo, role requirements, comparison/reference exclusion and unfitted-edit protection. Asset calibration's existing checks now cover all five tabs. No imported asset or calibration/semantic annotation was edited.

## Playable map audit

The explicit matrix executes all seven registered playable maps through normal battle initialization, with two units per side and Eliminate. Seeds 16 and 17 are checked; each population-capable map runs with population both disabled and enabled. This produces **24 passing cases** in both headless and rendered runs. Each case checks tactical validity, legal deployments, stable replay identity, and reconstruction of static tactical geometry from the accepted manifest. It does not prove every mission or seed, or replace complete replay/action tests in the regular suite.

| Map | Cases | Observed rendered-run initialization | Visual findings |
| --- | ---: | ---: | --- |
| Service Depot | 4 | 666–3,872 ms | Compact imported building, cargo and process props; still sparse |
| Tactical Test Range | 4 | 433–2,469 ms | Deliberate mechanic lanes, ramps/stairs, galleries and parked vehicles |
| Refinery family | 4 | 2,357–2,831 ms | Supported plots and imported parts render; large open areas and a basic horizon remain |
| Urban family preview | 4 | 2,243–2,665 ms | Existing industrial/catwalk proof content remains; it is not a finished urban art set |
| Parking Garage | 4 | 780–2,764 ms | Two-deck structure and parked cars visible; floor/occlusion ergonomics still warrant playtesting |
| Refinery 2 | 2 | 3,462–3,911 ms | Most developed site composition, with connected elevated industrial elements |
| Loading Yard | 2 | 895–1,279 ms | Found and fixed hidden fixed cargo; see below |

These are whole-scene initialization observations during a concurrent test run, including cold/warm asset loads. They are not isolated generation benchmarks or performance budgets. Tactical quality scores ranged roughly 42–52; passing construction does not mean finished cover distribution, pacing or visual density.

Normal oblique and overhead captures are `artifacts/map-<battlefield-id>-<view>.png`. They retain normal battle UI/grid and have engineering diagnostic overlays disabled. All seven oblique views were inspected. `artifacts/asset-boundary-authoring.png` shows the new authoring tool. No manual full-mission playthrough was performed in this pass.

### Loading Yard mismatch

The standalone Loading Yard compiled its two authored containers and truck as obstacles while leaving their source parcel's population-guide nodes hidden. A new regression first failed all three visibility assertions. The standalone presenter now activates those already-compiled fixed occupants. This is a presentation correction; placement, tactical reservations, RNG and replay outcomes are unchanged. The regression passes and corrected clean overhead/oblique/service captures live in `artifacts/loading-yard-fixed/`. Earlier matrix images deliberately retain the before-fix evidence.

The map matrix is an explicit-only integration/rendered audit in the runner, like other expensive/manual diagnostics. It was executed separately; its exclusion from ordinary full runs is not a claim that it was skipped during this audit. Extended stress batches and exhaustive visual/manual gameplay remain separate work.

### Final automated results

- Full regular Ironclad run: **123 passed, 0 failed, 23 explicit-only workflows skipped**, 762.92 seconds. Logs: `artifacts/test-results/20261114-140350-full/`.
- Assets subsystem: **8 passed, 0 failed, 3 visual workflows skipped**. Logs: `artifacts/test-results/20261114-141223-subsystem-assets/`.
- New Loading Yard presentation regression: reproduced 3 failures before the fix, then passed. It was added after full-run discovery and therefore ran separately. Logs: `artifacts/loading-yard-visibility-baseline.log` and `artifacts/loading-yard-visibility-final.log`.
- Final boundary-tool focused rerun passed after the rendered UI adjustments. Asset calibration also passed all 6,052 internal checks. The existing four-tab expectation was intentionally updated to five; all five retain browsing and calibration-save access.
- Map matrix: **24/24 passed**, executed headless and again with rendering. Raw report: `artifacts/playable-map-validation.json`. The separate post-fix Loading Yard captures confirm visible cargo; its tactical data did not change.

Counts across runs overlap and are not unique-test totals. The full run exercises existing movement, elevation, cover, LOS, Guard, mission outcomes and replay checks; it does not mean every mission was newly played on every map. Final full/assets logs contain no script parse errors. Expected rejection tests and the existing sandbox certificate/editor-settings limitations still emit diagnostics. No imported GLBs, calibration records, confirmed semantics or tactical combat rules changed. The remaining mesh-profile-to-runtime adapter is deliberately pending rather than hidden behind a generic box fallback.
