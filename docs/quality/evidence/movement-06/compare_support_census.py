"""Summarize normalized standing points and directed edges from two census logs."""

import argparse
import json
from pathlib import Path


def read_cases(path):
    rows = (
        json.loads(line.split("[SurfaceCensus]", 1)[1])
        for line in path.read_text(encoding="utf-8-sig").splitlines()
        if "[SurfaceCensus]" in line
    )
    return {row["case"]: row for row in rows}


def compare(before, after):
    a, b = before["points"], after["points"]
    edges_a, edges_b = set(before["edges"]), set(after["edges"])
    return {
        "case": before["case"],
        **{field: [before[field], after[field]] for field in (
            "compiler", "logical", "stops", "transit", "signature", "geometry_key",
            "compile_us", "graph_us", "inventory_us", "route_us", "options",
        )},
        "recovered": {key: b[key] for key in sorted(b.keys() - a.keys())},
        "lost": {key: a[key] for key in sorted(a.keys() - b.keys())},
        "shifted": {key: [a[key], b[key]] for key in sorted(a.keys() & b.keys()) if a[key] != b[key]},
        "edges_added": sorted(edges_b - edges_a),
        "edges_removed": sorted(edges_a - edges_b),
        "unsupported_or_colliding_stops": [before["invalid"], after["invalid"]],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("corrected", type=Path)
    args = parser.parse_args()
    baseline, corrected = read_cases(args.baseline), read_cases(args.corrected)
    if not baseline or baseline.keys() != corrected.keys():
        parser.error("The logs must record the same nonempty case set")
    if any(case["errors"] for case in [*baseline.values(), *corrected.values()]):
        parser.error("A map failed to compile")
    print(json.dumps([compare(baseline[key], corrected[key]) for key in baseline], indent=2))


if __name__ == "__main__":
    main()
