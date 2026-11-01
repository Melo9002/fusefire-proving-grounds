# Proposed map plan: Prototype 1.5 to 2.0 to Miku versus Teto

Status: earlier discussion draft, 2026-11-01. For the newer XCOM-inspired direction, see [map study and requirements](xcom-map-study-and-requirements.md). Proposed scope and content counts need owner agreement. This is the map workstream, not the complete release roadmap. It supersedes neither gameplay contracts nor the archived generator by implication.

## Product requirements

The first game is a small, replayable Miku-versus-Teto tactical game. A deployment involves fighting, rescuing or reaching/interacting with something, followed by extraction. Multiple simultaneous/sequential objectives and the post-mission photo are mission/presentation work; maps must accommodate them without implementing those systems themselves.

Maps need recognizable places, readable combat, alternative routes, elevation where useful, reliable deployment/objective/extraction positions, repeatable seeded variations, and affordable authoring. Fully authored locations must remain supported. Building interiors are selective, not a requirement for every building. Large scenery is allowed, but playable encounter size must be judged by travel time and useful decisions.

Later FuseFire locations may persist across visits while movable contents change between days. Preserve a separation between permanent structure and movable contents now; defer campaign persistence and calendar rules.

## Small target architecture

Use one map definition referencing a normal Godot environment scene, explicit tactical surfaces/obstacles/traversal, mission-compatible markers, and optional population regions. Visual meshes do not independently decide protection percentages. Existing MapData and gameplay remain authoritative.

Preparation: choose authored environment or a supported layout variant -> place compatible movable content -> bind the selected mission -> validate -> activate the existing battle scene. Record the chosen map/content revision and resolved choices for reproduction; do not rely on the seed alone after content changes. Fully authored maps can omit population. Every strategy uses the same tactical/runtime boundary.

Refinery 2 is the first content proof. Its map-specific adapter, direct scene metadata and offline authoring script are not yet a general production workflow. Consolidate the demonstrated repeated operations when the second environment is authored; avoid copying a new writer/presenter for every map. Recover useful archived editor capabilities only when needed.

## 1.5: prove content production and one useful variation pass

1. Finish the refinery playability pass. Check all five ladder accesses, camera/floor selection, sightlines, approach exposure, objectives and extraction. Choose a representative encounter area if the whole site makes missions too slow. Preserve the old Refinery and Generator 1.
2. Make authoring repeatable for another agent and the owner. Provide a concise asset/scale guide, reusable structural scenes, measured connection examples, tactical annotations, a small validation command and required overview/detail captures. Prove this by authoring a distinct second environment without a new runtime recipe or personal guidance at every step.
3. Add contextual population over fixed environments. Start with loading, parking and maintenance regions. Choose from a few authored arrangements of compatible cargo, vehicles and barriers. Protect entrances, ladders, overhead clearance, permanent scenery and active mission routes. Fully authored population is a valid choice too.
4. Validate the same map under several seeds and objectives. A seed must visibly change useful cover/routes or deployment problems, not merely paint colors. Save/replay must preserve actual choices; failed preparation must not partially activate a battle.

Exit gate: two believable authored environments, a usable authoring workflow, one bounded population pass, meaningful seed variation, acceptable measured load/turn time, and owner playtesting. Suggested first environments: refinery/process site and a compact urban service block.

## 2.0: prove variety without restoring the old framework

5. Build an initial content set. Suggested target: two families (industrial and urban), with two permanent layouts per family. A loading/container depot can reuse industrial content; a service street/courtyard can establish urban content. Treat these counts as a starting proposal, not a content quota.
6. Trial bounded layout variation where it buys real variety. One family may choose authored arrangements of substantial areas: tank yard, process hall, loading yard. Fixed connection geometry and explicit access obligations must be satisfied. Start with a few known layouts; general road networks, arbitrary parcel packing and universal socket solvers are not prerequisites.
7. Prove mission reuse. Support the selected mission set across these layouts through explicit capacity/access markers. Test objective approach and extraction, not just spawn connectivity. Reserve room for multi-objective missions while developing their rules separately.
8. Consolidate and retire. Keep only one active map-preparation path for the new content. Remove superseded adapters after parity is established; archive useful tools locally. Retire Generator 1 only once its useful gameplay/replay obligations have replacements and the owner agrees.

Exit gate: a compact, playtested pool with perceptibly different layouts and encounters, reliable reproduction, practical authoring cost and bounded preparation time. If authored layouts plus population provide enough variety, procedural layout composition is optional; evaluate its benefit explicitly.

## Miku versus Teto: ship the game loop

Use the proven map system to support deploy -> objective(s) -> extraction -> result/photo -> next mission. Add faction-themed mission briefs, props and lighting as content. Expand the environment pool based on repeated-play feedback. A train station is optional later content; no new family is required merely to demonstrate generality.

Reusable boundaries should separate environment content, mission rules, faction/character data and simulation. Do not build a general tactical-engine SDK before the first game works.

## Deferred

Persistent revisits/day-based changes; broad enterable interiors; destructible structures; mesh-derived continuous protection percentages; unrestricted city/refinery generation; large bespoke editor infrastructure; world/campaign simulation. Revisit each when a concrete game requirement justifies it.

## Decisions for the owner

Recommended defaults: two initial families (industrial/urban); two authored environments for the 1.5 proof; four permanent layouts as an initial 2.0 target; contextual population before layout composition; simple selected interiors later; no requirement to procedurally construct every environment. These are proposed, not approved.

Immediate next task: the small authoring workflow, using the completed refinery as an example and a second environment as the acceptance test. Continue owner playtesting of the refinery alongside that work.
