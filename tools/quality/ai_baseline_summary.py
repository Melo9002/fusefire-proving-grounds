#!/usr/bin/env python3
"""Summarize AI baseline JSON (tests/ai_baseline_report.gd) into a markdown report.

usage: ai_baseline_summary.py DIR [--log LOGFILE] [--out FILE.md]

Reads only; the metrics are derived from decision records, committed/rejected outcomes,
per-round samples and (optionally) [AIPlan] planning-time lines joined to the
[BaselineBegin] markers in the Godot log. "thinking" planning time is wall time minus
frame yields; it excludes animation, but the scored slice still includes any frame time
spent inside a single planning call.

Newer logs also contain [AIActivation] samples with per-submission planner work,
uninterrupted slices, waits, stage counters and authoritative action windows.
"""
import argparse, collections, json, math, re, statistics, sys
from pathlib import Path

PLAN = re.compile(r"\[AIPlan\] (\S+) candidates=(\d+) inventory_ms=([\d.]+) routes_ms=([\d.]+) scores_ms=([\d.]+)"
                  r"(?: safety_ms=([\d.]+) yields_ms=([\d.]+) wall_ms=([\d.]+))?")

def activation_profiles(log_paths):
    profiles = []
    for log in log_paths:
        label = ""
        for line in Path(log).read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("[BaselineBegin] "):
                label = line.removeprefix("[BaselineBegin] ")
            if line.startswith("[AIActivation] "):
                record = json.loads(line.removeprefix("[AIActivation] "))
                profiles.append({**record, "match": label})
    return profiles


def activation_lines(profiles):
    if not profiles:
        return []
    samples = [{**decision, "match": profile["match"], "actor": profile["actor"]}
               for profile in profiles for decision in profile["decisions"]]
    if not samples:
        return []

    def describe(values):
        values = sorted(values)
        p95 = values[math.ceil(len(values) * 0.95) - 1]
        p99 = f"{values[math.ceil(len(values) * 0.99) - 1] / 1000:.2f}" if len(values) >= 100 else "—"
        return f"{len(values)} | {statistics.mean(values) / 1000:.2f} | {statistics.median(values) / 1000:.2f} | {p95 / 1000:.2f} | {p99} | {max(values) / 1000:.2f}"

    rows = [
        ("Planner work", [s["work_us"] for s in samples]),
        ("Longest slice per decision", [s["max_slice_us"] for s in samples]),
        ("Decision wall time", [s["wall_us"] for s in samples]),
        ("Authoritative action window", [s["action_window_us"] for s in samples]),
        ("Commit observers", [s["observers_us"] for s in samples if "observers_us" in s]),
        ("Activation excluding action windows and pacing delays",
         [a["activation_us"] - a["action_windows_us"] - a["delay_us"] for a in profiles]),
    ]
    lines = ["", "## Activation profile", "", "| Interval (ms) | Samples | Mean | Median | P95 | P99 | Max |",
             "|---|---:|---:|---:|---:|---:|---:|"]
    lines += [f"| {label} | {describe(values)} |" for label, values in rows if values]
    lines += ["", f"- Planner frame yields: {sum(s['yields'] for s in samples)}",
              f"- Planner suspension: {sum(s['yield_us'] for s in samples) / 1000:.1f} ms total", "",
              "| Observed stage | Counter | Total ms |", "|---|---:|---:|"]
    times = collections.Counter()
    counts = collections.Counter()
    for sample in samples + [a["tail"] for a in profiles]:
        times.update(sample["stages_us"])
        counts.update(sample["counts"])
    for key, duration in times.most_common():
        lines.append(f"| {key} | {counts[key]} | {duration / 1000:.1f} |")
    lines += ["", "Worst recorded uninterrupted slices"]
    for sample in sorted(samples, key=lambda s: s["max_slice_us"], reverse=True)[:5]:
        lines.append(f"- {sample['match']} · {sample['actor']} · {sample.get('action', '?')} "
                     f"transaction {sample.get('transaction', '?')} · {sample['max_slice_us'] / 1000:.2f} ms")
    return lines


def planning_by_label(log_path):
    out, label = collections.defaultdict(list), None
    for line in Path(log_path).read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("[BaselineBegin] "):
            label = line.split(" ", 1)[1].strip()
        m = PLAN.search(line)
        if m and label:
            wall, yields = (float(m.group(8)), float(m.group(7))) if m.group(8) else (None, 0.0)
            routes = float(m.group(4))
            out[label].append({"actor": m.group(1), "candidates": int(m.group(2)),
                               "thinking_ms": (wall - yields) if wall is not None else None,
                               "routes_ms": routes, "scores_ms": float(m.group(5))})
    return out


def cell_of(record):
    for c in record.get("position_candidates", []) or []:
        if c.get("chosen"):
            return tuple(c["cell"])
    nums = re.findall(r"-?\d+", str(record.get("subject", "")))
    return tuple(int(n) for n in nums[:3]) if len(nums) >= 3 else None


def normalize(reason):
    return re.sub(r"\d+(\.\d+)?", "N", reason or "").strip()[:90]


def analyse(data, plans):
    decisions = data.get("decisions", [])
    counts = collections.Counter(r["action"] for r in decisions)
    moves = collections.defaultdict(list)
    for r in decisions:
        if r["action"] == "Move" and r.get("stage") == "selected":
            moves[r["actor"]].append((tuple(r["grid_position"]), cell_of(r)))
    returns = 0
    for seq in moves.values():
        for a, b in zip(seq, seq[1:]):
            if b[1] == a[0] and a[1] == b[0]:  # A->B immediately followed by B->A
                returns += 1
    waits = collections.Counter(normalize(r.get("reason")) for r in decisions if r["action"] == "Wait")
    samples = data.get("round_samples", [])
    stagnant = 0
    first_progress = None
    for prev, cur in zip(samples, samples[1:]):
        key = lambda s: (json.dumps(s["objectives"], sort_keys=True), json.dumps(s["hp"], sort_keys=True), json.dumps(s["alive"], sort_keys=True))
        if key(prev) == key(cur):
            stagnant += 1
    for s in samples:
        if any(o["progress"] > 0 or o["status"] != 0 for o in s["objectives"]):
            first_progress = s["round"]
            break
    thinking = [p["thinking_ms"] for p in plans if p["thinking_ms"] is not None]
    return {
        "label": data["label"], "site": data["site"], "mission": data["mission_title"],
        "status": data["status"], "result": data["battle_result"], "rounds": data["rounds"],
        "elapsed": None,
        "decisions": data["decision_count"], "committed": data["committed_action_count"],
        "rejected": data["rejected_action_count"], "moves": counts["Move"], "attacks": counts["Attack"],
        "waits": counts["Wait"], "guards": counts["Guard"], "aims": counts["Aim"], "reloads": counts["Reload"],
        "move_returns": returns, "stagnant_rounds": stagnant, "first_progress_round": first_progress,
        "final_objectives": samples[-1]["objectives"] if samples else [],
        "top_wait_reasons": waits.most_common(3), "plans": len(thinking),
        "think_total": sum(thinking), "think_max": max(thinking, default=0.0),
        "think_p95": statistics.quantiles(thinking, n=20)[-1] if len(thinking) >= 20 else max(thinking, default=0.0),
        "think_over_50": sum(1 for t in thinking if t > 50.0),
        "reason": data.get("reason", ""),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("directory")
    ap.add_argument("--log")
    ap.add_argument("--out")
    args = ap.parse_args()
    plans = planning_by_label(args.log) if args.log else {}
    rows = []
    for path in sorted(Path(args.directory).glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        row = analyse(data, plans.get(data["label"], []))
        # Elapsed seconds are in the Godot summary only; round samples carry the final value.
        samples = data.get("round_samples", [])
        row["elapsed"] = samples[-1]["elapsed"] if samples else None
        rows.append(row)
    lines = ["| Match | Status | Result | Rounds | Time s | Dec | Rej | Move | Atk | Wait | Guard | Aim | Returns | Stagnant rds | 1st progress rd | Plans | Think total ms | Think max ms | >50 ms |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append("| {label} | {status} | {result} | {rounds} | {elapsed:.1f} | {decisions} | {rejected} | {moves} | {attacks} | {waits} | {guards} | {aims} | {move_returns} | {stagnant_rounds} | {fp} | {plans} | {tt:.0f} | {tm:.0f} | {o50} |".format(
            fp=r["first_progress_round"] if r["first_progress_round"] is not None else "-", tt=r["think_total"], tm=r["think_max"],
            o50=r["think_over_50"], **{**r, "elapsed": r["elapsed"] or 0.0}))
    unfinished = [r for r in rows if r["status"] != "Completed"]
    lines += ["", f"Matches: {len(rows)}; completed {len(rows) - len(unfinished)}; unfinished {len(unfinished)}."]
    for r in unfinished:
        lines.append(f"- UNFINISHED {r['label']}: {r['status']} — {r['reason']}")
    lines += ["", "Top Wait reasons (normalized):"]
    agg = collections.Counter()
    for r in rows:
        for reason, n in r["top_wait_reasons"]:
            agg[reason] += n
    lines += [f"- {n}x {reason}" for reason, n in agg.most_common(8)]
    if args.log:
        lines.extend(activation_lines(activation_profiles([args.log])))
    text = "\n".join(lines)
    print(text)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")
    Path(args.directory, "summary.json").write_text(json.dumps(rows, indent=1, default=str), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
