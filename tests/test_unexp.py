#!/usr/bin/env python3
"""Read-only lessons and live Zsh introspection, using workspace-only fixtures."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')
ZSH = shutil.which('zsh')


@unittest.skipUnless(BASH, 'Bash is required')
class Lessons(unittest.TestCase):
    def run_lesson(self, *args, expected=0, cli=False):
        command = [BASH, 'bin/zshcfg', 'unexp'] if cli else [BASH, 'bin/unexp']
        result = subprocess.run([*command, *args], cwd=ROOT, input='',
                                capture_output=True, text=True, encoding='utf-8', timeout=10)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_virtual_environment_lesson_teaches_each_step(self):
        output = self.run_lesson('mkvenv').stdout
        for text in ('python3 -m venv .venv', 'cd .venv', 'source bin/activate',
                     'PATH', '&&', 'deactivate', 'source .venv/bin/activate'):
            self.assertIn(text, output)
        self.assertNotIn('git status', output)

    def test_git_lesson_explains_flags_and_cli_routes_to_same_lesson(self):
        output = self.run_lesson('gs').stdout
        self.assertIn('git status -sb', output)
        self.assertIn('-s means short format; -b includes branch', output)
        self.assertEqual(output, self.run_lesson('gs', cli=True).stdout)

    def test_menu_and_help_do_not_wait_for_input(self):
        menu = self.run_lesson().stdout
        self.assertEqual(menu, self.run_lesson('--list').stdout)
        for name in ('mkvenv', 'gs', 'tp', 'TSH', 'unexp'):
            self.assertIn(name, menu)
        self.assertIn('Usage: unexp', self.run_lesson('--help').stdout)
        self.run_lesson('gs', 'extra', expected=1)
        self.assertIn('No reference lesson', self.run_lesson('missing-lesson', expected=2).stderr)

    def test_every_repository_alias_and_public_helper_has_a_lesson(self):
        lessons = (ROOT / 'bin/unexp.txt').read_text(encoding='utf-8')
        topics = re.findall(r'^@@ (.+)$', lessons, re.M)
        names = [name for topic in topics for name in topic.split()]
        self.assertEqual(len(names), len(set(names)), 'Duplicate lesson name')
        aliases = re.findall(r'^\s*alias\s+([^\s=]+)=',
                             (ROOT / 'zsh/aliases.zsh').read_text(encoding='utf-8'), re.M)
        for name in aliases + ['mkvenv', 'tp', 'TSH', 'tsh', 'rand', 'random',
                               'rint', 'check_recent_files', 'unexp']:
            self.assertIn(name, names)
        for name in names:
            with self.subTest(name=name):
                self.assertIn(f'Reference lesson / {name}', self.run_lesson(name).stdout)

    def test_topic_is_data_and_cannot_execute_commands(self):
        with tempfile.TemporaryDirectory(prefix='.unexp-test-', dir=ROOT) as directory:
            marker = Path(directory) / 'must-not-exist'
            # A literal command substitution must remain a lookup string.
            topic = f'$(touch "{marker.as_posix()}")'
            result = self.run_lesson(topic, expected=2)
            self.assertIn(topic, result.stderr)
            self.assertFalse(marker.exists())
        self.run_lesson('../unexp.txt', expected=2)
        self.run_lesson('--unknown-option', expected=2)


@unittest.skipUnless(ZSH, 'Live introspection requires Zsh; run this suite on Kali')
class ActiveShell(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='.unexp-test-', dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.fixture = Path(self.temp.name)
        self.marker = self.fixture / 'must-not-exist'

    def shell(self, script):
        env = dict(os.environ, UNEXP_REPO=ROOT.as_posix(),
                   UNEXP_MARKER=self.marker.as_posix())
        setup = '''
repo="$(cd -- "$UNEXP_REPO" && pwd -P)"
export PATH="$repo/bin:$PATH"
source "$repo/zsh/aliases.zsh"
source "$repo/zsh/functions.zsh"
'''
        return subprocess.run([ZSH, '-f', '-c', setup + script], cwd=self.fixture,
                              env=env, input='', capture_output=True, text=True,
                              encoding='utf-8', timeout=10)

    def test_live_alias_and_function_are_revealed_without_execution(self):
        result = self.shell('''
alias local_alias='touch "$UNEXP_MARKER"'
local_function() { touch "$UNEXP_MARKER"; }
unexp local_alias
unexp local_function
unexp mkvenv
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('local_alias (alias)', result.stdout)
        self.assertIn('local_function (function)', result.stdout)
        self.assertIn('touch "$UNEXP_MARKER"', result.stdout)
        self.assertIn('python3 -m venv', result.stdout)
        self.assertIn('Reference lesson / mkvenv', result.stdout)
        self.assertFalse(self.marker.exists())
        self.assertFalse((self.fixture / '.venv').exists())

    def test_local_override_is_shown_separately_from_repository_lesson(self):
        result = self.shell("alias gs='printf overridden'\nunexp gs\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('printf overridden', result.stdout)
        self.assertIn('active definitions may differ', result.stdout)
        self.assertIn('git status -sb', result.stdout)

    def test_unknown_name_and_invalid_arguments_fail_and_piped_menu_exits(self):
        self.assertEqual(self.shell('unexp unexp-no-such-command').returncode, 1)
        self.assertEqual(self.shell('unexp gs extra').returncode, 1)
        result = self.shell('unexp')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('UNEXP / shortcut lessons', result.stdout)
        self.assertNotIn('Shortcut (Enter to close):', result.stdout)

    def test_builtin_is_identified_and_adversarial_name_is_not_evaluated(self):
        result = self.shell('unexp cd')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('builtin', result.stdout)
        result = self.shell("unexp '$(touch \"$UNEXP_MARKER\")'")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
