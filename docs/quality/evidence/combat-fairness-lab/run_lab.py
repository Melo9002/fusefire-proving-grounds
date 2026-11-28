"""Run matched combat-policy comparisons on an explicit Windows Godot checkout."""
from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time

SCRIPT = 'res://docs/quality/evidence/combat-fairness-lab/tournament.gd'
MODES = range(4)

def file_hash(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()

def cases(batch):
    depot = 'service_depot_contextual_showcase_v1'
    freight = 'freight_yard_contextual_v1'
    if batch == 'pilot':
        designs = [(depot, 16, 2, 'cc', False, 0, 0), (depot, 16, 2, 'cc', False, 0, 1)]
    elif batch == 'main':
        designs = [(site, seed, size, coord, False, 0, 0)
                   for site, size, seeds in [(depot, 2, [16,17,18]), (freight, 2, [16,17]), ('fleet_station', 2, [16]), ('parking_garage', 2, [16]), (freight, 3, [18])]
                   for seed in seeds for coord in ['cc','ii','ic','ci']]
    elif batch == 'mirrored':
        designs = [('contextual_firing_bay', seed, 1, 'cc', True, 0, 0) for seed in [1,2,3,4]]
    else:
        designs = [(site, 16, 2, 'cc', steps, guard, 0)
                   for site in [depot, freight] for steps in [False, True] for guard in [0, 15]]
    for site, seed, size, coord, steps, guard, repeat in designs:
        for mode in MODES:
            if batch == 'pilot' and repeat == 1 and mode != 0:
                continue
            yield {
                'case_id': f'{site}-{seed}-{size}v{size}-{coord}-m{mode}-step{int(steps)}-g{guard}-r{repeat}',
                'battlefield_id': site, 'seed': seed, 'player_count': size, 'enemy_count': size,
                'coordination': coord, 'engagement_policy': mode, 'contextual_firing_disabled': not steps,
                'guard_minimum_chance': guard, 'maximum_rounds': 8, 'repeat': repeat,
            }

def main():
    parser = ArgumentParser()
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--batch', choices=['pilot','main','factorial','mirrored'], required=True)
    parser.add_argument('--workers', type=int, default=3)
    args = parser.parse_args()
    project, godot, out = (path.resolve() for path in (args.project, args.godot, args.out))
    if not (project / 'project.godot').is_file() or not godot.is_file():
        parser.error('Expected an explicit project directory and Godot executable')
    out.mkdir(parents=True, exist_ok=False)

    def git(*params):
        return subprocess.check_output(['git', '-C', str(project), *params])

    status = git('status','--porcelain=v1','-uall').decode('utf8',errors='replace')
    tracked_delta = git('diff','--binary','HEAD')
    source_files = [
        'systems/battle_controller.gd', 'systems/simulation/ai_match_simulator.gd',
        'systems/combat_rules.gd', 'docs/quality/evidence/combat-fairness-lab/tournament.gd',
        'docs/quality/evidence/combat-fairness-lab/run_lab.py',
    ]
    provenance = {
        'id': out.name, 'batch': args.batch, 'project': str(project), 'commit': git('rev-parse','HEAD').decode().strip(),
        'status': status.splitlines(), 'tracked_delta_sha256': hashlib.sha256(tracked_delta).hexdigest(),
        'selected_source_sha256': {name: file_hash(project / name) for name in source_files},
        'executable': str(godot), 'executable_sha256': file_hash(godot),
        'godot_version': subprocess.check_output([str(godot),'--version'],text=True).strip(),
        'host': platform.platform(), 'processor': platform.processor(), 'logical_cpus': os.cpu_count(),
        'fixed_fps': 60, 'workers': args.workers, 'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
    }
    (out/'provenance.json').write_text(json.dumps(provenance,indent=2),encoding='utf8')
    rows = list(cases(args.batch))

    def run(case):
        folder = out / case['case_id']
        folder.mkdir()
        profile = folder / 'profile'
        profile.mkdir()
        record = case | {'replay': str(folder / 'replay.json')}
        manifest = folder / 'manifest.json'
        receipt = folder / 'receipt.jsonl'
        command = [str(godot), '--headless', '--path', str(project), '--fixed-fps', '60',
                   '--script', SCRIPT, '--', str(manifest), str(receipt), 'profile-ai']
        trace = provenance | {'execution_id': case['case_id'], 'command': command}
        manifest.write_text(json.dumps({'provenance': trace, 'cases':[record]},indent=2),encoding='utf8')
        env = os.environ.copy()
        env.update(APPDATA=str(profile),LOCALAPPDATA=str(profile))
        with (folder / 'godot.log').open('wb') as log:
            result = subprocess.run(command, cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=220)
        if result.returncode or not receipt.is_file() or not receipt.stat().st_size:
            return case['case_id'], False
        return case['case_id'], True

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        outcomes = list(pool.map(run,rows))
    (out/'batch-results.json').write_text(json.dumps(dict(outcomes),indent=2),encoding='utf8')
    print(f'{sum(ok for _,ok in outcomes)}/{len(outcomes)} cases wrote receipts')
    return int(not all(ok for _,ok in outcomes))

if __name__ == '__main__':
    raise SystemExit(main())
