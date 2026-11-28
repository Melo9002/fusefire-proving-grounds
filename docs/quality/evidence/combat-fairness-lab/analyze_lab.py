"""Summarize the laboratory's authoritative receipts, with blocked paired uncertainty."""
from collections import Counter, defaultdict
from pathlib import Path
from random import Random
from statistics import mean, median, quantiles
import hashlib
import json
import sys

def read_cases(folder):
    for receipt in sorted(folder.glob('*/receipt.jsonl')):
        text = receipt.read_text(encoding='utf8').strip()
        if not text:
            continue
        data = json.loads(text)
        parent = receipt.parent
        replay = parent/'replay.json'
        recorded = json.loads(replay.read_text(encoding='utf8')) if replay.exists() else {}
        full_actions = recorded.get('ordered_records', recorded.get('actions', []))
        actions = data['configuration'].get('combat_transactions', [])
        actual_rounds = [int(r['expected_state'].split('|',1)[0].split('=',1)[1]) for r in full_actions]
        if len(actual_rounds) != len(actions):
            raise ValueError(f'Replay and diagnostic transaction counts differ at {parent}')
        attacks = [row for row in actions if row['kind']=='attack']
        gs = [g for row in actions for g in row['resolved'].get('reaction_events',[])]
        kinds = Counter(row['kind'] for row in actions)
        attack_ap = sum(x['resolved']['actor_ap_before']-x['resolved']['actor_ap_after'] for x in attacks)
        targets = defaultdict(set)
        damaged_rounds = set()
        first_attack_record = None
        action_count = 0
        kills = 0
        side_damage = Counter()
        for row, round_no in zip(actions, actual_rounds):
            action_count += 1
            if row['kind'] == 'attack':
                if first_attack_record is None: first_attack_record = action_count
                side = row['actor'].split('Unit')[0]
                targets[round_no,side,row['target']].add(row['actor'])
                kills += int(row['resolved']['target_defeated'])
                damage = row['resolved']['damage']
                if damage: damaged_rounds.add(round_no)
                side_damage[side] += damage
            for reaction in row['resolved'].get('reaction_events', []):
                if reaction['damage']: damaged_rounds.add(round_no)
                kills += int(reaction['target_defeated'])
                side_damage[reaction['watcher_id'].split('Unit')[0]] += reaction['damage']
        # Each counted round ended before the recorded final round, except
        # the terminal round of a completed battle, which ended by definition.
        round_limit = data['rounds'] + int(data['status'] == 'Completed')
        rounds_counted = set(range(1, round_limit))
        activations = []
        planning = []
        inventory_calls = 0
        for line in (parent/'godot.log').read_text(encoding='utf8',errors='replace').splitlines():
            if line.startswith('[AIActivation] '):
                profile = json.loads(line.removeprefix('[AIActivation] '))
                activations.append(profile['activation_us']/1000)
                for decision in profile['decisions']+[profile['tail']]:
                    if decision['work_us'] > 0:
                        planning.append(decision['work_us']/1000)
                    inventory_calls += decision.get('counts',{}).get('attack_inventory',0)
        fingerprint = hashlib.sha256(json.dumps(full_actions,sort_keys=True).encode()).hexdigest() if full_actions else ''
        metrics = {
            'moves': kinds['move'], 'waits': kinds['wait'], 'guard': kinds['overwatch'], 'reaction_events':len(gs),
            'reaction_damage':sum(g['damage'] for g in gs), 'attacks':len(attacks), 'attack_ap':attack_ap, 'kills':kills,
            'hit':sum(int(row['resolved']['did_hit']) for row in attacks),
            'context_attacks':sum(row['resolved'].get('firing_solution',{}).get('posture')=='side_step' for row in attacks),
            'concentrated_targets':sum(len(v)>1 for v in targets.values()),
            'rounds_without_damage':len(rounds_counted - damaged_rounds), 'rounds_counted':len(rounds_counted),
            'first_attack_record': first_attack_record, 'damage_by_side':dict(side_damage),
            'activation_ms':activations, 'planning_work_ms': planning, 'attack_inventories': inventory_calls,
            'transaction_fingerprint': fingerprint,
        }
        yield data | {'metrics':metrics}

def stat(values):
    if not values: return None
    return [round(median(values),3), round(quantiles(values,n=100,method='inclusive')[94],3) if len(values)>1 else round(values[0],3), round(max(values),3)]

def summarize(rows):
    sums = ['moves','waits','guard','reaction_events','reaction_damage','attacks','attack_ap','kills','hit',
            'context_attacks','concentrated_targets','rounds_without_damage','rounds_counted','attack_inventories']
    extra = ['hits_checked','hits_unchecked','one_way_damage','damage','return_queries','return_query_usec','guard_counterfactual_holds']
    by_status=Counter(row['status'] for row in rows)
    by_result=Counter(row['battle_result'] for row in rows)
    totals = {k:sum(row['metrics'][k] for row in rows) for k in sums}
    priors = {k:sum(row['evidence'][k] for row in rows) for k in extra}
    policy=[row['configuration'].get('combat_policy_evidence',{}) for row in rows]
    evidence={k:sum(x.get(k,0) for x in policy) for k in ['one_way_pairs','mutually_obstructed_pairs','protected_activations','sampled_activations']}
    damage=Counter()
    for row in rows: damage.update(row['metrics']['damage_by_side'])
    return {'count':len(rows),'status':dict(by_status),'outcome':dict(by_result),
            'rounds':stat([r['rounds'] for r in rows]),'elapsed_seconds':stat([r['elapsed_seconds'] for r in rows]),
            'activation_ms':stat([x for r in rows for x in r['metrics']['activation_ms']]),
            'work_ms':stat([x for r in rows for x in r['metrics']['planning_work_ms']]),
            'first_attack_record':stat([r['metrics']['first_attack_record'] for r in rows if r['metrics']['first_attack_record'] is not None]),
            'total':totals,'counter':priors,'observations':evidence,'damage_side':dict(damage)}

def paired(rows):
    blocks = defaultdict(dict)
    for r in rows:
        c = r['case']
        key = (c['battlefield_id'],c['seed'],c['player_count'],c['coordination'],c['contextual_firing_disabled'],c['guard_minimum_chance'])
        blocks[key][c['engagement_policy']] = int(r['status']=='Completed')
    result={}
    for m in (1,2,3):
        clusters=defaultdict(list)
        for key, d in blocks.items():
            if {m,0}<=d.keys(): clusters[key[:3]].append(d[m]-d[0])
        if not clusters: continue
        groups=list(clusters.values())
        rng=Random(7)
        delta=mean(x for grp in groups for x in grp)
        samples=sorted(mean(x for grp in (rng.choice(groups) for _ in groups) for x in grp) for _ in range(4000))
        result[m]=[sum(map(len,groups)),len(groups),round(delta,3),round(samples[100],3),round(samples[3900],3)]
    return result

def main():
    folder = Path(sys.argv[1])
    for batch in sys.argv[2:]:
        rows=list(read_cases(folder/batch))
        report={'by_mode':{},'by_map':{},'by_coordination':{},'factorial':{},'paired_completion':paired(rows),
                'repeat_fingerprints':{},'setup_failed':[]}
        for key in range(4): report['by_mode'][key]=summarize([r for r in rows if r['case']['engagement_policy']==key])
        for name,column in [('by_map','battlefield_id'),('by_coordination','coordination')]:
            for key in sorted({r['case'][column] for r in rows}):
                report[name][key]={m:summarize([r for r in rows if r['case'][column]==key and r['case']['engagement_policy']==m]) for m in range(4)}
        if 'factorial' in batch:
            groups=defaultdict(list)
            for r in rows:
                c=r['case']
                groups[f"m{c['engagement_policy']}-step{int(not c['contextual_firing_disabled'])}-g{c['guard_minimum_chance']}"].append(r)
            for key,values in sorted(groups.items()): report['factorial'][key]=summarize(values)
        for r in rows:
            if r['status']=='Setup_failed': report['setup_failed'].append([r['case'],r['validation_errors']])
            if 'pilot' in batch:
                report['repeat_fingerprints'][r['case']['case_id']]=[r['evidence'].get('initial_fingerprint'),r['metrics']['transaction_fingerprint']]
        (folder/f'{batch}-summary.json').write_text(json.dumps(report,indent=2),encoding='utf8')
        print(batch,len(rows), 'receipts', 'paired',report['paired_completion'])
        for mode,row in report['by_mode'].items(): print(mode,row)
        for field in ['by_map','by_coordination']:
            print(field, {k:{m:(v['count'],v['status'],v['outcome']) for m,v in modes.items()} for k,modes in report[field].items()})

if __name__=='__main__':
    main()
