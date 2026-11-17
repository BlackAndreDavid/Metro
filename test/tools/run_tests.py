#!/usr/bin/env python3
"""Run Godot tests from any directory; retain each run's logs and artifacts."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE', 'godot'))
    args = parser.parse_args()
    executable = shutil.which(args.godot)
    if not executable:
        parser.error('Godot not found; pass --godot /path/to/Godot-4.7.2')
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    output = root / 'results' / run_id
    output.mkdir(parents=True)
    env = os.environ.copy()
    env.update(METRO_TEST_ROOT=str(root), METRO_TEST_RESULTS=str(output),
               UV_OFFLINE='1', UV_PYTHON_DOWNLOADS='never', GODOT_AI_DISABLE_TELEMETRY='true')
    # Isolate settings, saves and caches from normal gameplay and local editors.
    for name, directory in [('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'), ('XDG_CACHE_HOME', 'cache')]:
        path = output / directory
        path.mkdir()
        env[name] = str(path)
    base = [executable, '--headless', '--path', str(root.parent / 'Demo')]
    results = []

    def run(name, arguments, expected=()):
        command = base + arguments
        try:
            process = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, timeout=120)
            log, code = process.stdout, process.returncode
        except subprocess.TimeoutExpired as error:
            log = (error.stdout or b'').decode(errors='replace') if isinstance(error.stdout, bytes) else (error.stdout or '')
            log += '\nTest timed out after 120 seconds\n'
            code = 124
        (output / (name + '.log')).write_text(log, encoding='utf-8')
        passed = code == 0 and all(marker in log for marker in expected) and 'SCRIPT ERROR:' not in log and 'ERROR:' not in log
        results.append(dict(name=name, exit_code=code, passed=passed, log=name + '.log'))
        print(f'{name}: {"PASS" if passed else "FAIL"}', flush=True)
        if not passed:
            print(log)
        return passed

    if run('import', ['--editor', '--import']):
        run('menu_flow', ['--script', str(root / 'cases/test_menu_flow.gd')],
            ['STATE_TESTS: 32 checks, 0 failures', 'MENU_FLOW: 18 checks, failed=false'])
        run('cabin_smoke', ['--script', str(root / 'cases/test_cabin_smoke.gd'), '--',
                            '--save-file=' + str(output / 'smoke_save.json')],
            ['ONBOARDING_SMOKE: rules and cabin UI initialized'])
        run('home_flow', ['--script', str(root / 'cases/test_home_flow.gd'), '--',
                          '--save-file=' + str(output / 'home_flow_save.json')],
            ['HOME_FLOW: 31 checks, 0 failures'])
    passed = len(results) == 4 and all(item['passed'] for item in results)
    summary = dict(run_id=run_id, passed=passed, results=results)
    (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Results: {output}')
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
