#!/usr/bin/env python3
"""Portable publish/pull checks using real Git and local remotes.

Only Zsh syntax validation is stubbed here; test_workflow.py checks real Zsh
on Linux. Fixtures stay inside the workspace and never contact GitHub.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash') or 'bash'


class Publish(unittest.TestCase):
    def run_cmd(self, *args, expected=0, input=None):
        result = subprocess.run(args, cwd=ROOT, env=self.env, input=input,
                                text=True, capture_output=True, timeout=30)
        if expected is not None:
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def git(self, repo, *args):
        return self.run_cmd('git', '-C', str(repo), *args).stdout.strip()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='.publish-test-', dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'home').mkdir()
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.remote = self.root / 'cloud.git'
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        checker = self.tools / 'zsh'
        checker.write_bytes(b'#!/usr/bin/env bash\n[[ "$1" == -n ]]\n')
        checker.chmod(0o755)
        self.env = dict(os.environ, ZSHCFG_HOME=(self.root / 'home').as_posix(),
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        GIT_AUTHOR_NAME='Config test', GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_NAME='Config test', GIT_COMMITTER_EMAIL='test@example.invalid')
        for name in ('.zshrc', '.nanorc', '.p10k.zsh', 'VERSION', '.gitignore',
                     '.gitattributes', 'install.sh', 'bin/zshcfg'):
            dest = self.repo / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, dest)
        shutil.copytree(ROOT / 'zsh', self.repo / 'zsh')
        self.git(self.repo, 'init', '-b', 'main')
        self.git(self.repo, 'add', '.')
        self.git(self.repo, 'commit', '-m', 'Initial config')
        self.run_cmd('git', 'init', '--bare', str(self.remote))
        self.git(self.repo, 'remote', 'add', 'origin', str(self.remote))
        self.git(self.repo, 'push', '-u', 'origin', 'main')

    def cli(self, *args, **kwargs):
        return self.run_cmd(BASH, '-c',
                            'test_tools="$(cd -- "$1" && pwd -P)"; '
                            'export ZSHCFG_HOME="$(cd -- "$ZSHCFG_HOME" && pwd -P)"; '
                            'export PATH="$test_tools:$PATH"; '
                            'exec "$BASH" "$2/bin/zshcfg" "${@:3}"',
                            'publish-test', self.tools.as_posix(), self.repo.as_posix(),
                            *args, **kwargs)

    def edit(self, name, content):
        (self.repo / name).write_bytes(content.encode())

    def test_prompt_publishes_multiple_files_and_keeps_private_files_local(self):
        self.edit('zsh/aliases.zsh', "alias hello='echo hello'\n")
        self.edit('zsh/functions.zsh', 'hello() { echo hello; }\n')
        self.edit('zsh/new module.zsh', '# extra tracked module\n')
        self.edit('zsh/local.zsh', '# private override\n')
        self.edit('README.md', '# unrelated draft\n')
        (self.repo / '.nanorc').unlink()
        message = 'Add aliases, functions & a module; remove Nano settings'
        result = self.cli('push', input=message + '\n')
        self.assertIn('Commit message', result.stdout)
        self.assertEqual(self.git(self.remote, 'log', '-1', '--format=%s', 'main'), message)
        files = self.git(self.remote, 'ls-tree', '-r', '--name-only', 'main').splitlines()
        self.assertIn('zsh/new module.zsh', files)
        for name in ('zsh/local.zsh', 'README.md', '.nanorc'):
            self.assertNotIn(name, files)
        self.assertEqual(self.git(self.repo, 'diff', '--name-only'), '')

    def test_blank_whitespace_and_eof_cancel_without_staging_or_version_changes(self):
        self.edit('zsh/aliases.zsh', '# pending alias\n')
        head = self.git(self.repo, 'rev-parse', 'HEAD')
        version = (self.repo / 'VERSION').read_bytes()
        for answer in ('\n', '  \t\n', ''):
            self.cli('push', input=answer, expected=1)
            self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), head)
            self.assertEqual(self.git(self.repo, 'diff', '--cached', '--name-only'), '')
            self.assertEqual((self.repo / 'VERSION').read_bytes(), version)
            self.assertEqual(self.git(self.remote, 'rev-parse', 'main'), head)

    def test_explicit_message_and_retry_after_rejected_push(self):
        hook = self.remote / 'hooks/pre-receive'
        hook.write_bytes(b'#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        self.edit('zsh/aliases.zsh', '# saved even when push fails\n')
        result = self.cli('push', '-m', 'My alias backup', expected=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local commit is saved', result.stderr)
        head = self.git(self.repo, 'rev-parse', 'HEAD')
        hook.unlink()
        result = self.cli('push', input='')
        self.assertNotIn('Commit message', result.stdout)
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), head)
        self.assertEqual(self.git(self.remote, 'rev-parse', 'main'), head)

    def test_unrelated_staged_file_is_preserved_and_blocks_publish(self):
        self.edit('README.md', '# staged elsewhere\n')
        self.git(self.repo, 'add', 'README.md')
        self.edit('zsh/aliases.zsh', '# my alias\n')
        result = self.cli('push', '-m', 'Save alias', expected=1)
        self.assertIn('Unrelated staged file', result.stderr)
        self.assertEqual(self.git(self.repo, 'diff', '--cached', '--name-only'), 'README.md')

    def test_invalid_arguments_and_syntax_failure_leave_changes_uncommitted(self):
        self.edit('zsh/aliases.zsh', '# pending alias\n')
        head = self.git(self.repo, 'rev-parse', 'HEAD')
        for args in (('push', '-m'), ('push', '-m', ''), ('push', '-m', '  '),
                     ('push', 'unexpected'), ('push', 'force', 'force')):
            self.cli(*args, expected=1)
            self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), head)
            self.assertEqual(self.git(self.repo, 'diff', '--cached', '--name-only'), '')
        (self.tools / 'zsh').write_bytes(b'#!/usr/bin/env bash\nexit 1\n')
        result = self.cli('push', '-m', 'Must not commit', expected=1)
        self.assertIn('Shell syntax check failed', result.stderr)
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), head)
        self.assertEqual(self.git(self.remote, 'rev-parse', 'main'), head)

    def test_second_machine_imports_backup_and_preserves_local_edits(self):
        peer = self.root / 'second machine'
        self.run_cmd('git', 'clone', '--branch', 'main', str(self.remote), str(peer))
        self.edit('zsh/aliases.zsh', '# alias from first machine\n')
        self.cli('publish', '--message', 'Share my alias')
        first = self.repo
        self.repo = peer
        self.cli('pull')
        self.assertEqual((peer / 'zsh/aliases.zsh').read_text(), '# alias from first machine\n')
        self.edit('zsh/aliases.zsh', '# unsaved second-machine edit\n')
        self.repo = first
        self.edit('zsh/functions.zsh', '# another remote change\n')
        self.cli('push', '-m', 'Share function')
        self.repo = peer
        self.cli('pull', expected=1)
        self.assertEqual((peer / 'zsh/aliases.zsh').read_text(), '# unsaved second-machine edit\n')

    def test_lf_checkout_even_when_autocrlf_is_enabled(self):
        peer = self.root / 'windows checkout'
        self.run_cmd('git', '-c', 'core.autocrlf=true', 'clone', '--branch', 'main',
                     str(self.remote), str(peer))
        for name in ('.zshrc', '.p10k.zsh', 'bin/zshcfg', 'install.sh', 'zsh/aliases.zsh'):
            self.assertNotIn(b'\r', (peer / name).read_bytes(), name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
