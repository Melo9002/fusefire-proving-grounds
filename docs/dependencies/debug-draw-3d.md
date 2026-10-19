# Debug Draw 3D integration

FuseFire vendors [Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d) **1.7.3** under `addons/debug_draw_3d`. The add-on is Copyright © 2026 Dmitriy Salnikov and distributed under the MIT license retained beside the binaries in `addons/debug_draw_3d/LICENSE`.

The release descriptor declares Godot 4.4.1 as its minimum. FuseFire validates it with the project's pinned Godot 4.7.2 Windows build. The complete upstream release directory is retained so future platform exports can use the matching release binaries without mixing versions.

Reference SHA-256 values for the reviewed package are:

- `debug_draw_3d.gdextension`: `AC6C34739459E6246A4309A8696E55A933BB96FCB686DA06AC1AE8A435A58F7E`
- `libdd3d.windows.editor.x86_64.dll`: `AACD20D93F0D186993D831AE10DF5C2FAD61BCEFC498C21FADEC47BC867B38E6`
- `LICENSE`: `45E0855DEA5B6ECB5F836809A3969F3E2B0FC78A9CD9B68F9A36B7AE799EB3A1`

## Project boundary

Project code uses `FuseFireDebugDraw3D`, never the vendor singleton directly. The wrapper reports availability and owns the small set of supported drawing calls. This keeps diagnostics removable and prevents visual debug state from becoming tactical authority.

The Map Editor is the first consumer. Select a module and enable **Spatial contracts** or press `D`:

- green boxes: authored tactical footprint;
- amber boxes: required functional clearance;
- magenta box: calibrated visual envelope;
- cyan arrows: rotated semantic connection sockets.

The overlay is regenerated each frame while enabled. Turning it off calls the add-on's explicit clear operation. Release binaries supplied by the add-on disable drawing by default; FuseFire does not use the forced-debug release feature.

The upstream editor-enabled library offers optional anonymous editor-usage telemetry. It does not run in exported game libraries. Developers who prefer to disable it can set **Editor Settings → Debug Draw 3D → Settings → Telemetry State** to disabled; this is a per-user Godot editor preference and is intentionally not stored in the project.

## Verification and updates

`tests/debug_draw_3d_integration_test.gd` verifies the pinned record, descriptor, native singleton, wrapper calls, explicit clearing, and Map Editor contract extraction. It is part of the Ironclad smoke tier, so GitHub's clean Windows checkout must load the vendored DLL before the rest of the suite can pass. `tests/debug_draw_3d_capture.gd` is the explicit GPU workflow for visual inspection.

To update the dependency, replace the entire add-on directory with one reviewed upstream release, retain its license, update the wrapper version and hashes, run the smoke tier, and capture the Map Editor overlay. Do not combine descriptors and binaries from different releases.

To remove it, delete the Map Editor toggle and calls, remove the project wrapper and focused tests, then delete `addons/debug_draw_3d`. Tactical modules, generation, calibration, and `MapData` require no migration.
