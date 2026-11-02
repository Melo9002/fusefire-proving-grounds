# FuseFire documentation

## Start here

- [Human editing guide](human-editing-guide.md): assets, units, animation and focused checks.
- [Architecture](architecture.md) and [code organization](code-organization.md): current ownership and entry points.
- [Current map architecture](generation/current-map-architecture.md): active identities, ownership and authoring boundary.
- [Generation status](generation/status.md): supported maps and local quarantine recovery.
- [Map direction and XCOM SDK study](generation/xcom-map-study-and-requirements.md): evidence behind the bounded parcel direction.
- [Project Ironclad](quality/project-ironclad.md): test commands and failure investigation.

## Gameplay and engineering

- [Simulation and reproducibility](simulation.md)
- [Battle replay](replay.md)
- [AI documentation](ai/README.md)
- [Tactical Tempo contracts](architecture/tactical-tempo-freeze.md)
- [Tactical conditions reference](architecture/tactical-conditions-fictional-systems-reference.md)
- [Debug map inspection](debug-map-inspection.md)
- [Industrial Warehouse](generation/industrial-warehouse-vertical-slice.md)

## Assets and animation

- [Asset import](asset-import.md)
- [Animation editing](animation-editing-guide.md)
- [Industrial asset inventory](generation/industrial-asset-inventory.md)
- [Asset calibration laboratory](generation/asset-calibration-laboratory.md)
- [Semantic asset metadata](generation/semantic-asset-catalog.md)
- [Debug Draw dependency](dependencies/debug-draw-3d.md)

## Ideas and research — not an implementation queue

- [Idea vault](prototype-2/idea-vault.md) and [pre-production workshop](prototype-2/preproduction-plan.md)
- [Experiment notebook](prototype-2/experiments/README.md)
- [Operation XCOM research](prototype-2/operation-xcom/research-ledger.md)
- [External resources](prototype-2/external-resources.md) and [animation sources](prototype-2/animation-source-survey.md)
- [Prototype 1 release reference](prototype-1-release.md)

Superseded generator reports, completed migration audits and the retired character roadmap are preserved outside the project in the [local quarantine](generation/status.md). They are historical evidence, not current editing instructions. The chunk authoring tool remains recoverable there.

Commands assume the repository root. Do not edit generated `.godot/` files; edit sources and let Godot rebuild its cache.
