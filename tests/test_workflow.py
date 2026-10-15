#!/usr/bin/env python3
"""Real Git integration tests in disposable ZSHCFG_HOME roots. Never changes HOME."""
from datetime import datetime
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Workflow(unittest.TestCase):
    def run_cmd(self, *args, cwd=None, expected=0, input=None, env=None):
        result = subprocess.run(args, cwd=cwd or self.outside, env=env or self.env,
                                input=input, capture_output=True, text=True, timeout=30)
        if expected is not None:
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def git(self, directory, *args, **kwargs):
        return self.run_cmd('git', '-C', str(directory), *args, **kwargs)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='zshcfg workflow ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.outside = self.root / 'unrelated working directory'
        self.outside.mkdir()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.seed = self.root / 'source checkout'
        self.seed.mkdir()
        self.remote = self.root / 'remote.git'
        self.repo = self.home / '.local/share/zshcfg/repo'
        self.env = os.environ.copy()
        self.env.update(ZSHCFG_HOME=str(self.home), ZSHCFG_REMOTE=str(self.remote),
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        GIT_AUTHOR_NAME='Config test', GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_NAME='Config test', GIT_COMMITTER_EMAIL='test@example.invalid')
        names = subprocess.check_output(['git', 'ls-files', '--cached', '--others',
                                         '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
        for name in names:
            source = ROOT / name
            if not name or not source.is_file() or source.suffix.lower() in ('.jpg', '.png'):
                continue
            destination = self.seed / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        self.git(self.seed, 'init', '-b', 'main')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-m', 'Fixture configuration')
        self.run_cmd('git', 'init', '--bare', '--initial-branch=main', str(self.remote))
        self.git(self.seed, 'remote', 'add', 'origin', str(self.remote))
        self.git(self.seed, 'push', '-u', 'origin', 'main')
        self.old_zshrc = '# previous zshrc\n'
        (self.home / '.zshrc').write_text(self.old_zshrc)
        (self.home / '.nanorc').write_text('# previous nano\n')
        (self.home / '.zsh_config').mkdir()
        (self.home / '.zsh_config/local.zsh').write_text('# private machine settings\n')

    def install(self, script=None, expected=0, env=None):
        return self.run_cmd('bash', str(script or self.seed / 'install.sh'), '--yes',
                            '--skip-deps', '--no-chsh', expected=expected, env=env)

    def cli(self, *args, **kwargs):
        return self.run_cmd('bash', str(self.repo / 'bin/zshcfg'), *args, **kwargs)

    def peer_change(self, text='# remote change\n'):
        with (self.seed / '.nanorc').open('a') as file:
            file.write(text)
        self.git(self.seed, 'add', '.nanorc')
        self.git(self.seed, 'commit', '-m', text.strip())
        self.git(self.seed, 'push')
        return self.git(self.seed, 'rev-parse', 'HEAD').stdout.strip()

    def local_change(self):
        with (self.home / '.zsh_config/aliases.zsh').open('a') as file:
            file.write('\n# local alias edit\n')

    def test_install_backups_links_reinstall_and_private_override(self):
        self.install()
        self.assertEqual((self.home / '.zshrc').resolve(), self.repo / '.zshrc')
        self.assertEqual((self.home / '.nanorc').resolve(), self.repo / '.nanorc')
        backups = list(self.home.glob('.zshrc.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), self.old_zshrc)
        self.assertRegex(backups[0].name, r'\.zshrc\.bak\.\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d+')
        self.install()
        self.assertEqual(len(list(self.home.glob('.zshrc.bak.*'))), 1)
        self.assertEqual((self.home / '.zsh_config/local.zsh').read_text(), '# private machine settings\n')
        self.assertFalse((self.home / '.zsh_config/local.zsh').is_symlink())
        self.assertIn('set linenumbers', (self.home / '.nanorc').read_text())
        self.local_change()
        self.assertIn('local alias edit', self.git(self.repo, 'diff').stdout)
        self.assertFalse((self.home / 'Pictures').exists())

    def test_dependency_installation_with_mock_package_manager(self):
        # Real host packages and external networks are never used by this test.
        fakebin = self.root / 'package tools'
        fakebin.mkdir()
        def executable(name, text):
            item = fakebin / name
            item.write_text('#!/bin/bash\n' + text)
            item.chmod(0o755)
        executable('sudo', 'exec "$@"\n')
        executable('python3', '[[ -f "$ZSHCFG_HOME/venv-ready" ]]\n')
        executable('apt-get', '''
printf '%s\\n' "$*" >> "$ZSHCFG_HOME/package-log"
if [[ "$1" == install ]]; then
  for tool in fzf rg batcat eza; do
    printf '#!/bin/sh\\nexit 0\\n' > "$(dirname "$0")/$tool"
    chmod +x "$(dirname "$0")/$tool"
  done
  touch "$ZSHCFG_HOME/venv-ready"
fi
''')
        executable('git', '''
if [[ "$1" == clone && "$*" == *https://github.com/* && "$*" != *pvtcfg* ]]; then
  for argument in "$@"; do destination="$argument"; done
  mkdir -p "$destination"
  case "$*" in
    *ohmyzsh/ohmyzsh*) touch "$destination/oh-my-zsh.sh" ;;
    *romkatv/powerlevel10k*) touch "$destination/powerlevel10k.zsh-theme" ;;
    *zsh-users/zsh-autosuggestions*) touch "$destination/zsh-autosuggestions.plugin.zsh" ;;
    *zsh-users/zsh-syntax-highlighting*) touch "$destination/zsh-syntax-highlighting.plugin.zsh" ;;
  esac
  exit 0
fi
exec /usr/bin/git "$@"
''')
        env = dict(self.env, PATH=str(fakebin) + ':/usr/bin:/bin')
        self.run_cmd('bash', str(self.seed / 'install.sh'), '--yes', '--no-chsh', env=env)
        log = (self.home / 'package-log').read_text()
        for tool, package in (('fzf', 'fzf'), ('rg', 'ripgrep'), ('bat', 'bat'), ('eza', 'eza')):
            if not shutil.which(tool, path='/usr/bin:/bin'):
                self.assertIn(package, log)
        self.assertIn('python3-venv', log)
        self.assertTrue((self.home / '.oh-my-zsh/oh-my-zsh.sh').exists())
        self.assertTrue((self.home / '.zshrc').is_symlink())


    def test_invalid_sudo_caller_stops_before_changes(self):
        if os.geteuid() != 0:
            self.skipTest('requires root to exercise sudo caller resolution')
        env = dict(self.env, SUDO_USER='zshcfg-no-such-user', SUDO_UID='65534')
        self.assertIn('Cannot resolve sudo caller', self.install(expected=1, env=env).stderr)
        self.assertFalse(self.repo.exists())
        self.assertEqual((self.home / '.zshrc').read_text(), self.old_zshrc)
        env = dict(self.env, SUDO_USER='nobody', SUDO_UID='0')
        self.assertIn('do not match', self.install(expected=1, env=env).stderr)
        self.assertFalse(self.repo.exists())

    def prepare_unprivileged_fixture(self):
        import pwd
        if os.geteuid() != 0 or not shutil.which('sudo'):
            self.skipTest('requires root and sudo for a real privilege drop')
        try:
            account = pwd.getpwnam('nobody')
        except KeyError:
            self.skipTest('requires the nobody test account')
        self.root.chmod(0o755)
        for directory in (self.home, self.seed):
            try:
                os.chown(directory, account.pw_uid, account.pw_gid)
            except OSError as error:
                if error.errno in (1, 22):
                    self.skipTest('runtime cannot map a non-root UID/GID for ownership checks')
                raise
            for parent, dirs, files in os.walk(directory):
                for name in dirs + files:
                    os.chown(Path(parent) / name, account.pw_uid, account.pw_gid)
        return account

    def assert_user_owns_install(self, account):
        self.assertEqual((self.home / '.zshrc').resolve(), self.repo / '.zshrc')
        self.assertEqual((self.home / '.zshrc').read_text(), (self.repo / '.zshrc').read_text())
        self.assertEqual(len(list(self.home.glob('.zshrc.bak.*'))), 1)
        for path in self.home.rglob('*'):
            self.assertEqual(path.lstat().st_uid, account.pw_uid, str(path))

    def test_sudo_targets_caller_and_keeps_user_ownership(self):
        account = self.prepare_unprivileged_fixture()
        # Simulate sudo's caller metadata, then exercise REAL sudo -u calls.
        env = dict(self.env, SUDO_USER=account.pw_name, SUDO_UID=str(account.pw_uid))
        help_env = env.copy()
        help_env.pop('ZSHCFG_HOME')
        result = self.run_cmd('bash', str(self.seed / 'install.sh'), '--help', env=help_env)
        self.assertIn(f'Install target: {account.pw_name} ({account.pw_dir})', result.stdout)
        self.install(env=env)
        self.assert_user_owns_install(account)
        self.install(env=env)
        self.assert_user_owns_install(account)
        # Git's safe.directory check must work without configuration workarounds.
        self.run_cmd('sudo', '-H', '-u', account.pw_name, '--', 'git', '-C',
                     str(self.repo), 'status', '--porcelain')

    def test_sudo_routes_home_operations_to_original_caller(self):
        if os.geteuid() != 0:
            self.skipTest('requires root to exercise sudo caller resolution')
        fakebin = self.root / 'sudo tools'
        fakebin.mkdir()
        wrapper = fakebin / 'sudo'
        wrapper.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$ZSHCFG_HOME/sudo-log"
[[ "$1" == -H && "$2" == -u && "$3" == nobody && "$4" == -- ]] || exit 2
shift 4
exec "$@"
''')
        wrapper.chmod(0o755)
        previous_nano = self.root / 'previous.nanorc'
        previous_nano.write_text('# old linked nano config\n')
        (self.home / '.nanorc').unlink()
        (self.home / '.nanorc').symlink_to(previous_nano)
        env = dict(self.env, SUDO_USER='nobody', SUDO_UID='65534',
                   PATH=str(fakebin) + ':' + self.env['PATH'])
        help_env = env.copy()
        help_env.pop('ZSHCFG_HOME')
        result = self.run_cmd('bash', str(self.seed / 'install.sh'), '--help', env=help_env)
        self.assertIn('Install target: nobody (/nonexistent)', result.stdout)
        self.install(env=env)
        log = (self.home / 'sudo-log').read_text().splitlines()
        self.assertTrue(all(line.startswith('-H -u nobody -- ') for line in log))
        for command in ('git', 'mkdir', 'ln', 'mv', 'cp', 'rm'):
            self.assertTrue(any('-- ' + command + ' ' in line for line in log), command)
        self.assertEqual((self.home / '.zshrc').resolve(), self.repo / '.zshrc')
        backups = list(self.home.glob('.nanorc.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), '# old linked nano config\n')

    def test_normal_nonroot_user_installation(self):
        account = self.prepare_unprivileged_fixture()
        self.run_cmd('sudo', '-H', '-u', account.pw_name, '--', 'env',
                     'ZSHCFG_HOME=' + str(self.home),
                     'ZSHCFG_REMOTE=' + str(self.remote),
                     'bash', str(self.seed / 'install.sh'),
                     '--yes', '--skip-deps', '--no-chsh')
        self.assert_user_owns_install(account)

    def test_standalone_bootstrap(self):
        standalone = self.outside / 'install.sh'
        shutil.copy2(self.seed / 'install.sh', standalone)
        self.install(standalone)
        self.assertTrue((self.repo / '.git').is_dir())
        self.assertEqual(self.git(self.repo, 'remote', 'get-url', 'origin').stdout.strip(), str(self.remote))

    def test_cancel_before_changes(self):
        result = self.run_cmd('bash', str(self.seed / 'install.sh'), input='n\n')
        self.assertIn('cancelled', result.stdout)
        self.assertFalse(self.repo.exists())
        self.assertEqual((self.home / '.zshrc').read_text(), self.old_zshrc)

    def test_destination_directory_refused(self):
        (self.home / '.nanorc').unlink()
        (self.home / '.nanorc').mkdir()
        self.assertIn('directory occupies', self.install(expected=1).stderr)
        self.assertEqual((self.home / '.zshrc').read_text(), self.old_zshrc)

    def test_activation_failure_restores_original_files(self):
        fakebin = self.root / 'fakebin'
        fakebin.mkdir()
        fake_ln = fakebin / 'ln'
        fake_ln.write_text('#!/bin/bash\ncase "$*" in */.nanorc) exit 9;; esac\nexec /usr/bin/ln "$@"\n')
        fake_ln.chmod(0o755)
        env = dict(self.env, PATH=str(fakebin) + ':' + self.env['PATH'])
        result = self.install(expected=9, env=env)
        self.assertIn('restoring', result.stderr)
        self.assertFalse((self.home / '.zshrc').is_symlink())
        self.assertEqual((self.home / '.zshrc').read_text(), self.old_zshrc)
        self.assertEqual((self.home / '.nanorc').read_text(), '# previous nano\n')

    def test_versions_publish_and_explicit_stable_file(self):
        self.install()
        for command in ('v', 'V', 'version'):
            self.assertIn('1.26.10.15.0 (clean)', self.cli(command).stdout)
        self.local_change()
        experimental = '1.' + datetime.now().strftime('%y.%m.%d') + '.1'
        self.assertIn(experimental + ' (local edits)', self.cli('v').stdout)
        self.assertEqual(self.git(self.repo, 'diff', '--', 'VERSION').stdout, '')
        cache = self.home / '.local/state/zshcfg/dirty-version'
        old_cache = cache.read_text()
        self.cli('v')
        self.assertEqual(cache.read_text(), old_cache)
        self.cli('publish')
        self.assertEqual(self.git(self.repo, 'status', '--porcelain').stdout, '')
        self.assertIn(experimental + ' (clean)', self.cli('v').stdout)
        self.assertEqual(self.git(self.remote, 'show', 'main:VERSION').stdout.strip(), experimental)
        (self.repo / 'VERSION').write_text('1.26.10.15.0\n')
        self.cli('push')
        self.assertIn('1.26.10.15.0 (clean)', self.cli('v').stdout)

    def test_failed_push_and_explicit_force_lease(self):
        self.install()
        checked_head = self.peer_change()
        self.local_change()
        result = self.cli('push', expected=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local commit is saved', result.stderr)
        self.assertEqual(self.git(self.repo, 'status', '--porcelain').stdout, '')
        local_head = self.git(self.repo, 'rev-parse', 'HEAD').stdout.strip()
        self.assertIn('diverged', self.cli('check').stdout)
        self.assertNotEqual(self.cli('pull', expected=None).returncode, 0)
        new_remote = self.peer_change('# newer remote after check\n')
        self.assertNotEqual(self.cli('publish', 'force', expected=None).returncode, 0)
        self.assertEqual(self.git(self.remote, 'rev-parse', 'main').stdout.strip(), new_remote)
        self.cli('check')
        self.cli('push', 'force')
        self.assertEqual(self.git(self.remote, 'rev-parse', 'main').stdout.strip(), local_head)
        backups = self.git(self.repo, 'for-each-ref', '--format=%(objectname)',
                           'refs/heads/zshcfg-backup/').stdout
        self.assertIn(checked_head, backups)
        self.assertIn(new_remote, backups)

    def test_clean_pull_and_check_confirmation(self):
        self.install()
        remote_head = self.peer_change()
        self.cli('check', input='n\n')
        self.assertNotEqual(self.git(self.repo, 'rev-parse', 'HEAD').stdout.strip(), remote_head)
        self.cli('check', input='y\n')
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD').stdout.strip(), remote_head)
        self.assertIn('remote change', (self.home / '.nanorc').read_text())
        self.local_change()
        self.assertNotEqual(self.cli('pull', expected=None).returncode, 0)
        self.assertNotEqual(self.cli('pull', 'force', expected=None).returncode, 0)

    def test_network_failure_and_unrelated_staged_file(self):
        self.install()
        (self.repo / 'README.md').write_text('unrelated staged documentation\n')
        self.git(self.repo, 'add', 'README.md')
        self.assertIn('Unrelated staged file', self.cli('publish', expected=1).stderr)
        self.git(self.repo, 'reset', '--hard', 'HEAD')
        self.git(self.repo, 'remote', 'set-url', 'origin', str(self.root / 'missing.git'))
        result = self.cli('check', expected=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('remote status is unknown', result.stderr)
        self.local_change()
        self.assertIn('local commit is saved', self.cli('publish', expected=None).stderr)
        self.assertEqual(self.git(self.repo, 'status', '--porcelain').stdout, '')

    def test_bad_syntax_prevents_publish(self):
        self.install()
        (self.repo / 'zsh/aliases.zsh').write_text('if then broken\n')
        head = self.git(self.repo, 'rev-parse', 'HEAD').stdout
        self.assertIn('syntax check failed', self.cli('publish', expected=1).stderr)
        self.assertEqual(head, self.git(self.repo, 'rev-parse', 'HEAD').stdout)

    def test_aliases_editor_and_startup(self):
        self.install()
        fakebin = self.root / 'tools'
        fakebin.mkdir()
        for tool in ('batcat', 'eza', 'rg'):
            script = fakebin / tool
            script.write_text('#!/bin/sh\nprintf "%s\\n" "' + tool + '" "$@"\n')
            script.chmod(0o755)
        omz = self.home / '.oh-my-zsh'
        omz.mkdir()
        (omz / 'oh-my-zsh.sh').write_text(':\n')
        env = dict(self.env, PATH=str(fakebin) + ':/usr/bin:/bin')
        result = self.run_cmd('zsh', '-f', '-i', '-c', '''
source "$ZSHCFG_HOME/.zshrc"
[[ "$EDITOR" == nano && "$VISUAL" == nano ]] || exit 1
[[ "$HISTFILE" == "$ZSHCFG_HOME/.zsh_history" ]] || exit 1
if (( $+aliases[vi] || $+aliases[vim] )); then exit 1; fi
alias cat ls ll chkv
eval 'cat example.txt'
eval 'ls'
zshcfg v
''', env=env)
        self.assertIn('batcat --style=numbers --paging=never', result.stdout)
        self.assertIn('eza --group-directories-first', result.stdout)
        self.assertIn('1.26.10.15.0', result.stdout)

    @unittest.skipUnless(shutil.which('nano'), 'nano is not installed')
    def test_nanorc_loads_in_real_nano(self):
        self.install()
        sample = self.outside / 'sample.txt'
        sample.write_text('one\ntwo\n')
        master, slave = pty.openpty()
        env = dict(self.env, TERM='xterm')
        process = subprocess.Popen(['nano', '--rcfile', str(self.home / '.nanorc'),
                                    '--view', str(sample)], stdin=slave, stdout=slave,
                                   stderr=slave, env=env)
        os.close(slave)
        output = b''
        try:
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    output += os.read(master, 65536)
                    if b'one' in output and b'two' in output:
                        break
            os.write(master, b'\x18')
            process.wait(timeout=5)
            self.assertEqual(process.returncode, 0, output)
            self.assertNotIn(b'Error in', output)
            self.assertIn(b'one', output)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)


if __name__ == '__main__':
    unittest.main(verbosity=2)
