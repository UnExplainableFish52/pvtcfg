#!/usr/bin/env python3
"""Check installer rendering and isolated activation; never change the real HOME."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')
ANSI = re.compile(r'\x1b\[[0-9;]*m')


@unittest.skipUnless(BASH, 'Bash is required')
class InstallerUI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='.installer-ui-', dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.fixture = Path(self.temp.name)
        self.home = self.fixture / 'untouched-home'
        target = self.home.as_posix()
        if os.name == 'nt':
            target = '/' + target[0].lower() + target[2:]
        self.env = dict(os.environ, ZSHCFG_HOME=target, TERM='xterm-256color',
                        COLORTERM='truecolor', LC_ALL='C.UTF-8')
        self.env.pop('NO_COLOR', None)
        self.source = (ROOT / 'install.sh').read_text(encoding='utf-8')

    def command(self, *args, input=None, extra=None):
        result = subprocess.run([BASH, *args], cwd=ROOT,
                                env=dict(self.env, **(extra or {})), input=input,
                                text=True, encoding='utf-8', capture_output=True,
                                timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    @staticmethod
    def bash_path(path):
        value = path.as_posix()
        if os.name == 'nt':
            value = '/' + value[0].lower() + value[2:]
        return value

    def installer_fixture(self, animated=False, failing_link=False):
        seed = self.fixture / 'seed'
        seed.mkdir()
        for name in ('.zshrc', '.p10k.zsh', '.nanorc', 'VERSION', '.gitattributes',
                     '.gitignore', 'install.sh', 'bin/zshcfg', 'bin/commands.txt'):
            target = seed / name
            target.parent.mkdir(exist_ok=True, parents=True)
            shutil.copyfile(ROOT / name, target)
        shutil.copytree(ROOT / 'zsh', seed / 'zsh')
        if animated:
            source = self.source.replace('init_style\n', 'init_style\nset_palette truecolor\n', 1)
            (seed / 'install.sh').write_text(source, encoding='utf-8', newline='\n')
        for args in (('init', '-b', 'main'), ('add', '.'),
                     ('-c', 'user.name=UI test', '-c', 'user.email=test@example.invalid',
                      'commit', '-m', 'Fixture')):
            subprocess.run(['git', '-C', str(seed), *args], check=True, capture_output=True)
        tools = self.fixture / 'tools'
        tools.mkdir()
        # Portable suite validates installer flow; Linux workflow tests use real Zsh.
        (tools / 'zsh').write_text('#!/usr/bin/env bash\n[[ "$1" == -n ]]\n', newline='\n')
        (tools / 'zsh').chmod(0o755)
        if failing_link:
            (tools / 'ln').write_text('''#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == "$ZSHCFG_HOME/.nanorc" ]]; then
    echo 'simulated link failure' >&2
    exit 29
  fi
done
exec "$REAL_LN" "$@"
''', newline='\n')
            (tools / 'ln').chmod(0o755)
        self.home.mkdir()
        (self.home / '.zshrc').write_text('# original startup\n')
        (self.home / '.nanorc').write_text('# original editor\n')
        return seed, tools

    def install(self, seed, tools):
        return subprocess.run([BASH, '-c',
                               'export REAL_LN="$(command -v ln)"; '
                               'export PATH="$1:$PATH"; '
                               'exec bash "$2/install.sh" --yes --skip-deps --no-chsh',
                               'ui-test', self.bash_path(tools), self.bash_path(seed)],
                              cwd=ROOT, env=self.env, text=True, encoding='utf-8',
                              capture_output=True, timeout=20)

    def render(self, width=80, mode='truecolor', utf8=True):
        # Exercise the actual reusable UI functions, before the install entrypoint.
        # Explicit palettes allow deterministic coverage without faking a TTY.
        ui = self.source.split('# sudo may change', 1)[0]
        script = self.fixture / 'render.sh'
        script.write_text(ui + f'\nUI_WIDTH={width}; UI_UTF8={str(utf8).lower()}; '
                          f'set_palette {mode}; banner\n', encoding='utf-8', newline='\n')
        return self.command(script.relative_to(ROOT).as_posix())

    def test_bash_syntax(self):
        self.command('-n', 'install.sh')

    def test_redirected_preview_is_plain_and_does_not_install(self):
        output = self.command('install.sh', '--preview')
        self.assertTrue(output.startswith('SHCFG\n  Preview only; no files changed.\n'))
        self.assertEqual(output.count('  *  '), 4)
        self.assertNotIn('\x1b', output)
        self.assertFalse(self.home.exists())

    def test_plain_color_and_locale_fallbacks(self):
        for args, extra in [
            (['--plain'], {}), (['--no-color'], {}),
            ([], {'NO_COLOR': ''}), ([], {'TERM': 'dumb'}),
            ([], {'LC_ALL': 'C'}), ([], {'COLUMNS': '008'}),
            ([], {'COLUMNS': 'invalid'}), ([], {'COLUMNS': '000'}),
        ]:
            with self.subTest(args=args, env=extra):
                output = self.command('install.sh', '--preview', *args, extra=extra)
                self.assertNotIn('\x1b', output)
                self.assertTrue(output.isascii())
                self.assertFalse(self.home.exists())

    def test_confirmation_cancels_before_changes(self):
        output = self.command('install.sh', input='n\n')
        self.assertIn('Installation cancelled.', output)
        self.assertFalse(self.home.exists())

    def test_help_describes_existing_switches(self):
        output = self.command('install.sh', '--help')
        for option in ('--preview', '--plain', '--no-color', '--skip-deps', '--no-chsh'):
            self.assertIn(option, output)
        self.assertFalse(self.home.exists())

    def test_pixels_are_a_small_valid_rectangle(self):
        data = re.search(r'LOKI_PIXELS=\(\n(.*?)\n\)', self.source, re.S)[1]
        rows = re.findall(r"'([^']*)'", data)
        self.assertEqual(len(rows), 24)
        self.assertTrue(all(len(row) == 28 for row in rows))
        self.assertEqual(set(''.join(rows)), set('.gyhsdvGcb'))

    def test_supported_palettes_and_background_reset(self):
        for mode, expected in [('truecolor', '\x1b[38;2;'),
                               ('256', '\x1b[38;5;'), ('basic', '\x1b[33m')]:
            with self.subTest(mode=mode):
                output = self.render(mode=mode)
                self.assertIn(expected, output)
                self.assertIn('\x1b[49m', output)
                self.assertIn('▀', output)
                self.assertTrue(output.endswith('\x1b[0m\n\n'))

    def test_title_is_centered_and_welcome_fits_terminal(self):
        for width in (20, 27, 28, 32, 33, 40, 80, 120):
            with self.subTest(width=width):
                lines = ANSI.sub('', self.render(width=width)).splitlines()
                self.assertTrue(all(len(line) <= width for line in lines))
                if width >= 33:
                    title = lines[1:6]
                    self.assertEqual(len(title), 5)
                    left = min(len(line) - len(line.lstrip()) for line in title)
                    right = max(len(line.rstrip()) for line in title)
                    self.assertEqual(left, (width - 33) // 2)
                    self.assertEqual(right - left, 33)
                    self.assertLessEqual(abs(left - (width - right)), 1)
                else:
                    title = next(line for line in lines if 'SHCFG' in line)
                    self.assertEqual(len(title) - len(title.lstrip()), (width - 5) // 2)
                self.assertEqual(any('▀' in line or '▄' in line for line in lines), width >= 28)

    def test_non_utf8_renderer_uses_ascii(self):
        output = ANSI.sub('', self.render(utf8=False))
        self.assertTrue(output.isascii())
        self.assertIn('SHCFG', output)

    def test_no_promotional_copy_or_dashboard(self):
        output = ANSI.sub('', self.render())
        self.assertIn('Zsh environment setup', output)
        copy = self.source.replace('Oh My Zsh', '').replace('oh-my-zsh', '')
        self.assertNotRegex(copy, r'\b[Mm]y\b|\bI (?:am|can|need)\b|ideal workspace')
        self.assertNotRegex(output.lower(), r'\byour\b|every machine|ultimate|shell environment')
        self.assertLessEqual(len(output.splitlines()), 22)

    def test_spinner_updates_one_line_and_stops_before_completion(self):
        ui = self.source.split('# sudo may change', 1)[0]
        script = self.fixture / 'spinner.sh'
        script.write_text(ui + '''
exec 3>&1
set_palette truecolor
step 1 'Tools and plugins'
sleep 0.55
complete_step
[[ -z "$SPINNER_PID" ]]
printf 'stopped\\n'
sleep 0.2
''', encoding='utf-8', newline='\n')
        output = self.command(script.relative_to(ROOT).as_posix())
        for frame in '|/-\\':
            self.assertIn(f'{frame}\x1b[0m  Tools and plugins', output)
        self.assertIn('\x1b[2K', output)
        self.assertIn('*\x1b[0m  Tools and plugins', output)
        self.assertTrue(output.endswith('stopped\n'))

    def test_install_is_quiet_and_keeps_diagnostics_in_a_log(self):
        seed, tools = self.installer_fixture()
        result = self.install(seed, tools)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count('  *  '), 4)
        self.assertNotIn('Linked:', result.stdout)
        self.assertNotIn('Cloning into', result.stdout)
        self.assertEqual(result.stderr, '')
        self.assertIn('shcfghelp', result.stdout)
        logs = list((self.home / '.local/state/zshcfg').glob('install-*.log'))
        self.assertEqual(len(logs), 1)
        log = logs[0].read_text()
        self.assertIn('Backup:', log)
        self.assertIn('Linked:', log)
        self.assertIn('Cloning into', log)
        self.assertIn('shcfghelp', (self.home / '.zsh_config/aliases.zsh').read_text(encoding='utf-8'))
        self.assertIn('# original startup', next(self.home.glob('.zshrc.bak.*')).read_text())

    def test_failure_stops_spinner_reports_error_and_rolls_back(self):
        seed, tools = self.installer_fixture(animated=True, failing_link=True)
        result = self.install(seed, tools)
        self.assertEqual(result.returncode, 29, result.stdout + result.stderr)
        self.assertIn('!\x1b[0m  Dotfiles', result.stdout)
        self.assertNotIn('Configuration ready.', result.stdout)
        self.assertIn('simulated link failure', result.stderr)
        self.assertIn('Full log:', result.stderr)
        self.assertIn('restoring replaced configuration', result.stderr)
        self.assertIn('Installation stopped during: Dotfiles', result.stderr)
        self.assertEqual((self.home / '.zshrc').read_text(), '# original startup\n')
        self.assertEqual((self.home / '.nanorc').read_text(), '# original editor\n')
        self.assertFalse((self.home / '.p10k.zsh').exists())

    def test_administrator_prompt_pauses_spinner_and_bypasses_log(self):
        ui = self.source.split('# sudo may change', 1)[0]
        admin = 'as_admin() {' + self.source.split('as_admin() {', 1)[1].split('as_user() {', 1)[0]
        script = self.fixture / 'auth.sh'
        script.write_text(ui + admin + '''
exec 3>&1 4<&0 5>&2
(( EUID != 0 )) || exit 0
set_palette truecolor
sudo() {
  if [[ "$1" == -v ]]; then
    [[ -z "$SPINNER_PID" ]] || return 88
    printf 'authentication prompt\\n'
  else
    [[ "$1" == -n && -n "$SPINNER_PID" ]] || return 89
    printf 'package diagnostics\\n' >&2
  fi
}
step 1 'Tools and plugins'
as_admin package >> "${BASH_SOURCE[0]}.log" 2>&1
complete_step
''', encoding='utf-8', newline='\n')
        output = self.command(script.relative_to(ROOT).as_posix())
        if not output:
            self.skipTest('requires a non-root caller for administrator authentication')
        self.assertIn('authentication prompt', output)
        self.assertNotIn('package diagnostics', output)
        log = Path(str(script) + '.log').read_text()
        self.assertIn('package diagnostics', log)
        self.assertNotIn('authentication prompt', log)


if __name__ == '__main__':
    unittest.main(verbosity=2)
