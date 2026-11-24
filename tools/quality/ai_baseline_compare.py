#!/usr/bin/env python3
"""Compares two AI baseline runs match by match (milestone 05).

    python tools/quality/ai_baseline_compare.py artifacts/ai-baseline/<before> artifacts/ai-baseline/<after>

Both directories hold the per-match JSON written by tests/ai_baseline_report.gd. A match is IDENTICAL when its result, round count and
final state signature agree AND its decision sequence (actor, action, subject) is the same; otherwise the first decision that differs is
printed with its neighbours, so a behavioural change can be traced to the exact choice that caused it. Decisions are compared, not wall
times: planning time is machine noise and is reported only as a total.
"""
import glob
import json
import os
import sys


def load(directory):
    runs = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        runs[data.get("label", os.path.basename(path))] = data
    return runs


def sequence(run):
    return [(d.get("actor"), d.get("action"), d.get("subject")) for d in run.get("decisions", [])]


def describe(run):
    return "%s r%d %s/%s" % (run.get("status"), run.get("rounds", 0), run.get("battle_result"), run.get("reason") or "-")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    before, after = load(sys.argv[1]), load(sys.argv[2])
    labels = sorted(set(before) | set(after))
    identical = 0
    changed = []
    for label in labels:
        if label not in before or label not in after:
            changed.append((label, "present in only one run"))
            continue
        a, b = before[label], after[label]
        sa, sb = sequence(a), sequence(b)
        same = sa == sb and a.get("battle_result") == b.get("battle_result") and a.get("rounds") == b.get("rounds") and a.get("final_state") == b.get("final_state")
        if same:
            identical += 1
            continue
        first = next((i for i, (x, y) in enumerate(zip(sa, sb)) if x != y), min(len(sa), len(sb)))
        changed.append((label, "%s -> %s; decisions %d -> %d; first differs at decision %d: %s vs %s" % (
            describe(a), describe(b), len(sa), len(sb), first + 1,
            sa[first] if first < len(sa) else "(none)", sb[first] if first < len(sb) else "(none)")))
    print("%d match(es) compared: %d identical, %d changed" % (len(labels), identical, len(changed)))
    for label, text in changed:
        print("  CHANGED %s: %s" % (label, text))
    for name, runs in (("before", before), ("after", after)):
        results = {}
        for run in runs.values():
            key = "%s/%s" % (run.get("status"), run.get("battle_result"))
            results[key] = results.get(key, 0) + 1
        print("  %s: %s; %d decisions, %d rejected actions" % (
            name, ", ".join("%s %d" % (k, v) for k, v in sorted(results.items())),
            sum(run.get("decision_count", 0) for run in runs.values()), sum(run.get("rejected_action_count", 0) for run in runs.values())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
