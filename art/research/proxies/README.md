# FuseFire original proxy kit

These deliberately simple, untextured assets are original FuseFire research
tools. They can be committed, fetched at work, edited, packaged in development
builds, and replaced freely. They contain no extracted XCOM geometry, animation,
texture, audio, or code.

## Included assets

- `models/fusefire_animation_proxy.glb` — a 1.60 m block mannequin with the core
  Mixamo-style bone names currently used by MIRA-0.
- `models/fusefire_rifle_proxy.glb` — a block rifle with `WeaponOrigin`,
  `GripReference`, `SupportHandTarget`, `MuzzleSocket`, `SightReference`, and
  `ButtstockContact` nodes.
- `source/fusefire_proxy_kit.blend` — editable source containing both assets.
- `source/build_proxy_kit.py` — deterministic Blender generator.
- `source/PROXY_KIT_REPORT.json` — dimensions, bones, contacts, and output paths.

The source folder contains `.gdignore` so Godot does not try to import the
editable `.blend`; the generated GLBs remain available under `models/`.

## Regenerate

From the repository root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' `
  --background --factory-startup `
  --python art/research/proxies/source/build_proxy_kit.py
```

Blender rewrites the `.blend`, both `.glb` files, and the JSON report. Review all
generated changes before committing.

Validate the generated Godot contract with:

```powershell
godot_console --headless --path . -s tests/proxy_kit_test.gd
```

## Human editing

Open `source/fusefire_proxy_kit.blend` in Blender. Everything uses metres and
plain names. The mannequin stands 1.60 m tall. The rifle points along Blender
`-Y`, which imports as Godot `+Z` in the current workflow.

Edit body blocks to explore proportions or modular boundaries. Keep bone names
stable when testing the current MIRA-0 animation path. Edit rifle contact empties
to describe how a weapon should sit:

- `GripReference` — dominant hand origin;
- `SupportHandTarget` — off-hand contact;
- `MuzzleSocket` — projectile and muzzle-effect origin;
- `SightReference` — aiming reference;
- `ButtstockContact` — shoulder contact.

The proxy is a functional measuring tool, not FuseFire art direction. Replace a
block when its production requirement becomes clear; do not polish it merely
because it exists.

## Animation policy

Original FuseFire animation tests may be added to this kit and committed.
Borrowed XCOM animations remain under ignored `research/xcom-local/`; only their
names, roles, retargeting notes, and replacement tasks belong in Git. The
procedural FuseFire clips remain the work-safe and release-safe fallback.
