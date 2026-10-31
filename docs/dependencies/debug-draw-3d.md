# Debug Draw 3D integration

FuseFire vendors [Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d) **1.7.3** under `addons/debug_draw_3d`. The add-on is Copyright © 2026 Dmitriy Salnikov and distributed under the MIT license retained beside the binaries in `addons/debug_draw_3d/LICENSE`.

The release descriptor declares Godot 4.4.1 as its minimum. FuseFire validates it with the project's pinned Godot 4.7.2 Windows build. The complete upstream release directory is retained so future platform exports can use the matching release binaries without mixing versions.

Reference SHA-256 values for the reviewed package are:

- `debug_draw_3d.gdextension`: `AC6C34739459E6246A4309A8696E55A933BB96FCB686DA06AC1AE8A435A58F7E`
- `libdd3d.windows.editor.x86_64.dll`: `AACD20D93F0D186993D831AE10DF5C2FAD61BCEFC498C21FADEC47BC867B38E6`
- `LICENSE`: `45E0855DEA5B6ECB5F836809A3969F3E2B0FC78A9CD9B68F9A36B7AE799EB3A1`

## Project boundary

Project code uses `FuseFireDebugDraw3D`, never the vendor singleton directly. The wrapper reports availability and owns the small set of supported drawing calls. This keeps diagnostics removable and prevents visual debug state from becoming tactical authority.

The former Map Editor overlays are preserved in the local quarantine. The vendored add-on and small wrapper remain available for diagnostics; they do not define tactical behavior.

The upstream editor-enabled library offers optional anonymous editor-usage telemetry. It does not run in exported game libraries. Developers who prefer to disable it can set **Editor Settings → Debug Draw 3D → Settings → Telemetry State** to disabled; this is a per-user Godot editor preference and is intentionally not stored in the project.

## Verification and updates

`tests/debug_draw_3d_integration_test.gd` verifies the pinned record, descriptor, native singleton, wrapper drawing calls and explicit clearing. It remains in the Ironclad smoke tier. The old Map Editor extraction checks and capture script are quarantined with that editor.

Update the entire add-on release together, retain its license, update the wrapper version and hashes, and run the smoke tier. Do not mix descriptors and binaries from different releases. Removal requires checking current wrapper consumers first; the retired Map Editor is no longer an active dependency.
