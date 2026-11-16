# Combat geometry and LOS — step 4

2026-11-16. Extends the [controlled range](../combat-controlled-examples.md). Accuracy formula, cover penalties, Aim/Guard/Shield modifiers and damage are unchanged. Shot legality can change where geometry or supported height was previously wrong.

## Demonstrated defects and corrections

| Reproduction | Before | Now |
| --- | --- | --- |
| A precise beam entirely above ground, with no intersecting tactical deck | Rays pass through its visible height because no standing cell indexes the part. | Revision-4 compilation retains its raised shot bounds in a separate column index. Rays through the beam block; rays above/below it clear. No navigation cell or ground reservation is added. |
| Supported surface Y=0.35 or -0.2, while its logical floor is level 0 | Shot origin/target are anchored to rounded grid height. | Origin, target samples and 3D weapon-range distance use the cell's actual supported world position. Actor animation transforms remain irrelevant. |
| All body samples blocked | The blocker belongs to a body-sample ray, but the displayed destination is the body center. | Select the blocked sample nearest the body center, using fixed sample order for ties; report the nearest blocker on that same ray. A tall target can select a shoulder rather than upper body. |
| Multiple precise parts reserve one cell | Highlighting the merged bounds includes an empty gap or unrelated part. | Evaluation exposes the intersected part's bounds; the marker consumes those bounds, retaining the old fallback for plain cells. |
| Old/unknown replay simulation header | Header acceptance could defer incompatibility until action divergence. | Reject incompatible simulation identities before battle reconstruction with a specific geometry-change explanation. |

The initial focused regression had **11 failures**: eight raised-beam direction/rotation cases, two surface-height anchors and one mismatched feedback ray. The final expanded geometry check passes **44 checks**. The additions cover exact compound-part highlighting, a tall target, nearest raised blockers in both directions, map clearing and validator rejection of missing/unowned index entries.

## Existing rules deliberately retained

- One origin at supported position plus the attacker's `standing_height`. Five target samples retain their upper-body/head/shoulder/lower-body offsets. A clear sample makes a geometric shot possible; all blocked makes it illegal. Queries consume no RNG.
- Attack/Guard coverage, AI scoring, normal queries and predicted cells continue using the same body-sample evaluator. A point-ray utility is still a point ray, not an alternate attack-legality calculation.
- Single-corner tangency may pass; touching full diagonal obstacles seal a zero-width slit; rays above the solids pass. The existing 0.001 world-unit numerical tolerance is retained.
- Existing movement stamping remains authoritative for walkability, stopping, cover and vault cost. Raised shot entries are explicitly separate from `MapData.cells`, spawn/objective zones and the path graph.
- Automatic asset placement still saves mesh-derived parts through the existing metadata/compiler path. New overhead checks exercise that exact path, all four quarter-turns and tile scales 1.0/0.5. No boundary fitting or export workflow was added.

The LOS validator now checks ownership by object identity for both ordinary and raised blockers, requires raised bounds to be finite and inside the map, and requires both LOS and column indexes. An orphan blocker is still an error; this is an updated data contract, not a bypass of validation.

## Content and replay compatibility

Current authored compiler/shape revision is **4**. Explicit compiler revisions 1–3 remain reconstructible; a regression proves revision 3 retains its previous raised-part result. Normal new generation selects revision 4. The range parcel revision is **3**, because station 10 adds fixed content.

Current simulation identity is **`prototype-1.5-geometry-los-4`**. Older, missing and unknown simulation identities reject before playback. This is intentional: compiler compatibility does not preserve changed global shot-origin semantics. The schema is unchanged, and schema-2 record decoding remains available when its simulation identity is compatible. Existing files are not rewritten or deleted.

## Verification

| Check | Result |
| --- | --- |
| New geometry regression, final focused run | **44 checks, 0 failures** |
| Controlled range, headless subsystem run | Passed; **101 checks** including raised-beam cases |
| Combat subsystem | **28 pass, 0 fail, 1 optional metrics check excluded** |
| Replay subsystem | **15 pass, 0 fail, 0 skip**; includes current mission/replay matrix and real content playthroughs |
| UI subsystem | **25 pass, 0 fail, 1 explicit rendered workflow excluded** |
| Rendered controlled range | **106 checks, 0 failures**, five captures saved; raised-beam ray and exact-height blocker marker visually inspected |
| Automatic mesh boundaries, extended overhead assertions | Passed, zero failures |
| Authored tactical shapes, parcel catalog, current generation, map validation | All passed with zero assertion failures |

Combat logs: `artifacts/test-results/20261116-070449-subsystem-combat/`. Replay logs: `artifacts/test-results/20261116-070530-subsystem-replay/`. UI logs: `artifacts/test-results/20261116-071019-subsystem-ui/`. Focused before/after logs: `artifacts/combat-geometry-los-before.log` and `artifacts/combat-geometry-los-after.log`. The broad combat/replay runs preceded the final extra validator/tall-target coverage and blocked-sample selection refinement; the expanded focused geometry and prediction-consistency checks passed afterwards. UI and rendered verification followed the refinement. No complete full-project suite or manual battle was run for this step.

The original synthetic fixture mismatch in step 3 and the initial validator rejection during this change were diagnosed as, respectively, missing raised geometry and the old assumption that every LOS blocker is a navigation cell. The fix updates both implementation and validation; it does not weaken the existing missing-blocker checks. Windows root-certificate-store errors appeared in some processes; they are environment diagnostics, not geometry assertions. The current-generation suite intentionally prints a stale-content rejection.

## Limits and next step

The automatic starting boundary is still a box per mesh, not an exact triangle mesh or a guarantee that a concave mesh has an opening. This change fixes raised **precise** parts; historical conservative/round-volume metadata retains its existing stamping. No automatic free peeking, destructible cover, continuous height accuracy bonus, new range curve or 20/40 cover balancing ships here.

Next is step 5: test whether a physical neighboring surface protects the target from the incoming direction, then apply the intended half/full-cover and flanking rules. Animation can later follow those rules. These checks are not a claim that every asset or every camera angle has been manually played.
