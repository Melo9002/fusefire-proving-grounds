"""Run a single comparison probe and attach exact execution provenance."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

if len(sys.argv) < 5:
    raise SystemExit('Usage: run_probe.py PROJECT GODOT OUTPUT SCRIPT [GODOT USER ARGS]')
project, godot, output = (Path(arg).resolve() for arg in sys.argv[1:4])
script, *args = sys.argv[4:]
rendered = "--play" in args
args = [arg for arg in args if arg != "--play"]
output.mkdir(parents=True, exist_ok=False)
profile = output / 'profile'
profile.mkdir()
def git(*args):
    return subprocess.check_output(['git','-C',str(project),*args])
display = [] if rendered else ['--headless','--fixed-fps','60']
cmd = [str(godot),'--path',str(project),*display,'--script',script,'--',*args]
provenance = {
    'id': output.name, 'project': str(project), 'commit': git('rev-parse','HEAD').decode().strip(),
    'status': git('status','--porcelain=v1','-uall').decode('utf8',errors='replace').splitlines(),
    'tracked_delta_sha256': hashlib.sha256(git('diff','--binary','HEAD')).hexdigest(),
    'execution_script_sha256': hashlib.sha256((project/script.removeprefix('res://')).read_bytes()).hexdigest(),
    'command': cmd, 'profile': str(profile),
    'godot_version': subprocess.check_output([str(godot),'--version'],text=True).strip(),
    'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
}
(output/'provenance.json').write_text(json.dumps(provenance,indent=2),encoding='utf8')
build = provenance['commit'][:7] + (' + local edits' if provenance['status'] else '')
env = os.environ | {'APPDATA':str(profile),'LOCALAPPDATA':str(profile),'FUSEFIRE_LAB_BUILD':build}
with (output/'godot.log').open('wb') as log:
    run = subprocess.run(cmd,cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=None if rendered else 120)
print(f'{output}: exit {run.returncode}')
raise SystemExit(run.returncode)
