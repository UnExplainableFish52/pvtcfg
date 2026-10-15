#!/usr/bin/env python3
"""Run navigation/reset checks in disposable directories; never change HOME.

Only TSH's Documents assignment is redirected in a temporary copy of the module.
The functions and guards are otherwise exercised unchanged by a real Zsh process.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'zsh/functions.zsh'


def run_case(name, body):
    with tempfile.TemporaryDirectory(prefix='loki shell test ') as temp:
        fixture = Path(temp)
        source = SOURCE.read_text()
        assignment = 'local docs="$HOME/Documents"'
        assert source.count(assignment) == 1
        (fixture / 'functions.zsh').write_text(
            source.replace(assignment, 'local docs="$TSH_TEST_ROOT/Documents"')
        )
        env = os.environ.copy()
        env['TSH_TEST_ROOT'] = str(fixture)
        env['TSH_TEST_REPO'] = str(ROOT)
        script = '''
setopt ERR_EXIT NO_UNSET
source "$TSH_TEST_ROOT/functions.zsh"
_tp_docs_dir() { print -r -- "$TSH_TEST_ROOT/Documents"; }
check() { [[ "$1" == "$2" ]] || { print -u2 -r -- "Mismatch: $1 != $2"; exit 1; }; }
local_docs="$TSH_TEST_ROOT/Documents"
workspace="$local_docs/shell/temp_session"
outside="$TSH_TEST_ROOT/outside"
command mkdir -p -- "$outside"
print keep > "$outside/keep"
''' + body
        result = subprocess.run(['zsh', '-f', '-c', script], env=env,
                                text=True, capture_output=True)
        if result.returncode:
            raise AssertionError(f'{name}:\n{result.stdout}{result.stderr}')
        print(f'PASS: {name}')


run_case('create, reset, hidden/nested files, and repeat from inside', '''
original_shell_level="$SHLVL"
TSH
check "$PWD" "$workspace"
check "$SHLVL" "$original_shell_level"
print stale > visible
print stale > .hidden
command mkdir -p -- nested/deeper
print stale > nested/deeper/file
command ln -s -- "$outside" external
command ln -s -- "$outside/missing" dangling
TSH
check "$PWD" "$workspace"
entries=( "$workspace"/*(DN) )
check "${#entries}" 0
[[ -f "$outside/keep" ]]
tsh
check "$PWD" "$workspace"
''')

run_case('arguments cannot redirect or clear the workspace', '''
TSH
print keep > "$workspace/keep"
if TSH "$outside"; then exit 1; fi
[[ -f "$workspace/keep" && -f "$outside/keep" ]]
''')

for component in ('Documents', 'Documents/shell', 'Documents/shell/temp_session'):
    for kind in ('symlink', 'file'):
        run_case(f'refuse {kind} at {component}', f'''
component="$TSH_TEST_ROOT/{component}"
command mkdir -p -- "${{component:h}}"
''' + ('command ln -s -- "$outside" "$component"\n' if kind == 'symlink'
       else 'print keep > "$component"\n') + '''
before="$PWD"
if TSH; then exit 1; fi
check "$PWD" "$before"
[[ -f "$outside/keep" ]]
''')

run_case('failed deletion returns failure and preserves remaining data', '''
TSH
print keep > "$workspace/keep"
fakebin="$TSH_TEST_ROOT/fakebin"
command mkdir -- "$fakebin"
printf '#!/bin/sh\\nexit 1\\n' > "$fakebin/rm"
command chmod +x -- "$fakebin/rm"
PATH="$fakebin:$PATH"
if TSH; then exit 1; fi
[[ -f "$workspace/keep" ]]
''')

run_case('named config directory and shortcut from unrelated directories', '''
ZSHCFG_DIR="$TSH_TEST_ROOT/config modules"
command mkdir -p -- "$ZSHCFG_DIR"
source "$TSH_TEST_REPO/zsh/options.zsh"
source "$TSH_TEST_REPO/zsh/aliases.zsh"
builtin cd -- "$outside"
cd shell_config
check "$PWD" "$ZSHCFG_DIR"
builtin cd -- "$outside"
eval shell_config
check "$PWD" "$ZSHCFG_DIR"
builtin cd -- "$outside"
command mkdir -- shell_config
cd ~shell_config
check "$PWD" "$ZSHCFG_DIR"
''')

run_case('tp search, menu, picker, reset, and PATH preservation', '''
original_path="$PATH"
check "$(_tp_best_match_path notes)" "$local_docs/notes"
_tp_list_matches notes
check "$PATH" "$original_path"
tp n
tp notes
check "$PWD" "$local_docs/notes"
tp -s codes
tp c
check "$PWD" "$local_docs/codes"
tp t <<<'y'
check "$PWD" "$local_docs/codes/temp"
print stale > "$PWD/.hidden"
tp t <<<'y'
[[ ! -e "$PWD/.hidden" ]]
tp <<<'n'
check "$PWD" "$local_docs/notes"
fzf() { IFS= read -r selected; print -r -- "$selected"; }
tp -f
check "$PWD" "$local_docs/codes"
check "$PATH" "$original_path"
command -v awk >/dev/null
''')

for module in (ROOT / 'zsh').glob('*.zsh'):
    subprocess.run(['zsh', '-n', str(module)], check=True)
subprocess.run(['zsh', '-n', str(ROOT / '.zshrc')], check=True)
subprocess.run(['zsh', '-n', str(ROOT / '.p10k.zsh')], check=True)
subprocess.run(['bash', '-n', str(ROOT / 'install.sh')], check=True)
print('PASS: syntax checks for all bundled shell files')
