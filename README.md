# ZshCFG — Loki's shell configuration

A modular Zsh setup with a small, readable Git wrapper. Nano is the default editor.

## Install

```sh
git clone https://github.com/UnExplainableFish52/pvtcfg.git
bash pvtcfg/install.sh
```

You can run the installer by its path from any working directory. Alternatively,
once this implementation is on the default branch, download just the installer:

```sh
curl -fL https://raw.githubusercontent.com/UnExplainableFish52/pvtcfg/main/install.sh -o install.sh
bash install.sh
```

The installer asks before proceeding and before changing the default login shell.
Run as your normal user; it uses sudo only for missing system packages.
It prepares Zsh, Git, curl, **Nano, fzf, ripgrep, bat, eza, Python and venv support**,
Oh My Zsh, Powerlevel10k, autosuggestions and syntax highlighting.
The terminal itself still needs a compatible icon font for the existing prompt.
No GUI is required. Wallpapers are ignored.

Debian/Kali/Ubuntu package names are the primary target. Package mappings also
exist for dnf, pacman, zypper and apk, but those distributions have not been
integration-tested. Packages must be available from the machine's configured
repositories: the installer does not add third-party repositories or silently
skip missing tools. A dependency installation failure stops before replacing
configuration files. Use your package manager's error to resolve availability.

## Installed layout and backups

The permanent checkout is `~/.local/share/zshcfg/repo`. These are individual links:

| Installed file | File in the checkout |
| --- | --- |
| `~/.zshrc` | `.zshrc` |
| `~/.p10k.zsh` | `.p10k.zsh` |
| `~/.nanorc` | `.nanorc` |
| `~/.zsh_config/{env,options,aliases,functions,keybinds}.zsh` | `zsh/` modules |
| `~/.local/bin/zshcfg` | `bin/zshcfg` |

Before replacement, old files get adjacent backups such as
`~/.zshrc.bak.2026-10-15_14-54-13-1234`. The final component is the process ID
so separate runs within one second do not collide. Existing symlink contents are
copied into a standalone backup so future updates cannot change that backup.
If activation fails partway through, the installer restores replaced files.
Reinstalling already-correct links does not create redundant backups.

`~/.zsh_config/local.zsh` remains a regular machine-local override, is loaded last,
and is never overwritten or automatically published. Put private values there.
The blank template is `zsh/local.example.zsh`. Existing unknown modules are kept.
Do not put secrets into tracked modules: these are intended for the remote repo.

Editing an installed linked file edits its tracked source directly. Keep the
permanent checkout in place. Re-running installation retains it; updating is an
explicit `zshcfg pull`. Installation from a Git clone requires committed files so
the permanent clone contains the version you intended. A standalone installer or
ZIP without Git history obtains the configured remote branch instead.

## Daily tools

| Command | Behavior |
| --- | --- |
| `nano FILE` | Nano, with line numbers enabled by the generic `.nanorc` |
| `cat FILE` | `bat --style=numbers --paging=never`; uses `batcat` where that is the installed name |
| `ls` | `eza --group-directories-first` |
| `ll`, `lla` | Detailed listings, including hidden entries |
| `grep` | `rg` (ripgrep syntax/behavior, not full grep compatibility) |
| Ctrl+R | Custom fzf command-history picker |
| Ctrl+T / Alt+C | File insertion / directory picker when the distro's fzf integration scripts exist |

Nano is both `EDITOR` and `VISUAL`. Replace `.nanorc` with your own settings later.
`vi` and `vim` are no longer redirected to Neovim. If optional tools are absent
(e.g. when you explicitly skip dependency installation), the replacements fall
back to the original tools. Use `command cat`, `command ls`, or `command grep`
when you specifically need their original behavior.

## ZshCFG commands

| Command | Action |
| --- | --- |
| `zshcfg v`, `zshcfg V`, `zshcfg version` | Show version and local modification status |
| `chkv`, `zshcfg chkv`, `zshcfg check` | Fetch upstream information and report commit counts and remote version |
| `zshcfg pull` | Update a clean checkout with a fast-forward; never merge/rebase/discard edits |
| `zshcfg push`, `zshcfg publish` | Syntax-check, commit managed changes, then push |
| `zshcfg push force`, `zshcfg publish force` | Explicit force-with-lease push |
| `zshcfg help` | Display the command list |

These commands always operate on their own checkout, not the repository you happen
to be standing in. `check` offers a pull when only the remote is ahead and the
checkout is clean. A failed fetch reports remote status as unknown. Diverged
histories and dirty pulls stop with guidance to use ordinary Git. No automatic
integration workspace, merge, rebase or force-pull is involved.

Publishing stages only `VERSION`, `.zshrc`, `.nanorc`, `.p10k.zsh`, `zsh/`, `bin/`,
`install.sh`, and `.gitignore`, excluding `zsh/local.zsh`. Unrelated files already
staged cause it to stop. README, tests and images can be committed with ordinary
Git. Git's author identity, authentication and repository permissions must already
be configured. Errors retain the original Git output and a nonzero exit status;
a failed push leaves your local commit saved. `0` means success. Unknown commands
use exit code `2`; ordinary workflow refusals use `1`.

Force publishing requires a prior `zshcfg check`. It uses the exact remote commit
observed during that check as its lease, so an intervening remote change rejects
the push. It saves local and checked remote histories under
`zshcfg-backup/local-*` and `zshcfg-backup/remote-*` branches. **Force can remove
remote-only commits from the active branch; it replaces history rather than
combining changes.** It never overrides authentication or branch protection.

### Version rules

`1.26.10.15.0` means major `1`, year `26`, month `10`, day `15`, status `0`.
`0` is stable and `1` is experimental. Changing managed files displays today's
date and `.1` when the new content is observed. The displayed date is cached in
`~/.local/state/zshcfg`, outside Git, and remains fixed until another edit is
observed. Checking a version does not dirty the VERSION file.

Publishing writes the displayed version into `VERSION` before committing, so `.1`
remains even after the checkout is clean. To mark a release stable, edit only
`VERSION` to the desired `.0` and publish. There is no mark-stable command.
Commit history, rather than the version label, determines ahead/behind/diverged.

## Existing personal shortcuts

| Command | Destination / action |
| --- | --- |
| `..`, `...` | One / two directories up |
| `doc` | `~/Documents` |
| `cdpg`, `cdtemp` | `~/Documents/playground`, its `temp` folder (no clearing) |
| `cdsh` | `~/Documents/bash/shell` |
| `cdshc`, `cdshcfg`, `shell_config` | `~/.zsh_config` |
| `cd shell_config` | Named-directory fallback; use `shell_config` or `cd ~shell_config` to avoid a local-name collision |
| `TSH`, `tsh` | Clear and enter `~/Documents/shell/temp_session` in the current shell |
| `tp` | Destination menu |
| `tp c/p/t/i/d/n/b/s/h` | Codes / codes / temp / config / Downloads / notes / local bin / SSH / home |
| `tp TEXT`, `tp -s TEXT`, `tp -f` | Best substring match / list matches / fzf picker |
| `check_recent_files DIR` | Newest-first file list (GNU find) |
| `rand`, `random`, `rint` | Random integer: default 1–100, maximum, or two bounds |
| `mkvenv NAME`, `py3` | Create/activate a Python venv; Python 3 shortcut |

TSH takes no arguments. Each invocation removes prior contents, including hidden
files and subfolders, and keeps the workspace directory itself. It refuses
symlinked Documents/shell/temp_session path components. Links inside the workspace
are removed without following their targets. Contents remain until the next TSH
invocation; this does not clear history, provide a separate shell, or securely
erase files. The older `tp t` remains separate and asks before clearing its folder.
`tp` uses the XDG Documents location where configured; TSH uses literal Documents.

Existing general Git aliases are preserved in `zsh/aliases.zsh`: status/log/diff,
stage/commit, branches, fetch/pull/push, stash, restore, rebase and merge helpers.
The existing `gaddconf` uses whitespace splitting, so stage conflict filenames
with spaces manually. Other retained settings include 50,000-entry shared history,
prefix search with Up/Down, Emacs keys, and the existing Powerlevel10k prompt.

## Validation and installer options

```sh
python3 tests/test_navigation.py
python3 tests/test_workflow.py
```

The navigation tests cover TSH reset boundaries and tp behavior. Workflow tests
use real Git with local bare remotes and alternate homes, cover rollback,
reinstallation, standalone bootstrap, versions, normal/rejected/forced pushes,
clean/dirty/diverged pulls, aliases, and a real Nano PTY session. Package-manager
and dependency-clone calls are mocked; they do not download/install host packages.
They do not test distro package availability, real GitHub authentication, a real
login-shell change, or the installed Powerlevel10k appearance.

Installer options: `--yes` skips installation confirmation, `--no-chsh` skips the
login-shell prompt, and `--skip-deps` assumes dependencies are already installed.
`ZSHCFG_HOME` selects an alternate target home for fixtures/staging without changing
HOME; account changes are disabled for alternate homes. `ZSHCFG_REMOTE` and
`ZSHCFG_BRANCH` select a fork/branch for standalone bootstrap. Git-backed source
installs keep the source checkout's branch and origin.

Upstream references: [Nano options](https://nano-editor.org/dist/latest/nanorc.5.html),
[bat](https://github.com/sharkdp/bat), [eza installation](https://github.com/eza-community/eza/blob/main/INSTALL.md),
[Git push / leases](https://git-scm.com/docs/git-push).
