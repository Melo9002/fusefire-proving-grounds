# Generator redesign — task sets and implementation prompts

Date: 2026-10-25. Status: proposed execution pack; no implementation has started through this pack.

Architecture reference: [feasibility and development plan](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/2026-10-25-generation-redesign-feasibility-and-plan.md).

## How to use this pack

Work on one numbered task at a time. A set is a milestone, not a request to implement every task simultaneously. Start with T00. Subsequent implementation requires the owner to authorize the selected task or set; this document alone is not authorization. When a set is authorized, routine implementation choices and its listed tasks do not need repeated approval. Stop at its completion/review gate or an unresolved material product decision.

Use the launcher below, replacing the task ID. Its task brief is supplied in this file, so no one needs to paste the entire architecture report into every conversation.

```text
Work on FuseFire task T01 from
C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/generation/generation-redesign-task-pack.md.

Read this pack's Execution rules and the selected task brief. This authorizes
implementation of that task only, within its stated scope. Verify its
prerequisites against the current repository and accepted decisions. Read the
relevant architecture sections and source, not every historical report.
Complete the task, its focused validation and its consolidation obligations.
Do not start another task, commit, push, or delete unrelated work.
Report evidence, limitations, and the next dependency-ready task.
```

For T00 use the planning-only starter at the end of this file. If a prerequisite has materially changed, explain the discrepancy and make an updated bounded proposal; do not quietly implement around an unapproved contract.

## Recommended staffing and budget discipline

My project-specific recommendation is Astra for ambiguous shared contracts and selected independent review gates, with Sol implementing most bounded tasks. Both can be used for implementation; the assignment should follow observed quality, not a permanent rule that one model may only plan. Official guidance positions Astra for demanding analysis and GPT-6.1 Sol for complex work where cost matters; compare actual outcomes on these tasks rather than assume total token cost from model names. [OpenAI model-selection guidance](https://developers.openai.com/api/docs/guides/model-selection)

If this consulting chat becomes an implementation chat, its self-checks are useful but are not independent review. Use a fresh reviewer/context at the major gates. No separate agents or chats are automatically created by this pack.

To control usage:

- Give each task an explicit outcome and small relevant reading set. Avoid asking every implementer to audit the entire repository again.
- Maintain one compact progress ledger and one current decision record; update them rather than producing a long certification report per edit.
- Preserve concise failure evidence and exact commands. Repeat expensive suites only after relevant changes or unresolved failures.
- Use focused implementation tasks, then milestone-level integration and visual reviews. Do not use the strongest model/highest reasoning setting for every mechanical step by default.
- Measure rework and accepted outcomes as well as tokens. A cheaper initial answer that causes a schema rewrite may cost more overall.
- Re-estimate later tasks after the first usable chunk workflow. Do not promise a fixed total budget before that evidence exists.

## Execution rules shared by every task

1. Read applicable `AGENTS.md` and `docs/quality/project-ironclad.md`. Inspect HEAD and working-tree changes; preserve unrelated user work. Historical evidence was gathered at `fb373e6`, not a command to reset the repository.
2. Read the current accepted redesign decision record and progress ledger if present. T00 establishes them. Distinguish proposed choices from owner-accepted choices.
3. Preserve `MapData` as runtime tactical authority. Reuse proven transforms and gameplay systems. Do not create a second combat map, tactical writer or competing approval registry.
4. Implement the selected task end to end, including focused regression coverage where practical. Do not weaken assertions to manufacture success. Diagnose failures before changing contracts or tests.
5. Never imply that headless success proves visual quality. Record visual evidence where requested; a human approval field requires actual human approval of that revision.
6. Treat draft saving, technical validation, visual review and generator registration as distinct states. Invalid drafts may be saved; they may not silently become published content or playable results.
7. Consolidate within the task: remove superseded code when callers and support obligations permit. Document temporary adapters with their retirement condition. Do not add abstractions merely to make all producers look identical.
8. Do not delete downloaded assets, historical evidence, user saves, unrelated experiments or regression tests as generic cleanup. Investigate references, dynamic loading, manifests, scenes, exports and compatibility before removing code. Historical artifacts need a separate retention decision.
9. Commit/push only if separately authorized. Task completion is a validated change and a concise handoff, not necessarily a commit.
10. If interrupted, leave a compact checkpoint: changed files, completed criteria, remaining failures, exact resume command and next action. Do not mark partial work complete.

**Completion entry:** task ID; HEAD/working-tree context; behavior changed; acceptance results; commands and pass/fail/skip status; visual evidence/approval status; removed/consolidated code; temporarily retained code and retirement condition; unresolved issues; next task. Prefer a short entry in `docs/generation/generation-redesign-progress.md`, created by T00, over another long report.

**Definition of “enxugar”:** fewer competing authorities, duplicated algorithms, special-case paths and authoring steps. File count and lines removed are secondary metrics. Moving old code to a new folder or adding a wrapper is not by itself simplification.

## Sequence at a glance

| Set | Tasks | User-visible result | Suggested use of models |
| --- | --- | --- | --- |
| A — Decide the contract | T00 | Small accepted scope and proof-content plan | Astra useful |
| B — Trustworthy composition | T01–T04 | Stable edits, correct tactical composition, reliable revision checks | Sol implementation; Astra review of shared contracts |
| C — Usable chunk authoring | T05–T07 | Create, save, edit, inspect and register a reusable chunk | Sol; fresh review at the gate |
| D — Population on a fixed environment | T08 | A useful standalone generation strategy | Sol |
| E — Compose battlefields | T09–T11 | Two authored plots using the shared library, playable and replayable | Sol; Astra for planner/mission boundary review |
| F — Vertical and modular proof | T12–T13 | Reusable vertical chunk and optional procedural draft producer | Either; escalate difficult geometry/contract issues |
| G — Performance and consolidation | T14–T16 | Measured latency, retired duplicate paths, release decision | Sol implementation; fresh final review |
| Optional expansion | T17 | Decision on a procedural road/plot planner | Astra analysis first; no automatic implementation |

Milestone mapping: A = M0; B = M1; C = M2; D = M3; E = M4; F = M5/M6; G = M8; optional expansion = M7. Deferring M7 until the core is consolidated is deliberate.

## Set A — Decide the contract

### T00 — Freeze the smallest useful redesign scope

**Type:** analysis/documentation only. **Dependencies:** none. **Read:** architecture executive assessment, D2–D7 and G; verify the relevant current interfaces.

```text
Prepare the implementation decision record for the FuseFire redesign; do not
change production code. Propose the smallest coherent contracts for stable
instances, chunk source, authored plot, resolved battlefield output, tactical
composition, and publication. Choose proof content from the existing assets.
Separate necessary decisions from optional features. Explain unresolved owner
choices with a recommended default and consequence; do not label them approved.

Create a concise decision record and a progress ledger. Include the task
dependency order, baseline test/capture references, and a retirement register
for current generation paths. Reuse existing evidence rather than rerun the
whole investigation. End with the concrete decisions needed to start Set B.
```

**Done:** one concise schema/ownership sketch, selected pilot content, compatibility scope and owner decision list. **Enxugar:** identify competing authorities and intended survivors; delete nothing. **Gate A:** owner accepts the material contracts/scope; acceptance can authorize a whole subsequent set.

## Set B — Trustworthy composition

### T01 — Stable placement identity and edit semantics

**Dependencies:** accepted T00. **Read:** architecture A3.3, D8; placement model, document edit handling and editor commands.

```text
Implement stable placement identities through create, move, rotate, variant
change, duplicate, delete and save/load. Transforming an object preserves its
identity; duplication assigns fresh identities and remaps internal references.
Deletion reports required-reference loss explicitly. Migrate legacy identity
deterministically without inventing approval. Route existing editor operations
through this identity model. Avoid a separate editor-only identity system.
```

**Verify:** transformed referenced occupants keep ownership/access refs; duplicate and deletion semantics; round-trip stability; rejected load preserves current state. **Enxugar:** retire signature-based identity inference from current edits; retain it only in a clearly scoped legacy importer if needed. Undo UI is T06, but commands must be compatible with it.

### T02 — Explicit tactical compilation rules

**Dependencies:** T00, T01. **Read:** D6; current map writer/compiler and the temporary `boundary_probe.gd` under `artifacts/architecture-redesign-research/` if available. Recreate the tiny oracle if artifacts are absent.

```text
Replace insertion-order tactical mutation with the accepted contribution and
conflict rules. Preserve MapData and existing gameplay contracts. Establish
surfaces before applying occupants/effects and traversal links. Omitted fields
must not erase another contribution; incompatible claims must fail explicitly.
Correct the reproduced ground-after-obstacle bug in the shared compiler path.
Do not introduce a second writer or hide undefined semantics by merely sorting.
```

**Verify:** permutations of equivalent legal placements produce the same map; ground cannot reopen blocking cells; missing surfaces/endpoints reject; valid existing fixtures still compile. **Enxugar:** remove superseded mutation paths after callers migrate. Intentional behavior changes must be documented with tests.

### T03 — Elevation-aware placement and shared spatial queries

**Dependencies:** T02. **Read:** D4/D6; module layout, reservation ledger, vertical fixtures.

```text
Implement the accepted elevation/support model for occupancy, visual envelopes
and clearance. Distinguish floor-specific from deliberate whole-column
reservations. Reuse canonical transforms and expose the same spatial queries to
authoring and generation. Support the pilot's separate floors and real overlap
rejection; do not build arbitrary polygon packing or unrestricted stacking.
```

**Verify:** same X/Z on independent supported floors succeeds; intersecting volumes or inadequate headroom fail; rotated rectangular content and traversal work; deliberate whole-column mission protection remains effective. **Enxugar:** consolidate duplicate geometric reservation calculations without merging unrelated semantic policies.

### T04 — Approved revisions and one resolution context

**Dependencies:** T01–T03. **Read:** D2/D7; assembly contracts, library, document dependencies, presenter.

```text
Implement approved revision baselines and a per-operation resolved dependency
context. Cover geometry, calibration and behavior-changing assembly fields.
Execute substantive validation instead of trusting a certification flag.
Resolve exact visual choices once and make compilation/presentation consume
those records. Changed content must not acquire fresh approval automatically.
Keep technical validation and human approval distinct. Avoid a new parallel
registry; use the accepted small content index/resolver design.
```

**Verify:** changes to geometry/calibration/transform/socket/clearance/effects invalidate the appropriate records for both old-document load and new generation; repeated instances reuse resolution; renderer does not reroll variants. **Enxugar:** remove redundant live resolution and repeated reads where replaced; retain explicit invalidation.

**Gate B:** fresh review of identity, merge semantics, dimensionality and revision enforcement. Review actual source and negative tests. Passing old suites alone is insufficient. Necessary corrections belong to these tasks before chunk-library expansion.

## Set C — Usable chunk authoring

### T05 — Chunk source, draft persistence and versioned import

**Dependencies:** Gate B. **Read:** D2/D3/D7; existing document/store.

```text
Add the accepted local chunk source representation with stable instances,
rectangular bounds, ports, explicit tactical contributions, clearances and
dependencies. Separate source-file validity from publication/play validity.
Support named draft save/load even while content is incomplete. Reuse shared
records and validation services; keep battlefield mission binding out of chunk
sources. Add explicit non-destructive legacy import with diagnostics.
```

**Verify:** incomplete drafts round-trip; malformed files fail transactionally; unsupported versions reject; no silent source rewrite or fabricated approval; two instances of the same source remain independent. **Enxugar:** share persistence infrastructure rather than copy the map store into a second unrelated implementation.

### T06 — Editor session, history and construction controls

**Dependencies:** T05. **Read:** D8; current composer and Asset Lab gallery/preview facilities.

```text
Restructure the existing Map Editor around an editable session and stable-ID
commands. Implement undo/redo, duplicate/delete, snapped transforms, elevation
selection, named drafts and a searchable asset/component/chunk gallery with
previews. Reuse the viewport, camera, calibration ownership and useful overlays.
Expose chunk bounds, ports, working faces and actionable placement errors.
Invalid drafts remain editable/saveable. Clearly distinguish preview-only
inspection adjustments from persisted edits. Do not create another application.
```

**Verify:** construct a small chunk manually without editing code; save/reopen; undo/redo transforms and duplication without broken refs; invalid placement feedback identifies the object/location. Include rendered or interactive evidence. **Enxugar:** remove replaced index-based UI state and duplicated gallery/transform behavior. If needed, divide gallery and command work into bounded substeps within T06; avoid unrelated editor features.

### T07 — Validate, review and register a small chunk library

**Dependencies:** T04–T06. **Read:** D3/D7 and F1.

```text
Implement explicit validate/review/register actions tied to immutable chunk
revisions. Create the agreed small industrial proof library using downloaded
assets: frontage, loading/service yard, alley/courtyard and supported street
pieces. Use content-driven rectangular sizes and actual port geometry. Capture
review evidence. Agent visual inspection may report findings but cannot invent
owner approval. Registration is allowed only when all required gates are met.
```

**Verify:** generator eligibility excludes draft/stale content; editing a registered source produces a new draft; mismatched ports and incomplete structures reject; every proposed registered chunk has a reviewable thumbnail/capture and dependencies. **Enxugar:** replace the migrated code recipes with data where their consumers can already use it; record remaining adapters. Do not force all catalog assets into this pilot.

**Gate C:** owner can create, edit, save and explicitly approve a chunk without a new code recipe. If that workflow is awkward or slow, improve it before scaling the library. Human visual approval remains a genuine gate.

## Set D — Tactical population on a fixed environment

### T08 — Extract an independent population pass

**Dependencies:** Gate C. **Read:** D5/D6; legacy cover generation and mission reservations.

```text
Implement bounded tactical population over an established authored composition.
Reuse useful legacy placement policies, but preserve immutable base content.
Place compatible cover/obstacles/props only in declared regions, protecting
access, support and active mission requirements. Record exact seeded choices in
the accepted document and use the shared compiler. Provide one playable fixed
environment with meaningful population variation; no random global scattering.
```

**Verify:** base-content signature unchanged across seeds; protected routes remain usable; deterministic accepted output; valid save/load/play/replay. Capture different seeds with tactical overlays and clean views. **Enxugar:** extract and reuse policies instead of retaining a copied population algorithm. Remove obsolete orchestration only after its compatibility obligation is satisfied.

**Gate D:** strategy A works independently. It is a useful deliverable even if later chunk composition is delayed.

## Set E — Compose battlefields from chunks

### T09 — Authored plots and active-mission requirements

**Dependencies:** Gate C; T08 need not be complete for source authoring. **Read:** D2/D4/D5.

```text
Implement authored plot sources and the corresponding editor workspace: map
boundary, fixed street ownership, slots, port/frontage obligations, reservations
and active-mission requirements. Author the two agreed plots using the same
small library. Keep local chunk internals separate from world placement.
Detect impossible slot requirements against the library. Do not implement a
procedural road-graph generator in this task.
```

**Verify:** street/sidewalk ownership is unambiguous; variable slots do not stretch assets; required mission capacity/access is represented; impossible configurations explain the missing requirement. **Enxugar:** use the accepted plan representation instead of adding another competing road/parcel plan.

### T10 — Deterministic selection, connections and bounded search

**Dependencies:** T08, T09. **Read:** D4/D5/D7; existing candidate search and relationship validation.

```text
Fill authored plot slots from approved chunk revisions using deterministic
candidate ordering, compatible rotations, explicit connections and bounded
search. Prioritize constrained slots and respect active-mission reservations.
Apply the population pass only to allowed regions. Reuse existing search and
relationship algorithms where their contracts fit. Required-slot failure must
not silently become an empty lot. Produce the common accepted snapshot.
```

**Verify:** matching tags with mismatched geometry rejects; all mandatory connections and frontage are satisfied; same inputs reproduce choices; budget exhaustion is bounded/actionable; two plots yield distinct useful arrangements. **Enxugar:** replace hardcoded template dispatch for migrated content; keep an explicit adapter only for unmigrated reference fixtures.

### T11 — Gameplay, edited-map replay and composition review

**Dependencies:** T10. **Read:** F2/F3; existing runtime and replay integration.

```text
Complete the common runtime preparation path for the redesigned plots without
creating a second battle scene or simulation. Exercise natural Eliminate and
Terminal playthroughs, saved edited maps and action-by-action replay. Evaluate
the fixed and holdout seed sets with clean/diagnostic captures. Report visual
failures honestly; do not replace failing seeds silently or use teleports as
evidence of complete natural traversal. Fix integration defects within scope.
```

**Verify:** owner-editable generated map; required paths and mission completion; exact saved choices reproduced; recorded/replayed state agrees; no partial activation on validation failure. **Enxugar:** retire superseded industrial-specific preparation/presentation branches where the common path proves parity.

**Gate E:** fresh architectural review plus owner visual/playability review. Decide whether chunk reuse improves authoring time, composition and variety enough to proceed. Do not automatically authorize an unrestricted procedural planner.

## Set F — Vertical content and modular draft production

### T12 — One reusable vertical warehouse

**Dependencies:** Gate E. **Read:** D3/D4/D6; warehouse/traversal/cutaway implementation.

```text
Convert one agreed vertical warehouse or facility into reusable source content.
Preserve supported surfaces, cover/LOS, traversals, support and per-building
floor/cutaway membership. Place it at multiple origins and supported rotations
without world-coordinate special cases. Use the same chunk, compiler and editor
workflow. This does not authorize unrestricted multistorey chunk stacking.
```

**Verify:** movement to elevated areas and back, headroom/overlap rejection, camera/floor selection, rotated placements and replay. **Enxugar:** remove the converted facility's duplicated production constants/presenter branches when equivalent content is demonstrated; retain small useful regression fixtures deliberately.

### T13 — Modular assembly as a normal draft producer

**Dependencies:** Gate C; integrate after E in the default sequence. **Read:** D3/D5; measured socket and recipe examples.

```text
Adapt one useful measured socket/assembly family to emit ordinary editable
chunk drafts. Preserve source provenance, local transforms and dependency
revisions. Generate two drafts, edit one manually, then validate/review it through
the normal workflow. A published result must load without rerunning the draft
generator. Do not implement a universal grammar or auto-approve outputs.
```

**Verify:** generated draft and handcrafted source share editing/persistence; wrong attachment/completeness rejects publication; approved result can fill an existing plot slot. **Enxugar:** remove any special save/presenter path introduced solely for that producer; no parallel content representation.

**Gate F:** the three creation strategies converge on the accepted boundary, and the vertical proof exposes no hidden world-coordinate dependencies.

## Set G — Performance, retirement and release

### T14 — Profile and meet agreed interaction budgets

**Dependencies:** T11, T12, T13 in the default full scope. **Read:** E4 and current measured logs.

```text
Measure cold/warm resolution, editor edits, chunk validation, composition,
tactical compilation, presentation and replay initialization separately on a
named machine. Address demonstrated bottlenecks while preserving invalidation
and diagnostics. Reuse resolved dependencies; prevent stale asynchronous
preview results from replacing current edits. Do not remove validation to make
benchmarks pass. Report before/after evidence and remaining budget decisions.
```

**Verify:** comparable workloads/revisions and functional outputs; changed dependencies still detected; interactive preview remains correct. **Enxugar:** consolidate duplicated caches/resolution paths rather than add an independent cache per subsystem. Profiling may occur earlier when a milestone's usability requires it; T14 is the integrated pass.

### T15 — Retire obsolete production paths

**Dependencies:** T14 and accepted parity evidence. **Read:** retirement register, actual call sites and compatibility scope.

```text
Audit and remove superseded generation/editor/presentation code whose retirement
criteria are satisfied. Trace static and dynamic references, scenes, resources,
test discovery, export lists and supported saves before deletion. Consolidate
remaining authorities and document unavoidable adapters with removal triggers.
Preserve downloaded assets, useful tests, user work and historical evidence.
Do not delete files merely because a text search finds no caller. Replace obsolete
contract tests only with explicit justification and retained valid invariants.
```

**Verify:** no production caller of removed paths; supported import/legacy policy works; representative regression and export/resource-loading checks pass. **Enxugar evidence:** what authority/algorithm/path disappeared, remaining adapters, authoring-step reduction, and optional line/file counts. Do not use a deletion quota.

### T16 — Independent acceptance and roadmap update

**Dependencies:** T15. **Type:** review/documentation; use a fresh reviewer where possible.

```text
Independently assess the completed redesign against the accepted contracts and
milestone criteria. Inspect current code and a representative runtime/visual
sample, not only implementer reports. Verify all three workflows, publication
boundaries, tactical authority, deterministic saves/replay and claimed removals.
Separate confirmed defects, coverage gaps and optional improvements. Update the
roadmap to demonstrated capability. Do not implement a new redesign or conceal
blocking findings with a certification label; hand back bounded repair tasks.
```

**Done:** release/continued-opt-in recommendation, known limitations, supported configurations, remaining debt with owners/retirement conditions. No claim of generality beyond demonstrated content and missions.

## Optional expansion

### T17 — Decide whether procedural plot/road planning is worth building

**Dependencies:** accepted Gate E or later; separate owner authorization. **Type:** analysis first.

```text
Evaluate the remaining need for procedural road/plot planning using observed
limits of the authored plots and actual available road assets. Compare adding
authored plot variety with a graph planner that emits the existing plan format.
Estimate engineering/content/debugging burden and define a bounded proof only
if the benefit is credible. Do not implement a second plan schema or start the
planner automatically. Recommend build, defer or decline with evidence.
```

If approved, derive a separate implementation task from this decision. General grammars, arbitrary polygon packing and unrestricted nesting remain outside this pack unless explicitly commissioned.

## Reusable milestone review prompt

```text
Review FuseFire task set [SET] against the accepted decision record and
docs/generation/generation-redesign-task-pack.md. This is review-only.
Read the completion entries, then independently inspect the changed code and
run the smallest meaningful checks. Verify claimed simplification, compatibility
and negative cases. For visual claims inspect actual captures/runtime output.
Classify findings by impact, cite evidence, and distinguish acceptance blockers
from optional improvements. Return accept, accept with stated limitations, or
needs correction. Do not treat missing evidence as success. Do not modify
production code, commit, or push.
```

## Starting prompt — copy this first

```text
Start T00 from
C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/generation/generation-redesign-task-pack.md.

This is a planning-only task. Prepare the concrete decision record, proof-content
scope, execution dependencies and retirement register needed to begin Set B.
Use the existing feasibility report and inspect only the current interfaces
needed to resolve the decisions. Make recommendations rather than asking me to
design the schemas. Distinguish proposed choices from accepted choices. Keep
the decision summary concise. Do not implement production changes or start T01.
```
