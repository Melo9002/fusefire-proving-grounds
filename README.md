# FuseFire

A Godot 4.7.2 tactical combat prototype.

## Play

Open `project.godot` and press **F5**. Match Setup offers **Service Depot**, the current Generation 2.0 example.

- The seed chooses between two authored site layouts, compatible loading parcels and movable objects.
- **Vary cars / containers** controls movable tactical population. Off keeps the site and buildings.
- Disable **Automatic New Seed** and enter **16** or **17** to reproduce either site.
- Move and Attack select an action; click a destination or enemy to commit. End Turn lets the AI act.
- WASD pans; wheel zooms; middle drag orbits; right drag pans. F/Home focuses selection. Esc pauses.
- Replay Battle and Save Replay are available after a battle. Replays store actual content choices.

## Understand or edit

Start with [Generation 2.0](docs/generation-2.md): what is authored, what varies, and how to test it.
[Architecture](docs/architecture.md) is the short code map. [Other documentation](docs/index.md) covers replay, simulation and animation.

The Parcel Editor edits individual areas. Its Preview is a possible seeded result; saving a draft does not automatically replace battle content. The current limitations are listed in the generation guide.

## Verify

Run from this folder with `godot_console` on PATH:

```powershell
.\tools\run_tests.ps1 smoke
.\tools\run_tests.ps1 subsystem -Subsystem generation
.\tools\run_tests.ps1 full
```

[Project Ironclad](docs/quality/project-ironclad.md) explains results and focused checks. Passing headless tests does not establish visual quality.

Historical maps, experiments, research and superseded documents are outside the project in a recoverable local quarantine. The generation guide records the location. Imported asset packs and calibration remain intact.
