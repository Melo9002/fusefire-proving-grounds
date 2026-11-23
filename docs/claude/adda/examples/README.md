# Example ADDA reports

Real output of `tools/adda.ps1 run` and `compare` on the rescue and carry scenario, kept so the format can be read without running anything. They were produced at revision `d71b139` with a few uncommitted documentation edits (the report says `dirty`), at a fixed 60 fps, so the numbers are from that code, not necessarily the current one. Regenerate them with the `config.cli` command in each report.

| File | What it is |
|---|---|
| `mira-rescue.report.json` | MIRA, armed, scenario `rescue` (7 findings: out-of-reach hand contacts at full claim weight, pose snaps at the lift) |
| `small-mira-rescue.report.json` | Small MIRA, armed, the same scenario |
| `rescue-mira-vs-small-mira.comparison.json` | `compare` of the two: lengths per body ratio, which findings persist or resolve |

Read order: `summary.headline`, `findings[0]`, `config`, then `samples.rows` around `worst_frames`. See [../07-usage.md](../07-usage.md).
