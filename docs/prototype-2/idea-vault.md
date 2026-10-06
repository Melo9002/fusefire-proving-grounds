# 🔥 FuseFire Prototype 2 — Idea Vault

> **North star:** Make the rectangles become FuseFire.
>
> Prototype 2 builds the reusable tactical and content foundation. Once it can
> support everything **Miku vs. Teto SRPG** needs, that game receives its own
> repository for characters, maps, missions, balance, polish, and release work.

This is a garden of possibilities, not a backlog or promise. Ideas move into a
roadmap only after we understand their value, dependencies, smallest useful
experiment, and effect on what Prototype 1 already proved:

For concrete next steps, task cards, and the current “start now / discuss /
research / park” split, see the [Pre-production Workshop](preproduction-plan.md).

> **THE RECTANGLES ARE FUN. Do not destroy that while making them prettier.**

## 🧭 How to read the vault

| Mark | Meaning |
|---|---|
| ⭐ | Strong candidate: likely important to P2's identity or production path |
| 🌱 | Candidate: promising, but must earn scope |
| 🧪 | Experiment: test cheaply before designing a permanent system |
| 🔬 | Research question: investigate before choosing an approach |
| 🧰 | Tooling: helps us create or understand the game |
| 🧊 | Later: preserve the idea without burdening P2 |
| 🫘 | Sacred archaeological material |

Effort is deliberately rough: **S** (days), **M** (roughly a focused week or
two), **L** (multi-system work), and **XL** (its own development phase). Content
burden matters separately: a simple system can still demand dozens of assets.

| Lane | Meaning |
|---|---|
| **Foundation** | Enables many later systems or content workflows |
| **Identity** | Makes the project recognizably FuseFire |
| **Production** | Needed to build Miku vs. Teto primarily as content |
| **Experiment** | Must prove value before entering architecture |
| **Future** | Valuable beyond the P2/Miku-vs-Teto boundary |

## 🗺️ Battlefield and maps

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| MAP-01 | Shared authored/procedural map representation | ⭐ | L | Foundation | Define one map resource both workflows can read and validate |
| MAP-02 | Modular environment kit: primitives → modules → patterns → battlefield | ⭐ / 🧪 | L | Foundation | Build 5–10 crude pieces and two tiny maps; avoid designing a giant schema first |
| MAP-03 | Developer Map Maker / Map Editor | ⭐ | L | Production | Edit MAP-01 data; begin as an internal tool rather than a polished player feature |
| MAP-04 | Simple procedural module assembler | 🧪 | M | Experiment | Assemble the same kit used by MAP-03 and compare cleanup cost |
| MAP-05 | Richer cover, concealment, traversal, and terrain properties | ⭐ | L | Identity | Extend existing cell data from demonstrated combat needs |
| MAP-06 | Elevation and vertical traversal refinement | ⭐ | M | Production | Build on P1 ladders, stairs, ramps, roofs, and stacked selection |
| MAP-07 | Tactical Area / Peripheral Area / Distant World | ⭐ / 🔬 | XL | Identity | Prototype one small playable area with cheap surrounding scenery |
| MAP-08 | Natural battlefield boundaries | 🌱 | M | Identity | Replace obvious board edges without hiding legal-space readability |
| MAP-09 | Smoke and vegetation | 🌱 | L | Experiment | Prove one terrain property and its LOS/UI language before adding varieties |
| MAP-10 | Roof, upper-floor, and wall hiding | ⭐ | L | Production | Depends on richer buildings and camera obstruction rules |
| MAP-11 | Destructible cover | 🧊 | XL | Future | Requires destruction state, navigation/LOS updates, AI understanding, VFX, and replay |

### 🧱 Modular-kit vertical slice

1. Create approximately 5–10 intentionally crude environment modules.
2. Record only metadata that a real use case proves necessary: footprint,
   traversable surfaces, cover, entrances, elevation, connectors, and clearance.
3. Hand-author one compact battlefield from the kit.
4. Assemble a second battlefield with a deliberately simple procedural tool.
5. Compare authoring speed, tactical quality, visual coherence, metadata cost,
   and manual repair.
6. Refine the shared representation only after the comparison.

The human designer and generator should speak the same environmental language.
Improving `Warehouse_A` should improve every authored or generated map using it.

## 📷 Camera, interface, and combat presentation

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| PRE-01 | Camera obstruction and environmental cutaway | ⭐ | L | Production | Fade, hide, or cut one obstructing wall while preserving tactical context |
| PRE-02 | Camera collision and push-in | ⭐ | M | Production | Cooperate with PRE-01 rather than fighting it |
| PRE-03 | Shared tactical/action/replay camera logic | ⭐ | M | Foundation | Consolidate policy while preserving P1 replay and pause behavior |
| PRE-04 | Improved live action cameras | ⭐ | M | Identity | Reuse the director with contextual candidates and readable transitions |
| PRE-05 | Better tactical UI | ⭐ | L | Production | Define information hierarchy before reskinning widgets |
| PRE-06 | Muzzle flashes, impacts, and audio feedback | ⭐ | M | Identity | One weapon archetype from trigger to hit/miss feedback |
| PRE-07 | Mission photographs and XCOM-style posters | 🌱 | M | Identity | Generate one post-mission composition from replay/battle state |
| PRE-08 | Accessibility and presentation settings | 🌱 | M | Production | Text scale, camera intensity, motion/shake, color-independent team cues |

## 🤖 MIRAs and unit presentation

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| MIRA-01 | Replace P1 dummy with the proper early MIRA-0 | ⭐ | L | Identity | Finish rig, import one clip, validate scale/feet/forward axis |
| MIRA-02 | Canonical FuseFire humanoid skeleton contract | ⭐ | L | Foundation | Define required bones and retarget boundary from the real MIRA-0 rig |
| MIRA-03 | Character presentation profiles | ⭐ | M | Foundation | Model, clips, sockets, contacts, offsets, materials, height, and camera anchors |
| MIRA-04 | Equipment sockets and convincing weapon handling | ⭐ | M | Production | Shoulder stock, hands, muzzle, sights, stow point, and correction offsets |
| MIRA-05 | Authored animation library and import workflow | ⭐ | L | Production | Replace one prototype clip end-to-end, then repeat |
| MIRA-06 | MIRA-00 compact/non-human body-family proof | 🌱 | XL | Foundation | Separate rig and clips behind the same gameplay presentation requests |
| MIRA-07 | Material and emissive team accents | ⭐ | M | Identity | Friendly blue, ally green, enemy red without destroying authored materials |
| MIRA-08 | Modular or detachable MIRA parts | 🌱 | XL | Future | First decide cosmetic modularity versus gameplay-bearing components |
| MIRA-09 | Human/MIRA mechanical asymmetry | 🌱 / 🔬 | L | Identity | Specify one meaningful difference players can understand and exploit |
| MIRA-10 | Component damage | 🧊 / 🔬 | XL | Future | Depends on body parts, damage language, AI valuation, animation, UI, and repair |

## 🔫 Combat and equipment

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| COM-01 | Data-driven weapon profiles | ⭐ | M | Foundation | Separate rules and presentation for one rifle and one contrasting weapon |
| COM-02 | Weapon archetypes and differentiation | ⭐ | L | Production | Choose a small representative set; named guns are usually skins/content |
| COM-03 | Reliable → Risky → Impossible accuracy language | ⭐ | L | Identity | Prototype readable bands driven by range, cover, stance, and weapon profile |
| COM-04 | Nonlinear disadvantage penalties | 🧪 | M | Experiment | Simulate edge cases and compare player comprehension |
| COM-05 | Miss-streak protection | 🧪 | M | Experiment | Keep deterministic replay and surface whether correction occurred |
| COM-06 | Aim action | ⭐ / 🧪 | M | Experiment | Spend AP for a clear, bounded accuracy benefit |
| COM-07 | Active Take Cover / Crouch | 🧪 | L | Experiment | Must have a distinct choice and readable state, not duplicate passive cover |
| COM-08 | Equipment-dependent actions | ⭐ | L | Foundation | Action availability comes from equipped data rather than unit-specific branches |
| COM-09 | Shields and defensive equipment | 🌱 | L | Production | One shield-bearing loadout as the first defensive equipment proof |
| COM-10 | Suppression | 🌱 | L | Identity | Define effect, counterplay, AI value, and feedback before implementation |
| COM-11 | EMP, disruption, and offline states | 🌱 | L | Identity | Strong MIRA-flavored status family; begin with one temporary disruption |
| COM-12 | Hacking specific systems | 🌱 | XL | Future | Needs hackable targets, information, counterplay, objectives, and AI |
| COM-13 | Overwatch, perhaps equipment/training-gated | 🌱 | L | Production | Reaction timing, interrupts, replay ordering, UI preview, and AI safety |
| COM-14 | Assisted/coordinated actions | 🌱 | XL | Identity | Specify one two-unit action before generalizing |
| COM-15 | Armor versus mobility | 🌱 | L | Production | Equipment trade-off through existing movement and damage systems |
| COM-16 | Facing and stance mechanics | 🌱 / 🔬 | XL | Future | Adopt only if decisions justify the UI and AI complexity |
| COM-17 | Close-range deterrence / future melee | 🌱 | L | Experiment | Test whether it prevents unhealthy clustering before building broad melee |

## 🧠 Tactical simulation and AI

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| AI-01 | Side/faction-agnostic tactical simulation | ⭐ | L | Foundation | Any controller can operate any faction under explicit relationships |
| AI-02 | Controller separate from faction | ⭐ | M | Foundation | Player, AI, replay, and debug control become policies rather than faction assumptions |
| AI-03 | Explicit ally/hostile/neutral relationships | 🌱 | M | Foundation | Replace implicit team pairings only when scenarios require it |
| AI-04 | Reusable objective semantics | ⭐ | M | Foundation | Actions query objective meaning without mission-specific tangles |
| AI-05 | Shared tactical reasoning | ⭐ | L | Foundation | Common evaluation; role/doctrine/controller changes priorities |
| AI-06 | Tactical roles | ⭐ | L | Identity | Start with carrier, escort, assault, support, and one ranged role |
| AI-07 | Squad coordination | ⭐ | XL | Identity | Share targets, destinations, intent, and limited plans without a god controller |
| AI-08 | Spatial and threat scoring | ⭐ | L | Foundation | Preserve decomposed, inspectable score components |
| AI-09 | Path and destination reservations | ⭐ | M | Foundation | Extend P1 reservations to narrow routes and coordinated plans |
| AI-10 | Deadlock and stagnation protection | ⭐ | M | Production | Detect repeated low-value states and relax constraints deliberately |
| AI-11 | Explainable decisions and debugging | ⭐ | M | Production | Candidate actions, score parts, selected action, rejected reasons, remembered state |
| AI-12 | Commander doctrines | ⭐ | XL | Identity | A small set of priority profiles over shared reasoning |
| AI-13 | Difficulty through believable mistakes | ⭐ | L | Identity | Controlled information/choice quality rather than raw stat cheating |
| AI-14 | AI-vs-AI support | ⭐ | M | Tooling | Maintain P1 simulation as balance, regression, and spectacle infrastructure |
| AI-15 | Rescue attacker restraint/focus limits | 🔬 | M | Experiment | Improve escort competence first; then test believable target distribution |

## 🌎 Reconnaissance and campaign

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| CAM-01 | Real-time exploration | ⭐ but 🧊 | XL | Future | Separate prototype after tactical/content foundation unless MvT proves it necessary |
| CAM-02 | Real-time → turn-based contact transition | ⭐ but 🧊 | XL | Future | Depends on CAM-01 and encounter boundaries |
| CAM-03 | Reconnaissance-driven mission discovery | ⭐ but 🧊 | XL | Future | Prototype as a paper/data loop before world exploration |
| CAM-04 | Information as progression | ⭐ | L | Identity | Define what information changes decisions and how it persists |
| CAM-05 | Rumor → Scout → Discover → Extract → Operation | ⭐ | XL | Future | Strong campaign loop; preserve as a later prototype thesis |
| CAM-06 | Riskier recon reveals deeper information | 🌱 | L | Future | Depends on CAM-03/04 |
| CAM-07 | Autonomous scout expeditions and logs | 🌱 | L | Future | Begin as a deterministic event simulation |
| CAM-08 | Campaign fog and uncertainty | 🌱 | XL | Future | Needs information provenance and UI |
| CAM-09 | Persistent sector consequences | 🧊 | XL | Future | Requires stable campaign state and content volume |

## 💙 MIRA life and campaign memory

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| LIFE-01 | Ambient MIRA life | 🌱 ❤️ | XL | Identity | One small post-mission vignette before simulating a living base |
| LIFE-02 | Mission photographs | 🌱 | M | Identity | Shared with PRE-07; first contained emotional-memory feature |
| LIFE-03 | Base photo mural | 🌱 | M | Future | Display persisted LIFE-02 artifacts |
| LIFE-04 | Personal/dorm photographs | 🌱 | L | Future | Requires persistent units and spaces |
| LIFE-05 | Memorial photographs | 🌱 | L | Future | Requires persistent loss and careful tone |
| LIFE-06 | MIRAs observing/interacting with photos | 🌱 | L | Future | Small authored reactions before systemic behavior |
| LIFE-07 | Backup continuity and external memories | 🔬 | XL | Future | Narrative/design research before mechanics |

## 🛠️ Tools and human-friendly production

| ID | Idea | Status | Effort | Lane | First proof / dependency |
|---|---|---:|:---:|---|---|
| TOOL-01 | Tactical overlays | ⭐ | M | Production | Keep P1 visualizer configuration centralized |
| TOOL-02 | AI score and decision visualization | ⭐ | M | Production | Extend the current heatmap and compact explanation panel |
| TOOL-03 | Heatmaps | 🧰 | S–M | Tooling | Cache/publish at decision time; never stall action presentation |
| TOOL-04 | Cover, traversal, terrain, and boundary visualization | 🧰 | M | Tooling | Read authoritative map data rather than duplicate geometry rules |
| TOOL-05 | Map and reachability validation | ⭐ | M | Foundation | Validate modules, connectors, objectives, spawns, and tactical routes |
| TOOL-06 | Content validation | ⭐ | M | Production | Character profiles, weapons, clips, sockets, missions, and attribution |
| TOOL-07 | Performance budgets and repeatable captures | 🌱 | M | Production | CPU/GPU frame time, draw calls, memory, setup, and AI latency scenarios |
| TOOL-08 | P2 → Miku-vs-Teto content boundary/export | ⭐ | L | Production | Prove game-specific content can live outside core systems |

## 🌐 External resources, plugins, and references

Use external work when it saves boring labor. Build our own when behavior is
part of FuseFire's identity. Every candidate needs a concrete benefit and an
exit strategy.

| ID | Resource / area | Status | License | Risk | Proposed use |
|---|---|---:|---|---|---|
| EXT-01 | [Prototype Texture](https://godotengine.org/asset-library/asset/5503) ([source](https://github.com/xAnTuA/Prototype-Texture)) | 🧪 | MIT | Low, but new/lightly proven | Graybox MAP-02 modules with scale-independent triplanar materials; grid remains authoritative for distance |
| EXT-02 | Godot editor gizmos and inspector helpers | 🔬 | TBD | Low–M | Study before building MAP-03 tooling |
| EXT-03 | Blender rigging/retargeting helpers | 🔬 | TBD | M | Reduce repetitive MIRA import labor without surrendering the skeleton contract |
| EXT-04 | Generic camera/cutaway references | 🔬 | TBD | M | Study approaches for PRE-01/02; avoid replacing working P1 camera ownership blindly |
| EXT-05 | UI themes and generic audio/VFX utilities | 🔬 | TBD | Low–M | Accelerate polish when removal and attribution remain simple |

For every candidate, record:

- exact version, source, author, and license;
- Godot/Blender compatibility and maintenance activity;
- what problem it solves better than a small local implementation;
- runtime/editor coupling and effect on exported builds;
- local modifications and attribution requirements;
- how to remove or replace it;
- whether we adopt it, adapt it, or only study it.

## 🗿 Developer archaeology

| ID | Relic | Status | Rule |
|---|---|---:|---|
| RELIC-01 | THE_BEAN | 🫘 sacred | Preserve as debug model, cheat, museum piece, or inexplicable secret |
| RELIC-02 | SUPER_HOT_TEST_MIRA | 🧊 fossil | Preserve intentionally; never confuse it with production content |
| RELIC-03 | AK47_KNIFE — the Brazilian meme | 🔪 eternal | Containment protocol pending |
| RELIC-04 | Historical bugs/assets as cheats | 🌱 | Curate only memorable examples; do not preserve broken production paths |
| RELIC-05 | `PIXI_WAS_HERE.txt` | 🔥 artifact | Architectural warning, rectangle testimony, and chicken directive |

## 🔫 Content pool — ingredients, not scope

The giant weapon list is a candidate pool. Prototype 2 should select a few
archetype representatives—possibly HS2000, P90, Type 64, and other favorites—then
treat most real-world variations as skins, manufacturer identity, balance data,
or future content. Every additional weapon creates modeling, animation, socket,
VFX, audio, UI, balance, AI, and testing work.

## 🚦Provisional dependency trail

```text
MIRA-0 rig + character profile
        ↓
animation / sockets / materials
        ↓
data-driven equipment and weapon archetypes
        ↓
accuracy and equipment actions
        ↓
side-independent controllers + shared reasoning
        ↓
roles / coordination / doctrines

shared map representation
        ↓
modular environment experiment
        ↓
internal Map Maker + simple assembler
        ↓
richer terrain + obstruction/cutaway
        ↓
content production for Miku vs. Teto
```

## 🧪 Candidate first experiments

| Order | Experiment | Question answered | Stop condition |
|:---:|---|---|---|
| 1 | MIRA-0 import and one replacement animation | Can a real FuseFire character use a human-editable profile and clip workflow? | One clean model/clip round-trip works without shared-script edits |
| 2 | Prototype Texture + crude modular kit | Can authored and procedural maps share useful building blocks? | Two tiny maps expose enough evidence to adopt, revise, or reject the representation |
| 3 | Two contrasting weapon profiles | Can content data create tactically distinct behavior and presentation? | Players can explain the difference without reading raw stats |
| 4 | Reliable/Risky/Impossible accuracy | Is FuseFire's accuracy language readable and strategically useful? | Forecast, result, AI, and replay agree deterministically |
| 5 | One obstruction/cutaway case | Can denser environments remain legible at tactical and action-camera angles? | The unit and legal space remain visible without camera nausea |
| 6 | Two tactical roles sharing one evaluator | Can role identity emerge without duplicating AI? | Roles choose measurably different, explainable actions in the same state |
| 7 | External content boundary | Can Miku vs. Teto become mostly a content project? | A sample external pack supplies a character, weapon, map, and mission without core edits |

## 🎯 Questions that must be answered before a roadmap

1. Which transformations make P2 recognizably FuseFire rather than P1 with more features?
2. What exact capabilities must exist before Miku vs. Teto can enter its own repository?
3. Which features require player-facing content volume that we cannot yet afford?
4. Which experiments can fail cheaply without leaving permanent architecture?
5. Which P1 invariants—determinism, replay, pause, map validation, readable AP,
   explainable AI—must every experiment preserve?
6. What is the smallest complete P2 vertical slice that combines a proper MIRA,
   distinct equipment, a reusable environment, objective-aware AI, and finished feedback?

## 📦 Promotion rules

An idea moves from vault to roadmap only when it has:

- a player or production problem it solves;
- an owner and dependency position;
- a smallest useful implementation;
- an acceptance criterion and regression strategy;
- a stated content burden;
- a deferral/removal path if the experiment fails.

Ideas are allowed to merge, shrink, wait, or die. Expensive enthusiasm is not a
dependency. Miku vs. Teto is the consumer of the P2 foundation, not an excuse to
put every future FuseFire system into P2.

---

*The Beans served with honor. The MIRAs are coming.* 🔥🤖🫘
